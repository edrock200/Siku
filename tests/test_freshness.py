# SPDX-License-Identifier: AGPL-3.0-or-later
"""Freshness.brs: when a page reads its data again because signed artwork may have expired."""
import unittest

from brs import check_cases

FILES = ["components/common/Freshness.brs", "components/common/Utils.brs"]
NOW = 1_800_000_000


class Freshness(unittest.TestCase):
    def test_cases(self):
        s, a = "Fresh_isStale", "Fresh_artReloadDue"
        check_cases(self, FILES, [
            ("never loaded is not stale", s, [0, NOW], False),
            ("ten minutes is fresh", s, [NOW - 600, NOW], False),
            ("fifteen minutes is stale", s, [NOW - 900, NOW], True),
            ("overnight is stale", s, [NOW - 8 * 3600, NOW], True),
            ("a fresh answer's broken image is not expiry", a, [NOW - 60, 0, NOW], False),
            ("an old answer's failed image re-reads", a, [NOW - 400, 0, NOW], True),
            ("not twice within ten minutes", a, [NOW - 400, NOW - 300, NOW], False),
            ("again after ten minutes", a, [NOW - 4000, NOW - 700, NOW], True),
            ("never loaded never re-reads", a, [0, 0, NOW], False),
            ("remote uri", "Fresh_isRemoteUri", ["https://silo.example/a.jpg?exp=1&sig=x"], True),
            ("package uri", "Fresh_isRemoteUri", ["pkg:/images/ui/r16.9.png"], False),
        ])


if __name__ == "__main__":
    unittest.main()
