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


def source_strings():
    """Every English text Siku marks for translation: {text: [file:line, ...]}."""
    found = {}

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
                    elif name.endswith(".xml") and 'i18n="no"' not in line:
                        for m in XML_ATTRS.finditer(line):
                            text = html.unescape(m.group(1))
                            if not text.startswith(("pkg:", "font:", "#", "0x")) and not re.fullmatch(r"[\d\s.:,/%x-]+", text):
                                add(text, "%s:%d" % (rel, i))
    return found


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
    if len(t) >= 2 and t[0] == '"' and t[-1] == '"':
        t = t[1:-1]
    return t


def roku_entries(folder):
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
    """{normalised English: translation with positional placeholders} for one language."""
    values_dir, roku_folder = LANGS[lang]
    result = {}
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
    return result


def build():
    strings = source_strings()
    os.makedirs(os.path.join(ROOT, "i18n", "siku"), exist_ok=True)
    built, missing, stats = {}, {}, {}
    for lang in LANGS:
        p = pool(lang)
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
        # Server text by catalog key (Silo's docs/architecture/i18n.md): Home row titles
        # (title_key, named {placeholders} filled from title_args) and problem types, as "@key".
        for k, v in roku_entries(LANGS[lang][1]).items():
            if k.startswith(("home.section.", "error.")) and "#" not in k and v:
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
