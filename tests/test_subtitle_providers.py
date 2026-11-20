# SPDX-License-Identifier: AGPL-3.0-or-later
"""Subtitle search only when the server can search (Silo Android #608, SubtitleProviderStatusTest):
GET /api/v2/subtitles/providers/status decides; a failed or timed-out probe keeps the last answer
and otherwise offers search."""
import unittest

from brs import check_cases

FILES = ["components/player/SubtitleSuite.brs", "components/common/Settings.brs", "components/common/Utils.brs",
         "components/common/Content.brs"]

AVAILABLE = {"revision": "r1", "state": "available", "allowed": True, "enabled": True, "schema_version": 1,
             "providers": ["opensubtitles"]}
NO_PROVIDERS = {"state": "disabled", "allowed": False, "enabled": False}


class Verdict(unittest.TestCase):
    def test_verdict(self):
        v = "Subs_providerVerdict"
        check_cases(self, FILES, [
            ("available", v, [AVAILABLE], "yes"),
            ("no providers", v, [NO_PROVIDERS], "no"),
            ("not allowed", v, [dict(AVAILABLE, allowed=False)], "no"),
            ("not enabled", v, [dict(AVAILABLE, enabled=False)], "no"),
            ("other state", v, [dict(AVAILABLE, state="unavailable")], "no"),
            ("state case matters", v, [dict(AVAILABLE, state="Available")], "no"),
            ("empty provider list still searches", v, [dict(AVAILABLE, providers=[])], "yes"),
            ("missing fields: defaults say no", v, [{}], "no"),
            ("missing allowed", v, [{"state": "available", "enabled": True}], "no"),
            ("not an object", v, [None], ""),
            ("a list", v, [[1]], ""),
            ("string flag does not decode", v, [dict(AVAILABLE, allowed="true")], ""),
            ("number flag does not decode", v, [dict(AVAILABLE, enabled=1)], ""),
            ("numeric state does not decode", v, [dict(AVAILABLE, state=3)], ""),
            ("providers not a list", v, [dict(AVAILABLE, providers="opensubtitles")], ""),
        ])


class After(unittest.TestCase):
    def test_server_answer_decides(self):
        a = "Subs_providerSearchAfter"
        check_cases(self, FILES, [
            ("available after no", a, [True, AVAILABLE, "no"], "yes"),
            ("none after yes", a, [True, NO_PROVIDERS, "yes"], "no"),
            ("not allowed, first answer", a, [True, dict(AVAILABLE, allowed=False), ""], "no"),
        ])

    def test_failed_probe_keeps_known_answer_and_otherwise_offers(self):
        a = "Subs_providerSearchAfter"
        check_cases(self, FILES, [
            ("failed keeps no", a, [False, None, "no"], "no"),
            ("failed keeps yes", a, [False, None, "yes"], "yes"),
            ("failed, none yet: offer", a, [False, None, ""], "yes"),
            ("undecodable answer counts as failed", a, [True, dict(AVAILABLE, allowed="yes"), "no"], "no"),
            ("undecodable, none yet: offer", a, [True, "<html>", ""], "yes"),
            ("data ignored when not answered", a, [False, AVAILABLE, "no"], "no"),
        ])


if __name__ == "__main__":
    unittest.main()
