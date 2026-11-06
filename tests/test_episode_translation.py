# SPDX-License-Identifier: AGPL-3.0-or-later
"""Auto translation of a series page's shown season (Silo Android #822, EpisodeTranslation.brs):
the capability's on-view mode, the pending language, isEpisodeDescriptionTranslating (a port of
EpisodeDescriptionTranslatingTest), the card label from the job state, and the job receipt."""
import unittest

from brs import check_cases

FILES = ["components/common/EpisodeTranslation.brs", "components/common/Utils.brs"]


class Translating(unittest.TestCase):
    def test_is_translating(self):
        f = "EpTr_isTranslating"
        check_cases(self, FILES, [
            ("shown season job, episode pending", f, ["de", "season-1", "season-1"], True),
            ("episode already translated", f, [None, "season-1", "season-1"], False),
            ("blank pending language", f, ["  ", "season-1", "season-1"], False),
            ("another season's job", f, ["de", "season-2", "season-1"], False),
            ("no job, no shown season", f, ["de", None, None], False),
            ("no job", f, ["de", "season-1", ""], False),
        ])

    def test_label(self):
        f = "EpTr_label"
        check_cases(self, FILES, [
            ("job filling it", f, [True, False, True], "translating"),
            ("progress hides the mark", f, [True, True, True], "translating"),
            ("text arrived", f, [False, True, True], "translated"),
            ("translated but hidden by spoiler protection", f, [False, True, False], ""),
            ("nothing", f, [False, False, True], ""),
        ])

    def test_pending_language(self):
        f = "EpTr_pendingLanguage"
        check_cases(self, FILES, [
            ("first non-blank", f, [[{"pending_translation_language": ""}, {"pending_translation_language": "de"},
                                    {"pending_translation_language": "fr"}]], "de"),
            ("none", f, [[{"overview": "x"}]], ""),
            ("not a list", f, [None], ""),
        ])

    def test_on_view(self):
        f = "EpTr_onView"
        check_cases(self, FILES, [
            ("auto", f, [{"state": "available", "on_view": "auto"}], "auto"),
            ("button", f, [{"state": "available", "on_view": "button"}], "button"),
            ("not configured", f, [{"state": "not_configured", "on_view": "auto"}], "off"),
            ("unknown mode", f, [{"state": "available", "on_view": "later"}], "off"),
            ("no answer", f, [None], "off"),
        ])

    def test_job(self):
        f = "EpTr_jobAccepted"
        check_cases(self, FILES, [
            ("running", f, [{"status": "running", "content_id": "s1"}, "s1"], True),
            ("pending", f, [{"status": "pending", "content_id": "s1"}, "s1"], True),
            ("reused failed job", f, [{"status": "failed", "content_id": "s1"}, "s1"], False),
            ("canceled", f, [{"status": "canceled", "content_id": "s1"}, "s1"], False),
            ("another item", f, [{"status": "running", "content_id": "s2"}, "s1"], False),
            ("no body", f, [None, "s1"], False),
        ])

    def test_backoff_and_merge(self):
        check_cases(self, FILES, [
            ("backoff about 50 s", "EpTr_backoff", [], lambda v: v[:4] == [1, 2, 3, 4] and sum(v) == 45 and len(v) == 11),
            ("merge keeps personal state", "EpTr_merge",
             [{"content_id": "e1", "overview": "old", "pending_translation_language": "de", "user_data": {"played": True}},
              {"content_id": "e1", "overview": "neu", "machine_translated_fields": ["overview"]}],
             lambda v: v["overview"] == "neu" and v["user_data"] == {"played": True} and v.get("machine_translated_fields") == ["overview"]
             and v.get("pending_translation_language") is None),
        ])


if __name__ == "__main__":
    unittest.main()
