# SPDX-License-Identifier: AGPL-3.0-or-later
"""Markers_finalCreditsStart (Silo Android #694 / #994): the closing credits begin at the LAST credits
range, extended back over credits ranges that run into it, so a scene between two credits ranges still
counts as part of the episode; NextUp_crossesPromptPoint (#994): Up Next opens when playback crosses
the Show Next Up point before the end of the file, never because of a credits marker."""
import unittest

from brs import check_cases

FILES = ["components/player/MarkerTimeline.brs", "components/common/Utils.brs"]


def mk(kind, s, e):
    return {"kind": kind, "start": s, "end": e}


class UpNextCredits(unittest.TestCase):
    def test_cases(self):
        c = "Markers_finalCreditsStart"
        check_cases(self, FILES, [
            ("no credits", c, [[mk("intro", 30, 90)]], -1),
            ("no markers", c, [[]], -1),
            ("one credits range", c, [[mk("intro", 30, 90), mk("credits", 2800, 2990)]], 2800),
            ("two ranges around a scene: the last", c, [[mk("credits", 2500, 2600), mk("credits", 2700, 2990)]], 2700),
            ("order on the wire does not matter", c, [[mk("credits", 2700, 2990), mk("credits", 2500, 2600)]], 2700),
            ("touching ranges merge (1 s rounding)", c, [[mk("credits", 2500, 2699.5), mk("credits", 2700, 2990)]], 2500),
            ("overlapping ranges merge", c, [[mk("credits", 2500, 2750), mk("credits", 2700, 2990)]], 2500),
            ("invalid ranges are ignored", c, [[mk("credits", 2700, 2990), mk("credits", 2995, 2990), mk("credits", -5, 10)]], 2700),
            ("numbers as strings", c, [[mk("credits", "2500", "2600"), mk("credits", "2700", "2990")]], 2700),
            ("kind is case-insensitive", c, [[mk("Credits", 2700, 2990)]], 2700),
        ])
        r = check_cases(self, FILES, [
            ("ranges sorted by start then end", "Markers_ranges",
             [[mk("credits", 300, 400), mk("credits", 100, 300), mk("credits", 100, 200), mk("intro", 0, 10)], "credits"],
             lambda v: [(x["start"], x["end"]) for x in v] == [(100, 200), (100, 300), (300, 400)]),
        ])
        self.assertTrue(r[0]["ok"])


class NextUpPrompt(unittest.TestCase):
    """Silo Android's NextUpPromptTest: a 48:12 episode whose credits marker starts at 46:31; the
    marker must not move the prompt (silo-android #910)."""

    def test_cases(self):
        c = "NextUp_crossesPromptPoint"
        d = 2892.0
        check_cases(self, FILES, [
            ("crossing 30 s before the end", c, [2861.6, 2862.1, d, 30], True),
            ("crossing 10 s before the end", c, [2881.5, 2882.0, d, 10], True),
            ("the credits marker's start does not open it", c, [2791.0, 2792.0, d, 30], False),
            ("already past the point: no reopening", c, [2870.0, 2870.5, d, 30], False),
            ("a resume past the point (no crossing)", c, [2875.0, 2875.0, d, 30], False),
            ("At end never opens before the stream ends", c, [2891.0, 2892.0, d, 0], False),
            ("unknown duration never opens it", c, [10.0, 11.0, 0.0, 30], False),
            ("landing exactly on the point counts", c, [2861.0, 2862.0, d, 30], True),
            ("strings from a loose settings value", c, [2861.6, 2862.1, "2892", "30"], True),
            ("a missing setting is At end", c, [2861.6, 2862.1, d, None], False),
        ])


def bands(v):
    return [(b["kind"], b["start"], b["end"], b["color"]) for b in v]


class ScrubberBands(unittest.TestCase):
    """Markers_bands (Silo Android #933 / #934, silo-roku 42249ca): every occurrence of every kind,
    clamped to the file, in TheIntroDB's palette at 34% (45% emphasised)."""

    def test_cases(self):
        c = "Markers_bands"
        two_credits = [mk("credits", 2700, 2990), mk("intro", 30, 90), mk("credits", 2500, 2600),
                       mk("recap", 0, 20), mk("preview", 2990, 3000)]
        check_cases(self, FILES, [
            ("every range, kind by kind, each kind by start", c, [two_credits, 3000, False],
             lambda v: bands(v) == [("intro", 30, 90, "0x51A2FF57"), ("recap", 0, 20, "0xFF890457"),
                                    ("credits", 2500, 2600, "0xC27AFF57"), ("credits", 2700, 2990, "0xC27AFF57"),
                                    ("preview", 2990, 3000, "0x00D3F257")]),
            ("two intros both drawn", c, [[mk("intro", 30, 90), mk("intro", 1500, 1560)], 3000, False],
             lambda v: [(b["start"], b["end"]) for b in v] == [(30, 90), (1500, 1560)]),
            ("emphasised while focused or scrubbing", c, [[mk("intro", 30, 90)], 3000, True],
             lambda v: [b["color"] for b in v] == ["0x51A2FF73"]),
            ("clamped to the duration; past the end dropped", c,
             [[mk("credits", 2900, 3010), mk("preview", 3005, 3020)], 3000, False],
             lambda v: [(b["kind"], b["start"], b["end"]) for b in v] == [("credits", 2900, 3000)]),
            ("unknown kinds and empty ranges left out", c,
             [[mk("commercial", 10, 20), mk("intro", 50, 50), mk("intro", "40", "70")], 3000, False],
             lambda v: [(b["kind"], b["start"], b["end"]) for b in v] == [("intro", 40, 70)]),
            ("no duration, no bands", c, [[mk("intro", 30, 90)], 0, False], []),
            ("duration as a string", c, [[mk("intro", 30, 90)], "3000", False], lambda v: len(v) == 1),
        ])


if __name__ == "__main__":
    unittest.main()
