# SPDX-License-Identifier: AGPL-3.0-or-later
"""Home Sections layout per server + profile (Settings_homeLayoutFor / Settings_homeLayoutsWith),
as Android TV keys its home-section store by server, account and profile."""
import unittest

from brs import check_cases

FILES = ["components/common/Utils.brs", "components/common/Content.brs", "components/common/Settings.brs"]
A = "http://s:8097|p-owner"
B = "http://s:8097|p-sam"


class HomeLayout(unittest.TestCase):
    def test_read(self):
        f = "Settings_homeLayoutFor"
        stored = {"homeLayouts": [{"key": A, "hidden": ["cw"], "order": ["recent", "cw"]}]}
        legacy = {"hiddenSections": ["x"], "sectionOrder": ["y"]}
        check_cases(self, FILES, [
            ("stored for this profile", f, [stored, A], {"hidden": ["cw"], "order": ["recent", "cw"]}),
            ("another profile starts empty", f, [stored, B], {"hidden": [], "order": []}),
            ("an older build's device-wide lists", f, [legacy, A], {"hidden": ["x"], "order": ["y"]}),
            ("stored wins over the old lists", f, [dict(stored, **legacy), A], {"hidden": ["cw"], "order": ["recent", "cw"]}),
            ("no prefs", f, [None, A], {"hidden": [], "order": []}),
            ("junk entries", f, [{"homeLayouts": ["x", 3, {"key": A, "hidden": "no"}]}, A], {"hidden": [], "order": []}),
        ])

    def test_write(self):
        f = "Settings_homeLayoutsWith"
        prefs = {"homeLayouts": [{"key": B, "hidden": [], "order": ["a"]}, {"key": A, "hidden": ["old"], "order": []}]}
        many = {"homeLayouts": [{"key": "k%d" % i, "hidden": [], "order": []} for i in range(10)]}
        big = {"homeLayouts": [{"key": "k%d" % i, "hidden": ["section-%d-%s" % (j, "x" * 40) for j in range(10)], "order": []}
                               for i in range(5)]}
        check_cases(self, FILES, [
            ("replaced and moved first", f, [prefs, A, {"hidden": ["cw"], "order": []}],
             [{"key": A, "hidden": ["cw"], "order": []}, {"key": B, "hidden": [], "order": ["a"]}]),
            ("first write", f, [{}, A, {"hidden": [], "order": ["z"]}], [{"key": A, "hidden": [], "order": ["z"]}]),
            ("capped at 8 entries", f, [many, A, {"hidden": [], "order": []}], lambda v: len(v) == 8 and v[0]["key"] == A),
            ("byte budget drops the oldest", f, [big, A, {"hidden": ["cw"], "order": []}],
             lambda v: 1 <= len(v) < 6 and v[0]["key"] == A and v[1]["key"] == "k0"),
        ])


if __name__ == "__main__":
    unittest.main()
