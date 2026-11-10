# SPDX-License-Identifier: AGPL-3.0-or-later
"""Interface language (I18n in Utils.brs; tools/i18n_build.py): choosing the language from the
profile's ui.app_language and the Roku's locale, Tx / TxF / TxP lookups and plural forms, and the
built language files covering every marked text."""
import json
import os
import subprocess
import sys
import unittest

from brs import ROOT, check_cases

UTILS = ["components/common/Utils.brs"]
DE = {"appLocale": "de", "strings": {"Play": "Wiedergeben", "Sign in on {0}": "Bei {0} anmelden",
                                     "1 season": "1 Staffel", "{0} seasons": "{0} Staffeln"}}
FR = {"appLocale": "fr", "strings": {"1 season": "1 saison", "{0} seasons": "{0} saisons"}}


class Resolve(unittest.TestCase):
    def test_cases(self):
        r = "I18n_resolve"
        check_cases(self, UTILS, [
            ("profile override wins", r, ["de", "en_US"], "de"),
            ("unset follows the Roku", r, ["", "fr_CA"], "fr"),
            ("invalid follows the Roku", r, [None, "es_MX"], "es"),
            ("regional tag", r, ["es-MX", "en_US"], "es"),
            ("European Portuguese uses Brazilian", r, ["pt-PT", "en_US"], "pt_BR"),
            ("Brazilian tag", r, ["pt-BR", "en_US"], "pt_BR"),
            ("unshipped override falls back to the Roku", r, ["ja", "de_DE"], "de"),
            ("nothing shipped is English", r, ["ja", "ko_KR"], "en"),
            ("pseudo-locale never matches", r, ["en-XA", "fr_FR"], "fr"),
            ("tag of Brazilian", "I18n_tagOf", ["pt_BR"], "pt-BR"),
            ("native name", "I18n_nativeName", ["de"], "Deutsch"),
        ])


class Lookup(unittest.TestCase):
    def test_cases(self):
        check_cases(self, UTILS, [
            ("English is the key", "Tx", ["Play"], "Play", {"global": {"appLocale": "en", "strings": {}}}),
            ("translated", "Tx", ["Play"], "Wiedergeben", {"global": DE}),
            ("missing shows English", "Tx", ["Pause"], "Pause", {"global": DE}),
            ("format", "TxF", ["Sign in on {0}", ["Home"]], "Bei Home anmelden", {"global": DE}),
            ("format a number", "TxF", ["Sign in on {0}", [3]], "Bei 3 anmelden", {"global": DE}),
            ("German one", "TxP", ["1 season", "{0} seasons", 1], "1 Staffel", {"global": DE}),
            ("German other", "TxP", ["1 season", "{0} seasons", 0], "0 Staffeln", {"global": DE}),
            ("French zero is one", "TxP", ["1 season", "{0} seasons", 0], "1 saison", {"global": FR}),
            ("English other", "TxP", ["1 season", "{0} seasons", 4], "4 seasons", {"global": {"appLocale": "en", "strings": {}}}),
        ])


KEYED = {"appLocale": "de", "strings": {"@home.section.recentlyAddedIn": "Neu in {library}",
                                          "@error.not_found": "Nicht gefunden."}}


class ServerKeys(unittest.TestCase):
    def test_cases(self):
        k = "TxKey"
        check_cases(self, UTILS, [
            ("keyed title with its argument", k, ["home.section.recentlyAddedIn", {"library": "Filme"}, "Recently Added in Movies"], "Neu in Filme", {"global": KEYED}),
            ("missing argument keeps the server title", k, ["home.section.recentlyAddedIn", {}, "Recently Added in Movies"], "Recently Added in Movies", {"global": KEYED}),
            ("unknown key keeps the server title", k, ["home.section.nope", None, "Nope"], "Nope", {"global": KEYED}),
            ("no key keeps the server title", k, [None, None, "Custom row"], "Custom row", {"global": KEYED}),
            ("English keeps the server title", k, ["error.not_found", None, "Not found"], "Not found", {"global": {"appLocale": "en", "strings": {}}}),
            ("problem type", k, ["error.not_found", None, ""], "Nicht gefunden.", {"global": KEYED}),
        ])


class LanguageFiles(unittest.TestCase):
    def test_built_files_are_current_and_parse(self):
        res = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "i18n_build.py"), "--check"],
                             capture_output=True, text=True)
        self.assertNotIn("out of date", res.stdout, res.stdout)
        for lang in ("es", "de", "fr", "pt_BR"):
            with open(os.path.join(ROOT, "locale", lang, "strings.json"), encoding="utf-8") as f:
                table = json.load(f)
            lowered = {}
            for k in table:
                self.assertNotIn(k.lower(), lowered, "%s: %r and %r differ only by case (Roku keys ignore case)" % (lang, k, lowered.get(k.lower())))
                lowered[k.lower()] = k
            for k, v in table.items():
                for i in range(5):
                    ph = "{%d}" % i
                    self.assertEqual(ph in k, ph in v, "%s: %r -> %r loses or adds %s" % (lang, k, v, ph))


if __name__ == "__main__":
    unittest.main()
