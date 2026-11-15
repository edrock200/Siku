# SPDX-License-Identifier: AGPL-3.0-or-later
"""Home and library rows (components/common/SectionRows.brs, Silo Android #688): the item_limit
sent for an advertised section_item_limit_max, the 422 that makes Siku drop it, the 20-card cap,
the "Explore all" rule, and the row page's Movies / Series filter (LibraryPage Section_pageCards)."""
import unittest

from brs import check_cases

FILES = ["components/common/SectionRows.brs", "components/common/Utils.brs"]
PAGE_FILES = ["components/screens/library/LibraryPage.brs", "components/common/Utils.brs"]

UNKNOWN = {"type": "https://siloserver.org/problems/validation_failed", "title": "Validation failed", "status": 422,
           "errors": [{"location": "query.item_limit", "code": "unknown_parameter"}]}


class ItemLimitParam(unittest.TestCase):
    """sectionItemLimitParam: min(20, max), nothing when absent or below 1."""

    def test_limit_choice(self):
        f = "SectionRows_itemLimitParam"
        check_cases(self, FILES, [
            ("absent", f, [None], 0),
            ("zero", f, [0], 0),
            ("negative", f, [-5], 0),
            ("below the cap", f, [5], 5),
            ("the cap", f, [20], 20),
            ("above the cap", f, [100], 20),
            ("float", f, [50.0], 20),
            ("numeric string", f, ["12"], 12),
            ("garbage string", f, ["lots"], 0),
            ("boolean", f, [True], 0),
            ("object", f, [{"max": 100}], 0),
        ])

    def test_row_cap(self):
        check_cases(self, FILES, [
            ("max", "SectionRows_max", [], 20),
            ("30 cards capped", "SectionRows_capped", [list(range(30))], list(range(20))),
            ("short row kept", "SectionRows_capped", [[1, 2, 3]], [1, 2, 3]),
        ])


class Rejection(unittest.TestCase):
    """Only v2's 422 validation_failed naming query.item_limit / unknown_parameter retries."""

    def test_detection(self):
        f = "SectionRows_rejectsItemLimit"
        other_field = dict(UNKNOWN, errors=[{"location": "query.poster_width", "code": "unknown_parameter"}])
        other_code = dict(UNKNOWN, errors=[{"location": "query.item_limit", "code": "out_of_range"}])
        with_code = {"code": "validation_failed", "status": 422, "errors": [{"location": "query.item_limit", "code": "unknown_parameter"}]}
        check_cases(self, FILES, [
            ("unknown item_limit", f, [422, UNKNOWN], True),
            ("code field instead of type", f, [422, with_code], True),
            ("status as string", f, ["422", UNKNOWN], True),
            ("another parameter", f, [422, other_field], False),
            ("item_limit out of range", f, [422, other_code], False),
            ("400 with the same body", f, [400, UNKNOWN], False),
            ("500", f, [500, {"type": "x/internal"}], False),
            ("no body", f, [422, None], False),
            ("errors not a list", f, [422, dict(UNKNOWN, errors={"a": 1})], False),
            ("another problem", f, [422, dict(UNKNOWN, type="x/not_found")], False),
        ])


class ExploreAll(unittest.TestCase):
    """Every non-featured row with cards ends with "Explore all"."""

    def test_rule(self):
        f = "SectionRows_offersExploreAll"
        check_cases(self, FILES, [
            ("row with cards", f, [{"id": "trending", "featured": False}, 8], True),
            ("featured missing", f, [{"id": "trending"}, 3], True),
            ("featured", f, [{"id": "hero", "featured": True}, 8], False),
            ("no cards", f, [{"id": "trending"}, 0], False),
            ("no id", f, [{"title": "x"}, 4], False),
            ("featured as string is not featured", f, [{"id": "t", "featured": "true"}, 4], True),
            ("no section", f, [None, 4], False),
        ])

    def test_whole_list(self):
        """A Continue Watching or Next Up row that shows its whole list ends without Explore all
        (Silo Android bb53e20d, silo-roku cfda7be): a playback type, a total_count of at least 1 and
        no more than the cards sent, and fewer cards than its limit."""
        f = "SectionRows_offersExploreAll"
        cw = {"id": "continue_watching", "section_type": "continue_watching", "total_count": 1}
        check_cases(self, FILES, [
            ("a one-title Continue Watching row has no Explore all", f, [cw, 1, 1], False),
            ("Next Up holding all three", f, [{"id": "n", "section_type": "next_up", "total_count": 3}, 3, 3], False),
            ("In Progress holding all", f, [{"id": "p", "section_type": "In_Progress", "total_count": "2"}, 2, 2], False),
            ("a total above the cards keeps it", f, [{"id": "n", "section_type": "next_up", "total_count": 9}, 3, 3], True),
            ("a row filled to 20 keeps it", f, [{"id": "c", "section_type": "continue_watching", "total_count": 20}, 20, 20], True),
            ("more sent than 20, counted before the cut", f,
             [{"id": "c", "section_type": "continue_watching", "total_count": 25}, 20, 25], True),
            ("a row filled to its item_limit keeps it", f,
             [{"id": "c", "section_type": "continue_watching", "total_count": 6, "item_limit": 6}, 6, 6], True),
            ("under its item_limit it is whole", f,
             [{"id": "c", "section_type": "continue_watching", "total_count": 5, "item_limit": 6}, 5, 5], False),
            ("no total_count keeps it", f, [{"id": "c", "section_type": "continue_watching"}, 2, 2], True),
            ("a zero total_count keeps it", f, [{"id": "c", "section_type": "continue_watching", "total_count": 0}, 2, 2], True),
            ("other rows keep it however short", f, [{"id": "t", "section_type": "trending_on_server", "total_count": 2}, 2, 2], True),
            ("an unknown sent count keeps it", f, [cw, 1], True),
            ("the row's own items answer counts", f,
             [{"id": "c", "section_type": "continue_watching", "total_count": 40}, 2, 2, 2], False),
            ("hide-watched leaves fewer cards than sent: still whole", f, [{"id": "c", "section_type": "next_up", "total_count": 4}, 2, 4], False),
        ])


class ActiveLimit(unittest.TestCase):
    """The stored capability applies to the server it was read from only."""

    def test_per_server(self):
        url = "http://silo.example:8097"
        g = {"session": {"serverUrl": url}, "sectionLimit": {"serverUrl": url, "limit": 20}}
        other = {"session": {"serverUrl": "http://other:8097"}, "sectionLimit": {"serverUrl": url, "limit": 20}}
        off = {"session": {"serverUrl": url}, "sectionLimit": {"serverUrl": url, "limit": 0}}
        check_cases(self, FILES, [
            ("advertised", "SectionRows_activeLimit", [], 20, {"global": g}),
            ("another server", "SectionRows_activeLimit", [], 0, {"global": other}),
            ("unsupported", "SectionRows_activeLimit", [], 0, {"global": off}),
            ("never read", "SectionRows_activeLimit", [], 0, {"global": {"session": {"serverUrl": url}}}),
            ("settled", "SectionRows_capsSettled", [], True, {"global": off}),
            ("not settled elsewhere", "SectionRows_capsSettled", [], False, {"global": other}),
        ])


class RowPage(unittest.TestCase):
    """A row's full page keeps a mixed library's Movies / Series view and drops repeats."""

    CARDS = [{"content_id": "movie:a", "type": "movie"}, {"content_id": "series:b", "type": "series"},
             {"content_id": "episode:c", "type": "episode"}, {"content_id": "movie:a", "type": "movie"}, "junk"]

    def test_filter(self):
        f = "Section_pageCards"
        ids = lambda want: (lambda v: [c["content_id"] for c in v] == want)
        check_cases(self, PAGE_FILES, [
            ("every card, repeats dropped", f, [self.CARDS, "", {}], ids(["movie:a", "series:b", "episode:c"])),
            ("movies", f, [self.CARDS, "movie", {}], ids(["movie:a"])),
            ("series and episodes", f, [self.CARDS, "Series", {}], ids(["series:b", "episode:c"])),
            ("already shown", f, [self.CARDS, "", {"movie:a": True}], ids(["series:b", "episode:c"])),
            ("a page filtered away", f, [[{"content_id": "movie:x", "type": "movie"}], "series", {}], []),
        ])


if __name__ == "__main__":
    unittest.main()
