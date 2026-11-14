# SPDX-License-Identifier: AGPL-3.0-or-later
"""Card overlay layout maths after Silo Android #882 (the web's poster overlay layout,
silo-server #2765): the bottom corners' shared rows that wrap (Ovl_bottomLayout, Android's
OverlayLayoutMathTest cases), the band's marks that fit, the bottom inset that lifts clear of a
progress bar, the top row that stops short of the watch-status corner, the corner's size and what
it shows (CardOverlayKeys.brs: CardOverlay_check, CardOverlay_status, a port of CardWatchStatusTest),
a stored top-right badge on the right rail and the corner/rail capacity."""
import unittest

from brs import check_cases

FILES = ["components/common/Overlays.brs", "tests/overlays_io.brs", "components/common/Utils.brs"]
KEYS = ["components/common/CardOverlayKeys.brs"]


def rows(left, right, available, gap=8, stack_gap=4):
    return ("Ovl_bottomLayout", [[w for w, _ in left], [h for _, h in left], [w for w, _ in right], [h for _, h in right],
                                 available, gap, stack_gap])


def lay(expect):
    """Compares a layout with expected {lx, ly, rx, ry, h} (only the keys given), as whole numbers."""
    def check(v):
        got = {k.lower(): x for k, x in v.items()}
        for k, want in expect.items():
            have = got[k]
            if isinstance(want, list):
                if [round(x) for x in have] != want:
                    return False
            elif round(have) != want:
                return False
        return True
    return check


def case(name, left, right, available, expect):
    fn, args = rows(left, right, available)
    return (name, fn, args, lay(expect))


class BottomRows(unittest.TestCase):
    def test_android_cases(self):
        check_cases(self, FILES, [
            case("a pair that fits shares one row, the right badge at the end", [(60, 14)], [(40, 14)], 169,
                 {"h": 14, "lx": [0], "rx": [129], "ry": [0]}),
            case("a pair that fits exactly stays on one row", [(100, 14)], [(61, 14)], 169, {"h": 14, "ry": [0]}),
            case("a pair one pixel too wide wraps the right badge onto its own line", [(100, 14)], [(62, 14)], 169,
                 {"ly": [0], "ry": [18], "rx": [107], "h": 32}),
            case("a badge as wide as the card pushes its partner down", [(169, 14)], [(30, 14)], 169,
                 {"lx": [0], "rx": [139], "ry": [18]}),
            case("levels count from the bottom", [(50, 10), (50, 10), (50, 10)], [(40, 10)], 169,
                 {"ly": [0, 14, 28], "ry": [28], "h": 38}),
            case("a long badge wraps only its own level", [(150, 10), (40, 10)], [(40, 10), (40, 10)], 169,
                 {"ly": [0, 28], "ry": [14, 28], "h": 38}),
            case("badges on one line align to its bottom", [(40, 20)], [(40, 12)], 169, {"ly": [0], "ry": [8], "h": 20}),
            case("a right corner alone sits at the end", [], [(30, 10), (50, 10)], 169, {"rx": [139, 119], "ry": [0, 14]}),
            case("nothing", [], [], 169, {"h": 0}),
            ("fits", "Ovl_fitsOneLine", [100, 61, 169, 8], True),
            ("does not fit", "Ovl_fitsOneLine", [100, 62, 169, 8], False),
        ])

    def test_band(self):
        check_cases(self, FILES, [
            ("every mark that fits", "Ovl_bandFit", [[40, 30, 30], 130, 7, 1], 3),
            ("drops the first that overflows and every mark after it", "Ovl_bandFit", [[40, 30, 31, 1], 130, 7, 1], 2),
            ("keeps a first mark too wide on its own", "Ovl_bandFit", [[130, 10], 130, 7, 1], 1),
            ("one mark", "Ovl_bandFit", [[130], 130, 7, 1], 1),
            ("none", "Ovl_bandFit", [[], 130, 7, 1], 0),
        ])


class Insets(unittest.TestCase):
    def test_bottom_inset(self):
        f = "Ovl_bottomInset"
        near = lambda want: (lambda v: abs(v - want) < 0.01)  # noqa: E731
        check_cases(self, FILES, [
            ("poster: the edge inset", f, ["poster", 1.0, False, 28], near(8)),
            ("poster scales with its width", f, ["poster", 1.5, False, 28], near(12)),
            ("poster over the keyline bar: its clearance (Silo Android #902 BadgeClearance)", f, ["poster", 1.0, True, 28], near(28)),
            ("a large poster over a bar: one edge step more when that is higher", f, ["poster", 2.0, True, 28], near(32)),
            ("poster with no clearance asked: one edge step more", f, ["poster", 1.0, True, 0], near(16)),
            ("landscape: Android TV's 24", f, ["landscape", 1.0, False, 28], near(24)),
            ("landscape over a bar lifts one edge step", f, ["landscape", 1.0, True, 28], near(32)),
            ("episode rail without progress: 12", f, ["episode", 1.0, False, 28], near(12)),
            ("episode rail over a bar: the clearance (TvEpisodeCard)", f, ["episode", 1.0, True, 28], near(28)),
            ("a Large landscape card's inset grows with it (Silo Android #912)", f, ["landscape", 1.2, False, 28], near(28.8)),
            ("a Compact landscape card's inset keeps its size at scale 1", f, ["landscape", 0.86, False, 28], near(24)),
            ("a Compact episode still's too", f, ["episode", 0.86, False, 28], near(12)),
            ("a Compact poster's inset still follows its width", f, ["poster", 0.5, False, 28], near(4)),
        ])

    def test_top_row_end(self):
        f = "Ovl_topRowEnd"
        check_cases(self, FILES, [
            ("poster: inset + status + gap (8 + 22 + 8)", f, [8, 22, 1.0], lambda v: abs(v - 38) < 0.01),
            ("no status: the edge inset", f, [0, 0, 1.0], lambda v: abs(v - 8) < 0.01),
        ])


class WatchStatus(unittest.TestCase):
    def test_corner(self):
        f = "CardOverlay_check"
        check_cases(self, KEYS, [
            ("reference poster: 22 and 8", f, ["poster", 185], {"size": 22, "inset": 8}),
            ("a wider poster scales", f, ["poster", 370], {"size": 44, "inset": 16}),
            ("square art too", f, ["square", 185], {"size": 22, "inset": 8}),
            ("landscape draws none", f, ["landscape", 320], {"size": 0, "inset": 0}),
            ("episode rail keeps its own check", f, ["episode", 320], {"size": 44, "inset": 12}),
            ("episode rail's check at a Large wide scale (Silo Android #912)", f, ["episode", 320, 1.2], {"size": 53, "inset": 14}),
            ("episode rail's check at a Compact wide scale", f, ["episode", 320, 0.86], {"size": 38, "inset": 10}),
        ])

    def test_status(self):
        f = "CardOverlay_status"
        check_cases(self, KEYS, [
            ("started, unfinished series shows its count", f, [False, 6, True], "count"),
            ("nothing left or untouched shows nothing", f, [False, 0, True], ""),
            ("watched shows the check, even with a count", f, [True, 6, True], "check"),
            ("unknown watched flag (pitfall 16)", f, [None, 0, True], ""),
            ("landscape art never shows it", f, [True, 6, False], ""),
        ])


class OverlayScale(unittest.TestCase):
    """A port of Silo Android #912's OverlayScaleTest: overlay scale = card scale x text factor."""

    def near(self, want):
        return lambda v: abs(v - want) < 1e-4

    def test_text_factor(self):
        f = "CardOverlay_textFactor"
        n = self.near
        check_cases(self, KEYS, [
            ("smaller text never shrinks badges", f, [0.85], n(1.0)),
            ("default text", f, [1.0], n(1.0)),
            ("larger text", f, [1.15], n(1.15)),
            ("up to the cap", f, [1.35], n(1.35)),
            ("held at the cap", f, [2.0], n(1.35)),
            ("an unset font scale (Roku has none)", f, [None], n(1.0)),
        ])

    def test_card_scale(self):
        f = "CardOverlay_cardScale"
        n = self.near
        check_cases(self, KEYS, [
            ("a poster's width against the web reference", f, ["poster", 185, 1.2], n(1.0)),
            ("half the reference width", f, ["poster", 92.5, 0.86], n(0.5)),
            ("square art measures its width too", f, ["square", 370, 1.0], n(2.0)),
            ("a Compact wide card", f, ["landscape", 280, 0.86], n(0.86)),
            ("a Standard wide card", f, ["landscape", 280, 1.0], n(1.0)),
            ("a Large wide card", f, ["landscape", 280, 1.2], n(1.2)),
            ("an episode still follows Poster Size", f, ["episode", 360, 1.2], n(1.2)),
            ("a hero ignores Poster Size", f, ["hero", 900, 1.2], n(1.0)),
            ("Poster Size multipliers", "CardOverlay_posterScaleOf", ["compact"], n(0.86)),
            ("Large", "CardOverlay_posterScaleOf", ["Large"], n(1.2)),
            ("unknown is Standard", "CardOverlay_posterScaleOf", ["huge"], n(1.0)),
            ("none is Standard", "CardOverlay_posterScaleOf", [None], n(1.0)),
        ])

    def test_value(self):
        f = "CardOverlay_scale"
        n = self.near
        check_cases(self, KEYS, [
            ("card scale times the held text factor", f, [1.2, 1.6], n(1.2 * 1.35)),
            ("smaller text leaves the card scale", f, [0.86, 0.9], n(0.86)),
            ("larger text", f, [1.0, 1.3], n(1.3)),
        ])

    def test_scale_for_the_open_profile(self):
        f = "CardOverlay_scaleFor"
        n = self.near
        large = {"global": {"cardPosterScale": 1.2}}
        check_cases(self, KEYS, [
            ("a wide card at the recorded Poster Size", f, ["landscape", 360], n(1.2), large),
            ("a poster ignores it", f, ["poster", 370], n(2.0), large),
            ("before ShellScreen recorded one: Standard", f, ["episode", 360], n(1.0)),
        ])


class Positions(unittest.TestCase):
    def test_top_right_reads_as_right_rail(self):
        doc = {"version": 2, "preset": "classic", "order": [],
               "items": {k: {"enabled": True, "position": "top-right"} for k in ["rating_imdb", "rating_tmdb", "rating_rt", "rating_rt_audience", "year"]}}
        data = {"rating_imdb": 8.1, "rating_tmdb": 7.5, "rating_rt_critic": 90, "rating_rt_audience": 80, "year": 2001}
        check_cases(self, FILES, [
            ("stored top-right is the right rail", "Ovl_placedOf", [doc, "right-edge"],
             ["rating_imdb", "rating_tmdb", "rating_rt", "rating_rt_audience", "year"]),
            ("nothing is placed top-right", "Ovl_placedOf", [doc, "top-right"], []),
            ("the rail draws four", "Ovl_resolveIds", [doc, data],
             lambda v: v["rightEdge" if "rightEdge" in v else "rightedge"] == ["rating_imdb", "rating_tmdb", "rating_rt", "rating_rt_audience"]),
            ("capacities", "Ovl_maxCorner", [], 3),
            ("rail capacity", "Ovl_maxRail", [], 4),
        ])

    def test_show_status_untrimmed(self):
        check_cases(self, FILES, [
            ("known status", "Ovl_showStatusKey", ["Returning Series"], "Returning"),
            ("padded value passes through as sent", "Ovl_showStatusKey", [" ended "], " ended "),
        ])

    def test_tracking(self):
        check_cases(self, FILES, [
            ("classic is tracking-wide", "Ovl_lookOf", ["classic", None], lambda v: abs(v["tracking"] - 0.025) < 1e-6),
            ("minimal is tracking-widest", "Ovl_lookOf", ["minimal", None], lambda v: abs(v["tracking"] - 0.1) < 1e-6),
            ("square is tracking-widest", "Ovl_lookOf", ["square", None], lambda v: abs(v["tracking"] - 0.1) < 1e-6),
        ])


if __name__ == "__main__":
    unittest.main()
