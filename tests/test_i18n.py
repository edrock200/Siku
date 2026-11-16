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
FR = {"appLocale": "fr", "strings": {"1 season": "1 saison", "{0} seasons": "{0} saisons", "{0} title": "{0} titre", "{0} titles": "{0} titres"}}
RU = {"appLocale": "ru", "strings": {"1 season": "1 сезон", "{0} seasons": "{0} сезона",
                                     "{0} seasons#one": "{0} сезон", "{0} seasons#few": "{0} сезона",
                                     "{0} seasons#many": "{0} сезонов"}}
PL = {"appLocale": "pl", "strings": {"1 season": "1 sezon", "{0} seasons": "{0} sezonu",
                                     "{0} seasons#few": "{0} sezony", "{0} seasons#many": "{0} sezonów"}}
CS = {"appLocale": "cs", "strings": {"1 season": "1 řada", "{0} seasons": "{0} řad", "{0} seasons#few": "{0} řady"}}


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
            ("Dutch (silo-roku 1cc1149)", r, ["nl-BE", "en_US"], "nl"),
            ("Norwegian no is Bokmål", r, ["no", "en_US"], "nb"),
            ("a Norwegian Roku is Bokmål", r, ["", "no_NO"], "nb"),
            ("Nynorsk has no folder", r, ["nn", "en_US"], "en"),
            ("Ukrainian Roku", r, ["", "uk_UA"], "uk"),
            ("Korean stays out (no font)", r, ["ko", "en_US"], "en"),
            ("tag of Brazilian", "I18n_tagOf", ["pt_BR"], "pt-BR"),
            ("tag of Bokmål", "I18n_tagOf", ["nb"], "nb"),
            ("native name", "I18n_nativeName", ["de"], "Deutsch"),
            ("native name in Cyrillic", "I18n_nativeName", ["uk"], "Українська"),
            ("seventeen languages", "I18n_folders", [], lambda v: len(v) == 17 and v[0] == "en" and v[-1] == "uk"),
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
            ("French zero is one, but \"1 saison\" would say 1", "TxP", ["1 season", "{0} seasons", 0], "0 saisons", {"global": FR}),
            ("French zero with a {0} one form", "TxP", ["{0} title", "{0} titles", 0], "0 titre", {"global": FR}),
            ("English other", "TxP", ["1 season", "{0} seasons", 4], "4 seasons", {"global": {"appLocale": "en", "strings": {}}}),
            ("Russian one", "TxP", ["1 season", "{0} seasons", 1], "1 сезон", {"global": RU}),
            ("Russian 21 is one, with its number", "TxP", ["1 season", "{0} seasons", 21], "21 сезон", {"global": RU}),
            ("Russian few", "TxP", ["1 season", "{0} seasons", 3], "3 сезона", {"global": RU}),
            ("Russian many", "TxP", ["1 season", "{0} seasons", 5], "5 сезонов", {"global": RU}),
            ("Russian 12 is many", "TxP", ["1 season", "{0} seasons", 12], "12 сезонов", {"global": RU}),
            ("Russian zero is many", "TxP", ["1 season", "{0} seasons", 0], "0 сезонов", {"global": RU}),
            ("Polish few", "TxP", ["1 season", "{0} seasons", 22], "22 sezony", {"global": PL}),
            ("Polish 21 is many", "TxP", ["1 season", "{0} seasons", 21], "21 sezonów", {"global": PL}),
            ("Czech few", "TxP", ["1 season", "{0} seasons", 4], "4 řady", {"global": CS}),
            ("Czech other", "TxP", ["1 season", "{0} seasons", 5], "5 řad", {"global": CS}),
            ("a missing form falls back to other", "TxP", ["1 season", "{0} seasons", 3], "3 sezonu", {"global": {"appLocale": "pl", "strings": {"{0} seasons": "{0} sezonu"}}}),
        ])

    def test_plural_categories(self):
        c = "I18n_pluralCategory"
        check_cases(self, UTILS, [(lang + " " + str(n), c, [lang, n], want) for lang, n, want in [
            ("en", 1, "one"), ("en", 0, "other"), ("fr", 0, "one"), ("pt_BR", 1, "one"), ("pt_BR", 2, "other"),
            ("pl", 1, "one"), ("pl", 2, "few"), ("pl", 12, "many"), ("pl", 22, "few"), ("pl", 25, "many"), ("pl", 0, "many"),
            ("cs", 1, "one"), ("cs", 3, "few"), ("cs", 5, "other"), ("cs", 22, "other"),
            ("hr", 1, "one"), ("hr", 21, "one"), ("hr", 11, "other"), ("hr", 23, "few"), ("hr", 13, "other"),
            ("ru", 1, "one"), ("ru", 101, "one"), ("ru", 111, "many"), ("ru", 4, "few"), ("ru", 14, "many"),
            ("uk", 31, "one"), ("uk", 32, "few"), ("uk", 35, "many"),
            ("tr", 1, "one"), ("tr", 2, "other"), ("fi", 0, "other"),
        ]])

    def test_turkish_capitals(self):
        u = "I18n_upper"
        check_cases(self, UTILS, [
            ("Turkish dotted i", u, ["Dizi"], "DİZİ", {"global": {"appLocale": "tr", "strings": {}}}),
            ("Turkish dotless ı", u, ["Kapalı"], "KAPALI", {"global": {"appLocale": "tr", "strings": {}}}),
            ("other languages keep UCase", u, ["Series"], "SERIES", {"global": {"appLocale": "en", "strings": {}}}),
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
        for lang in ("es", "de", "fr", "pt_BR", "nl", "it", "pl", "tr", "sv", "da", "nb", "fi", "cs", "hr", "ru", "uk"):
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
