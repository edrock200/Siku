# SPDX-License-Identifier: AGPL-3.0-or-later
"""Saved servers, each keeping its own sign-in (components/common/Session.brs): the list after a
save, the registry budget, removal and the session a saved entry restores (Android TV's
ServerRegistry; silo-roku source/storage/registry.bs)."""
import json
import unittest

from brs import check_cases

FILES = ["components/common/Session.brs", "components/common/Utils.brs"]
A = "https://a.example"
B = "http://b.local:8090"
C = "https://c.example"


def session(url, token="acc-1", profile="p1", name="", sid=""):
    return {"serverUrl": url, "serverOrigin": url, "serverName": name, "serverId": sid, "accessToken": token,
            "refreshToken": "ref" if token else "", "expiresAt": 100, "user": {"id": "u1"} if token else {},
            "profileId": profile, "profileToken": "", "profileName": "Laura", "profileAvatar": "", "deviceId": "dev"}


def lower(v):
    """brs-cli keeps dot-assigned keys lower-case; compare case-insensitively."""
    if isinstance(v, dict):
        return {k.lower(): lower(x) for k, x in v.items()}
    if isinstance(v, list):
        return [lower(x) for x in v]
    return v


def urls(v):
    return [e["url"] for e in v]


def stored(v, url):
    for e in lower(v):
        if e["url"] == url:
            return e.get("session")
    return "missing"


class Next(unittest.TestCase):
    def test_list(self):
        old = [{"url": A, "name": "A", "id": "a"}, {"url": B, "name": "B", "id": ""}]
        f = "Session_serversNext"
        check_cases(self, FILES, [
            ("switching stashes the old server's sign-in", f, [old, session(A), session(B, token="acc-b")],
             lambda v: urls(v) == [B, A] and stored(v, A)["accesstoken"] == "acc-1" and stored(v, A)["profileid"] == "p1"),
            ("the active server keeps no copy", f, [old, session(A), session(B, token="acc-b")], lambda v: stored(v, B) is None),
            ("a refresh on the same server stashes nothing", f, [old, session(A), session(A, token="acc-2")],
             lambda v: urls(v) == [A, B] and stored(v, A) is None),
            ("a signed-out server stores no sign-in", f, [old, session(A, token=""), session(B)], lambda v: stored(v, A) is None),
            ("Change server (no server) keeps the old sign-in", f, [old, session(A), session("")],
             lambda v: urls(v) == [A, B] and stored(v, A)["accesstoken"] == "acc-1"),
            ("a removed server is not added back", f, [[{"url": B}], session(A), session(B)], lambda v: urls(v) == [B]),
            ("a new server goes first", f, [old, session(A), session(C, name="C")], lambda v: urls(v) == [C, A, B] and v[0]["name"] == "C"),
            ("older entries read as signed out", f, [old, None, session(A)], lambda v: stored(v, B) is None),
            ("keeps other stored sign-ins", f, [[{"url": A}, {"url": B, "session": {"accessToken": "acc-b"}}], session(A), session(C)],
             lambda v: stored(v, B) is not None and stored(v, B) != "missing"),
            ("at most six", f, [[{"url": "https://s%d.example" % i} for i in range(9)], None, session(C)], lambda v: len(v) == 6 and v[0]["url"] == C),
            ("no tokens in names", f, [old, session(A), session(B)], lambda v: "acc" not in json.dumps([e.get("name") for e in v])),
        ])

    def test_budget(self):
        big = "x" * 3000
        many = [{"url": "https://s%d.example" % i, "session": {"accessToken": big}} for i in range(5)]
        check_cases(self, FILES, [
            ("least recently used sign-ins go first", "Session_serversNext", [many, None, session(C)],
             lambda v: len(json.dumps(v)) <= 8200 and len(v) == 6 and stored(v, "https://s0.example") is not None
             and stored(v, "https://s4.example") is None),
        ])

    def test_restore(self):
        e = {"url": B, "name": "Den", "id": "srv-b", "session": lower({"accessToken": "acc-b", "refreshToken": "ref-b", "expiresAt": 5,
                                                                      "user": {"id": "u2"}, "profileId": "p-sam", "profileToken": "pt", "profileName": "Sam"})}
        f = "Session_fromEntry"
        check_cases(self, FILES, [
            ("restores the sign-in and profile", f, [e, "dev", False],
             lambda v: lower(v)["accesstoken"] == "acc-b" and lower(v)["profileid"] == "p-sam" and lower(v)["serverurl"] == B
             and lower(v)["serverorigin"] == B and lower(v)["deviceid"] == "dev" and lower(v)["serverid"] == "srv-b"),
            ("Profile Selection asks: no profile", f, [e, "dev", True], lambda v: lower(v)["profileid"] == "" and lower(v)["profiletoken"] == ""
             and lower(v)["accesstoken"] == "acc-b"),
            ("an older entry is signed out", f, [{"url": A, "name": "A"}, "dev", False], lambda v: lower(v)["accesstoken"] == "" and lower(v)["serverurl"] == A),
            ("without", "Session_serversWithout", [[{"url": A}, {"url": B}], A], [{"url": B}]),
            ("signed in entry", "Session_entrySignedIn", [e], True),
            ("signed out entry", "Session_entrySignedIn", [{"url": A}], False),
        ])


if __name__ == "__main__":
    unittest.main()
