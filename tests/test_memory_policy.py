# SPDX-License-Identifier: AGPL-3.0-or-later
"""MemoryPolicy.brs (levels and budgets), GridWindow.brs (bounded library grid) and the device tier
read in source/MainEvents.brs."""
import unittest

from brs import check_cases

POLICY = ["components/common/MemoryPolicy.brs"]
WINDOW = ["components/common/GridWindow.brs"]
EVENTS = ["source/MainEvents.brs"]


def window(pages):
    """pages: [(start, size, loaded)]"""
    return {"pages": [{"start": s, "size": n, "cursor": "c%d" % s, "loaded": l} for s, n, l in pages]}


class MemoryPolicy(unittest.TestCase):
    def test_levels(self):
        n = "Memory_nextLevel"
        check_cases(self, POLICY, [
            ("quiet", n, [0, 40], 0),
            ("first warning trims", n, [0, 80], 1),
            ("70 trims", n, [0, 70], 1),
            ("85 is pressure", n, [0, 85], 2),
            ("90 is critical", n, [1, 92], 3),
            ("rises at once past a level", n, [0, 95], 3),
            ("stays while above 65", n, [3, 70], 3),
            ("falls one step below 65", n, [3, 60], 2),
            ("falls to normal from trim", n, [1, 10], 0),
            ("unknown sample keeps", n, [2, -1], 2),
        ])

    def test_budgets(self):
        check_cases(self, POLICY, [
            ("alive normal", "Memory_aliveBelow", [0, False], 2),
            ("alive low end", "Memory_aliveBelow", [0, True], 1),
            ("alive trim", "Memory_aliveBelow", [1, False], 1),
            ("alive pressure", "Memory_aliveBelow", [2, False], 0),
            ("pages normal", "Memory_gridPages", [0, False], 10),
            ("pages low end", "Memory_gridPages", [0, True], 5),
            ("pages trim", "Memory_gridPages", [1, True], 3),
            ("pages critical", "Memory_gridPages", [3, False], 2),
            ("prefetch normal", "Memory_prefetchRows", [0, False], 8),
            ("prefetch low end", "Memory_prefetchRows", [0, True], 5),
            ("prefetch trim", "Memory_prefetchRows", [1, False], 5),
            ("level from global", "Memory_currentLevel", [], 2, {"global": {"memoryLevel": 2}}),
            ("low end from global", "Memory_isLowEnd", [], True, {"global": {"lowEnd": True}}),
            ("no global fields", "Memory_currentLevel", [], 0, {"global": {}}),
        ])


class GridWindowTest(unittest.TestCase):
    def test_drop_and_reload(self):
        twelve = [(i * 60, 60, True) for i in range(12)]
        check_cases(self, WINDOW, [
            ("within budget drops nothing", "GridWindow_toDrop", [window(twelve[:10]), 300, 56, 10], []),
            # focus on the last page: the first pages are the furthest
            ("drops the furthest first", "GridWindow_toDrop", [window(twelve), 700, 56, 10], [0, 1]),
            # focus at the start of page 5 (300): the reach covers page 4, budget 1 keeps both
            ("never drops within reach", "GridWindow_toDrop", [window(twelve[:7]), 300, 56, 1],
             lambda v: sorted(v) == [0, 1, 2, 3, 6]),
            ("nothing to reload", "GridWindow_toReload", [window(twelve), 300, 56], -1),
            ("reloads an emptied page in reach", "GridWindow_toReload",
             [window([(0, 60, False), (60, 60, True), (120, 60, True)]), 90, 56], 0),
            ("emptied page out of reach waits", "GridWindow_toReload",
             [window([(0, 60, False), (60, 60, True), (120, 60, True)]), 150, 56], -1),
            ("nearest emptied page first", "GridWindow_toReload",
             [window([(0, 60, False), (60, 60, True), (120, 60, False)]), 100, 56], 2),
            ("loaded count", "GridWindow_loadedCount", [window([(0, 60, False), (60, 60, True)])], 1),
        ])


class DeviceTier(unittest.TestCase):
    def test_tier(self):
        t = "MainEvents_deviceTier"
        good = {"ui": "FHD", "graphics": "opengl", "warnings": True, "foregroundKb": 593920}
        check_cases(self, EVENTS, [
            ("standard", t, [good], {"low": False, "reasons": "", "foregroundMb": 580}),
            ("small limit", t, [dict(good, foregroundKb=307200)], {"low": True, "reasons": "foregroundLimit", "foregroundMb": 300}),
            ("HD UI without OpenGL", t, [dict(good, ui="HD", graphics="directfb")], lambda v: v["low"] and v["reasons"] == "ui,graphics"),
            ("nothing known", t, [{"ui": "", "graphics": "", "warnings": False, "foregroundKb": -1}],
             {"low": True, "reasons": "ui,graphics,monitor,foregroundLimit", "foregroundMb": -1}),
            ("sample without monitor", "MainEvents_memorySample", [None], -1),
        ])


if __name__ == "__main__":
    unittest.main()
