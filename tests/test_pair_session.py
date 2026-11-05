# SPDX-License-Identifier: AGPL-3.0-or-later
"""Phone sign-in of several accounts in one phone session (Silo Android #810; adapted from
Silo-Server/silo-roku, AGPL-3.0, #38: storage.sessionSignIns / roomForSignIn, companionCapable):
the advertised limit, which pushes are refused, whether the registry keeps every account the
session signed in when one more arrives, the session binding's eligibility and encoding, and the
_silopair-roku._tcp TXT extras (components/remote/PairSession.brs, components/lan/LanBytes.brs)."""
import base64
import hashlib
import unittest

from brs import check_cases

FILES = ["components/remote/PairSession.brs", "components/common/Accounts.brs", "components/common/Session.brs",
         "components/common/Utils.brs"]
LAN = ["components/lan/LanBytes.brs", "components/common/Utils.brs", "tests/pair_io.brs"]
A = "https://a.example"
B = "http://b.local:8090"
NOW = 1800000000
BINDING = {"secret": "s" * 43, "binding": "b" * 43}


def session(aid, url=A, uid="u1", name="laura", token="acc-1"):
    return {"serverUrl": url, "serverOrigin": url, "serverName": "Home", "serverId": "srv", "accessToken": token,
            "refreshToken": "ref-" + token, "expiresAt": NOW + 3600, "user": {"id": uid, "username": name},
            "profileId": "", "profileToken": "", "profileName": "", "profileAvatar": "", "deviceId": "dev", "accountId": aid}


def entry(aid, url=A, uid="u1", used=100, token=None):
    e = {"id": aid, "url": url, "userid": uid, "username": "user-" + uid, "profiles": -1, "added": used, "used": used, "expired": False}
    if token:
        e["session"] = {"accessToken": token, "refreshToken": "ref", "expiresAt": NOW, "user": {"id": uid, "username": "user-" + uid},
                        "profileId": "", "profileToken": "", "profileName": "", "profileAvatar": "", "serverOrigin": url}
    return e


def b64url(raw):
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


class Limit(unittest.TestCase):
    def test_limit_and_refusals(self):
        f = "PairSession_refusal"
        check_cases(self, FILES, [
            ("lim is 6 (six saved servers, the budget at 1800 bytes a stored sign-in plus the open one)", "PairSession_limit", [], 6),
            ("the first push is never refused", f, ["setup", 0, 6, False], ""),
            ("a second account on the server screen", f, ["setup", 1, 6, False], ""),
            ("the sixth account still fits", f, ["setup", 5, 6, False], ""),
            ("past lim", f, ["setup", 6, 6, False], "limit_reached"),
            ("the sign-in screen signs in one account", f, ["login", 1, 6, False], "limit_reached"),
            ("a session that is ending", f, ["setup", 1, 6, True], "auth_failed"),
            ("an account counts once", "PairSession_note", [["a", "b"], "a"], ["a", "b"]),
            ("accounts keep the order they first signed in", "PairSession_note", [["a"], "b"], ["a", "b"]),
            ("several signed in", "PairSession_completedText", [2, "Home"], "2 accounts are signed in. Next, choose which one to open."),
            ("one signed in", "PairSession_completedText", [1, "Home"], "Signed in to Home. Taking you to your profiles…"),
        ])


class Room(unittest.TestCase):
    def test_room(self):
        f = "PairSession_room"
        servers = [{"url": A, "name": "Home", "id": "srv"}]
        two = [entry("a1", used=NOW - 60, token="acc-a1"), entry("a2", uid="u2", used=NOW - 30)]
        big = "x" * 1700
        # Four stored sign-ins of this session and the open fifth: about 9.6 KB once it is stored too.
        heavy = [entry("s%d" % i, uid="u%d" % i, used=NOW - 100 + i, token=big + str(i)) for i in range(4)]
        heavy.append(entry("cur", uid="u9", used=NOW - 10))
        cur = session("cur", uid="u9", token=big + "c")
        heavy_ids = ["s0", "s1", "s2", "s3", "cur"]
        # The same session with older accounts not of this session holding sign-ins: they go first.
        light = [entry("s%d" % i, uid="u%d" % i, used=NOW - 100 + i, token="acc-%d" % i) for i in range(3)]
        older = [entry("o%d" % i, uid="o%d" % i, used=10 + i, token=big) for i in range(4)]
        five = ["https://s%d.example" % i for i in range(5)]
        spread_servers = [{"url": u, "name": "S", "id": ""} for u in [A] + five]
        spread = [entry("p%d" % i, url=u, uid="p%d" % i, used=NOW - 50 + i, token="acc-p%d" % i) for i, u in enumerate(five)]
        spread.append(entry("cur", uid="u9", used=NOW - 10))
        spread_ids = ["p%d" % i for i in range(5)] + ["cur"]
        check_cases(self, FILES, [
            ("nothing signed in yet: always room", f, [[], [], None, [], A, "Home", "srv", NOW], True),
            ("a second sign-in beside a small first one", f, [two, servers, session("a2", uid="u2", token="acc-a2"), ["a1", "a2"], A, "Home", "srv", NOW], True),
            ("the budget would take a stored sign-in of this session", f, [heavy, servers, cur, heavy_ids, A, "Home", "srv", NOW], False),
            ("an earlier account of the session that already lost its sign-in", f, [two, servers, session("a2", uid="u2"), ["a1", "a2", "gone"], A, "Home", "srv", NOW], False),
            ("older accounts lose their sign-ins first", f,
             [light + older + [entry("cur", uid="u9", used=NOW - 10)], servers, session("cur", uid="u9"), ["s0", "s1", "s2", "cur"], A, "Home", "srv", NOW], True),
            ("a seventh server would push out the first one's server", f, [spread, spread_servers, session("cur", uid="u9"), spread_ids, "https://new.example", "New", "", NOW], False),
            ("another account on a server already saved", f, [spread, spread_servers, session("cur", uid="u9"), spread_ids, five[0], "S", "", NOW], True),
        ])


class Binding(unittest.TestCase):
    def test_eligibility(self):
        f = "PairSession_bindingFor"
        r = "PairSession_noBindingReason"
        yes = {"state": "available", "session_binding": True}
        check_cases(self, FILES, [
            ("https and session_binding: true", f, [A, yes, BINDING], BINDING),
            ("plain HTTP never gets it, even when the server takes it", f, [B, yes, BINDING], None),
            ("a capability without session_binding is no", f, [A, {"state": "available"}, BINDING], None),
            ("session_binding false", f, [A, {"session_binding": False}, BINDING], None),
            ("a string is not true", f, [A, {"session_binding": "true"}, BINDING], None),
            ("a capability that could not be read", f, [A, None, BINDING], None),
            ("no secret for this session", f, [A, yes, None], None),
            ("reason: http", r, [B, yes, BINDING], "http"),
            ("reason: unread", r, [A, None, BINDING], "capability_unread"),
            ("reason: not offered", r, [A, {"state": "available"}, BINDING], "no_session_binding"),
            ("reason: none when it went", r, [A, yes, BINDING], ""),
        ])

    def test_encoding(self):
        secret = bytes(range(32))
        want = {"secret": b64url(secret), "binding": b64url(hashlib.sha256(secret).digest())}
        res = check_cases(self, LAN, [
            ("binding is base64url(SHA-256(secret)), the secret base64url, no padding", "PairIo_binding", [secret.hex()], want),
            ("new secrets are 32 bytes and differ", "PairIo_secrets", [], {"a": 32, "b": 32, "differ": True}),
        ])
        self.assertEqual(len(res[0]["value"]["binding"]), 43)


class Txt(unittest.TestCase):
    def test_txt(self):
        f = "Lan_pairTxtExtra"
        check_cases(self, LAN, [
            ("server screen: acct=1 and lim", f, ["setup", "", 6], [["acct", "1"], ["lim", "6"]]),
            ("no lim when none is given", f, ["setup", "", 0], [["acct", "1"]]),
            ("sign-in screen: srv, no acct", f, ["login", "srv-1", 6], [["srv", "srv-1"]]),
            ("sign-in screen without an identity", f, ["login", "", 0], []),
        ])


if __name__ == "__main__":
    unittest.main()
