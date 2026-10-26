# SPDX-License-Identifier: AGPL-3.0-or-later
"""Acts as a Silo server's LAN advertisement (`_silo._tcp`) so Siku's "Find servers on this
network" can be tested against the simulator or a real Roku.

What a Silo server sends (silo-server docs/architecture/server-discovery.md): PTR
_silo._tcp.local -> "<server name>._silo._tcp.local", SRV (port = the API port, plain HTTP), TXT
v=1 and id=<GET /api/v2/system/identity server_id>, A = the server's address; answers by
multicast, only to multicast queries from port 5353; goodbye (TTL 0) when it stops.

Two ways to run it:

  network (default): bind UDP 5353 (shared with SO_REUSEADDR/SO_REUSEPORT), join 224.0.0.251,
      announce twice, answer every PTR _silo._tcp query that comes from port 5353 by multicast,
      say goodbye on exit. For a real Roku on this machine's LAN; --address must be this
      machine's private address and --port where tools/mock_server.py listens.
        python3 tools/silo_responder.py --address 192.168.1.40 --port 8123 --id mock-server-1

  raw (--raw-to <ip>): for the simulator on this machine, which holds UDP 5353 without sharing
      it and never really joins the group. Needs root (raw sockets): packets are written with
      source port 5353 straight to <ip>:5353, an unsolicited announcement every second, and
      Siku's own queries are logged (and answered at once) when they are heard. Siku only accepts
      private senders, so the simulator run uses the deep link debugLanSelf=1, which also
      accepts this machine's own address:
        python3 tools/silo_responder.py --raw-to 192.0.2.2 --address 192.0.2.2 --port 8123 \\
            --id mock-server-1 --name "Mock Silo" --seconds 40

--scenario changes what is sent: normal, goodbye (announce, then a goodbye after 2 s), conflict
(two ids for one instance), wrongport (sent from port 5354), badtxt (no v=1), many (20 servers;
Siku lists 16), second (a second, different server too).
"""
import argparse
import os
import select
import socket
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import silo_lan as L  # noqa: E402

GROUP = "224.0.0.251"


def log(*a):
    print("[responder]", *a, flush=True)


def packets(args, ttl=120):
    """The announcement datagrams for the scenario, as (payload, source port)."""
    rec = L.silo_records(args.name, args.id, args.address, args.port, ttl=ttl)
    src = 5353
    out = []
    if args.scenario == "wrongport":
        src = 5354
    if args.scenario == "badtxt":
        rec = L.silo_records(args.name, args.id, args.address, args.port, ttl=ttl, txt=["id=" + args.id])
    if args.scenario == "conflict":
        out.append((L.dns_message(L.silo_records(args.name, args.id + "-other", args.address, args.port, ttl=ttl)), src))
    if args.scenario == "second":
        out.append((L.dns_message(L.silo_records("Attic Media", "attic-server-2", args.address, args.port + 1,
                                                 host="silo-attic-0d0e0f.local", ttl=ttl)), src))
    if args.scenario == "many":
        for i in range(20):
            out.append((L.dns_message(L.silo_records("Silo %02d" % i, "many-%02d" % i, args.address, 9000 + i,
                                                     host="silo-many%02d-000000.local" % i, ttl=ttl)), src))
        return out
    out.insert(0, (L.dns_message(rec), src))
    return out


def is_silo_query(data):
    """True for a DNS query (QR clear) asking PTR _silo._tcp.local."""
    if len(data) < 12 or data[2] & 0x80:
        return False
    try:
        qd = struct.unpack(">H", data[4:6])[0]
        off = 12
        for _ in range(qd):
            labels = []
            while data[off]:
                n = data[off]
                if n & 0xC0:
                    off += 1
                    break
                labels.append(data[off + 1:off + 1 + n].decode("ascii", "replace").lower())
                off += 1 + n
            off += 1
            qtype = struct.unpack(">H", data[off:off + 2])[0]
            off += 4
            if ".".join(labels) == "_silo._tcp.local" and qtype in (12, 255):
                return True
    except (IndexError, struct.error):
        return False
    return False


# ---------- raw mode (simulator) ----------

def ip_udp(src_ip, src_port, dst_ip, dst_port, payload):
    udp = struct.pack(">HHHH", src_port, dst_port, 8 + len(payload), 0) + payload
    hdr = struct.pack(">BBHHHBBH4s4s", 0x45, 0, 20 + len(udp), 0, 0, 255, 17, 0,
                      socket.inet_aton(src_ip), socket.inet_aton(dst_ip))
    return hdr + udp


def run_raw(args):
    out = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_RAW)
    sniff = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_UDP)
    # Group membership on any socket makes this host accept 224.0.0.251, so the sniffer hears
    # the multicast queries the simulator sends.
    member = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    member.bind(("0.0.0.0", 0))
    try:
        member.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, socket.inet_aton(GROUP) + socket.inet_aton("0.0.0.0"))
    except OSError as e:
        log("cannot join the group (%s); queries will not be heard, announcements still go out" % e)

    def send_all(ttl=120):
        for payload, src in packets(args, ttl):
            out.sendto(ip_udp(args.address, src, args.raw_to, 5353, payload), (args.raw_to, 0))

    log("raw mode: announcing %r id=%s at http://%s:%d to %s:5353 (scenario %s)" %
        (args.name, args.id, args.address, args.port, args.raw_to, args.scenario))
    end = time.time() + args.seconds
    next_announce = 0
    started = time.time()
    goodbye_sent = False
    heard = 0
    while time.time() < end:
        now = time.time()
        if args.scenario == "goodbye" and now - started > 2 and not goodbye_sent:
            send_all(0)
            goodbye_sent = True
            log("goodbye sent")
        elif now >= next_announce and not goodbye_sent:
            send_all()
            next_announce = now + 1
        r, _, _ = select.select([sniff], [], [], 0.2)
        if not r:
            continue
        pkt, _ = sniff.recvfrom(65535)
        ihl = (pkt[0] & 0x0F) * 4
        if len(pkt) < ihl + 8:
            continue
        sport, dport = struct.unpack(">HH", pkt[ihl:ihl + 4])
        src = socket.inet_ntoa(pkt[12:16])
        dst = socket.inet_ntoa(pkt[16:20])
        if dport == 5353 and is_silo_query(pkt[ihl + 8:]):
            heard += 1
            log("query #%d for _silo._tcp from %s:%d to %s" % (heard, src, sport, dst))
            if not goodbye_sent:
                send_all()
    if not goodbye_sent and args.goodbye_on_exit:
        send_all(0)
        log("goodbye sent")
    log("done; %d quer%s heard" % (heard, "y" if heard == 1 else "ies"))
    return 0


# ---------- network mode (real Roku) ----------

def run_network(args):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        try:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except OSError:
            pass
    s.bind(("0.0.0.0", 5353))
    s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, socket.inet_aton(GROUP) + socket.inet_aton(args.address))
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(args.address))
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)
    if args.scenario == "wrongport":
        log("wrongport needs raw mode; ignored")

    last_sent = 0.0

    def announce(ttl=120):
        nonlocal last_sent
        for payload, _ in packets(args, ttl):
            s.sendto(payload, (GROUP, 5353))
        last_sent = time.time()

    log("network mode: %r id=%s at http://%s:%d (scenario %s)" % (args.name, args.id, args.address, args.port, args.scenario))
    announce()
    second = time.time() + 1
    end = time.time() + args.seconds
    try:
        while time.time() < end:
            if second and time.time() >= second:
                announce()
                second = 0
            r, _, _ = select.select([s], [], [], 0.2)
            if not r:
                continue
            data, (src, sport) = s.recvfrom(9000)
            if not is_silo_query(data):
                continue
            if sport != 5353:
                log("query from %s:%d ignored (not from port 5353, as Silo's responder does)" % (src, sport))
                continue
            log("query from %s:%d" % (src, sport))
            # Each record at most once a second per link.
            if time.time() - last_sent >= 1:
                announce()
    except KeyboardInterrupt:
        pass
    announce(0)
    log("goodbye sent")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", default="Mock Silo", help="instance name (Silo uses the branding server name)")
    ap.add_argument("--id", default="mock-server-1", help="TXT id = the identity server_id")
    ap.add_argument("--address", required=True, help="the A record (and the source address in raw mode)")
    ap.add_argument("--port", type=int, default=8097, help="the API port (SRV)")
    ap.add_argument("--seconds", type=float, default=60)
    ap.add_argument("--raw-to", help="simulator mode: write raw packets to this address's port 5353")
    ap.add_argument("--goodbye-on-exit", action="store_true", help="raw mode: send a goodbye at the end")
    ap.add_argument("--scenario", default="normal", choices=["normal", "goodbye", "conflict", "wrongport", "badtxt", "many", "second"])
    args = ap.parse_args()
    return run_raw(args) if args.raw_to else run_network(args)


if __name__ == "__main__":
    sys.exit(main())
