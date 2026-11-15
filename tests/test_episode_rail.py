# SPDX-License-Identifier: AGPL-3.0-or-later
"""The series page's episode rail at each Poster Size (Silo Android TV TvDetailEpisodeRail:
tvEpisodeCardWidth().cardScaled(), 180 dp doubled to 360 px, ×0.86 / ×1 / ×1.2): the card's width and
16:9 still scale, the caption (218 px), the 40 px between cards and the 130 px above the row do not;
the cell keeps headroom for the focused still's lift and shadow; the watched check and the badges
follow the same scale (CardOverlay_check, CardOverlay_scaleFor)."""
import unittest

from brs import check_cases

FILES = ["components/common/EpisodeRail.brs", "components/common/CardFocus.brs", "components/common/CardOverlayKeys.brs"]


def geo(expect):
    def check(v):
        got = {k.lower(): x for k, x in v.items()}
        return all(got[k.lower()] == want for k, want in expect.items())
    return check


class Geometry(unittest.TestCase):
    def test_sizes(self):
        f = "EpisodeRail_geometry"
        check_cases(self, FILES, [
            ("Standard keeps v0.6.0's rail", f, [1.0],
             geo({"cardW": 360, "stillH": 202, "insetY": 20, "cellH": 440, "spacing": 40, "rowY": 110, "sectionH": 550})),
            ("Compact", f, [0.86],
             geo({"cardW": 310, "stillH": 174, "insetY": 20, "cellH": 412, "spacing": 40, "rowY": 110, "sectionH": 522})),
            ("Large", f, [1.2],
             geo({"cardW": 432, "stillH": 243, "insetY": 21, "cellH": 482, "spacing": 40, "rowY": 109, "sectionH": 591})),
            ("anything but a number is Standard", f, ["large"], geo({"cardW": 360, "cellH": 440})),
            ("zero is Standard", f, [0], geo({"cardW": 360})),
            ("the item's still matches the rail's", "EpisodeRail_stillHeight", [432], 243),
        ])

    def test_headroom_covers_the_lift_and_shadow(self):
        # The shadow reaches 14 px above the art (CardFocus_layoutShadow) and the card group scales
        # by 1.05 about its top-left after moving up by the lift: the highest drawn row must stay
        # inside the cell.
        for scale in (0.86, 1.0, 1.2):
            with self.subTest(scale=scale):
                g = check_cases(self, FILES, [("g", "EpisodeRail_geometry", [scale], lambda v: True)])[0]["value"]
                g = {k.lower(): v for k, v in g.items()}
                w, h = g["cardw"], g["stillh"]
                t = check_cases(self, FILES, [("t", "CardFocus_transform", [w, h, 1.0, [0, g["insety"]]], lambda v: True)])[0]["value"]
                t = {k.lower(): v for k, v in t.items()}
                top = t["translation"][1] - 14 * t["scale"][1]
                self.assertGreaterEqual(top, 0)
                # The still and three description lines fit in the cell below it.
                self.assertGreaterEqual(g["cellh"] - g["insety"] - h, 218)

    def test_check_follows_the_card(self):
        # The watched check is 44 px 12 in on a Standard card and scales with Poster Size, as the card does.
        cases = []
        for size, scale, want in (("compact", 0.86, {"size": 38, "inset": 10}), ("standard", 1.0, {"size": 44, "inset": 12}), ("large", 1.2, {"size": 53, "inset": 14})):
            cases.append(("check " + size, "CardOverlay_check", ["episode", 360, scale], want))
            cases.append(("scale " + size, "CardOverlay_posterScaleOf", [size], lambda v, s=scale: abs(v - s) < 1e-6))
        check_cases(self, FILES, cases)


if __name__ == "__main__":
    unittest.main()
