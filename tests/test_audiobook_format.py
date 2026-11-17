# SPDX-License-Identifier: AGPL-3.0-or-later
"""AudiobookFormat.brs (Silo Android #975, ported from Apple's AudiobookDetailFormatting): titles drop the
series locator the server bakes in, credits are cut for one line, and the hero's listening state.

The cases mirror Silo's AudiobookDetailFormattingTest.kt; a Python port of the Kotlin regexes (below) is the
reference for a wider corpus, because the BrightScript scans by hand instead of using roRegex."""
import re
import unittest

from brs import calls, check_cases

FILES = ["components/common/AudiobookFormat.brs"]

# ---- reference: AudiobookDetailFormatting.kt, regex for regex ----
TRIM_EDGES = " -–—:·,"
VOLUME_OF = re.compile(r"\(\s*(\d+)\s+of\s+(\d+)\s*\)\s*$", re.I | re.A)
TRAILING = [re.compile(r"\s*\(\s*\d+\s+of\s+\d+\s*\)$", re.I | re.A),
            re.compile(r"\s*\(\s*book\s+\d+\s*\)$", re.I | re.A),
            re.compile(r"\s*\(\s*vol(?:ume)?\.?\s*\d+\s*\)$", re.I | re.A)]
LOCATOR = re.compile(r"^\s*(?:#?\d+(?:\.\d+)?\s*[-–—:]?|[-–—:])\s*(.*)$", re.A)


def drop_article(s):
    low = s.lower()
    for a in ("the ", "a ", "an "):
        if low.startswith(a):
            return s[len(a):]
    return s


def ref_clean(raw, series):
    original = raw.strip()
    title = original
    if series and series.strip():
        core = drop_article(series).strip()
        hay = drop_article(title)
        if core and hay.lower().startswith(core.lower()):
            m = LOCATOR.search(hay[len(core):])
            if m and m.group(1).strip():
                title = m.group(1).strip()
    for p in TRAILING:
        title = p.sub("", title, count=1)
    title = title.strip(" \t\n\r\x0b\x0c" + TRIM_EDGES)
    return title or original


CORPUS = [
    ("Stormlight Archive 5 - Wind and Truth (5 of 5)", "The Stormlight Archive"),
    ("Black Rose Chronicles 2 - Torment and Treachery", "Black Rose Chronicles"),
    ("Project Hail Mary", None), ("The Way of Kings", "The Stormlight Archive"), ("Some Story (2 of 3)", None),
    ("American Gods", "A"), ("Dunes of Arrakis", "Dune"), ("Dune Saga 12 - Dune Messiah", "Dune Saga"),
    ("Dune Messiah", "Dune"), ("Children of Dune", "Dune"), ("Stormlight Archive: Wind and Truth", "Stormlight Archive"),
    ("Stormlight Archive 5 Wind and Truth", "Stormlight Archive"), ("Stormlight Archive #5: Wind and Truth", "Stormlight Archive"),
    ("Mistborn", "Mistborn"), ("Mistborn 1", "Mistborn"), ("Mistborn: ", "Mistborn"),
    ("Discworld 2.5 – The Colour of Magic", "Discworld"), ("Discworld — Mort", "Discworld"),
    ("The Expanse #3 Abaddon's Gate (Book 3)", "The Expanse"), ("Leviathan Wakes (Vol. 1)", "The Expanse"),
    ("Leviathan Wakes (Volume 12)", None), ("Leviathan Wakes (vol 2)", None), ("Leviathan Wakes (Book 1) (1 of 9)", "x"),
    ("Leviathan Wakes (1 of 9) (Book 1)", "x"), ("  Spaced Title  (3 of 4)  ", None), ("(1 of 2)", None),
    ("THE EXPANSE 4 - Cibola Burn", "the expanse"), ("An Ember 2: A Torch", "An Ember"), ("Series #x - Title", "Series"),
    ("Series 5.x Title", "Series"), ("Series - ", "Series"), ("Wheel of Time 01 · The Eye of the World", "Wheel of Time"),
    ("Title, (2 of 3)", None), ("Title - (2 of 3)", None), ("Foundation (2 of 3)", "Foundation"), ("", "Dune"),
]


class CleanTitle(unittest.TestCase):
    def test_kotlin_cases(self):
        c = "AudiobookFormat_cleanTitle"
        check_cases(self, FILES, [
            ("series prefix and trailing volume", c, ["Stormlight Archive 5 - Wind and Truth (5 of 5)", "The Stormlight Archive"], "Wind and Truth"),
            ("series prefix with a number", c, ["Black Rose Chronicles 2 - Torment and Treachery", "Black Rose Chronicles"], "Torment and Treachery"),
            ("no series, no pattern", c, ["Project Hail Mary", None], "Project Hail Mary"),
            ("another book's title in the series", c, ["The Way of Kings", "The Stormlight Archive"], "The Way of Kings"),
            ("trailing volume without a series", c, ["Some Story (2 of 3)", None], "Some Story"),
            ("series name ends at a word boundary (A)", c, ["American Gods", "A"], "American Gods"),
            ("series name ends at a word boundary (Dune)", c, ["Dunes of Arrakis", "Dune"], "Dunes of Arrakis"),
            ("a title that repeats the series word", c, ["Dune Saga 12 - Dune Messiah", "Dune Saga"], "Dune Messiah"),
            ("Dune Messiah stays whole in Dune", c, ["Dune Messiah", "Dune"], "Dune Messiah"),
            ("the series name later in the title", c, ["Children of Dune", "Dune"], "Children of Dune"),
            ("a colon after the series", c, ["Stormlight Archive: Wind and Truth", "Stormlight Archive"], "Wind and Truth"),
            ("a bare volume number", c, ["Stormlight Archive 5 Wind and Truth", "Stormlight Archive"], "Wind and Truth"),
            ("#5 and a colon", c, ["Stormlight Archive #5: Wind and Truth", "Stormlight Archive"], "Wind and Truth"),
            ("the title is only the series name", c, ["Mistborn", "Mistborn"], "Mistborn"),
            ("not a string", c, [None, "Dune"], ""),
        ])

    def test_matches_the_kotlin_regexes(self):
        specs = [{"fn": "AudiobookFormat_cleanTitle", "args": [t, s]} for t, s in CORPUS]
        for (t, s), r in zip(CORPUS, calls(FILES, specs)):
            with self.subTest(title=t, series=s):
                self.assertTrue(r["ok"], r.get("error"))
                self.assertEqual(r["value"], ref_clean(t, s))


class Volume(unittest.TestCase):
    def test_cases(self):
        c = "AudiobookFormat_volume"
        check_cases(self, FILES, [
            ("index and total", c, ["Wind and Truth (5 of 5)"], {"index": 5, "total": 5}),
            ("trailing spaces and case", c, ["Wind (2 OF 9)  "], {"index": 2, "total": 9}),
            ("none", c, ["Wind and Truth"], {"index": None, "total": None}),
            ("Book N is not N of M", c, ["Wind (Book 2)"], {"index": None, "total": None}),
            ("not at the end", c, ["(2 of 3) Wind"], {"index": None, "total": None}),
        ])

    def test_matches_reference(self):
        titles = ["Wind and Truth (5 of 5)", "X (4 of 9)", "X ( 4  of  9 ) ", "X (4of9)", "X (a of 9)", "X (4 of 9))", "X"]
        rs = calls(FILES, [{"fn": "AudiobookFormat_volume", "args": [t]} for t in titles])
        for t, r in zip(titles, rs):
            m = VOLUME_OF.search(t)
            exp = {"index": int(m.group(1)), "total": int(m.group(2))} if m else {"index": None, "total": None}
            self.assertEqual(r["value"], exp, t)


class SeriesIndex(unittest.TestCase):
    def test_cases(self):
        c = "AudiobookFormat_seriesIndex"
        entries = [{"content_id": "a", "series_index": 1.0}, {"content_id": "b", "series_index": 2.5}, {"content_id": "c"},
                   {"content_id": "d", "series_index": "3"}, {"content_id": "e", "series_index": 0}]
        check_cases(self, FILES, [
            ("a whole-number entry wins over the title", c, ["a", "X (4 of 9)", entries], 1),
            ("a fractional entry falls back to the title", c, ["b", "X (4 of 9)", entries], 4),
            ("no entry index and no locator", c, ["c", "X", entries], None),
            ("a numeric string index", c, ["d", "X", entries], 3),
            ("index zero is not a place", c, ["e", "X (2 of 3)", entries], 2),
            ("no entries", c, ["z", "X (7 of 8)", None], 7),
        ])


class People(unittest.TestCase):
    def test_summary(self):
        c = "AudiobookFormat_peopleSummary"
        check_cases(self, FILES, [
            ("joined names are split and cut", c, [["Danny Montooth, James Konicek, A, B, C"]],
             {"shown": ["Danny Montooth", "James Konicek"], "remaining": 3}),
            ("one over visible is kept whole", c, [["A", "B", "C"]], {"shown": ["A", "B", "C"], "remaining": 0}),
            ("blank names", c, [[" ", ""]], None),
            ("person objects", c, [[{"name": "A"}, {"name": "B"}, {"name": "C"}, {"name": "D"}, {"name": "E"}], 3],
             {"shown": ["A", "B", "C"], "remaining": 2}),
            ("not a list", c, [None], None),
        ])

    def test_join(self):
        c = "AudiobookFormat_naturalJoin"
        check_cases(self, FILES, [
            ("none", c, [[]], ""), ("one", c, [["A"]], "A"), ("two", c, [["A", "B"]], "A & B"),
            ("three", c, [["A", "B", "C"]], "A, B & C"),
        ])


class State(unittest.TestCase):
    def test_cases(self):
        c = "AudiobookFormat_state"
        check_cases(self, FILES, [
            ("not started", c, [0, 3600, False], {"finished": False, "resume": -1.0, "played": False}),
            ("inside the 30 s grace", c, [25, 3600, False], {"finished": False, "resume": -1.0, "played": False}),
            ("listening", c, [600, 3600, False], {"finished": False, "resume": 600.0, "played": False}),
            ("near the end reads as finished but not played", c, [3597, 3600, False],
             {"finished": True, "resume": -1.0, "played": False}),
            ("the saved flag wins over a position", c, [600, 3600, True], {"finished": True, "resume": -1.0, "played": True}),
            ("unknown length still resumes", c, [600, 0, None], {"finished": False, "resume": 600.0, "played": False}),
            ("a numeric string position", c, ["120", "3600", False], {"finished": False, "resume": 120.0, "played": False}),
            ("a string played flag is not a flag", c, [0, 3600, "true"], {"finished": False, "resume": -1.0, "played": False}),
        ])


class RowScroll(unittest.TestCase):
    def test_cases(self):
        c = "AudiobookFormat_rowScroll"
        xs, ws = [0, 300, 560, 880, 976], [282, 242, 302, 78, 220]  # five controls, 1196 px wide
        check_cases(self, FILES, [
            ("a row that fits never scrolls", c, [[0, 300], [282, 242], 1, 1176, 40], {"scroll": 0, "shown": [True, True]}),
            ("focus on the first control", c, [xs, ws, 0, 1176, 0], {"scroll": 0, "shown": [True, True, True, True, False]}),
            ("focus on the last scrolls just enough", c, [xs, ws, 4, 1176, 0], {"scroll": 20, "shown": [False, True, True, True, True]}),
            ("back to the first scrolls home", c, [xs, ws, 0, 1176, 20], {"scroll": 0, "shown": [True, True, True, True, False]}),
            ("a middle control already in view keeps the scroll", c, [xs, ws, 2, 1176, 20],
             {"scroll": 20, "shown": [False, True, True, True, True]}),
            ("never past the end", c, [xs, ws, 4, 1176, 900], {"scroll": 20, "shown": [False, True, True, True, True]}),
            ("no controls", c, [[], [], 0, 1176, 0], {"scroll": 0, "shown": []}),
        ])


if __name__ == "__main__":
    unittest.main()
