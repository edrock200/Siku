# SPDX-License-Identifier: AGPL-3.0-or-later
"""Req_discoverCarousels: the Requests hub follows the server admin's Discover layout (row_order)
as Silo Android's RequestCarouselMerge.discoverCarousels does, and falls back to the two merged
carousels on an older server."""
import unittest

from brs import check_cases

FILES = ["components/common/Requests.brs", "components/common/Utils.brs"]


def t(mt, tid, title="T"):
    return {"media_type": mt, "tmdb_id": tid, "title": title}


def keys(rows):
    return [(r["key"], r["title"], [x["tmdb_id"] for x in r["results"]]) for r in rows]


LAYOUT = {
    "items": [
        {"key": "trending_movies", "title": "Trending Movies", "results": [t("movie", 1), t("movie", 2)]},
        {"key": "staff_picks", "title": "Staff Picks", "results": [t("series", 3), t("person", 4), t("movie", 5)]},
        {"key": "empty_list", "title": "Empty", "results": []},
        {"key": "studios", "title": "Studios", "results": [t("movie", 9)]},
    ],
    "row_order": [
        {"key": "staff_picks", "type": "tmdb_list", "title": "Staff Picks"},
        {"key": "studios", "type": "studios", "title": "Studios"},
        {"key": "missing_row", "type": "mdblist", "title": "Not sent"},
        {"key": "empty_list", "type": "mdblist", "title": "Empty"},
        {"key": "trending_movies", "type": "tmdb_chart", "title": "Trending Movies"},
        {"key": "staff_picks", "type": "tmdb_list", "title": "Staff Picks again"},
    ],
}

LEGACY = {"items": [
    {"key": "trending_movies", "title": "Trending Movies", "results": [t("movie", 1), t("movie", 2)]},
    {"key": "trending_series", "title": "Trending Series", "results": [t("series", 3)]},
    {"key": "popular_movies", "title": "Popular Movies", "results": [t("movie", 1)]},
    {"key": "upcoming_movies", "title": "Upcoming", "results": [t("movie", 7)]},
]}


class DiscoverRows(unittest.TestCase):
    def test_cases(self):
        f = "Req_discoverCarousels"
        res = check_cases(self, FILES, [
            ("layout order, brand and empty rows skipped", f, [LAYOUT], lambda v: keys(v) == [
                ("staff_picks", "Staff Picks", [3, 5]), ("trending_movies", "Trending Movies", [1, 2])]),
            ("older server: merged carousels", f, [LEGACY], lambda v: keys(v) == [
                ("trending", "Trending now", [1, 3, 2]), ("popular", "Crowd favorites", [1])]),
            ("no answer", f, [None], []),
            ("empty row_order falls back", f, [dict(LEGACY, row_order=[])], lambda v: len(v) == 2),
        ])
        self.assertTrue(res)


class FollowFlag(unittest.TestCase):
    def test_cases(self):
        check_cases(self, FILES, [
            ("true", "Req_flag", [True], True),
            ("missing", "Req_flag", [None], False),
            ("a string is not a flag", "Req_flag", ["true"], False),
        ])


if __name__ == "__main__":
    unittest.main()
