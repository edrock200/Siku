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
ID = {"appLocale": "id", "strings": {"1 season": "1 musim", "{0} seasons": "{0} musim"}}
SL = {"appLocale": "sl", "strings": {"1 season": "1 sezona", "{0} seasons": "{0} sezon", "{0} seasons#one": "{0} sezona",
                                     "{0} seasons#two": "{0} sezoni", "{0} seasons#few": "{0} sezone"}}
LV = {"appLocale": "lv", "strings": {"1 season": "1 sezona", "{0} seasons": "{0} sezonas", "{0} seasons#one": "{0} sezona",
                                     "{0} seasons#zero": "{0} sezonu"}}
CS = {"appLocale": "cs", "strings": {"1 season": "1 řada", "{0} seasons": "{0} řad", "{0} seasons#few": "{0} řady"}}


class Resolve(unittest.TestCase):
    def test_cases(self):
        r = "I18n_resolve"
        check_cases(self, UTILS, [
            ("profile override wins", r, ["de", "en_US"], "de"),
            ("unset follows the Roku", r, ["", "fr_CA"], "fr"),
            ("invalid follows the Roku", r, [None, "es_MX"], "es"),
            ("regional tag", r, ["es-MX", "en_US"], "es"),
            ("European Portuguese (catalog 2026.11.20)", r, ["pt-PT", "en_US"], "pt_PT"),
            ("a Portuguese Roku in Portugal", r, ["", "pt_PT"], "pt_PT"),
            ("plain Portuguese is Brazilian", r, ["pt", "en_US"], "pt_BR"),
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
            ("Bulgarian (catalog 2026.11.20)", r, ["bg", "en_US"], "bg"),
            ("Catalan", r, ["ca-ES", "en_US"], "ca"),
            ("Indonesian", r, ["id", "en_US"], "id"),
            ("Indonesian's legacy code in", r, ["", "in_ID"], "id"),
            ("Hebrew stays out (no font), legacy iw too", r, ["iw", "de_DE"], "de"),
            ("Greek stays out (no font)", r, ["el", "en_US"], "en"),
            ("Vietnamese", r, ["vi-VN", "en_US"], "vi"),
            ("tag of European Portuguese", "I18n_tagOf", ["pt_PT"], "pt-PT"),
            ("native name of Bulgarian", "I18n_nativeName", ["bg"], "Български"),
            ("native name of Vietnamese", "I18n_nativeName", ["vi"], "Tiếng Việt"),
            ("tag of Brazilian", "I18n_tagOf", ["pt_BR"], "pt-BR"),
            ("tag of Bokmål", "I18n_tagOf", ["nb"], "nb"),
            ("native name", "I18n_nativeName", ["de"], "Deutsch"),
            ("native name in Cyrillic", "I18n_nativeName", ["uk"], "Українська"),
            ("thirty languages", "I18n_folders", [], lambda v: len(v) == 30 and v[0] == "en" and v[16] == "uk" and v[-1] == "ms"),
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
            ("Indonesian 1 is other", "TxP", ["1 season", "{0} seasons", 1], "1 musim", {"global": ID}),
            ("Slovenian 101 is one", "TxP", ["1 season", "{0} seasons", 101], "101 sezona", {"global": SL}),
            ("Slovenian two", "TxP", ["1 season", "{0} seasons", 2], "2 sezoni", {"global": SL}),
            ("Slovenian few", "TxP", ["1 season", "{0} seasons", 3], "3 sezone", {"global": SL}),
            ("Slovenian other", "TxP", ["1 season", "{0} seasons", 5], "5 sezon", {"global": SL}),
            ("Latvian zero", "TxP", ["1 season", "{0} seasons", 10], "10 sezonu", {"global": LV}),
            ("Latvian 21 is one", "TxP", ["1 season", "{0} seasons", 21], "21 sezona", {"global": LV}),
            ("Latvian other", "TxP", ["1 season", "{0} seasons", 3], "3 sezonas", {"global": LV}),
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
            ("bg", 1, "one"), ("bg", 2, "other"), ("ca", 1, "one"), ("hu", 1, "one"), ("et", 2, "other"), ("pt_PT", 0, "other"),
            ("id", 1, "other"), ("ms", 1, "other"), ("vi", 1, "other"),
            ("sk", 1, "one"), ("sk", 4, "few"), ("sk", 5, "other"),
            ("ro", 1, "one"), ("ro", 0, "few"), ("ro", 19, "few"), ("ro", 20, "other"), ("ro", 101, "few"), ("ro", 120, "other"),
            ("sl", 1, "one"), ("sl", 101, "one"), ("sl", 2, "two"), ("sl", 102, "two"), ("sl", 3, "few"), ("sl", 104, "few"), ("sl", 5, "other"), ("sl", 11, "other"),
            ("lt", 1, "one"), ("lt", 21, "one"), ("lt", 11, "other"), ("lt", 2, "few"), ("lt", 29, "few"), ("lt", 12, "other"), ("lt", 10, "other"),
            ("lv", 0, "zero"), ("lv", 10, "zero"), ("lv", 13, "zero"), ("lv", 1, "one"), ("lv", 21, "one"), ("lv", 11, "zero"), ("lv", 2, "other"),
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
        for lang in ("es", "de", "fr", "pt_BR", "nl", "it", "pl", "tr", "sv", "da", "nb", "fi", "cs", "hr", "ru", "uk",
                     "hu", "ro", "sk", "sl", "bg", "ca", "lt", "lv", "et", "vi", "pt_PT", "id", "ms"):
            with open(os.path.join(ROOT, "locale", lang, "strings.json"), encoding="utf-8") as f:
                table = json.load(f)
            lowered = {}
            for k in table:
                self.assertNotIn(k.lower(), lowered, "%s: %r and %r differ only by case (Roku keys ignore case)" % (lang, k, lowered.get(k.lower())))
                lowered[k.lower()] = k
            for k, v in table.items():
                if k.startswith("@android."):
                    # Read by catalog key (TxKey): the key holds no placeholders; the text keeps {0}.
                    self.assertIn("{0}", v, "%s: %r -> %r has no {0}" % (lang, k, v))
                    continue
                for i in range(5):
                    ph = "{%d}" % i
                    self.assertEqual(ph in k, ph in v, "%s: %r -> %r loses or adds %s" % (lang, k, v, ph))


class ServerTextFromAndroid(unittest.TestCase):
    """Languages silo-roku does not ship read server row titles and problem types from the Android
    catalog, with the Roku catalog's named placeholders."""

    def test_bulgarian_server_keys(self):
        with open(os.path.join(ROOT, "locale", "bg", "strings.json"), encoding="utf-8") as f:
            table = json.load(f)
        self.assertIn("@home.section.continueWatching", table)
        self.assertIn("{library}", table["@home.section.recentlyAddedIn"])
        self.assertIn("@error.not_found", table)
        self.assertFalse(any("%" in v for k, v in table.items() if k.startswith("@home.")))


class Glyphs(unittest.TestCase):
    """Every character a language file shows is in Siku's Inter fonts: a Roku has no fallback font
    for a channel's own fonts, so a missing glyph draws a box (subset by tools/subset_fonts.py)."""

    def test_fonts_draw_every_language(self):
        try:
            from fontTools.ttLib import TTFont
        except ImportError:
            self.skipTest("fontTools not installed")
        import glob
        for font in glob.glob(os.path.join(ROOT, "fonts", "Inter-*.otf")):
            cmap = TTFont(font).getBestCmap()
            for path in glob.glob(os.path.join(ROOT, "locale", "*", "strings.json")):
                with open(path, encoding="utf-8") as f:
                    table = json.load(f)
                missing = sorted({c for v in table.values() for c in v if ord(c) > 32 and ord(c) not in cmap})
                self.assertEqual(missing, [], "%s lacks %s for %s" % (os.path.basename(font), "".join(missing),
                                                                     os.path.relpath(path, ROOT)))


if __name__ == "__main__":
    unittest.main()
