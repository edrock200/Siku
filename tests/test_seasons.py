# SPDX-License-Identifier: AGPL-3.0-or-later
"""Seasons.brs (Silo Android #929 / #931, silo-roku a41d106): Specials are season zero and come first;
a fresh series still opens on a numbered season."""
import unittest

from brs import check_cases

FILES = ["components/common/Seasons.brs", "components/common/Utils.brs"]


def season(n, specials=False, **ud):
    s = {"content_id": "season:%s" % n, "season_number": n, "episode_count": ud.pop("episodes", 10), "is_specials": specials}
    if ud:
        s["user_data"] = ud
    return s


def numbers(v):
    return [x.get("season_number") for x in v]


class Order(unittest.TestCase):
    def test_cases(self):
        c = "Seasons_ordered"
        check_cases(self, FILES, [
            ("specials first whatever the input order", c, [[season(2), season(0), season(1)]], lambda v: numbers(v) == [0, 1, 2]),
            ("a flagged specials season comes first too", c, [[season(1), season(2), season(99, True)]],
             lambda v: numbers(v) == [99, 1, 2]),
            ("numbers as strings sort as numbers", c, [[season("10"), season("2"), season("0")]],
             lambda v: numbers(v) == ["0", "2", "10"]),
            ("a season without a number goes last", c, [[{"title": "Extras"}, season(1)]],
             lambda v: numbers(v) == [1, None]),
            ("stable for a number listed twice", c, [[dict(season(1), content_id="a"), dict(season(1), content_id="b")]],
             lambda v: [x["content_id"] for x in v] == ["a", "b"]),
            ("not a list", c, [None], []),
        ])

    def test_is_specials(self):
        c = "Seasons_isSpecials"
        check_cases(self, FILES, [
            ("season zero", c, [season(0)], True),
            ("flagged", c, [season(99, True)], True),
            ("missing flag on a numbered season", c, [{"season_number": 3}], False),
            ("no number, no flag", c, [{"title": "x"}], False),
            ("flag as a string is not a flag", c, [{"season_number": 4, "is_specials": "true"}], False),
            ("invalid", c, [None], False),
        ])


class Initial(unittest.TestCase):
    def test_cases(self):
        c = "Seasons_initial"
        watched = {"played": True, "watched_count": 10}
        check_cases(self, FILES, [
            ("the server's play season when listed", c, [[season(0), season(1), season(2)], 2], 2),
            ("play season 0 opens Specials", c, [[season(0), season(1)], 0], 0),
            ("an unlisted play season falls through", c, [[season(0), season(1)], 5], 1),
            ("fresh series with unplayed specials opens on season 1", c, [[season(2), season(0), season(1)], None], 1),
            ("unplayed specials once every numbered season is watched", c,
             [[season(1, **watched), season(2, **watched), season(0)], None], 0),
            ("fully watched series opens on season 1", c,
             [[season(0, **watched), season(1, **watched), season(2, **watched)], None], 1),
            ("specials in progress open on specials", c, [[season(0, in_progress_count=1), season(1), season(2)], None], 0),
            ("a numbered season in progress beats specials in progress", c,
             [[season(0, in_progress_count=1), season(1), season(3, in_progress_count=1)], None], 3),
            ("a partly watched numbered season beats partly watched specials", c,
             [[season(0, watched_count=2), season(1, **watched), season(2, watched_count=4)], None], 2),
            ("nothing listed", c, [[], None], None),
        ])


if __name__ == "__main__":
    unittest.main()
