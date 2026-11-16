# SPDX-License-Identifier: AGPL-3.0-or-later
"""Nav_detailSeed (Silo Android #971, DetailSeed.kt): a movie or series card seeds the detail page it
opens with its own title, facts and artwork; files, watch state, cast and anything else wait for the
detail. Other cards, another title's page, or a card without a title seed nothing."""
import unittest

from brs import check_cases

FILES = ["components/common/Nav.brs", "components/common/Utils.brs"]

MOVIE = {"content_id": "movie:glass-city", "type": "movie", "title": "Glass City", "year": 2004, "runtime": 112,
         "overview": "A city story.", "content_rating": "PG-13", "genres": ["Drama"],
         "poster_url": "/p.jpg", "backdrop_url": "/b.jpg", "logo_url": "/l.jpg",
         "user_state": {"played": True}, "versions": [{"file_id": "42"}], "user_data": {"position_seconds": 60}}


class DetailSeed(unittest.TestCase):
    def test_cases(self):
        c = "Nav_detailSeed"
        check_cases(self, FILES, [
            ("a movie card seeds its title and art", c, [MOVIE, "movie:glass-city"],
             lambda v: v["title"] == "Glass City" and v["type"] == "movie" and v["backdrop_url"] == "/b.jpg"
             and v["runtime"] == 112 and v["genres"] == ["Drama"]),
            ("watch state and files wait for the detail", c, [MOVIE, "movie:glass-city"],
             lambda v: all(k not in v for k in ("user_state", "user_data", "versions"))),
            ("a series card seeds", c, [{"content_id": "series:orbital", "type": "Series", "title": "Orbital"}, "series:orbital"],
             lambda v: v["type"] == "series" and v["title"] == "Orbital"),
            ("another title's page", c, [MOVIE, "movie:other"], None),
            ("an episode card", c, [{"content_id": "episode:x", "type": "episode", "title": "Pilot"}, "episode:x"], None),
            ("no title", c, [{"content_id": "movie:x", "type": "movie", "title": "  "}, "movie:x"], None),
            ("no card", c, [None, "movie:x"], None),
            ("a string where a card should be", c, ["movie:x", "movie:x"], None),
        ])


if __name__ == "__main__":
    unittest.main()
