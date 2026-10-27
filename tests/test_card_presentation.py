# SPDX-License-Identifier: AGPL-3.0-or-later
"""ui.card_presentation after the caption choice was retired (Silo Android #700): poster size is the
only option, a stored caption is ignored, and writes always carry caption "title_metadata"."""
import unittest

from brs import check_cases, glob

FILES = ["components/common/Settings.brs", "components/common/Utils.brs", "components/common/Content.brs",
         "components/common/Spoilers.brs"]
THEME = ["components/common/Theme.brs", "components/common/Utils.brs"]


def g(value, prefs=None):
    return {"global": glob({"ui.card_presentation": value} if value is not None else {}, prefs)}


class CardPresentation(unittest.TestCase):
    def test_settings_reads_poster_size_only(self):
        check_cases(self, FILES, [
            ("artwork caption ignored", "Settings_cardPresentation", [],
             {"postersize": "large"}, g({"poster_size": "large", "caption": "artwork"})),
            ("title caption ignored", "Settings_cardPresentation", [],
             {"postersize": "compact"}, g({"poster_size": "COMPACT", "caption": "title"})),
            ("no value falls back to the device pref", "Settings_cardPresentation", [],
             {"postersize": "large"}, g(None, {"posterSize": "large"})),
            ("write body", "Settings_cardPresentationBody", ["compact"],
             {"poster_size": "compact", "caption": "title_metadata"}, g(None)),
            ("ui signature does not change with the caption", "Settings_uiSignature", [],
             lambda v: "artwork" not in v, g({"poster_size": "large", "caption": "artwork"})),
        ])

    def test_theme_reads_poster_size_only(self):
        check_cases(self, THEME, [
            ("theme ignores the caption", "Theme_cardPresentation", [],
             {"postersize": "large"}, g({"poster_size": "large", "caption": "artwork"})),
        ])


if __name__ == "__main__":
    unittest.main()
