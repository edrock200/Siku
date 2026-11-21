# SPDX-License-Identifier: AGPL-3.0-or-later
"""Builds Siku's interface translations: locale/<language>/strings.json.

Siku's code marks interface text with Tx("English"), TxF("English with {0}", [args]) and
TxP("one form", "other form {0}", n); layout XML keeps English text in text/title/hintText
attributes, translated at runtime by I18n_translateTree. Each language file maps that English
text to its translation, so a missing entry simply shows English.

Translations come from Silo's own apps (third_party/silo-translations, AGPL-3.0): the Android
catalog (strings_catalog.xml) and the Roku catalog (strings.json), matched by English text with
apostrophes, ellipses and placeholders normalised. Text only Siku has is translated in
i18n/siku/<language>.json ({"English": "translation"}), which also overrides a catalog match.
Where an Android catalog entry's English collides with other text, the code reads it by key,
TxKey("android.<name>", {"0": arg}, fallback), and the file holds it as "@android.<name>".

  python3 tools/i18n_build.py            write locale/*/strings.json and i18n/missing.json
  python3 tools/i18n_build.py --check    fail when locale/ is out of date or text is untranslated
"""
import argparse
import html
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TP = os.path.join(ROOT, "third_party", "silo-translations")
LANGS = {  # Siku folder: (Android values dir, Roku folder)
    "es": ("values-es", "es"),
    "de": ("values-de", "de"),
    "fr": ("values-fr", "fr"),
    "pt_BR": ("values-pt-rBR", "pt_BR"),
    "nl": ("values-nl", "nl"),
    "it": ("values-it", "it"),
    "pl": ("values-pl", "pl"),
    "tr": ("values-tr", "tr"),
    "sv": ("values-sv", "sv"),
    "da": ("values-da", "da"),
    "nb": ("values-nb", "nb"),
    "fi": ("values-fi", "fi"),
    "cs": ("values-cs", "cs"),
    "hr": ("values-hr", "hr"),
    "ru": ("values-ru", "ru"),
    "uk": ("values-uk", "uk"),
    # Catalog languages Silo's Android apps added in 2026.11.20-9403fbd (silo-android 63c898084) that
    # silo-roku does not ship: Android catalog only. Indonesian's Android folder is the legacy "in".
    "hu": ("values-hu", None),
    "ro": ("values-ro", None),
    "sk": ("values-sk", None),
    "sl": ("values-sl", None),
    "bg": ("values-bg", None),
    "ca": ("values-ca", None),
    "lt": ("values-lt", None),
    "lv": ("values-lv", None),
    "et": ("values-et", None),
    "vi": ("values-vi", None),
    "pt_PT": ("values-pt-rPT", None),
    "id": ("values-in", None),
    "ms": ("values-ms", None),
}
# Plural categories (CLDR, whole numbers) a language needs beyond English's one/other. TxP("1 x",
# "{0} xs", n) looks these up as "{0} xs#few" etc. (I18n_pluralCategory in Utils.brs); "one" is
# listed where it also covers 21, 31, ... and so needs a form with {0} (so do Latvian "zero", which
# covers 10, 20, ..., and Slovenian "two", which covers 102, ...).
PLURAL_FORMS = {
    "pl": ("few", "many"),
    "cs": ("few",),
    "hr": ("one", "few"),
    "ru": ("one", "few", "many"),
    "uk": ("one", "few", "many"),
    "ro": ("few",),
    "sk": ("few",),
    "sl": ("one", "two", "few"),
    "lt": ("one", "few"),
    "lv": ("zero", "one"),
}

# A string literal: "..." with BrightScript's "" escape.
LIT = r'"((?:[^"]|"")*)"'
TR_CALLS = [
    re.compile(r'\bTx\(\s*' + LIT + r'\s*\)', re.I),
    re.compile(r'\bTxF\(\s*' + LIT + r'\s*,', re.I),
    re.compile(r'\bTxP\(\s*' + LIT + r'\s*,\s*' + LIT, re.I),
]
XML_ATTRS = re.compile(r'\b(?:text|title|hintText|description|placeholder|a11yLabel|label)="([^"]*[A-Za-z][^"]*)"')


def unescape_brs(s):
    return s.replace('""', '"')


TXP_PAIR = re.compile(r'\bTxP\(\s*' + LIT + r'\s*,\s*' + LIT, re.I)
# Android catalog text read by its key where its English collides with other text (TxKey("android.
# <name>", {"0": arg}, englishFallback)): "by %1$s" is both an author and a collection's maker.
TXKEY_ANDROID = re.compile(r'\bTxKey\(\s*"android\.([A-Za-z0-9_]+)"')


def android_keys():
    """{catalog name: [file:line, ...]} of the Android entries Siku reads by key."""
    found = {}
    for base in ("components", "source"):
        for dirpath, _, names in os.walk(os.path.join(ROOT, base)):
            for name in names:
                if not name.endswith(".brs"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT)
                with open(path, encoding="utf-8") as f:
                    for i, line in enumerate(f.read().splitlines(), 1):
                        if line.lstrip().startswith("'"):
                            continue
                        for m in TXKEY_ANDROID.finditer(line):
                            found.setdefault(m.group(1), []).append("%s:%d" % (rel, i))
    return found


def source_strings():
    """Every English text Siku marks for translation: {text: [file:line, ...]}, and the "other"
    texts of TxP pairs ({other: [file:line, ...]}), which need extra plural forms in some languages."""
    found = {}
    plurals = {}

    def add(text, where):
        if text.strip():
            found.setdefault(text, []).append(where)

    for base in ("components", "source"):
        for dirpath, _, names in os.walk(os.path.join(ROOT, base)):
            for name in names:
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT)
                with open(path, encoding="utf-8") as f:
                    lines = f.read().splitlines()
                for i, line in enumerate(lines, 1):
                    if name.endswith(".brs"):
                        code = line.split("'", 1)[0] if line.lstrip().startswith("'") else line
                        for rx in TR_CALLS:
                            for m in rx.finditer(code):
                                for g in m.groups():
                                    add(unescape_brs(g), "%s:%d" % (rel, i))
                        for m in TXP_PAIR.finditer(code):
                            plurals.setdefault(unescape_brs(m.group(2)), []).append("%s:%d" % (rel, i))
                    elif name.endswith(".xml") and 'i18n="no"' not in line:
                        for m in XML_ATTRS.finditer(line):
                            text = html.unescape(m.group(1))
                            if not text.startswith(("pkg:", "font:", "#", "0x")) and not re.fullmatch(r"[\d\s.:,/%x-]+", text):
                                add(text, "%s:%d" % (rel, i))
    return found, plurals


PLACEHOLDER = re.compile(r"%(\d+\$)?[sdf]|\{[A-Za-z_][A-Za-z0-9_]*\}|\{\d+\}")


def norm(text):
    """The matching key: placeholders, apostrophes, quotes, ellipses and spacing made uniform."""
    t = text.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"')
    t = t.replace("…", "...").replace(" ", " ")
    t = PLACEHOLDER.sub("{}", t)
    return re.sub(r"\s+", " ", t).strip()


def to_positional(english, translated):
    """Rewrites a catalog pair's placeholders as {0}, {1}, ... in the English order."""
    order = [m.group(0) for m in PLACEHOLDER.finditer(english)]
    named = {}
    for i, ph in enumerate(order):
        named.setdefault(ph, i)
    seq = [0]

    def repl(m):
        ph = m.group(0)
        if ph in named and (ph.startswith("{") or m.group(1)):
            return "{%d}" % named[ph]
        if ph.startswith("%") and m.group(1):
            return "{%d}" % (int(m.group(1)[:-1]) - 1)
        if ph.startswith("%"):
            i = seq[0]
            seq[0] += 1
            return "{%d}" % i
        return ph

    return PLACEHOLDER.sub(repl, translated)


def android_entries(values_dir):
    path = os.path.join(TP, "android", values_dir, "strings_catalog.xml")
    out = {}
    root = ET.parse(path).getroot()
    for el in root:
        name = el.get("name")
        if el.tag == "string":
            out[name] = android_text(el)
        elif el.tag == "plurals":
            for item in el:
                out["%s#%s" % (name, item.get("quantity"))] = android_text(item)
    return out


def android_text(el):
    t = "".join(el.itertext())
    t = t.replace("\\'", "'").replace('\\"', '"').replace("\\n", "\n").replace("\\@", "@").replace("\\?", "?")
    # Android resource escapes \uXXXX (the catalogs write a kept space as \u0020).
    t = re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), t)
    if len(t) >= 2 and t[0] == '"' and t[-1] == '"':
        t = t[1:-1]
    return t


def roku_entries(folder):
    if folder is None:
        return {}
    with open(os.path.join(TP, "roku", folder, "strings.json"), encoding="utf-8") as f:
        data = json.load(f)
    out = {}
    for k, v in data.items():
        if isinstance(v, str):
            out[k] = v
        elif isinstance(v, dict):  # plural forms
            for q, s in v.items():
                if isinstance(s, str):
                    out["%s#%s" % (k, q)] = s
    return out


def pool(lang):
    """{normalised English: translation with positional placeholders} for one language, and
    {normalised English "other" form: {category: translation}} for its plurals."""
    values_dir, roku_folder = LANGS[lang]
    result = {}
    forms = {}
    pairs = [
        (roku_entries("en_US"), roku_entries(roku_folder)),
        (android_entries("values"), android_entries(values_dir)),
    ]
    for en, tr in pairs:  # Android last: it ports the app Siku ports, so it wins a clash
        for key, english in en.items():
            translated = tr.get(key)
            if not translated or translated == english and key.split("#")[0] not in tr:
                continue
            if "#" in key and key.endswith(("#few", "#many", "#two", "#zero")):
                continue
            result[norm(english)] = (english, to_positional(english, translated))
            if key.endswith("#other"):
                name = key[:-len("#other")]
                cats = {}
                for q in ("zero", "one", "two", "few", "many"):
                    t = tr.get(name + "#" + q)
                    if t:
                        cats[q] = to_positional(english, t)
                forms[norm(english)] = (english, cats)
    return result, forms


NAMED = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")


def server_keys(lang):
    """{catalog key: translation} of the server text Siku reads by key (home.section.*, error.*), with
    the Roku catalog's named {placeholders}. A language silo-roku does not ship takes them from the
    Android catalog, whose names are the keys with "_" for "." and whose %1$s, %2$s, ... are the Roku
    English's placeholders in order."""
    keep = lambda k: k.startswith(("home.section.", "error.")) and "#" not in k
    roku_folder = LANGS[lang][1]
    if roku_folder is not None:
        return {k: v for k, v in roku_entries(roku_folder).items() if keep(k) and v}
    out = {}
    tr = android_entries(LANGS[lang][0])
    for k, en in roku_entries("en_US").items():
        t = tr.get(k.replace(".", "_")) if keep(k) else None
        if not t:
            continue
        names = NAMED.findall(en)
        t = re.sub(r"%(\d+)\$[sd]", lambda m: "{%s}" % names[int(m.group(1)) - 1] if int(m.group(1)) <= len(names) else m.group(0), t)
        if "%" in t and re.search(r"%(\d+\$)?[sd]", t):
            continue
        out[k] = t
    return out


def build():
    strings, plurals = source_strings()
    keyed = android_keys()
    en_android = android_entries("values")
    os.makedirs(os.path.join(ROOT, "i18n", "siku"), exist_ok=True)
    built, missing, stats = {}, {}, {}
    for lang in LANGS:
        p, pforms = pool(lang)
        extra_path = os.path.join(ROOT, "i18n", "siku", lang + ".json")
        extra = {}
        if os.path.exists(extra_path):
            with open(extra_path, encoding="utf-8") as f:
                extra = json.load(f)
        table, miss = {}, []
        from_catalog = 0
        for text in sorted(strings):
            if text in extra and extra[text]:
                table[text] = extra[text]
                continue
            hit = p.get(norm(text))
            if hit:
                table[text] = to_positional(text, hit[1]) if PLACEHOLDER.search(text) else hit[1]
                from_catalog += 1
            else:
                miss.append(text)
        for other in sorted(plurals):
            hit = pforms.get(norm(other))
            for q in PLURAL_FORMS.get(lang, ()):
                key = other + "#" + q
                if key in extra and extra[key]:
                    table[key] = extra[key]
                    continue
                t = hit[1].get(q) if hit else None
                if t and (q not in ("zero", "one", "two") or "{0}" in t):
                    table[key] = to_positional(other, t) if PLACEHOLDER.search(other) else t
                    from_catalog += 1
                else:
                    miss.append(key)
        # Android catalog text by key ("@android.<name>", placeholders as {0}, {1}, ...).
        tr_android = android_entries(LANGS[lang][0])
        for name in sorted(keyed):
            en, t = en_android.get(name), tr_android.get(name)
            if en and t:
                table["@android." + name] = to_positional(en, t)
                from_catalog += 1
            else:
                miss.append("@android." + name)
        # Server text by catalog key (Silo's docs/architecture/i18n.md): Home row titles
        # (title_key, named {placeholders} filled from title_args) and problem types, as "@key".
        for k, v in server_keys(lang).items():
            table["@" + k] = v
        built[lang] = case_merge(table)
        missing[lang] = miss
        stats[lang] = (len(strings), from_catalog, len(table) - from_catalog, len(miss))
    return strings, built, missing, stats


def case_merge(table):
    """One entry per text ignoring case (Roku's table keys do): mixed case wins over ALL CAPS, the
    first otherwise. A screen that needs capitals uppercases the translation itself (UCase(Tx(..)))."""
    out = {}
    for k in sorted(table, key=lambda k: (k.isupper(), k)):
        if not any(o.lower() == k.lower() for o in out):
            out[k] = table[k]
    return out


def dump(obj):
    return json.dumps(obj, ensure_ascii=False, indent=1, sort_keys=True) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    strings, built, missing, stats = build()
    strings = dict(strings)
    for name, where in android_keys().items():
        strings["@android." + name] = where
    for t in {t for m in missing.values() for t in m if t not in strings}:
        strings[t] = strings.get(t.rsplit("#", 1)[0], ["(plural form)"])
    stale = []
    for lang, table in built.items():
        path = os.path.join(ROOT, "locale", lang, "strings.json")
        text = dump(table)
        if args.check:
            current = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
            if current != text:
                stale.append(path)
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
    miss_union = sorted({t for m in missing.values() for t in m})
    if not args.check:
        with open(os.path.join(ROOT, "i18n", "missing.json"), "w", encoding="utf-8") as f:
            f.write(dump({t: strings[t][:3] for t in miss_union}))
    for lang, (total, cat, extra, miss) in stats.items():
        print("%s: %d texts, %d from Silo's catalogs, %d Siku's own, %d untranslated" % (lang, total, cat, extra, miss))
    if args.check:
        bad = False
        if stale:
            print("out of date (run python3 tools/i18n_build.py): " + ", ".join(os.path.relpath(p, ROOT) for p in stale))
            bad = True
        if miss_union:
            print("untranslated: %d texts (see i18n/missing.json after a build)" % len(miss_union))
            bad = True
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
