# SPDX-License-Identifier: AGPL-3.0-or-later
"""Acts as Silo's Android phone app against Siku (simulator or a real Roku) on the LAN.

  browse   send mDNS queries for _silocast-roku._tcp / _silopair-roku._tcp and print the answers
  pair     sign Siku in from "the phone" (Siku on its server or sign-in screen)
  cast     connect as a SiloCast controller (plain, or sealed with the pairing link's key), hand
           the profile over, launch a title and send controls, printing what the Roku answers

Examples (mock server on 8111, simulator on this machine):
  python3 tools/silo_phone.py browse
  python3 tools/silo_phone.py pair --host 127.0.0.1 --server http://127.0.0.1:8111 --identity mock-server-1
  python3 tools/silo_phone.py cast --link 'silo://cast?v=2&host=...&key=...' --server http://127.0.0.1:8111 \\
      --identity mock-server-1 --profile p-owner --content movie:glass-city
  python3 tools/silo_phone.py cast --host 192.168.1.20 --port 52817 --server https://media.example.com ...

`cast --endpoint URL` offers the server's other addresses (serverEndpoints); the Roku runs the
handoff at the first address reporting --identity (its own saved one first; mock log `HANDOFF ...
port=`). `cast --expect-refused` succeeds only on a handoff_cancel; `--expect-identity ID` checks the
identity the Roku's hello advertises (Silo Android #717).
`cast --check-refusals` also verifies that a wrong pairing key and a foreign server are refused;
`cast --check-limits` that an oversized frame before the hello is refused and a seventh controller
is turned away; `cast --hold N` stops after the handoff and keeps the connection N seconds (sign out
or change server on the Roku meanwhile to see the borrowed profile end); `pair --idle` connects and
says nothing, expecting the Roku to close the sign-in connection after about 30 s.
The protocol code is tools/silo_lan.py (ported from silo-android FETCH_HEAD 88db96c). The phone
approves handoff codes through the mock's /api/v2/auth/device/approve-handoff; against a real
server pass --token (an access token of the phone's account) to approve with it.
"""
import argparse
import json
import os
import socket
import struct
import sys
import threading
import time
import urllib.request
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import silo_lan as L  # noqa: E402


def log(*a):
    print("[phone]", *a, flush=True)


# ---------- browse ----------

def mdns_query(names, unicast=True):
    hdr = struct.pack(">HHHHHH", 0, 0, len(names), 0, 0, 0)
    body = b""
    for n in names:
        body += b"".join(bytes([len(p)]) + p.encode() for p in n.split(".")) + b"\x00"
        body += struct.pack(">HH", 12, 0x8001 if unicast else 1)
    return hdr + body


def cmd_browse(args):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from lan_vectors import dns_parse
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)
    s.bind(("", 0))
    s.settimeout(0.5)
    q = mdns_query([L.CAST_TYPE + ".local", L.PAIR_TYPE + ".local"])
    target = (args.target, 5353) if args.target else ("224.0.0.251", 5353)
    end, sent, found = time.time() + args.seconds, 0, {}
    while time.time() < end:
        if sent < 3:
            s.sendto(q, target)
            sent += 1
        try:
            data, src = s.recvfrom(9000)
        except socket.timeout:
            continue
        try:
            _, recs = dns_parse(data)
        except Exception as e:  # noqa: BLE001
            log("unparsable answer from", src, e)
            continue
        for name, t, _, ttl, val in recs:
            key = (name, t, str(val))
            if key not in found:
                found[key] = True
                log("%s from %s: %s type=%d ttl=%d %s" % ("answer", src[0], name, t, ttl, val))
    if not found:
        log("no answer (on a real network, try --target <roku-ip> for a unicast query)")
    return 0 if found else 1


# ---------- pair ----------

def cmd_pair(args):
    sock = socket.create_connection((args.host, args.port), timeout=10)
    conn = L.PlainConnection(sock)
    hello = conn.recv(15)
    log("roku hello:", hello)
    if args.idle:
        started = time.time()
        try:
            m = conn.recv(60)
        except socket.timeout:
            m = "nothing (still open)"
        except OSError:
            m = None
        waited = time.time() - started
        if m is None and 25 <= waited <= 45:
            log("ok: the Roku closed the silent sign-in connection after %.0f s" % waited)
            return 0
        log("FAIL: after %.0f s the Roku sent %r" % (waited, m))
        return 1
    if not hello or hello.get("type") != "hello" or 1 not in hello.get("supportedVersions", []):
        log("not a compatible pairing hello")
        return 1
    push = {"v": 1, "type": "pushServer", "serverURL": args.server, "serverName": args.name}
    if args.identity:
        push["serverIdentity"] = args.identity
    if args.endpoint:
        push["endpoints"] = [{"url": u, "kind": "public"} for u in args.endpoint]
    conn.send(push)
    log("pushed", args.server, "- allow it on the Roku (OK on Allow) if it asks")
    started = None
    deadline = time.time() + args.timeout
    while time.time() < deadline:
        m = conn.recv(deadline - time.time())
        if m is None:
            log("roku closed the connection")
            return 1
        log("roku:", m)
        if m.get("type") == "deviceStarted":
            started = m
            log("the phone would now look up %s and ask its user to confirm, then approve" % m.get("userCode"))
            if args.approve:
                http("POST", args.server.rstrip("/") + "/api/v2/auth/device/approve", {"user_code": m.get("userCode")})
                log("approved on the (mock) server")
        elif m.get("type") == "serverResult":
            ok = m.get("status") == "signedIn"
            if ok:
                conn.send({"v": 1, "type": "done"})
                log("signed in; sent done")
            conn.close()
            return 0 if ok and started else 1
        elif m.get("type") == "cancel":
            return 1
    log("timed out")
    return 1


# ---------- cast ----------

class Controller:
    def __init__(self, conn):
        self.conn = conn
        self.lock = threading.Lock()
        self.inbox = []
        self.cv = threading.Condition()
        self.state = None
        self.closed = False
        threading.Thread(target=self._read, daemon=True).start()

    def send(self, obj):
        with self.lock:
            self.conn.send(obj)

    def _read(self):
        try:
            while True:
                m = self.conn.recv(timeout=60)
                if m is None:
                    break
                t = m.get("type")
                if t == "ping":
                    self.send({"type": "pong", "v": 2})
                    continue
                if t == "state":
                    st = m["state"]
                    if self.state is None or summary(st) != summary(self.state):
                        log("state:", summary(st))
                    self.state = st
                else:
                    log("roku:", json.dumps(redact(m))[:400])
                with self.cv:
                    self.inbox.append(m)
                    self.cv.notify_all()
        except Exception as e:  # noqa: BLE001
            log("read ended:", e)
        self.closed = True
        with self.cv:
            self.cv.notify_all()

    def wait(self, pred, timeout):
        end = time.time() + timeout
        with self.cv:
            while time.time() < end:
                for i, m in enumerate(self.inbox):
                    if pred(m):
                        return self.inbox.pop(i)
                if self.closed:
                    return None
                self.cv.wait(0.2)
        return None


def redact(m):
    """A copy of a message with resume tokens hidden (never print tokens)."""
    if isinstance(m, dict):
        return {k: ("<redacted>" if k == "resumeToken" else redact(v)) for k, v in m.items()}
    if isinstance(m, list):
        return [redact(v) for v in m]
    return m


def summary(st):
    return "%s | %s | playing=%s t=%.0f/%.0f muted=%s audio=%s sub=%s q=%s tracks a%d s%d%s%s" % (
        st.get("contentId"), st.get("title"), st.get("isPlaying"), st.get("currentTime", 0), st.get("duration", 0),
        st.get("isMuted"), st.get("selectedAudioTrackId"), st.get("selectedSubtitleTrackId"), st.get("activeQualityId"),
        len(st.get("audioTracks", [])), len(st.get("subtitleTracks", [])),
        " poster" if st.get("posterUrl") else "", " error=" + st["error"] if st.get("error") else "")


def http(method, url, body=None, headers=None):
    req = urllib.request.Request(url, method=method, data=None if body is None else json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", **(headers or {})})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read() or b"{}")


def dial_target(args):
    key = None
    host, port = args.host, args.port
    if args.link:
        link = L.parse_pairing_link(args.link)
        if not link:
            raise SystemExit("not a valid silo://cast link")
        host, port, key = link["host"], link["port"], link["key"]
        log("link: %s:%d %s" % (host, port, link["security"]))
    if args.key:
        key = L.parse_key(args.key)
    return host, port, key


def phone_hello(args, server_url=None, identity=None):
    url = server_url or args.server
    return {"type": "hello", "v": 2, "hello": {
        "role": "phone", "deviceName": args.device_name, "deviceId": args.device_id, "serverId": L.server_id_for(url),
        "serverName": "Phone's server", "supportedVersions": [2], "serverIdentity": identity or args.identity or None,
        "features": ["close_reason", "resume_token", "replace_confirmation"]}}


def cmd_cast(args):
    host, port, key = dial_target(args)
    if args.check_refusals:
        ok = check_refusals(args, host, port, key)
        if not ok:
            return 1
    if args.check_limits:
        ok = check_limits(args, host, port, key)
        if not ok:
            return 1
    conn = L.dial(host, port, key)
    log("connected (%s)" % ("sealed" if key else "plain"))
    c = Controller(conn)
    tv = c.wait(lambda m: m.get("type") == "hello", 10)
    if not tv:
        log("no hello from the Roku")
        return 1
    feats = tv["hello"].get("features", [])
    log("roku hello: name=%r server=%r identity=%s features=%s" % (tv["hello"].get("deviceName"), tv["hello"].get("serverName"),
        "yes" if tv["hello"].get("serverIdentity") else "none", feats))
    if args.expect_identity and tv["hello"].get("serverIdentity") != args.expect_identity:
        log("FAIL: the Roku advertises identity %r, expected %r" % (tv["hello"].get("serverIdentity"), args.expect_identity))
        return 1
    c.send(phone_hello(args))
    request_id = str(uuid.uuid4())
    offer = {"requestId": request_id, "serverId": L.server_id_for(args.server), "serverURL": args.server.rstrip("/"),
             "serverName": "Phone's server", "profileId": args.profile, "profileName": args.profile, "title": "A title"}
    if args.identity:
        offer["serverIdentity"] = args.identity
    if args.endpoint:
        # The deployment's other addresses (SiloCastHandoffOffer.serverEndpoints, Silo Android #716).
        offer["serverEndpoints"] = [{"url": u, "kind": "public"} for u in args.endpoint]
    c.send({"type": "handoff_offer", "v": 2, "handoffOffer": offer})
    reply = c.wait(lambda m: m.get("type") in ("handoff_ready", "handoff_challenge", "handoff_cancel"), 20)
    if not reply:
        log("no handoff answer")
        return 1
    if reply["type"] == "handoff_cancel":
        log("handoff refused:", reply["handoffCancel"])
        if args.expect_refused:
            log("ok: refused as expected")
            return 0
        return 1
    if args.expect_refused:
        log("FAIL: expected the handoff to be refused, got", reply["type"])
        return 1
    if reply["type"] == "handoff_challenge":
        ch = reply["handoffChallenge"]
        look = http("GET", args.server.rstrip("/") + "/api/v2/auth/device?user_code=" + ch["userCode"])
        log("challenge %s; server says purpose=%s temporary=%s match=%s" % (ch["userCode"], look.get("client_purpose"), look.get("temporary"), look.get("match_code") == ch["matchCode"]))
        hdr = {"X-Profile-Id": args.profile}
        if args.token:
            hdr["Authorization"] = "Bearer " + args.token
        http("POST", args.server.rstrip("/") + "/api/v2/auth/device/approve-handoff", {"user_code": ch["userCode"]}, hdr)
        reply = c.wait(lambda m: m.get("type") in ("handoff_ready", "handoff_cancel"), 40)
        if not reply or reply["type"] != "handoff_ready":
            log("handoff did not complete:", reply)
            return 1
    log("handoff ready: reused=%s profile=%s" % (reply["handoffReady"].get("reused"), reply["handoffReady"].get("profileId")))
    if args.hold:
        log("holding the connection for %.0f s (no launch)" % args.hold)
        closed = c.wait(lambda m: m.get("type") == "close", args.hold)
        if closed:
            log("roku closed the connection:", closed.get("close"))
        elif c.closed:
            log("roku dropped the connection")
        else:
            c.send({"type": "close", "v": 2})
        conn.close()
        return 0
    playback = {"contentId": args.content, "startFromBeginning": True}
    if args.subtitle is not None:
        playback["subtitleTrackIndex"] = args.subtitle
    if args.file_id is not None:
        playback["fileId"] = args.file_id
    c.send({"type": "launch", "v": 2, "launch": {"serverId": L.server_id_for(args.server), "playback": playback}})
    st = c.wait(lambda m: m.get("type") == "state" and m["state"].get("contentId") == args.content, 40)
    if not st:
        log("the Roku never reported the launched title")
        return 1
    ok = True
    for cmd in [{"name": "pause"}, {"name": "play"}, {"name": "seek", "seconds": 120.0}, {"name": "set_muted", "enabled": True},
                {"name": "select_subtitle_track", "trackId": 0}, {"name": "select_audio_track", "trackId": 0},
                {"name": "set_muted", "enabled": False}, {"name": "set_playback_speed", "speed": 1.5}]:
        log("control", cmd)
        c.send({"type": "control", "v": 2, "control": cmd})
        time.sleep(args.step)
    err = c.wait(lambda m: m.get("type") == "error" and m["error"].get("code") == "command_failed", 3)
    log("speed refused as expected" if err else "speed was not refused")
    ok = ok and err is not None
    last = c.state or {}
    log("final state:", summary(last))
    if args.stop:
        c.send({"type": "control", "v": 2, "control": {"name": "stop"}})
        idle = c.wait(lambda m: m.get("type") == "state" and not m["state"].get("contentId"), 15)
        log("roku back to Ready" if idle else "roku did not report Ready")
        ok = ok and idle is not None
    c.send({"type": "close", "v": 2})
    conn.close()
    return 0 if ok else 1


def hangup(conn):
    """Close now: a reader thread blocked in recv would otherwise hold the socket open (no FIN)."""
    try:
        conn.sock.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    conn.close()


def check_refusals(args, host, port, key):
    ok = True
    if key is not None:
        wrong = bytes(16)
        try:
            L.dial(host, port, wrong).close()
            log("FAIL: a wrong pairing key was accepted")
            ok = False
        except L.PairingRefused:
            log("ok: a wrong pairing key is refused")
        except IOError as e:
            log("ok: a wrong pairing key is refused (%s)" % e)
        # A phone that speaks plain to a sealed Roku gets nothing it can use.
        conn = L.dial(host, port, None)
        conn.send(phone_hello(args))
        m = None
        try:
            m = conn.recv(5)
        except Exception:  # noqa: BLE001
            m = None
        if m and m.get("type") == "hello":
            log("FAIL: a sealed Roku answered a plain hello")
            ok = False
        else:
            log("ok: a plain connection to a sealed Roku gets %s" % (m,))
        conn.close()
    conn = L.dial(host, port, key)
    c = Controller(conn)
    c.wait(lambda m: m.get("type") == "hello", 10)
    c.send(phone_hello(args, server_url="https://other.example", identity="another-deployment"))
    c.send({"type": "control", "v": 2, "control": {"name": "pause"}})
    err = c.wait(lambda m: m.get("type") == "error", 5)
    if err and err["error"]["code"] == "unauthorized":
        log("ok: a phone on another server is unauthorized")
    else:
        log("FAIL: a phone on another server was not refused:", err)
        ok = False
    hangup(conn)
    time.sleep(2)
    return ok


def check_limits(args, host, port, key):
    ok = True
    # A frame header declaring 5000 bytes before the hello: the Roku closes the connection.
    sock = socket.create_connection((host, port), timeout=10)
    if key is None:
        L.PlainConnection(sock).recv(5)  # the Roku's plain hello comes first
    sock.sendall(struct.pack(">I", 5000) + b"{" * 64)
    sock.settimeout(8)
    try:
        data = sock.recv(4096)
        while data:
            data = sock.recv(4096)
        log("ok: an oversized frame before the hello closes the connection")
    except socket.timeout:
        log("FAIL: an oversized frame before the hello was kept open")
        ok = False
    except OSError as e:
        log("ok: an oversized frame before the hello closes the connection (%s)" % e)
    sock.close()
    # Six controllers fill the TV; a seventh is turned away.
    held = []
    for i in range(6):
        conn = L.dial(host, port, key)
        c = Controller(conn)
        c.wait(lambda m: m.get("type") == "hello", 10)
        a = argparse.Namespace(**vars(args))
        a.device_id = "limit-%d-%s" % (i, uuid.uuid4().hex[:6])
        c.send(phone_hello(a))
        held.append((conn, c))
        # An authorized controller gets the state; wait for it so a slow simulator does not
        # close this one for a late hello while the next ones dial.
        if not c.wait(lambda m: m.get("type") == "state", 30):
            log("controller %d got no state (is this phone's server the Roku's?)" % i)
    if any(c.closed for _, c in held):
        log("FAIL: a controller was closed before the limit was reached")
        ok = False
    time.sleep(1)
    try:
        conn = L.dial(host, port, key)
        got = []
        while True:
            try:
                m = conn.recv(5)
            except socket.timeout:
                got.append({"type": "still-open"})
                break
            if m is None:
                break
            got.append(m)
        conn.close()
    except (IOError, OSError) as e:
        got = None
        log("seventh controller: %s" % e)
    if key is None:
        codes = [m.get("type") + ":" + (m.get("error", {}).get("code") or m.get("close", {}).get("reason") or "") for m in got or []]
        if codes[-2:] == ["error:too_many_controllers", "close:too_many_controllers"]:
            log("ok: a seventh controller gets too_many_controllers (%s)" % codes)
        else:
            log("FAIL: a seventh controller got %s" % codes)
            ok = False
    elif got is None or not got:
        log("ok: a seventh sealed controller is closed without an answer")
    else:
        log("FAIL: a seventh sealed controller got %s" % got)
        ok = False
    for conn, c in held:
        c.send({"type": "close", "v": 2})
        hangup(conn)
    time.sleep(1)
    return ok


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("browse")
    b.add_argument("--seconds", type=float, default=4)
    b.add_argument("--target", help="send the query to this address instead of the multicast group")
    p = sub.add_parser("pair")
    p.add_argument("--host", required=True)
    p.add_argument("--port", type=int, default=52819)
    p.add_argument("--server", required=True)
    p.add_argument("--name", default="Mock Silo")
    p.add_argument("--identity")
    p.add_argument("--endpoint", action="append", default=[])
    p.add_argument("--timeout", type=float, default=120)
    p.add_argument("--approve", action="store_true", help="approve the code on the mock (switch device_manual=1)")
    p.add_argument("--idle", action="store_true", help="say nothing; expect the Roku to close after about 30 s")
    c = sub.add_parser("cast")
    c.add_argument("--link")
    c.add_argument("--host")
    c.add_argument("--port", type=int, default=52817)
    c.add_argument("--key", help="pairing key (base32 or hex) for a sealed Roku")
    c.add_argument("--server", required=True, help="the phone's active server URL")
    c.add_argument("--identity", help="the server's deployment identity (GET /api/v2/system/identity)")
    c.add_argument("--endpoint", action="append", default=[],
                   help="another address of the server, offered as serverEndpoints (repeatable)")
    c.add_argument("--expect-identity", help="fail unless the Roku's hello advertises this deployment identity")
    c.add_argument("--expect-refused", action="store_true", help="succeed only if the Roku refuses the handoff")
    c.add_argument("--profile", default="p-owner")
    c.add_argument("--token", help="access token for approving a handoff on a real server")
    c.add_argument("--content", default="movie:glass-city")
    c.add_argument("--file-id", type=int)
    c.add_argument("--subtitle", type=int)
    c.add_argument("--step", type=float, default=1.5)
    c.add_argument("--stop", action="store_true", help="stop playback at the end")
    c.add_argument("--check-refusals", action="store_true")
    c.add_argument("--check-limits", action="store_true", help="oversized pre-hello frame and a seventh controller")
    c.add_argument("--hold", type=float, default=0, help="after the handoff, keep the connection this long and launch nothing")
    c.add_argument("--device-name", default="Test Phone")
    c.add_argument("--device-id", default="phone-" + uuid.uuid4().hex[:8])
    args = ap.parse_args()
    sys.exit({"browse": cmd_browse, "pair": cmd_pair, "cast": cmd_cast}[args.cmd](args))


if __name__ == "__main__":
    main()
