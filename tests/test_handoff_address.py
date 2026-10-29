# SPDX-License-Identifier: AGPL-3.0-or-later
"""Where a phone's handoff runs (Silo Android #716, components/remote/HandoffAddress.brs).

Mirrors silo-android RemotePlaybackServerAddressTest: a Roku signed in over the LAN keeps using
the LAN when a phone on the server's public address hands it a profile; the handoff runs at the
first address that reports the phone's deployment identity from here.
"""
import unittest

from brs import check_cases

FILES = ["components/remote/HandoffAddress.brs", "components/lan/LanBytes.brs", "components/common/Utils.brs",
         "tests/handoff_io.brs"]

IDENTITY = "deployment-1"
PUBLIC = "https://media.example.test"
LAN = "http://192.168.1.20:8090"
TAILNET = "https://silo.tailnet.test"
OWN = {"serverUrl": LAN, "serverId": IDENTITY}


def ident(i=IDENTITY):
    return {"state": "identity", "id": i}


def offer(identity=IDENTITY, endpoints=None, url=PUBLIC):
    o = {"requestId": "request", "serverURL": url, "profileId": "profile-1", "serverName": "Home"}
    if identity is not None:
        o["serverIdentity"] = identity
    if endpoints:
        o["serverEndpoints"] = [{"url": u, "kind": "public"} for u in endpoints]
    return o


def choose(name, offer_, answers, own=None, remembered=None, final=True, expect=None):
    return (name, "HandoffIo_choose", [offer_, own, remembered or [], answers, final], expect)


def picks(url, kind=None):
    return lambda r: r["done"] and r["url"] == url and (kind is None or r["kind"] == kind)


def fails(why):
    return lambda r: r["done"] and r["url"] == "" and r["failure"] == why


class Choice(unittest.TestCase):
    def test_android_cases(self):
        many_unapproved = ["http://10.0.0.%d:8090" % i for i in range(1, 7)]
        check_cases(self, FILES, [
            choose("the Roku's own LAN address is used for the phone's server", offer(),
                   {LAN: ident(), PUBLIC: ident()}, own=OWN, expect=picks(LAN, "own")),
            choose("the phone's address when the Roku's own is unreachable", offer(),
                   {PUBLIC: ident()}, own=OWN, expect=picks(PUBLIC, "phone")),
            choose("a saved address now serving another server is skipped", offer(),
                   {LAN: ident("other-deployment"), PUBLIC: ident()}, own={"serverUrl": LAN, "serverId": ""},
                   expect=picks(PUBLIC, "phone")),
            choose("another server at the phone's address ends the handoff", offer(endpoints=[TAILNET]),
                   {PUBLIC: ident("other-deployment"), TAILNET: ident()}, expect=fails("mismatch")),
            choose("... even when the Roku saved that address", offer(endpoints=[TAILNET]),
                   {PUBLIC: ident("other-deployment"), TAILNET: ident()}, own={"serverUrl": PUBLIC, "serverId": ""},
                   expect=fails("mismatch")),
            choose("the endpoint cap counts only addresses the Roku may probe",
                   offer(endpoints=[PUBLIC] + many_unapproved + [TAILNET]), {TAILNET: ident()},
                   expect=picks(TAILNET, "endpoint")),
            choose("an offered address is tried when neither the Roku's nor the phone's answers",
                   offer(endpoints=[TAILNET]), {TAILNET: ident()}, expect=picks(TAILNET, "endpoint")),
            choose("an unapproved plain-HTTP address is never probed", offer(endpoints=[LAN]), {LAN: ident()},
                   expect=lambda r: r["failure"] == "unreachable" and LAN not in r["probed"]),
            choose("a plain-HTTP endpoint at a saved origin is approved", offer(endpoints=[LAN + "/silo"]),
                   {LAN + "/silo": ident()}, remembered=[{"url": LAN, "id": "other-deployment"}],
                   expect=picks(LAN + "/silo", "endpoint")),
            choose("an offer without an identity uses the phone's address unprobed", offer(identity=None), {},
                   own=OWN, expect=lambda r: r["url"] == PUBLIC and r["probed"] == []),
            choose("a blank identity counts as none", offer(identity="  "), {}, own=OWN,
                   expect=lambda r: r["url"] == PUBLIC and r["probed"] == []),
            choose("stale saved addresses: nothing is decided while they are out", offer(),
                   {PUBLIC: ident()}, remembered=[{"url": "https://old-1.example.test", "id": IDENTITY},
                                                  {"url": "https://old-2.example.test", "id": IDENTITY}],
                   final=False, expect=lambda r: not r["done"]),
            choose("... and the budget's end counts them unreachable at once", offer(),
                   {PUBLIC: ident()}, remembered=[{"url": "https://old-1.example.test", "id": IDENTITY},
                                                  {"url": "https://old-2.example.test", "id": IDENTITY}],
                   expect=picks(PUBLIC, "phone")),
            choose("a later answer cannot win over an earlier unanswered one", offer(endpoints=[TAILNET]),
                   {TAILNET: ident()}, own=OWN, final=False, expect=lambda r: not r["done"]),
            choose("an offer probes a bounded number of addresses",
                   offer(endpoints=["https://e%d.example.test" % i for i in range(1, 21)]), {},
                   expect=lambda r: r["failure"] == "unreachable" and len(r["probed"]) == 7),
            choose("a server that can't say who it is: trusted only at the phone's address", offer(),
                   {LAN: {"state": "unsupported"}, PUBLIC: {"state": "unsupported"}}, own=OWN,
                   expect=picks(PUBLIC, "phone")),
            choose("nothing answers", offer(), {}, own=OWN, expect=fails("unreachable")),
            choose("an own address recorded as another deployment is never tried", offer(),
                   {PUBLIC: ident()}, own={"serverUrl": LAN, "serverId": "other-deployment"},
                   expect=lambda r: r["url"] == PUBLIC and LAN not in r["probed"]),
        ])

    def test_policy(self):
        entries = [
            {"url": "https://elsewhere.test", "id": "other-deployment"},
            {"url": "https://unverified.test", "id": ""},
            {"url": "https://recorded.test", "id": IDENTITY},
            {"url": LAN, "id": ""},
        ]
        check_cases(self, FILES, [
            ("recorded matches, then unverified (active first), never another deployment", "HandoffAddr_savedUrls",
             [entries, LAN, IDENTITY], ["https://recorded.test", LAN, "https://unverified.test"]),
            ("another deployment being active hides no unverified server", "HandoffAddr_savedUrls",
             [entries, "https://elsewhere.test", IDENTITY], ["https://recorded.test", "https://unverified.test", LAN]),
            ("at most six saved addresses", "HandoffAddr_savedUrls",
             [[{"url": "https://s%d.test" % i, "id": ""} for i in range(10)], "", IDENTITY], lambda v: len(v) == 6),
            ("candidates put the Roku's address first and drop repeats", "HandoffAddr_candidates",
             [[LAN + "/"], PUBLIC, [PUBLIC, TAILNET, " %s " % LAN], {"http://192.168.1.20:8090": True}],
             [{"url": LAN, "kind": "own"}, {"url": PUBLIC, "kind": "phone"}, {"url": TAILNET, "kind": "endpoint"}]),
            ("the phone's own plain-HTTP address keeps its old treatment", "HandoffAddr_candidates",
             [[], "http://phone.lan:8090", [], {}], [{"url": "http://phone.lan:8090", "kind": "phone"}]),
            ("a long endpoint list is read only so far", "HandoffAddr_endpoints",
             [offer(endpoints=["http://10.0.%d.%d:8090" % (i // 256, i % 256) for i in range(1, 1001)])],
             lambda v: len(v) == 24),
            ("malformed endpoints are skipped", "HandoffAddr_endpoints",
             [{"serverEndpoints": [{"url": 5}, "x", {"kind": "public"}, {"url": TAILNET, "kind": "provider", "provider": "tailscale"}]}],
             ["", "", "", TAILNET]),
            ("endpoints missing", "HandoffAddr_endpoints", [{"serverURL": PUBLIC}], []),
            ("identity answer", "HandoffAddr_classify", [{"ok": True, "status": 200, "data": {"server_id": "abc-1"}}],
             {"state": "identity", "id": "abc-1"}),
            ("no answer", "HandoffAddr_classify", [{"ok": False, "status": 0}], {"state": "unreachable"}),
            ("gateway error", "HandoffAddr_classify", [{"ok": False, "status": 502}], {"state": "unreachable"}),
            ("an older server (404)", "HandoffAddr_classify", [{"ok": False, "status": 404}], {"state": "unsupported"}),
            ("a malformed id", "HandoffAddr_classify", [{"ok": True, "status": 200, "data": {"server_id": "a b"}}],
             {"state": "unsupported"}),
            ("probes fit the budget, which fits the phone's 15 s wait", "HandoffAddr_budgetSeconds", [],
             lambda v: 6 <= v <= 10),
            ("one probe fits the budget", "HandoffAddr_probeTimeout", [], lambda v: v <= 8),
        ])


if __name__ == "__main__":
    unittest.main()
