# SPDX-License-Identifier: AGPL-3.0-or-later
"""Reference implementation of the LAN protocols Silo's phone app speaks to a Roku.

Used by tools/silo_phone.py (a stand-in for the Android phone) and tools/lan_vectors.py (checks
Siku's BrightScript against the phone's own test vectors). Ported from silo-android FETCH_HEAD
88db96c: common/lan/SiloCastSealed.kt, common/cast/SiloCastPairingLink.kt,
shared/.../pairing/PairingFrame.kt. Needs the `cryptography` package for AES.
"""
import base64
import hashlib
import hmac
import json
import os
import socket
import struct
import urllib.parse

from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

FROM_PHONE = 1
FROM_TV = 2
LABEL = b"silo-cast-sealed-1"
BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
MAX_FRAME = 1 << 20

CAST_TYPE = "_silocast-roku._tcp"
PAIR_TYPE = "_silopair-roku._tcp"


# ---------- framing ----------

def frame(payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + payload


class FrameReader:
    def __init__(self, sock):
        self.sock = sock
        self.buf = b""

    def read(self, timeout=10.0):
        """The next frame payload, or None when the peer closed."""
        self.sock.settimeout(timeout)
        while True:
            if len(self.buf) >= 4:
                n = struct.unpack(">I", self.buf[:4])[0]
                if n > MAX_FRAME:
                    raise IOError("frame too large: %d" % n)
                if len(self.buf) >= 4 + n:
                    out = self.buf[4:4 + n]
                    self.buf = self.buf[4 + n:]
                    return out
            chunk = self.sock.recv(65536)
            if not chunk:
                return None
            self.buf += chunk


# ---------- sealed ----------

def key_id(key: bytes) -> str:
    return hashlib.sha256(key).digest()[:4].hex()


def _hmac(key, msg):
    return hmac.new(key, msg, hashlib.sha256).digest()


class SessionKeys:
    def __init__(self, key, phone_nonce, tv_nonce):
        prk = _hmac(phone_nonce + tv_nonce, key)
        def expand(purpose):
            return _hmac(prk, LABEL + b" " + purpose.encode() + b"\x01")
        self.enc = expand("enc")[:16]
        self.mac = expand("mac")
        self.iv = expand("iv")[:16]


def tv_iv(keys, direction, seq):
    block = bytes([direction]) + seq.to_bytes(8, "big") + bytes(7)
    e = Cipher(algorithms.AES(keys.iv), modes.ECB()).encryptor()
    return e.update(block) + e.finalize()


def seal(keys, direction, seq, plaintext: bytes, iv: bytes = None) -> bytes:
    if iv is None:
        iv = os.urandom(16)
    p = padding.PKCS7(128).padder()
    data = p.update(plaintext) + p.finalize()
    e = Cipher(algorithms.AES(keys.enc), modes.CBC(iv)).encryptor()
    signed = seq.to_bytes(8, "big") + iv + e.update(data) + e.finalize()
    return signed + _hmac(keys.mac, LABEL + bytes([direction]) + signed)


def open_sealed(keys, direction, expected_seq, body: bytes):
    if len(body) < 8 + 16 + 16 + 32:
        return None
    signed, tag = body[:-32], body[-32:]
    if not hmac.compare_digest(_hmac(keys.mac, LABEL + bytes([direction]) + signed), tag):
        return None
    if signed[:8] != expected_seq.to_bytes(8, "big"):
        return None
    d = Cipher(algorithms.AES(keys.enc), modes.CBC(signed[8:24])).decryptor()
    try:
        data = d.update(signed[24:]) + d.finalize()
        u = padding.PKCS7(128).unpadder()
        return u.update(data) + u.finalize()
    except ValueError:
        return None


def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def from_b64url(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def hello_text(kid: str, nonce: bytes) -> str:
    return json.dumps({"type": "sealed_hello", "v": 1, "keyId": kid, "nonce": b64url(nonce)}, separators=(",", ":"))


def read_hello(text: str):
    try:
        f = json.loads(text)
    except ValueError:
        return None
    if not isinstance(f, dict) or f.get("type") != "sealed_hello":
        return None
    kid = str(f.get("keyId", "")).lower()
    try:
        nonce = from_b64url(f.get("nonce", ""))
    except Exception:
        return None
    if len(kid) != 8 or len(nonce) != 16:
        return None
    return kid, nonce


def base32(key: bytes) -> str:
    out, bits, value = "", 0, 0
    for byte in key:
        value = (value << 8) | byte
        bits += 8
        while bits >= 5:
            bits -= 5
            out += BASE32[(value >> bits) & 31]
    if bits:
        out += BASE32[(value << (5 - bits)) & 31]
    return out


def parse_key(text: str):
    cleaned = "".join(c for c in text if not c.isspace() and c not in "-=")
    if len(cleaned) == 32 and all(c in "0123456789abcdefABCDEF" for c in cleaned):
        return bytes.fromhex(cleaned)
    bits, value, out = 0, 0, bytearray()
    for c in cleaned.upper():
        d = BASE32.find(c)
        if d < 0:
            return None
        value = (value << 5) | d
        bits += 5
        if bits >= 8:
            bits -= 8
            out.append((value >> bits) & 0xFF)
    return bytes(out) if len(out) == 16 and bits < 5 else None


def parse_pairing_link(text: str):
    """silo://cast?v=2&host=..&port=..&id=..&name=..&server=..&security=plain|sealed[&key=..]"""
    if not text.lower().startswith("silo://cast?"):
        return None
    q = dict(urllib.parse.parse_qsl(text.split("?", 1)[1].split("#")[0]))
    if q.get("v") != "2":
        return None
    sec = (q.get("security") or "plain").lower()
    key = parse_key(q["key"]) if sec == "sealed" and q.get("key") else None
    if sec == "sealed" and key is None:
        return None
    return {"host": q.get("host"), "port": int(q.get("port", "0")), "id": q.get("id"), "name": q.get("name", "Roku"),
            "server": q.get("server"), "security": sec, "key": key}


def server_id_for(url: str) -> str:
    """The phone's registry key for a server URL (AndroidServerRegistry.idFor)."""
    return b64url(url.strip().rstrip("/").encode())


# ---------- connections ----------

class PlainConnection:
    def __init__(self, sock):
        self.sock = sock
        self.reader = FrameReader(sock)

    def send(self, obj):
        data = obj if isinstance(obj, bytes) else json.dumps(obj, separators=(",", ":")).encode()
        self.sock.sendall(frame(data))

    def recv(self, timeout=10.0):
        p = self.reader.read(timeout)
        return None if p is None else json.loads(p.decode())

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


class SealedConnection(PlainConnection):
    def __init__(self, sock, keys):
        super().__init__(sock)
        self.keys = keys
        self.send_seq = 0
        self.recv_seq = 0

    def send(self, obj):
        data = obj if isinstance(obj, bytes) else json.dumps(obj, separators=(",", ":")).encode()
        self.sock.sendall(frame(seal(self.keys, FROM_PHONE, self.send_seq, data)))
        self.send_seq += 1

    def recv(self, timeout=10.0):
        body = self.reader.read(timeout)
        if body is None:
            return None
        opened = open_sealed(self.keys, FROM_TV, self.recv_seq, body)
        if opened is None:
            raise IOError("a sealed frame from the TV did not open")
        self.recv_seq += 1
        return json.loads(opened.decode())


class PairingRefused(IOError):
    pass


def dial(host, port, key=None, timeout=10.0):
    sock = socket.create_connection((host, port), timeout=timeout)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    plain = PlainConnection(sock)
    if key is None:
        return plain
    kid = key_id(key)
    nonce = os.urandom(16)
    plain.send(hello_text(kid, nonce).encode())
    reply = plain.reader.read(timeout)
    if reply is None:
        plain.close()
        raise IOError("the TV closed the connection during pairing")
    hello = read_hello(reply.decode())
    if hello is None or hello[0] != kid:
        plain.close()
        raise PairingRefused("the TV refused the pairing key: %s" % reply.decode()[:200])
    sealed = SealedConnection(sock, SessionKeys(key, nonce, hello[1]))
    # The TV's first sealed frame can arrive in the same read as its sealed_hello: keep the bytes.
    sealed.reader = plain.reader
    return sealed


# ---------- DNS-SD for Silo servers (_silo._tcp) ----------
# Silo server docs/architecture/server-discovery.md: instance = branding server name, host
# silo-<8 of id>-<6 hex>.local, SRV port = the API port (plain HTTP), TXT v=1 and id=<server_id>.

SILO_TYPE = "_silo._tcp.local"


def dns_message(records, flags=0x8400, questions=(), compress=True):
    """A DNS message. records: (name, rtype, ttl, rdata) with rdata ("ptr", target),
    ("srv", port, target[, priority, weight]), ("txt", [entries as str or bytes]), ("a", "1.2.3.4") or
    ("raw", bytes). questions: (name, qtype[, qclass]). Names are compressed against earlier ones."""
    buf = bytearray(12)
    table = {}

    def put_name(name):
        labels = [l for l in name.rstrip(".").split(".") if l]
        for i in range(len(labels)):
            suffix = ".".join(labels[i:]).lower()
            if compress and suffix in table:
                buf.extend(struct.pack(">H", 0xC000 | table[suffix]))
                return
            if len(buf) < 0x3FFF:
                table[suffix] = len(buf)
            lb = labels[i].encode()
            buf.append(len(lb))
            buf.extend(lb)
        buf.append(0)

    for q in questions:
        put_name(q[0])
        buf.extend(struct.pack(">HH", q[1], q[2] if len(q) > 2 else 1))
    for name, rtype, ttl, rdata in records:
        put_name(name)
        cls = 0x8001 if rtype in (1, 16, 33) else 1
        buf.extend(struct.pack(">HHI", rtype, cls, ttl))
        at = len(buf)
        buf.extend(b"\0\0")
        kind = rdata[0]
        if kind == "ptr":
            put_name(rdata[1])
        elif kind == "srv":
            prio = rdata[3] if len(rdata) > 3 else 0
            weight = rdata[4] if len(rdata) > 4 else 0
            buf.extend(struct.pack(">HHH", prio, weight, rdata[1]))
            put_name(rdata[2])
        elif kind == "txt":
            for e in rdata[1]:
                eb = e if isinstance(e, bytes) else e.encode()
                buf.append(len(eb))
                buf.extend(eb)
        elif kind == "a":
            buf.extend(socket.inet_aton(rdata[1]))
        else:
            buf.extend(rdata[1])
        struct.pack_into(">H", buf, at, len(buf) - at - 2)
    struct.pack_into(">HHHHHH", buf, 0, 0, flags, len(questions), len(records), 0, 0)
    return bytes(buf)


def silo_records(name, server_id, address, port, host=None, ttl=120, txt=None):
    """The PTR/SRV/TXT/A records a Silo server announces (ttl 0 = goodbye)."""
    host = host or "silo-%s-0a0b0c.local" % "".join(c for c in server_id if c.isalnum())[:8].lower()
    inst = name + "." + SILO_TYPE
    entries = txt if txt is not None else ["v=1", "id=" + server_id]
    return [(SILO_TYPE, 12, 4500 if ttl else 0, ("ptr", inst)),
            (inst, 33, ttl, ("srv", port, host)),
            (inst, 16, 4500 if ttl else 0, ("txt", entries)),
            (host, 1, ttl, ("a", address))]
