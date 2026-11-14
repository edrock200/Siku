# SPDX-License-Identifier: AGPL-3.0-or-later
"""The watch-progress keyline bar's geometry (Silo Android #902 WatchProgressBar at Android TV's
4 dp, doubled to px): 20 px in from the sides, 16 px up (8 under a box set's film count), 8 px tall,
the track Poster carrying 8 px of shadow room and the fill Poster a 1 px hairline; a tiny fraction
still draws the fill's round ends, a full one fills the track exactly. Badges clear it by 28 px."""
import unittest

from brs import check_cases

FILES = ["components/common/WatchProgress.brs", "components/common/Utils.brs"]


def geo(expect):
    def check(v):
        got = {k.lower(): x for k, x in v.items()}
        return all(got[k.lower()] == want for k, want in expect.items())
    return check


class Geometry(unittest.TestCase):
    def test_bar(self):
        f = "WatchProgress_geometry"
        check_cases(self, FILES, [
            ("a 360x203 landscape card half watched", f, [360, 203, 0.5, False],
             geo({"trackX": 12, "trackY": 171, "trackW": 336, "trackH": 24, "fillX": 19, "fillY": 178, "fillW": 162, "fillH": 10})),
            ("under a corner label it sits 8 px up", f, [246, 369, 1.0, True],
             geo({"trackY": 369 - 8 - 8 - 8, "fillW": 206 + 2})),
            ("a tiny fraction keeps the fill's round ends", f, [246, 369, 0.001, False], geo({"fillW": 9 + 2})),
            ("a fraction past 1 fills the track", f, [246, 369, 3, False], geo({"fillW": 206 + 2})),
            ("a string fraction from a server", f, [246, 369, "0.5", False], geo({"fillW": 103 + 2})),
            ("badges clear the bar by 28 px", "WatchProgress_metrics", [], lambda v: {k.lower(): x for k, x in v.items()}["clearance"] == 28),
        ])


if __name__ == "__main__":
    unittest.main()
