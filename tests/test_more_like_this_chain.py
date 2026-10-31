# SPDX-License-Identifier: AGPL-3.0-or-later
"""Nav_chainAction: a "More Like This" pick on a detail page (Silo Android #737). The first pick
pushes, later picks replace the page a rail opened, picking the chain's start goes back to it, and
the title already on screen opens nothing."""
import unittest

from brs import check_cases

FILES = ["components/common/Nav.brs", "components/common/Utils.brs"]


class ChainAction(unittest.TestCase):
    def test_cases(self):
        c = "Nav_chainAction"
        check_cases(self, FILES, [
            ("a page opened another way pushes", c, ["movie:a", "", "movie:b"], "push"),
            ("a rail-opened page replaces itself", c, ["movie:b", "movie:a", "movie:c"], "replace"),
            ("the chain's start goes back to it", c, ["movie:c", "movie:a", "movie:a"], "back"),
            ("the title on screen opens nothing", c, ["movie:b", "movie:a", "movie:b"], "ignore"),
            ("the title on screen, outside a chain", c, ["movie:a", "", "movie:a"], "ignore"),
            ("a card without an id", c, ["movie:a", "", ""], "ignore"),
        ])


if __name__ == "__main__":
    unittest.main()
