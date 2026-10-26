# SPDX-License-Identifier: AGPL-3.0-or-later
"""Trailer_entries: the "Trailers & More" rail (port of Android's TrailerRail.kt)."""
import unittest

from brs import check_cases

FILES = ["components/common/Trailers.brs", "components/common/Utils.brs", "components/common/Session.brs"]
G = {"global": {"session": {"serverOrigin": "http://silo.example:8097", "serverUrl": "http://silo.example:8097"}}}


def keys(v):
    return [e["key"] for e in v]


class Trailers(unittest.TestCase):
    def test_entries(self):
        item = {
            "extras": [
                {"content_id": "extra:1", "kind": "behind_the_scenes", "title": "", "duration_seconds": 151, "still_url": "/img/1.jpg"},
                {"content_id": "extra:2", "kind": "featurette", "title": "Making Of", "duration_seconds": "3723"},
                {"content_id": "extra:1", "kind": "trailer", "title": "Duplicate"},
                {"content_id": "", "kind": "trailer"},
                "not an object",
            ],
            "videos": [
                {"site": "YouTube", "site_key": "abc123", "kind": "trailer", "name": "Official Trailer"},
                {"site": "vimeo", "site_key": "v1", "kind": "trailer", "name": "Vimeo"},
                {"site": "youtube", "site_key": "  ", "kind": "teaser"},
                {"site": "youtube", "site_key": "abc123", "kind": "teaser", "name": "Duplicate"},
                {"site": "youtube", "site_key": "zz9", "kind": "fan_made_clip", "name": ""},
            ],
        }
        r = check_cases(self, FILES, [
            ("order and de-duplication", "Trailer_entries", [item], lambda v: keys(v) == [
                "local:extra:1", "local:extra:2", "remote:youtube:abc123", "remote:youtube:zz9"], G),
            ("null item", "Trailer_entries", [None], [], G),
            ("no lists", "Trailer_entries", [{"title": "x"}], [], G),
            ("lists of the wrong type", "Trailer_entries", [{"extras": {"a": 1}, "videos": "x"}], [], G),
            ("numeric content id", "Trailer_entries", [{"extras": [{"content_id": 77, "kind": "trailer"}]}],
             lambda v: keys(v) == ["local:77"], G),
            ("kind label", "Trailer_kindLabel", ["behind-the-scenes"], "Behind the Scenes"),
            ("unknown kind label", "Trailer_kindLabel", ["fan_made_clip"], "Fan Made Clip"),
            ("empty kind label", "Trailer_kindLabel", [None], "Extra"),
            ("duration m:ss", "Trailer_durationLabel", [151], "2:31"),
            ("duration h:mm:ss from a string", "Trailer_durationLabel", ["3723"], "1:02:03"),
            ("no duration", "Trailer_durationLabel", [0], ""),
        ])
        first = r[0]["value"]
        self.assertEqual(first[0]["title"], "Behind the Scenes")       # untitled extra -> its kind
        self.assertEqual(first[0]["subtitle"], "2:31")                  # kind not repeated
        self.assertEqual(first[0]["thumbUrl"], "http://silo.example:8097/img/1.jpg")
        self.assertTrue(first[0]["isLocal"])
        self.assertEqual(first[1]["subtitle"], "Featurette · 1:02:03")
        self.assertEqual(first[2]["thumbUrl"], "https://i.ytimg.com/vi/abc123/hqdefault.jpg")
        self.assertEqual(first[2]["videoId"], "abc123")
        self.assertFalse(first[2]["isLocal"])
        self.assertEqual(first[3]["title"], "Fan Made Clip")


if __name__ == "__main__":
    unittest.main()
