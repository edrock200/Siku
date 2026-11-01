# SPDX-License-Identifier: AGPL-3.0-or-later
"""Library_watchRule: the watch-status filter's catalog rule. Flag values must be JSON booleans;
the server answers 500 to "true"/"false" strings (Silo Android #702)."""
import unittest

from brs import check_cases

FILES = ["components/screens/library/LibraryPage.brs", "components/common/LibraryFilters.brs", "components/common/Utils.brs"]


def rule(field, value):
    return lambda v: v == {"field": field, "op": "is", "value": value} and isinstance(v["value"], bool)


class WatchRule(unittest.TestCase):
    def test_flag_values_are_booleans(self):
        f = "Library_watchRule"
        check_cases(self, FILES, [
            ("unwatched", f, ["unwatched"], rule("watched", False), {}),
            ("watched", f, ["watched"], rule("watched", True), {}),
            ("in progress", f, ["in_progress"], rule("in_progress", True), {}),
            ("favorited", f, ["favorited"], rule("favorited", True), {}),
            ("watchlist", f, ["watchlist"], rule("in_watchlist", True), {}),
        ])


class MoreRetryDelay(unittest.TestCase):
    """A failed "load more" waits before the grid asks again (no request and toast per key)."""

    def test_backoff(self):
        f = "Library_moreRetryDelay"
        check_cases(self, FILES, [
            ("no failure", f, [0], 0, {}),
            ("first", f, [1], 5, {}),
            ("second", f, [2], 10, {}),
            ("fourth", f, [4], 40, {}),
            ("capped", f, [5], 60, {}),
            ("many", f, [50], 60, {}),
        ])


LIBF = ["components/common/LibraryFilters.brs", "components/common/Utils.brs"]
FILTERS = {"genres": ["Drama", "Comedy", {"value": "Crime"}, "Drama"], "studios": ["Lantern Films"], "networks": [],
           "countries": [], "original_languages": [], "content_ratings": ["PG"], "authors": [], "narrators": [],
           "series": [], "technical": {"resolutions": ["4K", "1080p"], "audio_languages": ["en"], "subtitle_languages": []}}


class Facets(unittest.TestCase):
    """LibraryFilters.brs: Android TV's facets, multi-select, Match all / any, and saved filters."""

    def test_available_and_options(self):
        ids = lambda v: [d["id"] for d in v]
        check_cases(self, LIBF, [
            ("video facets the server lists, plus the fixed ones", "LibF_available", [False, FILTERS, {}],
             lambda v: ids(v) == ["genre", "decade", "status", "content_rating", "resolution", "dynamic_range", "studio", "audio_language"]),
            ("a saved value keeps its facet listed", "LibF_available", [False, FILTERS, {"network": ["HBO"]}],
             lambda v: "network" in ids(v)),
            ("audiobook facets", "LibF_available", [True, {"genres": ["Fiction"], "authors": ["A"]}, {}],
             lambda v: ids(v) == ["genre", "author", "decade", "status"]),
            ("genre values deduplicated", "LibF_values", [FILTERS["genres"]], ["Drama", "Comedy", "Crime"]),
            ("technical values", "LibF_vocab", [FILTERS, "resolutions"], ["4K", "1080p"]),
            ("decades", "LibF_options", [{"id": "decade"}, None], lambda v: v[0] == {"id": "2020", "label": "2020s"} and len(v) == 7),
        ])

    def test_toggle_and_count(self):
        check_cases(self, LIBF, [
            ("add a second genre", "LibF_toggle", [{"genre": ["Drama"]}, "genre", "Comedy"], {"genre": ["Drama", "Comedy"]}),
            ("remove the last value drops the facet", "LibF_toggle", [{"genre": ["Drama"]}, "genre", "Drama"], {}),
            ("watch status is single-select", "LibF_toggle", [{"status": ["watched"]}, "status", "unwatched"], {"status": ["unwatched"]}),
            ("re-picking watch status clears it", "LibF_toggle", [{"status": ["watched"]}, "status", "watched"], {}),
            ("count per facet", "LibF_activeCount", [{"genre": ["A", "B"], "decade": ["1990"], "dynamic_range": ["hdr"]}], 3),
            ("summary of several", "LibF_summary", [{"id": "genre", "vocab": "genres"}, {"genre": ["A", "B"]}, FILTERS], "2 selected"),
            ("summary of a decade", "LibF_summary", [{"id": "decade", "vocab": ""}, {"decade": ["1990"]}, None], "1990s"),
        ])

    def test_groups(self):
        sel = {"genre": ["Drama", "Comedy"], "decade": ["1990", "2010"], "dynamic_range": ["dolby_vision", "hdr"],
               "status": ["unwatched"], "resolution": ["4K"], "audio_language": ["en"]}
        expected = [
            {"match": "any", "rules": [{"field": "genre", "op": "contains", "value": "Comedy"},
                                       {"field": "genre", "op": "contains", "value": "Drama"}]},
            {"match": "any", "rules": [{"field": "resolution", "op": "is", "value": "4K"}]},
            {"match": "any", "rules": [{"field": "audio_language", "op": "is", "value": "en"}]},
            {"match": "any", "rules": [{"field": "year", "op": "between", "value": "", "values": ["1990", "1999"]},
                                       {"field": "year", "op": "between", "value": "", "values": ["2010", "2019"]}]},
            {"match": "any", "rules": [{"field": "hdr", "op": "is", "value": True},
                                       {"field": "dolby_vision", "op": "is", "value": True}]},
            {"match": "all", "rules": [{"field": "watched", "op": "is", "value": False}]},
        ]
        res = check_cases(self, LIBF, [("android tv query groups", "LibF_groups", [sel, False], expected)])
        flag = res[0]["value"][4]["rules"][0]["value"]
        self.assertIsInstance(flag, bool)

    def test_saved_state(self):
        check_cases(self, LIBF, [
            ("a save from before v0.1.31", "LibF_restore", [{"sort": "title", "genre": "Drama", "watchStatus": "watched"}],
             {"sel": {"genre": ["Drama"], "status": ["watched"]}, "matchAll": True}),
            ("facets and match any", "LibF_restore", [{"facets": {"genre": ["A", "B"], "decade": ["1990", "1234"]}, "match": "any"}],
             {"sel": {"genre": ["A", "B"], "decade": ["1990"]}, "matchAll": False}),
            ("unknown watch status dropped", "LibF_restore", [{"watchStatus": "liked"}], {"sel": {}, "matchAll": True}),
            ("nothing saved", "LibF_restore", [None], {"sel": {}, "matchAll": True}),
        ])


if __name__ == "__main__":
    unittest.main()
