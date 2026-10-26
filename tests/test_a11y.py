# SPDX-License-Identifier: AGPL-3.0-or-later
"""Screen reader wording (A11y.brs): "label, role, N of M", trimming and the never-read rules."""
import unittest

from brs import check_cases

FILES = ["components/common/A11y.brs", "components/widgets/PlayerTransportButton.brs"]


class Wording(unittest.TestCase):
    def test_text(self):
        t = "A11y_text"
        check_cases(self, FILES, [
            ("label, role, position", t, ["Play", "button", 0, 4], "Play, button, 1 of 4"),
            ("no position for a single control", t, ["Done", "button", 0, 1], "Done, button"),
            ("no position when unknown", t, ["Search", "button", -1, 0], "Search, button"),
            ("out-of-range index", t, ["Movies", "tab", 5, 3], "Movies, tab"),
            ("no role", t, ["Wrong PIN", "", -1, 0], "Wrong PIN"),
            ("trimmed", t, ["  Settings \n", "button", 1, 2], "Settings, button, 2 of 2"),
            ("empty label says nothing", t, ["   ", "button", 0, 2], ""),
            ("non-text label says nothing", t, [None, "button", 0, 2], ""),
            ("a URL is never read", t, ["http://192.168.1.5:8097", "button", 0, 1], ""),
            ("an e-mail login is never read", t, ["laura@example.com", "button", 0, 1], ""),
            ("cut to 120 characters", "A11y_clean", ["x" * 300], "x" * 120),
            ("number label", "A11y_clean", [5], ""),
        ])

    def test_transport_names(self):
        n = "Transport_iconName"
        check_cases(self, FILES, [
            ("pause", n, ["pkg:/images/icons/pause.png"], "Pause"),
            ("play", n, ["pkg:/images/icons/play.png"], "Play"),
            ("skip back", n, ["pkg:/images/icons/rewind.png"], "Skip back"),
            ("next episode", n, ["pkg:/images/icons/skip_next.png"], "Next episode"),
            ("close", n, ["pkg:/images/icons/close.png"], "Close player"),
            ("unknown icon", n, ["pkg:/images/icons/whatever.png"], ""),
            ("empty", n, [""], ""),
        ])


if __name__ == "__main__":
    unittest.main()
