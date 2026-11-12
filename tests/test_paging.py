# SPDX-License-Identifier: AGPL-3.0-or-later
"""components/common/Paging.brs (stale answers, cursors, load-more distance, back-off, the person
page's title count), Api_errorText / Api_reasonText for answers that never reached HTTP, and row
titles by title_key (For You, the Requests hub's Discover rows)."""
import unittest

from brs import check_cases

PAGING = ["components/common/Paging.brs", "components/common/Utils.brs"]
API = ["components/common/Api.brs", "components/common/Utils.brs"]
REQ = ["components/common/Requests.brs", "components/common/Utils.brs"]
EN = {"global": {"appLocale": "en", "strings": {}}}
DE = {"global": {"appLocale": "de", "strings": {
    "{0} title": "{0} Titel", "{0} titles": "{0} Titel", "{0}+ titles": "{0}+ Titel",
    "The server took too long to answer. Try again.": "Der Server hat zu lange gebraucht. Versuche es erneut.",
    "@home.section.trendingThisWeek": "Diese Woche im Trend",
    "@home.section.becauseYouWatchedTitle": "Weil du {title} geschaut hast"}}}


class Stale(unittest.TestCase):
    def test_is_current(self):
        f = "Paging_isCurrent"
        check_cases(self, PAGING, [
            ("newest read for the season shown", f, [{"season": 2, "seq": 5}, "season", 2, 5], True),
            ("Season 1's late answer under Season 2", f, [{"season": 1, "seq": 4}, "season", 2, 5], False),
            ("an older read of the same season", f, [{"season": 2, "seq": 4}, "season", 2, 5], False),
            ("season sent as a float", f, [{"season": 2.0, "seq": 5}, "season", 2, 5], True),
            ("filter", f, [{"filter": "movie", "seq": 3}, "filter", "movie", 3], True),
            ("left the filter", f, [{"filter": "movie", "seq": 3}, "filter", "series", 3], False),
            ("All is the empty filter", f, [{"filter": "", "seq": 1}, "filter", "", 1], True),
            ("no context", f, [None, "season", 2, 5], False),
            ("nothing selected", f, [{"season": 2, "seq": 5}, "season", None, 5], False),
            ("number against text", f, [{"season": "2", "seq": 5}, "season", 2, 5], False),
            ("no seq", f, [{"season": 2}, "season", 2, 5], False),
        ])


class Pages(unittest.TestCase):
    def test_cursor(self):
        f = "Paging_nextCursor"
        check_cases(self, PAGING, [
            ("more", f, [{"page": {"has_more": True, "next_cursor": "o40"}}], "o40"),
            ("last page", f, [{"page": {"has_more": False, "next_cursor": "o40"}}], ""),
            ("no page", f, [{"items": []}], ""),
            ("has_more as text", f, [{"page": {"has_more": "true", "next_cursor": "o40"}}], ""),
            ("cursor not text", f, [{"page": {"has_more": True, "next_cursor": 40}}], ""),
            ("not an object", f, [None], ""),
        ])

    def test_near_end(self):
        f = "Paging_nearEnd"
        check_cases(self, PAGING, [
            ("first row of 40", f, [0, 40, 6, 2], False),
            ("two rows from the end", f, [28, 40, 6, 2], True),
            ("just before", f, [27, 40, 6, 2], False),
            ("last card", f, [39, 40, 6, 2], True),
            ("nothing loaded", f, [0, 0, 6, 2], False),
            ("no focus", f, [-1, 40, 6, 2], False),
        ])

    def test_retry_delay(self):
        f = "Paging_retryDelay"
        check_cases(self, PAGING, [(str(n), f, [n], d) for n, d in ((0, 0), (1, 5), (2, 10), (3, 20), (4, 40), (5, 60), (9, 60))])

    def test_title_count(self):
        f = "Paging_titleCount"
        check_cases(self, PAGING, [
            ("the server's total wins", f, [72, 60, True], "72 titles", EN),
            ("one", f, [1, 1, False], "1 title", EN),
            ("no total, more to come", f, [None, 60, True], "60+ titles", EN),
            ("no total, all loaded", f, [None, 12, False], "12 titles", EN),
            ("total zero, loaded", f, [0, 3, False], "3 titles", EN),
            ("nothing yet", f, [None, 0, False], "", EN),
            ("total as text is not trusted", f, ["72", 60, True], "60+ titles", EN),
            ("German", f, [None, 60, True], "60+ Titel", DE),
        ])


class SearchResults(unittest.TestCase):
    """Search's All chip (Android TV's visibleOnTv + audiobook filter, mergePeopleSearchResults)."""

    def test_tv_visible(self):
        f = "Search_tvVisible"
        items = [{"type": "movie", "id": "m"}, {"type": "ebook", "id": "e"}, {"type": "Manga", "id": "g"},
                 {"type": "audiobook", "id": "a"}, {"type": "series", "id": "s"}, {"type": " comic ", "id": "c"},
                 {"id": "n"}, "junk"]
        check_cases(self, PAGING, [
            ("audiobooks hidden", f, [items, False], [items[0], items[4], items[6]]),
            ("audiobooks shown", f, [items, True], [items[0], items[3], items[4], items[6]]),
            ("not a list", f, [None, True], []),
        ])

    def test_merge_people(self):
        f = "Search_mergePeople"
        ann = {"id": "1", "name": "Ann Lee"}
        bob = {"id": "2", "name": "bob"}
        lee = {"id": "3", "name": "Lee"}
        check_cases(self, PAGING, [
            ("one list keeps the server's order", f, [[[lee, ann]], "lee", 20], [lee, ann]),
            ("one list, limit", f, [[[lee, ann, bob]], "lee", 2], [lee, ann]),
            ("merged: exact first, then by name, duplicates once", f, [[[ann, bob], [bob, lee]], "Lee", 20], [lee, ann, bob]),
            ("merged, limit", f, [[[ann, bob], [lee]], "x", 2], [ann, bob]),
        ])


class SearchCapabilities(unittest.TestCase):
    def test_people_scope(self):
        f = "Search_peopleScopeSupported"
        check_cases(self, PAGING, [
            ("advertised", f, [{"ok": True, "status": 200, "data": {"people_media_scope": True}}], True),
            ("an older server leaves it out", f, [{"ok": True, "status": 200, "data": {"revision": "1"}}], False),
            ("false", f, [{"ok": True, "status": 200, "data": {"people_media_scope": False}}], False),
            ("text is not a flag", f, [{"ok": True, "status": 200, "data": {"people_media_scope": "true"}}], False),
            ("a failed read", f, [{"ok": False, "status": 404, "data": {"people_media_scope": True}}], False),
            ("no answer", f, [{"ok": False, "status": 0}], False),
            ("no ok member", f, [{"status": 200, "data": {"people_media_scope": True}}], False),
            ("not an object", f, [None], False),
        ])

    def test_result_count_plural(self):
        f = "TxP"
        fr = {"global": {"appLocale": "fr", "strings": {"{0} result": "{0} résultat", "{0} results": "{0} résultats"}}}
        check_cases(self, PAGING, [
            ("one", f, ["{0} result", "{0} results", 1], "1 result", EN),
            ("several", f, ["{0} result", "{0} results", 4], "4 results", EN),
            ("none", f, ["{0} result", "{0} results", 0], "0 results", EN),
            ("French counts 0 as one", f, ["{0} result", "{0} results", 0], "0 résultat", fr),
        ])


class ErrorText(unittest.TestCase):
    def resp(self, code, status=0):
        return {"ok": False, "status": status, "error": {"code": code, "title": "x", "detail": "", "shown": ""}}

    def test_error_text(self):
        f = "Api_errorText"
        conn = "Can't reach the server. Check your connection and try again."
        check_cases(self, API, [
            ("timeout", f, [self.resp("timeout")], "The server took too long to answer. Try again.", EN),
            ("timeout in German", f, [self.resp("timeout")], "Der Server hat zu lange gebraucht. Versuche es erneut.", DE),
            ("too large", f, [self.resp("too_large")], "The server's answer was too large for this Roku.", EN),
            ("not v2", f, [self.resp("not_v2")], "Something went wrong", EN),
            ("bad download", f, [self.resp("bad_download")], "Something went wrong", EN),
            ("network", f, [self.resp("network")], conn, EN),
            ("no code", f, [{"ok": False, "status": 0, "error": {"title": "No response"}}], conn, EN),
            ("an HTTP problem keeps its title", f, [{"ok": False, "status": 404, "error": {"code": "not_found", "title": "Not found", "shown": ""}}],
             "Not found", EN),
            ("no response", f, [None], "Something went wrong", EN),
        ])

    def test_reason_text(self):
        f = "Api_reasonText"
        check_cases(self, API, [
            ("timeout", f, [self.resp("timeout"), "Try again."], "The server took too long to answer.", EN),
            ("too large", f, [self.resp("too_large"), "Try again."], "The server's answer was too large.", EN),
            ("not v2 uses the fallback", f, [self.resp("not_v2"), "Try again."], "Try again.", EN),
            ("network", f, [self.resp("network"), "Try again."], "Can't reach the server. Check your connection.", EN),
            ("a detail", f, [{"status": 409, "error": {"code": "conflict", "title": "Conflict", "detail": "Already watched", "shown": ""}}, "x"],
             "Already watched", EN),
        ])


class RowTitles(unittest.TestCase):
    def test_discover_title_key(self):
        layout = {
            "items": [
                {"key": "trending_movies", "title": "Trending This Week", "title_key": "home.section.trendingThisWeek",
                 "results": [{"media_type": "movie", "tmdb_id": 1, "title": "T"}]},
                {"key": "staff", "title": "Staff Picks", "results": [{"media_type": "movie", "tmdb_id": 2, "title": "T"}]},
                {"key": "unknown", "title": "Hidden Gems", "title_key": "home.section.noSuchKey",
                 "results": [{"media_type": "movie", "tmdb_id": 3, "title": "T"}]},
            ],
            "row_order": [{"key": "trending_movies", "type": "tmdb_chart"}, {"key": "staff", "type": "tmdb_list"},
                          {"key": "unknown", "type": "tmdb_list"}],
        }
        titles = lambda v: [r["title"] for r in v]  # noqa: E731
        check_cases(self, REQ, [
            ("German", "Req_discoverCarousels", [layout], lambda v: titles(v) == ["Diese Woche im Trend", "Staff Picks", "Hidden Gems"], DE),
            ("English", "Req_discoverCarousels", [layout], lambda v: titles(v) == ["Trending This Week", "Staff Picks", "Hidden Gems"], EN),
        ])


if __name__ == "__main__":
    unittest.main()
