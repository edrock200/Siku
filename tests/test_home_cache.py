# SPDX-License-Identifier: AGPL-3.0-or-later
"""Home cache (components/common/HomeCache.brs): owner key, freshness, payload trimming and the
check of a stored file; Session_homeCachePurgeReason (Session.brs). Ideas from ManavA/silo-roku's
tests/test_home_cache*.py (AGPL-3.0)."""
import json
import os
import unittest

from brs import ROOT, check_cases

FILES = ["components/common/HomeCache.brs", "components/common/Utils.brs"]
SESSION_FILES = ["components/common/Session.brs", "components/common/Utils.brs"]
HASH = "a" * 64
NOW = 1_800_000_000

SESSION = {"serverUrl": "http://silo.example:8097", "serverId": "srv-1", "accessToken": "acc-secret",
           "refreshToken": "ref-secret", "profileToken": "ptok-secret", "user": {"id": "u1"}, "profileId": "p1"}

CARD = {
    "content_id": "movie:glass-city", "type": "movie", "title": "Glass City", "year": 2021,
    "poster_url": "https://s3.example/p.jpg?X-Amz-Signature=abc", "backdrop_url": "/api/v2/images/x?exp=1&sig=2",
    "logo_url": "/img/logo.png", "poster_thumbhash": "xyz", "poster_urls": ["a", "b"],
    "genres": ["Drama", "Crime", "Comedy"], "overview": "x" * 1000, "content_rating": "PG-13",
    "user_state": {"played": False, "favorite": True, "avatar_url": "/a.png", "nested": {"x": 1}},
    "user_data": {"position_seconds": 120, "duration_seconds": 5400},
    "overlay_summary": {"resolution": "2160p", "hdr": "dv", "audio": "atmos"},
    "group": {"name": "Saga", "item_count": 3, "poster_urls": ["u"]},
    "backdrop_is_episode_still": False, "cast": [{"name": "A", "photo_url": "/p"}], "stream_token": "t",
}


def no_secrets(v):
    text = json.dumps(v)
    return all(s not in text for s in ["http", "/img", "/api", "secret", "sig", "thumbhash", "photo_url", "token", "_url"])


class Owner(unittest.TestCase):
    def test_owner_source(self):
        check_cases(self, FILES, [
            ("server, account and profile", "HomeCache_ownerSource", [SESSION],
             lambda v: json.loads(v) == ["siku-home", SESSION["serverUrl"], "srv-1", "u1", "p1"]),
            ("never carries tokens", "HomeCache_ownerSource", [SESSION], lambda v: "secret" not in v),
            ("no profile yet", "HomeCache_ownerSource", [dict(SESSION, profileId="")], ""),
            ("signed out", "HomeCache_ownerSource", [dict(SESSION, accessToken="")], ""),
            ("no server", "HomeCache_ownerSource", [dict(SESSION, serverUrl="")], ""),
            ("a phone's temporary profile", "HomeCache_ownerSource", [dict(SESSION, temporary=True)], ""),
            ("temporary false still caches", "HomeCache_ownerSource", [dict(SESSION, temporary=False)], lambda v: v != ""),
            ("numeric user id", "HomeCache_ownerSource", [dict(SESSION, user={"id": 7})], lambda v: json.loads(v)[3] == "7"),
            ("not a session", "HomeCache_ownerSource", [None], ""),
        ])

    def test_file_names(self):
        check_cases(self, FILES, [
            ("file name", "HomeCache_fileName", [HASH], "siku-home-v1-" + HASH + ".json"),
            ("owned", "HomeCache_isOwnedName", ["siku-home-v1-" + HASH + ".json"], True),
            ("owned temp", "HomeCache_isOwnedName", ["siku-home-v1-" + HASH + ".json.0f8e2c1a-1b2c-4d5e-8f90-123456789abc.part"], True),
            ("bare temp", "HomeCache_isOwnedName", ["siku-home-v1-" + HASH + ".json.part"], False),
            ("foreign file", "HomeCache_isOwnedName", ["silo-home-v1-" + HASH + ".json"], False),
            ("short hash", "HomeCache_isOwnedName", ["siku-home-v1-abc.json"], False),
            ("path traversal", "HomeCache_isOwnedName", ["siku-home-v1-" + HASH + ".json/../x"], False),
        ])


class Freshness(unittest.TestCase):
    def test_freshness(self):
        check_cases(self, FILES, [
            ("just written", "HomeCache_freshness", [NOW - 5, NOW], "fresh"),
            ("23 hours", "HomeCache_freshness", [NOW - 23 * 3600, NOW], "fresh"),
            ("25 hours", "HomeCache_freshness", [NOW - 25 * 3600, NOW], "stale"),
            ("small clock skew", "HomeCache_freshness", [NOW + 60, NOW], "fresh"),
            ("clock moved back", "HomeCache_freshness", [NOW + 3600, NOW], "future"),
            ("string time", "HomeCache_freshness", [str(NOW), NOW], "stale"),
            ("missing", "HomeCache_freshness", [None, NOW], "stale"),
        ])


class Trimming(unittest.TestCase):
    def test_card(self):
        check_cases(self, FILES, [
            ("no URLs, tokens or thumbhashes", "HomeCache_trimCard", [CARD], no_secrets),
            ("keeps what cards draw", "HomeCache_trimCard", [CARD],
             lambda v: v["content_id"] == "movie:glass-city" and v["title"] == "Glass City" and v["year"] == 2021
             and v["content_rating"] == "PG-13" and v["type"] == "movie"),
            ("two genres", "HomeCache_trimCard", [CARD], lambda v: v["genres"] == ["Drama", "Crime"]),
            ("overview clipped", "HomeCache_trimCard", [CARD], lambda v: len(v["overview"]) == 150),
            ("nested objects keep scalars", "HomeCache_trimCard", [CARD],
             lambda v: v["user_state"] == {"played": False, "favorite": True}
             and v["user_data"]["position_seconds"] == 120 and v["overlay_summary"]["hdr"] == "dv"
             and v["group"] == {"name": "Saga", "item_count": 3}),
            ("spoiler flags kept", "HomeCache_trimCard", [CARD], lambda v: v["backdrop_is_episode_still"] is False),
            ("cast dropped", "HomeCache_trimCard", [CARD], lambda v: "cast" not in v),
            ("not a card", "HomeCache_trimCard", ["x"], None),
        ])

    def test_payload(self):
        section = {"id": "recent", "title": "Recently Added", "section_type": "recently_added", "featured": False,
                   "items": [CARD] * 40, "description_url": "/x", "total_count": 40}
        entries = [{"section": section, "rawItems": [CARD] * 40}] + [{"section": {"id": "s%d" % i}, "rawItems": []} for i in range(40)]
        check_cases(self, FILES, [
            ("bounded sections and items", "HomeCache_payload", [entries],
             lambda v: v["schema"] == 1 and len(v["sections"]) == 30 and len(v["sections"][0]["items"]) == 24),
            ("section metadata", "HomeCache_payload", [entries],
             lambda v: v["sections"][0]["id"] == "recent" and v["sections"][0]["section_type"] == "recently_added"
             and v["sections"][0]["total_count"] == 40 and "description_url" not in v["sections"][0]),
            ("nothing secret anywhere", "HomeCache_payload", [entries], no_secrets),
            ("falls back to inline items", "HomeCache_payload", [[{"section": section, "items": [CARD]}]],
             lambda v: len(v["sections"][0]["items"]) == 1),
            ("under the size limit", "HomeCache_payload", [entries], lambda v: len(json.dumps(v)) < 1048576),
        ])

    def test_full_home_fits(self):
        """A full Home (30 sections of 24 cards) fits the byte limit in English and in CJK text
        (3 bytes a character); the file is written and read back in UTF-8 bytes. One card is
        trimmed in brs-cli and the file is sized here (720 cards through brs-cli take minutes)."""
        cjk = dict(CARD, title="\u6620" * 40, series_title="\u6620" * 40, episode_title="\u6620" * 40,
                   overview="\u6620" * 1000)
        r = check_cases(self, FILES, [
            ("limit in bytes", "HomeCache_limits", [], lambda v: v["bytes"] == 1048576 and v["overview"] == 150),
            ("an English card", "HomeCache_trimCard", [CARD], lambda v: len(v["overview"]) == 150),
            ("a CJK card", "HomeCache_trimCard", [cjk], lambda v: len(v["overview"]) == 150),
        ])
        for label, card in (("English", r[1]["value"]), ("CJK", r[2]["value"])):
            snapshot = {"schema": 1, "owner": HASH, "savedAt": NOW,
                        "sections": [{"id": "s%d" % i, "title": "\u6620" * 30, "section_type": "custom", "items": [card] * 24}
                                     for i in range(30)]}
            size = len(json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
            self.assertLess(size, 1048576, "a full %s Home is %d bytes" % (label, size))

class Check(unittest.TestCase):
    def snap(self, **kw):
        base = {"schema": 1, "owner": HASH, "savedAt": NOW - 60, "sections": [{"id": "recent", "items": [{"title": "A"}]}]}
        base.update(kw)
        return base

    def test_check(self):
        check_cases(self, FILES, [
            ("hit", "HomeCache_check", [self.snap(), HASH, NOW],
             lambda v: v["status"] == "hit" and v["age"] == 60 and v["sections"][0]["id"] == "recent"),
            ("another owner", "HomeCache_check", [self.snap(owner="b" * 64), HASH, NOW], lambda v: v["status"] == "miss" and v["reason"] == "owner"),
            ("no owner asked", "HomeCache_check", [self.snap(owner=""), "", NOW], lambda v: v["status"] == "miss"),
            ("old schema", "HomeCache_check", [self.snap(schema=0), HASH, NOW], lambda v: v["reason"] == "schema"),
            ("schema as string", "HomeCache_check", [self.snap(schema="1"), HASH, NOW], lambda v: v["reason"] == "schema"),
            ("stale", "HomeCache_check", [self.snap(savedAt=NOW - 90000), HASH, NOW], lambda v: v["status"] == "stale"),
            ("future", "HomeCache_check", [self.snap(savedAt=NOW + 9000), HASH, NOW],
             lambda v: v["status"] == "stale" and v["reason"] == "future"),
            ("corrupt", "HomeCache_check", [None, HASH, NOW], lambda v: v["reason"] == "corrupt"),
            ("sections not a list", "HomeCache_check", [self.snap(sections={"a": 1}), HASH, NOW], lambda v: v["reason"] == "corrupt"),
            ("empty", "HomeCache_check", [self.snap(sections=[]), HASH, NOW], lambda v: v["reason"] == "empty"),
            ("items repaired", "HomeCache_check", [self.snap(sections=[{"id": "x", "items": "bad"}]), HASH, NOW],
             lambda v: v["status"] == "hit" and v["sections"][0]["items"] == []),
        ])


class Purge(unittest.TestCase):
    def test_reason(self):
        check_cases(self, SESSION_FILES, [
            ("token refresh keeps it", "Session_homeCachePurgeReason", [SESSION, dict(SESSION, accessToken="new")], ""),
            ("sign-out", "Session_homeCachePurgeReason", [SESSION, dict(SESSION, accessToken="", profileId="")], "sign-out"),
            ("server change", "Session_homeCachePurgeReason", [SESSION, dict(SESSION, serverUrl="http://other")], "server"),
            ("forget server", "Session_homeCachePurgeReason", [SESSION, {"serverUrl": "", "accessToken": ""}], "server"),
            ("another account", "Session_homeCachePurgeReason", [SESSION, dict(SESSION, user={"id": "u2"})], "account"),
            ("another profile", "Session_homeCachePurgeReason", [SESSION, dict(SESSION, profileId="p2")], "profile"),
            ("Who's Watching keeps it", "Session_homeCachePurgeReason", [SESSION, dict(SESSION, profileId="")], ""),
            ("first sign-in", "Session_homeCachePurgeReason", [None, SESSION], ""),
            ("was signed out", "Session_homeCachePurgeReason", [dict(SESSION, accessToken=""), SESSION], ""),
        ])

    def test_check_reads_the_published_session(self):
        """MainScene keeps the file of m.global.session's owner, so the purge is asked for only
        after Session_save has published the new session; the check compares against it."""
        g = {"global": {"session": dict(SESSION, profileId="p2"), "homeCachePurge": 0, "homeCachePurgeReason": ""}}
        same = {"global": {"session": dict(SESSION), "homeCachePurge": 0, "homeCachePurgeReason": ""}}
        check_cases(self, ["tests/session_io.brs"] + SESSION_FILES, [
            ("profile switch asks for a purge", "SessionIo_check", [SESSION], {"purge": 1, "reason": "profile"}, g),
            ("unchanged owner asks nothing", "SessionIo_check", [SESSION], {"purge": 0, "reason": ""}, same),
        ])

    def test_save_publishes_before_the_check(self):
        with open(os.path.join(ROOT, "components/common/Session.brs"), encoding="utf-8") as fh:
            src = fh.read()
        body = src[src.index("sub Session_save("):src.index("end sub", src.index("sub Session_save("))]
        self.assertLess(body.index("m.global.session = s"), body.index("Session_homeCacheCheck("))


if __name__ == "__main__":
    unittest.main()


IO_FILES = ["tests/home_cache_io.brs", "components/tasks/HomeCacheTask.brs", "components/common/HomeCache.brs",
            "components/common/Utils.brs"]
PAYLOAD = {"schema": 1, "sections": [{"id": "recent", "title": "Recently Added", "items": [{"content_id": "m1", "title": "A"}]}]}


def io(steps):
    return {"global": {"session": dict(SESSION)}}, steps


class FileIo(unittest.TestCase):
    """HomeCacheTask's read / write / purge against brs-cli's cachefs: (temp file, rename, misses)."""

    def run_io(self, name, steps, check):
        g, st = io(steps)
        check_cases(self, IO_FILES, [(name, "HomeCacheIo_run", [st], check, g)])

    def test_round_trip(self):
        self.run_io("write then read", [{"op": "read"}, {"op": "write", "payload": PAYLOAD}, {"op": "read"}, {"op": "list"}],
                    lambda v: v[0]["status"] == "miss" and v[0]["reason"] == "none" and v[1]["status"] == "written"
                    and v[2]["status"] == "hit" and len(v[3]["names"]) == 1 and v[3]["names"][0].endswith(".json"))

    def test_non_ascii_round_trip(self):
        """The write limit counts bytes as the read does: a Home whose characters are under the
        limit but whose UTF-8 bytes are over it is not written (it used to be, then refused)."""
        def payload(n):
            return {"schema": 1, "sections": [{"id": "s", "title": "x", "items": [{"title": "\u00e9" * n}]}]}
        self.run_io("non-ASCII Home caches", [{"op": "write", "payload": payload(1000)}, {"op": "read"}],
                    lambda v: v[0]["status"] == "written" and v[0]["bytes"] > 2000 and v[1]["status"] == "hit")
        self.run_io("bytes over, characters under", [{"op": "write", "payload": payload(600000)}, {"op": "list"}],
                    lambda v: v[0]["reason"] == "size" and v[1]["names"] == [])

    def test_corrupt_is_a_miss_and_deleted(self):
        self.run_io("corrupt", [{"op": "corrupt"}, {"op": "read"}, {"op": "list"}],
                    lambda v: v[1]["status"] == "miss" and v[1]["reason"] == "corrupt" and v[2]["names"] == [])

    def test_other_owners_are_removed(self):
        self.run_io("one owner at a time", [{"op": "foreign"}, {"op": "write", "payload": PAYLOAD}, {"op": "list"}],
                    lambda v: len(v[2]["names"]) == 2 and "other-app.json" in v[2]["names"]
                    and not any(n.startswith("siku-home-v1-bbbb") for n in v[2]["names"]))

    def test_purge(self):
        self.run_io("purge all", [{"op": "write", "payload": PAYLOAD}, {"op": "foreign"}, {"op": "purge"}, {"op": "list"}],
                    lambda v: v[2]["files"] == 2 and v[3]["names"] == ["other-app.json"])
        self.run_io("purge keeps the active owner", [{"op": "write", "payload": PAYLOAD}, {"op": "foreign"}, {"op": "purge", "keep": True}, {"op": "read"}],
                    lambda v: v[2]["files"] == 1 and v[3]["status"] == "hit")

    def test_session_changed_while_running(self):
        g = {"global": {"session": dict(SESSION)}}
        check_cases(self, IO_FILES, [("stale job dropped", "homeCacheCurrent", ['["siku-home","x"]'], False, g),
                                     ("current job", "homeCacheCurrent", [json.dumps(["siku-home", SESSION["serverUrl"], "srv-1", "u1", "p1"], separators=(",", ":"))], True, g)])

    def test_profile_switch(self):
        self.run_io("another profile misses", [{"op": "write", "payload": PAYLOAD}, {"op": "switch", "profileId": "p2"}, {"op": "read"}, {"op": "list"}],
                    lambda v: v[2]["status"] == "miss" and v[2]["reason"] == "none" and v[3]["names"] == [])
