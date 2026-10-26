# SPDX-License-Identifier: AGPL-3.0-or-later
"""Checks Siku's LAN code (components/lan/*.brs) against the phone's test vectors and tools/silo_lan.py.

Usage:  python3 tools/lan_vectors.py [--brs-cli PATH] [--random N]

What it checks, by running tools/lan_vectors/run_vectors.brs in brs-cli:
  - level `sealed`: key id, HKDF session keys, the Roku's derived IV, sealing a TV frame and
    opening a phone frame, byte for byte against silo-android's SiloCastSealedTest vectors and
    N random cases sealed/opened by the Python reference; replayed, misdirected and tampered
    frames are refused; sealed_hello is written and read the way the phone does.
  - pairing keys in base32 / hex, server ids (base64url of the URL), server matching.
  - length-prefixed framing across split reads, and the 1 MiB limit.
  - mDNS: answers to PTR / SRV / TXT / A / meta queries and the announcement, parsed back here.
brs-engine implements roEVPCipher and roHMAC with Node's crypto, so this verifies the frame format
and the BrightScript logic; whether a Roku's own roEVPCipher/roHMAC agree is a device check
(Connect a Phone, then any sealed command; `[siku-lan] sealed` lines).
Exits non-zero on any mismatch.
"""
import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import silo_lan as L  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# silo-android android-shared/src/androidUnitTest/.../lan/SiloCastSealedTest.kt
KT_KEY = "000102030405060708090a0b0c0d0e0f"
KT_PHONE_NONCE = "101112131415161718191a1b1c1d1e1f"
KT_TV_NONCE = "202122232425262728292a2b2c2d2e2f"
KT_KEY_ID = "be45cb26"
KT_ENC = "239a09219f1c09a91e710d3c90e16a4d"
KT_MAC = "066768a42738a935b7ff4148306d0aaf4650844fbfa39191e41e9cdfea22fafe"
KT_IVK = "3816333626975d56fe75bbe953ab0834"
KT_TV_PING = ("0000000000000000e3c9c8e329cba6d9317f6e0442a21dd98277e1fd6de898e0832b3578392e71044f28b35fe6b562"
              "67e20d49e56e19cf095275faead9fe27b5d6cd3e7cba162cf9d3e5dead6001a4eb0e596a8ac45b2011")
KT_PHONE_PONG = ("0000000000000001ffeeddccbbaa99887766554433221100d6cffafe6c10c438a7bb4a4418b0e3e7e1ba097b39d77764"
                 "7df0c04ad0d79684d56990d6c483611bdfc4acf0b7d16c06ff0c50c169f9739cd58a17445e0daeec")


def dns_query(name, qtype, unicast=False, compress_second=None):
    hdr = struct.pack(">HHHHHH", 0, 0, 1 if compress_second is None else 2, 0, 0, 0)
    def enc(n):
        return b"".join(bytes([len(p)]) + p.encode() for p in n.split(".")) + b"\x00"
    body = enc(name) + struct.pack(">HH", qtype, (0x8001 if unicast else 1))
    if compress_second is not None:
        # "<label>" + pointer to the first name (offset 12): a compressed question.
        label, q2type = compress_second
        body += bytes([len(label)]) + label.encode() + b"\xc0\x0c" + struct.pack(">HH", q2type, 1)
    return hdr + body


def dns_parse(b):
    def name(off):
        labels, jumped, end = [], False, None
        while True:
            n = b[off]
            if n == 0:
                off += 1
                break
            if n & 0xC0 == 0xC0:
                if not jumped:
                    end = off + 2
                off = ((n & 0x3F) << 8) | b[off + 1]
                jumped = True
                continue
            labels.append(b[off + 1:off + 1 + n].decode())
            off += 1 + n
        return ".".join(labels), (end if jumped else off)
    _, flags, qd, an, ns, ar = struct.unpack(">HHHHHH", b[:12])
    off, recs = 12, []
    for _ in range(an + ns + ar):
        n, off = name(off)
        t, c, ttl, ln = struct.unpack(">HHIH", b[off:off + 10])
        off += 10
        rd = b[off:off + ln]
        if t == 12:
            val = name(off)[0]
        elif t == 33:
            val = (struct.unpack(">H", rd[4:6])[0], name(off + 6)[0])
        elif t == 16:
            val, i = [], 0
            while i < len(rd):
                val.append(rd[i + 1:i + 1 + rd[i]].decode())
                i += 1 + rd[i]
        elif t == 1:
            val = ".".join(str(x) for x in rd)
        else:
            val = rd.hex()
        recs.append((n, t, c, ttl, val))
        off += ln
    return flags, recs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--brs-cli", default=os.path.join(ROOT, "node_modules", ".bin", "brs-cli"))
    ap.add_argument("--random", type=int, default=6)
    args = ap.parse_args()

    sealed_cases = [{"key": KT_KEY, "phoneNonce": KT_PHONE_NONCE, "tvNonce": KT_TV_NONCE, "tvSeq": 0,
                     "tvPlain": '{"type":"ping","v":2}', "phoneSeq": 1, "phoneSealed": KT_PHONE_PONG,
                     "phonePlain": '{"type":"pong","v":2}',
                     "phoneHello": '{"type":"sealed_hello","v":1,"keyId":"BE45CB26","nonce":"EBESExQVFhcYGRobHB0eHw"}'}]
    for i in range(args.random):
        key, pn, tn = os.urandom(16), os.urandom(16), os.urandom(16)
        keys = L.SessionKeys(key, pn, tn)
        plain = json.dumps({"type": "control", "v": 2, "control": {"name": "seek", "seconds": 61.5 + i},
                            "note": "é ✓ " * (i * 7)}, ensure_ascii=False, separators=(",", ":"))
        sealed_cases.append({"key": key.hex(), "phoneNonce": pn.hex(), "tvNonce": tn.hex(), "tvSeq": i * 37,
                             "tvPlain": '{"type":"state","v":2,"i":%d}' % i, "phoneSeq": i * 5,
                             "phoneSealed": L.seal(keys, L.FROM_PHONE, i * 5, plain.encode()).hex(), "phonePlain": plain,
                             "phoneHello": L.hello_text(L.key_id(key), pn)})
    key_cases = [{"text": t, "hex": KT_KEY} for t in ("AAAQEAYEAUDAOCAJBIFQYDIOB4", "aaaq eaye auda ocaj bifq ydio b4",
                                                      KT_KEY, "AAAQEAYEAUDAOCAJBIFQYDIO", "AAAQEAYEAUDAOCAJBIFQYDIOB41",
                                                      "AAAQEAYEAUDAOCAJBIFQYDIOB!")]
    servers = ["https://media.example.com", "http://192.168.1.10:8096/silo/", "https://Media.Example.com:443"]
    queries = [dns_query("_silocast-roku._tcp.local", 12, unicast=True),
               dns_query("Siku-0123abcd._silocast-roku._tcp.local", 33, compress_second=("x", 16)),
               dns_query("siku-0123abcd.local", 1),
               dns_query("_services._dns-sd._udp.local", 12),
               dns_query("_silocast._tcp.local", 12)]
    cases = {"sealed": sealed_cases, "keys": key_cases, "servers": servers, "mdns": [q.hex() for q in queries]}

    work = tempfile.mkdtemp(prefix="lan-vectors-")
    fails = []
    try:
        with open(os.path.join(work, "cases.json"), "w") as f:
            json.dump(cases, f)
        srcs = [os.path.join(ROOT, "tools", "lan_vectors", "run_vectors.brs")] + [
            os.path.join(ROOT, "components", "lan", n) for n in ("LanBytes.brs", "SiloSealed.brs", "Mdns.brs")] + [
            os.path.join(ROOT, "components", "common", "Utils.brs")]
        for s in srcs:
            shutil.copy(s, work)
        out = subprocess.run([os.path.abspath(args.brs_cli), "-n", "-c", "0", "-r", ".", *[os.path.basename(s) for s in srcs]],
                             cwd=work, capture_output=True, text=True, timeout=600)
        text = out.stdout + out.stderr
        line = next((l for l in text.splitlines() if l.startswith("LAN-VECTORS ")), None)
        if line is None:
            print(text)
            sys.exit("brs-cli printed no result")
        got = json.loads(line[len("LAN-VECTORS "):])
    finally:
        shutil.rmtree(work, ignore_errors=True)

    def check(name, ok, detail=""):
        print(("ok    " if ok else "FAIL  ") + name + ("" if ok else "  " + detail))
        if not ok:
            fails.append(name)

    for i, (c, r) in enumerate(zip(sealed_cases, got["sealed"])):
        key, pn, tn = bytes.fromhex(c["key"]), bytes.fromhex(c["phoneNonce"]), bytes.fromhex(c["tvNonce"])
        keys = L.SessionKeys(key, pn, tn)
        tag = "sealed[%d] " % i
        check(tag + "key id", r["keyId"] == L.key_id(key), r["keyId"])
        check(tag + "session keys", (r["enc"], r["mac"], r["iv"]) == (keys.enc.hex(), keys.mac.hex(), keys.iv.hex()))
        check(tag + "tv iv", r["tvIv"] == L.tv_iv(keys, L.FROM_TV, c["tvSeq"]).hex())
        expect = L.seal(keys, L.FROM_TV, c["tvSeq"], c["tvPlain"].encode(), L.tv_iv(keys, L.FROM_TV, c["tvSeq"])).hex()
        check(tag + "tv frame sealed", r["tvSealed"] == expect, r["tvSealed"][:40])
        check(tag + "tv frame opens on the phone",
              L.open_sealed(keys, L.FROM_TV, c["tvSeq"], bytes.fromhex(r["tvSealed"])) == c["tvPlain"].encode())
        check(tag + "phone frame opened", r["phoneOpened"] == c["phonePlain"], str(r["phoneOpened"])[:60])
        check(tag + "replay/direction/tamper refused", r["replayRefused"] and r["directionRefused"] and r["tamperRefused"])
        h = L.read_hello(r["helloText"])
        check(tag + "sealed_hello written", h is not None and h[0] == L.key_id(key) and h[1] == tn, r["helloText"])
        check(tag + "sealed_hello read", r["phoneHello"] == {"keyId": L.key_id(key), "nonce": c["phoneNonce"]}, str(r["phoneHello"]))
        if i == 0:
            check("kotlin vector: key id", r["keyId"] == KT_KEY_ID)
            check("kotlin vector: enc/mac/iv keys", (r["enc"], r["mac"], r["iv"]) == (KT_ENC, KT_MAC, KT_IVK))
            check("kotlin vector: roku seals ping", r["tvSealed"] == KT_TV_PING, r["tvSealed"])
            check("kotlin vector: opens phone pong", r["phoneOpened"] == '{"type":"pong","v":2}')
    expect_keys = [KT_KEY, KT_KEY, KT_KEY, None, None, None]
    for k, e in zip(got["keys"], expect_keys):
        check("parse key %r" % k["text"], k["parsed"] == e, str(k["parsed"]))
        check("base32", k["base32"] == "AAAQEAYEAUDAOCAJBIFQYDIOB4", k["base32"])
    for u, r in zip(servers, got["links"]):
        check("server id %s" % u, r["id"] == L.server_id_for(u) and r["back"] == u.strip().rstrip("/"), str(r))
    check("random bytes", got["random"]["count"] == 16 and got["random"]["differs"])
    check("servers match", got["match"]["sameId"] and got["match"]["sameIdentity"] and not got["match"]["different"], str(got["match"]))
    check("frames across split reads", got["frames"] == ["abc", "de"], str(got["frames"]))
    check("frame over 1 MiB refused", got["tooBigRefused"])

    inst = "Siku-0123abcd._silocast-roku._tcp.local"
    m = got["mdns"]
    if m[0]:
        flags, recs = dns_parse(bytes.fromhex(m[0]))
        types = {(n, t) for n, t, _, _, _ in recs}
        txt = next((v for n, t, _, _, v in recs if t == 16), [])
        srv = next((v for n, t, _, _, v in recs if t == 33), None)
        check("mdns PTR answer + SRV/TXT/A", flags & 0x8400 == 0x8400 and ("_silocast-roku._tcp.local", 12) in types
              and (inst, 33) in types and (inst, 16) in types and ("siku-0123abcd.local", 1) in types, str(recs))
        check("mdns SRV port/target", srv == (52817, "siku-0123abcd.local"), str(srv))
        check("mdns TXT", txt == ["v=2", "id=roku-1", "name=Den Roku", "sec=sealed", "kid=be45cb26"], str(txt))
    else:
        check("mdns PTR answer", False, "no answer")
    if m[1]:
        _, recs = dns_parse(bytes.fromhex(m[1]))
        check("mdns compressed SRV+TXT questions", {(n, t) for n, t, _, _, _ in recs} >= {(inst, 33)}, str(recs))
    else:
        check("mdns compressed SRV question", False, "no answer")
    check("mdns A answer", m[2] is not None and any(t == 1 and v == "192.168.1.20" for _, t, _, _, v in dns_parse(bytes.fromhex(m[2]))[1]))
    check("mdns services meta query", m[3] is not None and any(v == "_silocast-roku._tcp.local" for _, t, _, _, v in dns_parse(bytes.fromhex(m[3]))[1]))
    check("mdns ignores other types", m[4] is None)
    _, recs = dns_parse(bytes.fromhex(got["announce"]))
    check("mdns announcement", any(t == 33 and v == (52819, "siku-0123abcd.local") for _, t, _, _, v in recs), str(recs))

    print("%d failure(s)" % len(fails))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
