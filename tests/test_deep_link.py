# SPDX-License-Identifier: AGPL-3.0-or-later
"""DeepLink.brs: Roku content deep links (certification 5.1 / 5.2). A movie or episode plays,
resuming where the profile left off; a series or season plays its next episode; bad links are
refused before any request."""
import unittest

from brs import check_cases

FILES = ["components/common/DeepLink.brs", "components/common/Utils.brs"]


def parsed(valid, cid="", mt="", kind="", reason=""):
    return {"valid": valid, "contentId": cid, "mediaType": mt, "kind": kind, "reason": reason}


class Parse(unittest.TestCase):
    def test_cases(self):
        p = "DeepLink_parse"
        check_cases(self, FILES, [
            ("an ordinary launch is no link", p, [{"source": "homescreen"}], None),
            ("a movie", p, [{"contentId": "movie:glass-city", "mediaType": "movie"}], parsed(True, "movie:glass-city", "movie", "video")),
            ("mediaType in any case", p, [{"contentId": "e1", "mediaType": "Episode"}], parsed(True, "e1", "episode", "video")),
            ("Roku's other video types", p, [{"contentId": "x", "mediaType": "shortFormVideo"}], parsed(True, "x", "shortformvideo", "video")),
            ("no mediaType resolves from the item", p, [{"contentId": "x"}], parsed(True, "x", "", "video")),
            ("music opens its page", p, [{"contentId": "a", "mediaType": "album"}], parsed(True, "a", "album", "audio")),
            ("live is refused", p, [{"contentId": "x", "mediaType": "live"}], parsed(False, reason="unsupported_media_type")),
            ("an empty id", p, [{"contentId": "  ", "mediaType": "movie"}], parsed(False, reason="missing_content_id")),
            ("a 256-character id", p, [{"contentId": "m" * 256, "mediaType": "movie"}], parsed(False, reason="content_id_too_long")),
            ("a 255-character id", p, [{"contentId": "m" * 255, "mediaType": "movie"}], lambda v: v["valid"]),
        ])


class Route(unittest.TestCase):
    def test_cases(self):
        r = "DeepLink_route"
        check_cases(self, FILES, [
            ("a movie plays", r, [{"content_id": "movie:a", "type": "movie", "title": "A"}], {"action": "play", "itemId": "movie:a", "title": "A"}),
            ("an episode plays", r, [{"content_id": "ep", "type": "episode", "title": "E"}], {"action": "play", "itemId": "ep", "title": "E"}),
            ("a series plays its next episode", r, [{"content_id": "series:o", "type": "series", "play_content_id": "ep2"}], {"action": "next", "itemId": "ep2"}),
            ("a season too", r, [{"content_id": "season:o-1", "type": "Season", "play_content_id": "ep3"}], {"action": "next", "itemId": "ep3"}),
            ("a series with nothing to play opens its page", r, [{"content_id": "series:o", "type": "series"}], {"action": "detail", "itemId": "series:o"}),
            ("an audiobook", r, [{"content_id": "b", "type": "audiobook"}], {"action": "audio", "itemId": "b", "itemType": "audiobook"}),
            ("no item", r, [None], {"action": "drop", "reason": "unavailable"}),
        ])

    def test_resume(self):
        f = "DeepLink_playerParams"
        check_cases(self, FILES, [
            ("resumes a started title", f, [{"content_id": "m", "title": "M", "user_data": {"position_seconds": 600, "duration_seconds": 6000}}],
             {"itemId": "m", "title": "M", "startPosition": 600.0}),
            ("numbers as strings", f, [{"content_id": "m", "title": "M", "user_data": {"position_seconds": "90", "duration_seconds": "6000"}}],
             {"itemId": "m", "title": "M", "startPosition": 90.0}),
            ("a finished title starts over", f, [{"content_id": "m", "title": "M", "user_data": {"position_seconds": 5998, "duration_seconds": 6000}}],
             {"itemId": "m", "title": "M"}),
            ("never started", f, [{"content_id": "m", "title": "M"}], {"itemId": "m", "title": "M"}),
        ])


if __name__ == "__main__":
    unittest.main()


class ProfileFor(unittest.TestCase):
    def test_cases(self):
        from brs import check_cases
        kids = {"id": "k", "is_child": True}
        pin = {"id": "p", "has_pin": True}
        laura = {"id": "l"}
        sam = {"id": "s"}
        check_cases(self, ["components/common/DeepLink.brs", "components/common/Utils.brs"], [
            ("first adult without a PIN", "DeepLink_profileFor", [[kids, pin, laura, sam], ""], lambda v: v and v.get("id") == "l"),
            ("remembered wins", "DeepLink_profileFor", [[laura, sam], "s"], lambda v: v and v.get("id") == "s"),
            ("none qualifies", "DeepLink_profileFor", [[kids, pin], ""], lambda v: v is None),
        ])
