# SPDX-License-Identifier: AGPL-3.0-or-later
"""Num_or / Content_num / Content_numOr: server numbers that may arrive as strings (pitfall 6)."""
import unittest

from brs import check_cases

FILES = ["components/common/Utils.brs", "components/common/Content.brs", "components/common/Settings.brs"]


class Numbers(unittest.TestCase):
    def test_cases(self):
        check_cases(self, FILES, [
            ("Num_or int", "Num_or", [42], 42),
            ("Num_or float", "Num_or", [1.5], 1.5),
            ("Num_or numeric string", "Num_or", ["42"], 42),
            ("Num_or padded string", "Num_or", [" 7.5 "], 7.5),
            ("Num_or blank string -> fallback", "Num_or", ["  ", 3], 3),
            ("Num_or null -> fallback", "Num_or", [None, 2], 2),
            ("Num_or object -> fallback", "Num_or", [{"a": 1}, 1], 1),
            ("Num_or bool -> fallback", "Num_or", [True, 9], 9),
            ("Num_or text -> 0", "Num_or", ["abc", 5], 0),
            ("Content_num int", "Content_num", [12], 12),
            ("Content_num null", "Content_num", [None], 0),
            ("Content_num numeric string (was 0 before the fix)", "Content_num", ["3600"], 3600),
            ("Content_num padded string", "Content_num", [" 90 "], 90),
            ("Content_num text", "Content_num", ["soon"], 0),
            ("Content_num array", "Content_num", [[1]], 0),
            ("Content_numOr string", "Content_numOr", ["6000", 0], 6000),
            ("Content_numOr blank", "Content_numOr", ["", 4], 4),
            ("Content_numOr null", "Content_numOr", [None, 4], 4),
        ])

    def test_returns_float(self):
        from brs import calls
        r = calls(FILES, [{"fn": "Num_or", "args": ["3"]}, {"fn": "Content_num", "args": [3]}])
        self.assertEqual([x["type"] for x in r], ["Float", "Float"])


if __name__ == "__main__":
    unittest.main()
