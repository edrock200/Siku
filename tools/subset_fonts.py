# SPDX-License-Identifier: AGPL-3.0-or-later
"""Rebuilds Siku's Inter fonts (fonts/Inter-{regular,medium,semibold,bold,black}.otf).

Siku draws every label with its own Inter fonts, and a Roku has no fallback font for a channel's
fonts: a character missing from them shows as a box. The fonts are subset from the Inter 4.1
release (SIL Open Font License 1.1, fonts/OFL.txt is the release's LICENSE.txt) to Latin,
Latin Extended, Cyrillic (for Russian and Ukrainian) and the punctuation, arrows and symbols the
interface uses, keeping the layout features Siku relies on (kerning, contextual alternates,
tabular figures). The same release, subset the same way for these scripts, is what
Silo-Server/silo-roku ships (fonts/SOURCE there).

  python3 tools/subset_fonts.py /path/to/Inter-4.1.zip      write fonts/*.otf
  python3 tools/subset_fonts.py /path/to/Inter-4.1.zip --check   fail when fonts/ differ

Needs fontTools (pip install fonttools). The zip is
https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip.
"""
import argparse
import hashlib
import io
import os
import sys
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ZIP_SHA256 = "9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e"
WEIGHTS = {"Regular": "regular", "Medium": "medium", "SemiBold": "semibold", "Bold": "bold", "Black": "black"}
UNICODES = ("U+0020-007E,U+00A0-00AC,U+00AE-0148,U+014A-01C3,U+01C5-024F,U+02B0-02FF,U+0400-052F,"
            "U+2000-200B,U+2010-2027,U+202F-2055,U+2057,U+205F,U+20AC,U+2122,U+2190-2193,U+2212,"
            "U+25B6,U+2713")
FEATURES = ["calt", "ccmp", "kern", "locl", "tnum"]


def subset(data):
    from fontTools import subset as fs
    from fontTools.ttLib import TTFont
    opts = fs.Options()
    opts.layout_features = FEATURES
    opts.notdef_outline = True
    opts.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
    font = TTFont(io.BytesIO(data), recalcTimestamp=False)
    sub = fs.Subsetter(opts)
    sub.populate(unicodes=fs.parse_unicodes(UNICODES))
    sub.subset(font)
    out = io.BytesIO()
    font.save(out)
    return out.getvalue()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("zip")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    raw = open(args.zip, "rb").read()
    if hashlib.sha256(raw).hexdigest() != ZIP_SHA256:
        print("unexpected zip: sha256 differs from Inter 4.1's")
        return 1
    z = zipfile.ZipFile(io.BytesIO(raw))
    bad = []
    for src, dst in WEIGHTS.items():
        out = subset(z.read("extras/otf/Inter-%s.otf" % src))
        path = os.path.join(ROOT, "fonts", "Inter-%s.otf" % dst)
        if args.check:
            if not os.path.exists(path) or open(path, "rb").read() != out:
                bad.append(path)
        else:
            with open(path, "wb") as f:
                f.write(out)
            print("%s %d bytes" % (os.path.relpath(path, ROOT), len(out)))
    if bad:
        print("out of date: " + ", ".join(os.path.relpath(p, ROOT) for p in bad))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
