# SPDX-License-Identifier: AGPL-3.0-or-later
"""AI subtitle jobs name the playback session (Silo Android #726) and are sent once more
without it when the server cannot find the session (404)."""
import unittest

from brs import check_cases

FILES = ["components/player/SubtitleSuite.brs", "components/common/Settings.brs", "components/common/Utils.brs",
         "components/common/Content.brs"]

REQ = {"media_file_id": "42", "kind": "transcribe", "source_index": 1, "source_language": "en",
       "target_language": "", "start_position": 12.5}


class AiSession(unittest.TestCase):
    def test_body(self):
        b = "Subs_aiRequestBody"
        check_cases(self, FILES, [
            ("names the session", b, [REQ, "s1"], dict(REQ, session_id="s1")),
            ("no session: no field", b, [REQ, ""], REQ),
        ])

    def test_resend(self):
        r = "Subs_aiResendWithoutSession"
        check_cases(self, FILES, [
            ("404 with a session: resend", r, [404, True, "submitting"], True),
            ("404 without a session: failed", r, [404, False, "submitting"], False),
            ("404 after cancel: nothing", r, [404, True, "idle"], False),
            ("other errors: failed", r, [422, True, "submitting"], False),
            ("missing status", r, [None, True, "submitting"], False),
            ("no session flag in the context", r, [404, None, "submitting"], False),
        ])


class AiTranscribeKind(unittest.TestCase):
    """Untagged audio is transcribed only, and the progress title names the job (the user's
    request, Nov 12 2026)."""

    def test_untagged(self):
        u = "Subs_aiUntaggedLanguage"
        check_cases(self, FILES, [
            ("empty", u, [""], True),
            ("missing", u, [None], True),
            ("und", u, ["und"], True),
            ("upper case", u, ["UND"], True),
            ("mul", u, ["mul"], True),
            ("zxx", u, ["zxx"], True),
            ("english", u, ["eng"], False),
            ("catalan", u, ["cat"], False),
        ])

    def test_progress_title(self):
        t = "Subs_aiProgressTitle"
        check_cases(self, FILES, [
            ("transcribe", t, ["transcribe", 40], "Transcribing… 40%"),
            ("transcribe and translate", t, ["transcribe_translate", 5], "Transcribing and translating… 5%"),
            ("translate", t, ["translate", 99], "Translating… 99%"),
            ("unknown kind", t, ["", 0], "Translating… 0%"),
        ])


if __name__ == "__main__":
    unittest.main()
