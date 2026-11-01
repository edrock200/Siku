# SPDX-License-Identifier: AGPL-3.0-or-later
"""Markers_upNextCreditsStart (Silo Android #694): Up Next waits for the LAST credits range, extended
back over credits ranges that run into it, so a scene between two credits ranges still plays."""
import unittest

from brs import check_cases

FILES = ["components/player/MarkerTimeline.brs", "components/common/Utils.brs"]


def mk(kind, s, e):
    return {"kind": kind, "start": s, "end": e}


class UpNextCredits(unittest.TestCase):
    def test_cases(self):
        c = "Markers_upNextCreditsStart"
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


if __name__ == "__main__":
    unittest.main()
