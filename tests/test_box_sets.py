# SPDX-License-Identifier: AGPL-3.0-or-later
"""Movie box sets (Silo Android #646, components/common/BoxSets.brs): the card a group=box_set
browse answers, the box set page's facts and play target, search cards, and the watched changes a
re-read must keep (ports of BoxSetModelsTest and BoxSetViewModelTest)."""
import unittest

from brs import check_cases

FILES = ["components/common/BoxSets.brs", "components/common/Utils.brs"]


def bs(**kw):
    out = {"id": "1241", "library_id": "7", "title": "Harry Potter Collection", "movie_count": 8, "played_count": 0}
    out.update(kw)
    return out


def movie(cid, played=False, pos=None):
    m = {"content_id": cid, "type": "movie", "title": cid.title(), "user_state": {"played": played}}
    if pos is not None:
        m["position_seconds"] = pos
    return m


def lower(v):
    """brs-cli lower-cases dot-assigned keys (skill pitfall 15); compare case-insensitively."""
    if isinstance(v, dict):
        return {k.lower(): lower(x) for k, x in v.items()}
    if isinstance(v, list):
        return [lower(x) for x in v]
    return v


class Cards(unittest.TestCase):
    def test_cases(self):
        card = {"content_id": "box_set:1241", "type": "box_set", "title": "Harry Potter Collection", "box_set": bs()}
        check_cases(self, FILES, [
            ("a box set card", "BoxSet_of", [card], lambda v: v["id"] == "1241"),
            ("a movie is no box set", "BoxSet_of", [movie("a")], None),
            ("a box_set type without its object", "BoxSet_of", [{"type": "box_set", "content_id": "x"}], None),
            ("not an object", "BoxSet_of", ["x"], None),
            ("a library with box sets on", "BoxSet_anyEnabled", [[{"id": "1"}, {"id": "2", "box_sets_enabled": True}]], True),
            ("an older server sends no flag", "BoxSet_anyEnabled", [[{"id": "1"}, {"id": "2"}]], False),
            ("a string flag is not true", "BoxSet_anyEnabled", [[{"id": "1", "box_sets_enabled": "true"}]], False),
            ("no list", "BoxSet_anyEnabled", [None], False),
            ("one film", "BoxSet_filmCount", [1], "1 film"),
            ("eight films", "BoxSet_filmCount", [8], "8 films"),
            ("a count sent as a string", "BoxSet_filmCount", ["3"], "3 films"),
            ("years span", "BoxSet_yearsLabel", [bs(first_year=2001, last_year=2011)], "2001 – 2011"),
            ("one year", "BoxSet_yearsLabel", [bs(first_year=2001, last_year=2001)], "2001"),
            ("only the last year", "BoxSet_yearsLabel", [bs(last_year=2011)], "2011"),
            ("no year", "BoxSet_yearsLabel", [bs(first_year=0)], ""),
            ("caption: years", "BoxSet_cardCaption", [bs(first_year=2001, last_year=2011)], "2001 – 2011"),
            ("caption: film count without years", "BoxSet_cardCaption", [bs()], "8 films"),
            ("caption: watched once started", "BoxSet_cardCaption", [bs(played_count=3, first_year=2001)], "3 / 8 watched"),
            ("hero facts", "BoxSet_heroFacts", [bs(first_year=2001, last_year=2011, played_count=3)],
             ["Box set", "8 films", "2001 – 2011", "3 of 8 watched"]),
            ("hero facts before the first", "BoxSet_heroFacts", [bs()], ["Box set", "8 films"]),
            ("watched share", "BoxSet_watchedFraction", [bs(played_count=2)], lambda v: abs(v - 0.25) < 1e-6),
            ("watched share capped", "BoxSet_watchedFraction", [bs(played_count=9)], lambda v: abs(v - 1.0) < 1e-6),
            ("watched share of an empty set", "BoxSet_watchedFraction", [bs(movie_count=0)], 0),
        ])


class PlayTarget(unittest.TestCase):
    def test_cases(self):
        check_cases(self, FILES, [
            ("the first unplayed", "BoxSet_nextIndex", [[movie("a", True), movie("b"), movie("c")]], 1),
            ("in progress is not played", "BoxSet_nextIndex", [[movie("a", pos=300), movie("b")]], 0),
            ("all played: the first", "BoxSet_nextIndex", [[movie("a", True), movie("b", True)]], 0),
            ("no movies", "BoxSet_nextIndex", [[]], -1),
            ("resume point", "BoxSet_resumePosition", [movie("a", pos=300)], lambda v: abs(v - 300) < 1e-6),
            ("a played movie starts over", "BoxSet_resumePosition", [movie("a", True, pos=300)], 0),
            ("play label", "BoxSet_playLabel", [bs(), movie("first")], "Play First"),
            ("continue a started set", "BoxSet_playLabel", [bs(played_count=1), movie("second")], "Continue · Second"),
            ("continue a resumable movie", "BoxSet_playLabel", [bs(), movie("first", pos=60)], "Continue · First"),
            ("all played: play again", "BoxSet_playLabel", [bs(played_count=8), movie("first", True)], "Play First"),
        ])


class SearchAndScreen(unittest.TestCase):
    def test_cases(self):
        res = check_cases(self, FILES, [
            ("search card", "BoxSet_searchCard", [bs(poster_url="/p.jpg")], lambda v: True),
            ("search cards skip rows without an id", "BoxSet_searchCards",
             [{"items": [bs(), {"title": "no id"}, bs(id="99", library_id="8")]}], lambda v: len(v) == 2),
            ("search cards from nothing", "BoxSet_searchCards", [None], []),
            ("screen params", "BoxSet_screenParams", [bs(), "1"], lambda v: True),
            ("screen params fall back to the browsing library", "BoxSet_screenParams", [bs(library_id=None), "1"], lambda v: True),
        ])
        card = lower(res[0]["value"])
        self.assertEqual(card["content_id"], "box_set:7:1241")
        self.assertEqual(card["type"], "box_set")
        self.assertEqual(card["box_set"]["id"], "1241")
        self.assertEqual(lower(res[1]["value"])[1]["content_id"], "box_set:8:99")
        self.assertEqual(lower(res[3]["value"]), {"boxsetid": "1241", "libraryid": "7", "title": "Harry Potter Collection"})
        self.assertEqual(lower(res[4]["value"])["libraryid"], "1")


class RowWindow(unittest.TestCase):
    """boxSetRowWindow (BoxSetModelsTest): which films a movie page's box set row shows."""

    def test_cases(self):
        fn = "BoxSet_rowWindow"
        check_cases(self, FILES, [
            ("starts at the first film", fn, [8, 2, 5], [0, 5]),
            ("slides so the film before the current leads", fn, [10, 5, 5], [4, 9]),
            ("stops at the end of the set", fn, [8, 7, 5], [3, 8]),
            ("a film outside the set", fn, [8, -1, 5], [0, 5]),
            ("more slots than films", fn, [3, 2, 5], [0, 3]),
            ("no slots", fn, [3, 1, 0], [0, 0]),
        ])


class ChangesSince(unittest.TestCase):
    """BoxSetViewModel.withChangesSince: changes made after a read started, and pending writes, go
    back on its answer; a pending change the answer already shows settles."""

    def test_cases(self):
        def detail(*items):
            return {"id": "1241", "title": "X", "movie_count": len(items),
                    "played_count": sum(1 for i in items if i["user_state"]["played"]), "items": list(items)}

        fn = "BoxSet_withChangesSince"
        res = check_cases(self, FILES, [
            ("no changes: the answer as is", fn, [detail(movie("a"), movie("b", True)), {}, 0], lambda v: True),
            ("a change after the read started goes back on", fn,
             [detail(movie("a"), movie("b")), {"a": {"n": 2, "watched": True, "pending": False}}, 1], lambda v: True),
            ("a settled change before the read is the server's to say", fn,
             [detail(movie("a"), movie("b")), {"a": {"n": 1, "watched": True, "pending": False}}, 1], lambda v: True),
            ("a pending write before the read goes back on", fn,
             [detail(movie("a"), movie("b")), {"a": {"n": 1, "watched": True, "pending": True}}, 1], lambda v: True),
            ("a pending write the answer shows settles", fn,
             [detail(movie("a", True), movie("b")), {"a": {"n": 1, "watched": True, "pending": True}}, 1], lambda v: True),
            ("unwatched clears the resume point", "BoxSet_withWatched", [movie("a", pos=300), False], lambda v: True),
        ])
        v = [lower(r["value"]) for r in res]
        self.assertEqual(v[0]["played_count"], 1)
        self.assertTrue(v[1]["items"][0]["user_state"]["played"])
        self.assertEqual(v[1]["played_count"], 1)
        self.assertFalse(v[2]["items"][0]["user_state"]["played"])
        self.assertEqual(v[2]["played_count"], 0)
        self.assertTrue(v[3]["items"][0]["user_state"]["played"])
        self.assertTrue(v[4]["items"][0]["user_state"]["played"])
        self.assertEqual(v[5]["position_seconds"], 0)
        self.assertFalse(v[5]["user_state"]["played"])


if __name__ == "__main__":
    unittest.main()
