# SPDX-License-Identifier: AGPL-3.0-or-later
"""Grouped counts (Silo Android #916, silo-roku ed824d3, Apple's LocaleFormat.groupedCount): library,
collection and person counts carry the interface language's thousands separator; Spanish groups
from five digits, Mexican Spanish and Canadian French follow the device's region."""
import unittest

from brs import check_cases

FILES = ["components/common/Utils.brs", "components/common/Paging.brs"]
NNBSP = " "
NBSP = " "


def g(name, n, folder, want, device="en_US"):
    return (name, "I18n_groupedCount", [n, folder, device], want)


def de_global():
    return {"global": {"appLocale": "de", "strings": {"{0} titles": "{0} Titel", "{0} title": "{0} Titel"}}}


class Grouped(unittest.TestCase):
    def test_separators(self):
        check_cases(self, FILES, [
            g("three digits stay as they are", 999, "en", "999"),
            g("English groups with a comma", 1284, "en", "1,284"),
            g("millions", 1234567, "en", "1,234,567"),
            g("German groups with a dot", 1284, "de", "1.284"),
            g("Brazilian Portuguese groups with a dot", 12840, "pt_BR", "12.840"),
            g("French uses a narrow no-break space", 1284, "fr", "1" + NNBSP + "284"),
            g("Canadian French uses a no-break space", 1284, "fr", "1" + NBSP + "284", "fr_CA"),
            g("Spanish leaves four digits alone", 1284, "es", "1284"),
            g("Spanish groups from five digits", 12840, "es", "12.840"),
            g("Mexican Spanish groups from four with a comma", 1284, "es", "1,284", "es_MX"),
            g("Dutch groups with a dot (silo-roku 1cc1149)", 1284, "nl", "1.284"),
            g("Italian, Turkish, Croatian and Danish group with a dot", 1284, "tr", "1.284"),
            g("Russian groups with a no-break space", 1284, "ru", "1" + NBSP + "284"),
            g("Finnish groups with a no-break space", 12840, "fi", "12" + NBSP + "840"),
            g("Polish leaves four digits alone", 1284, "pl", "1284"),
            g("Polish groups from five digits", 12840, "pl", "12" + NBSP + "840"),
            g("zero", 0, "de", "0"),
            g("negative", -1284, "en", "-1,284"),
        ])

    def test_counts(self):
        check_cases(self, FILES, [
            ("a person's titles are grouped", "Paging_titleCount", [1284, 60, True], "1,284 titles"),
            ("loaded titles with more to come", "Paging_titleCount", [None, 1200, True], "1,200+ titles"),
            ("a grouped count in German", "Paging_titleCount", [1284, 60, True], "1.284 Titel", de_global()),
            ("ungrouped TxP stays as it was", "TxP", ["{0} title", "{0} titles", 1284], "1284 titles"),
        ])


if __name__ == "__main__":
    unittest.main()
