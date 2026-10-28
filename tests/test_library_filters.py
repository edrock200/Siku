# SPDX-License-Identifier: AGPL-3.0-or-later
"""Library_watchRule: the watch-status filter's catalog rule. Flag values must be JSON booleans;
the server answers 500 to "true"/"false" strings (Silo Android #702)."""
import unittest

from brs import check_cases

FILES = ["components/screens/library/LibraryPage.brs"]


def rule(field, value):
    return lambda v: v == {"field": field, "op": "is", "value": value} and isinstance(v["value"], bool)


class WatchRule(unittest.TestCase):
    def test_flag_values_are_booleans(self):
        f = "Library_watchRule"
        check_cases(self, FILES, [
            ("unwatched", f, ["unwatched"], rule("watched", False), {}),
            ("watched", f, ["watched"], rule("watched", True), {}),
            ("in progress", f, ["in_progress"], rule("in_progress", True), {}),
            ("favorited", f, ["favorited"], rule("favorited", True), {}),
            ("watchlist", f, ["watchlist"], rule("in_watchlist", True), {}),
        ])


if __name__ == "__main__":
    unittest.main()
