#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Turns `print "[siku-<category>] ..."` console lines into Diag_log(...) calls, so they also reach
the on-device diagnostics log (Settings > Diagnostics; components/common/Diag.brs).

    python3 tools/diag_log_convert.py           rewrite components/ and source/ in place
    python3 tools/diag_log_convert.py --check   list the lines still to convert (exit 1 if any)

Only the categories in LOGGED are converted; the phone features' lines ([siku-lan], [siku-cast],
[siku-pair]) are chatty and stay console-only, as do debug-only ones ([siku-a11y], [siku-streamtest]).
`print a; b; c` becomes `Diag_log(Diag_join([a, b, c]))`. Run it after merging branches that add
new print lines; tests/test_diag.py runs --check.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOGGED = ("playback", "home", "auth", "memory", "launch", "trickplay", "theme", "trailer", "detail",
          "cards", "voice", "diag", "accounts", "overlays")
# source/main.brs runs before m.global exists on the main thread; its lines stay prints.
SKIP = {"source/main.brs"}
LINE = re.compile(r'^(?P<lead>\s*(?:.*?\bthen\s+)?)print\s+(?P<args>"\[siku-(?P<cat>[a-z0-9]+)\].*)$')


def split_args(text):
    """Top-level `;`-separated print arguments, or None when the line has a comment or is odd."""
    parts, cur, depth, i, quote = [], "", 0, 0, False
    while i < len(text):
        ch = text[i]
        if quote:
            cur += ch
            if ch == '"':
                if i + 1 < len(text) and text[i + 1] == '"':
                    cur += '"'
                    i += 1
                else:
                    quote = False
        elif ch == '"':
            quote = True
            cur += ch
        elif ch == "'":
            return None
        elif ch in "([{":
            depth += 1
            cur += ch
        elif ch in ")]}":
            depth -= 1
            cur += ch
        elif ch == ";" and depth == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
        i += 1
    if quote or depth != 0:
        return None
    if cur.strip():
        parts.append(cur.strip())
    if not parts or any(p == "" for p in parts):
        return None
    return parts


def convert_line(line):
    m = LINE.match(line)
    if not m or m.group("cat") not in LOGGED:
        return None
    args = split_args(m.group("args").rstrip())
    if args is None:
        return None
    if len(args) == 1:
        call = "Diag_log(%s)" % args[0]
    else:
        call = "Diag_log(Diag_join([%s]))" % ", ".join(args)
    return m.group("lead") + call


def files():
    for d in ("components", "source"):
        for p in sorted((ROOT / d).rglob("*.brs")):
            rel = p.relative_to(ROOT).as_posix()
            if rel not in SKIP:
                yield p, rel


def main(argv):
    check = "--check" in argv
    pending = []
    for p, rel in files():
        lines = p.read_text(encoding="utf-8").split("\n")
        changed = False
        for n, line in enumerate(lines):
            new = convert_line(line)
            if new is None:
                continue
            if check:
                pending.append("%s:%d: %s" % (rel, n + 1, line.strip()))
            else:
                lines[n] = new
                changed = True
        if changed:
            p.write_text("\n".join(lines), encoding="utf-8")
    if check and pending:
        print("print lines to convert (python3 tools/diag_log_convert.py):")
        print("\n".join(pending))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
