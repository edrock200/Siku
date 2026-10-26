# SPDX-License-Identifier: AGPL-3.0-or-later
"""Shared helpers for the host tests: Siku's BrightScript run in brs-cli (tools/brs_test.py)."""
import os
import sys
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from brs_test import BrsError, call, calls  # noqa: E402,F401

SESSION = {"serverUrl": "http://silo.example:8097", "profileId": "p1", "accessToken": "acc"}


def settings(items=None, available=True):
    """An m.global.settings snapshot for SESSION with {key: value} items."""
    return {
        "ready": True, "available": available, "identity": SESSION["serverUrl"] + "|" + SESSION["profileId"],
        "revision": 1, "manifestRevision": 21,
        "items": {k: {"value": v, "source": "profile", "scope": "profile"} for k, v in (items or {}).items()},
        "error": "",
    }


def glob(items=None, prefs=None):
    return {"session": dict(SESSION), "settings": settings(items), "prefs": prefs or {}}


class BrsCase(unittest.TestCase):
    FILES = []

    def run_all(self, specs):
        return calls(self.FILES, specs)

    def value(self, fn, *args, m=None, g=None):
        return call(self.FILES, fn, list(args), m=m, global_=g)


def check_cases(test, files, cases):
    """cases: [(name, fn, args, expected)] or with a 5th item {"m": ..., "global": ...}.
    Runs them in one brs-cli process; expected may be a callable(value) -> bool."""
    specs = []
    for c in cases:
        extra = c[4] if len(c) > 4 else {}
        specs.append({"fn": c[1], "args": list(c[2]), "m": extra.get("m"), "global": extra.get("global")})
    results = calls(files, specs)
    for c, r in zip(cases, results):
        with test.subTest(c[0]):
            test.assertTrue(r["ok"], "%s threw: %s" % (c[0], r.get("error")))
            exp = c[3]
            if callable(exp):
                test.assertTrue(exp(r["value"]), "%s: unexpected %r" % (c[0], r["value"]))
            else:
                test.assertEqual(r["value"], exp, c[0])
    return results
