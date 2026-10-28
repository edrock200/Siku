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


class MoreRetryDelay(unittest.TestCase):
    """A failed "load more" waits before the grid asks again (no request and toast per key)."""

    def test_backoff(self):
        f = "Library_moreRetryDelay"
        check_cases(self, FILES, [
            ("no failure", f, [0], 0, {}),
            ("first", f, [1], 5, {}),
            ("second", f, [2], 10, {}),
            ("fourth", f, [4], 40, {}),
            ("capped", f, [5], 60, {}),
            ("many", f, [50], 60, {}),
        ])


if __name__ == "__main__":
    unittest.main()
