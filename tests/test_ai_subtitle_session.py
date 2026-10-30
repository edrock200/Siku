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


if __name__ == "__main__":
    unittest.main()
