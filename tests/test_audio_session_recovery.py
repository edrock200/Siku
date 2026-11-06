# SPDX-License-Identifier: AGPL-3.0-or-later
"""AudioSessionRecovery's decisions (Silo Android #708, AudiobookReplanRecoveryTest): only an expired
session starts a fresh one, a session an administrator ended never does, and Play retries after an
error unless the server ended the session."""
import unittest

from brs import check_cases

FILES = ["components/player/AudioSessionRecovery.brs", "components/common/Utils.brs"]


def resp(status, code="", title="", detail=""):
    return {"ok": False, "status": status, "error": {"code": code, "title": title, "detail": detail}}


EXPIRED_V2 = resp(404, "not_found", "Not Found", "Playback session not found")
EXPIRED_V1 = resp(404, "playback_session_not_found", "Playback session not found")
ENDED = resp(410, "playback_session_ended", "An administrator ended this playback session")
MISSING_FILE = resp(404, "not_found", "Not Found", "Source media file is missing")
UNAVAILABLE = resp(503, "dependency_unavailable", "Playback is temporarily unavailable.")
NETWORK = resp(0, "network", "Can't reach the server")
OTHER_410 = resp(410, "gone", "Gone")


class AudioSessionRecovery(unittest.TestCase):
    def test_missing_and_ended(self):
        check_cases(self, FILES, [
            ("v2 not_found naming the session", "AudioSession_isMissing", [EXPIRED_V2], True),
            ("the v1 code", "AudioSession_isMissing", [EXPIRED_V1], True),
            ("another 404", "AudioSession_isMissing", [MISSING_FILE], False),
            ("ended is not missing", "AudioSession_isMissing", [ENDED], False),
            ("a string status", "AudioSession_isMissing", [dict(EXPIRED_V2, status="404")], True),
            ("no error body", "AudioSession_isMissing", [{"ok": False, "status": 404}], False),
            ("no answer", "AudioSession_isMissing", [None], False),
            ("an administrator ended it", "AudioSession_isEnded", [ENDED], True),
            ("another 410", "AudioSession_isEnded", [OTHER_410], False),
            ("expired is not ended", "AudioSession_isEnded", [EXPIRED_V1], False),
        ])

    def test_progress_action(self):
        c = "AudioSession_progressAction"
        check_cases(self, FILES, [
            ("expired while playing: fresh session now", c, [EXPIRED_V2, "audiobook", False, 0], "renew"),
            ("the v1 code too", c, [EXPIRED_V1, "audiobook", False, 2], "renew"),
            ("expired while paused: on Play", c, [EXPIRED_V2, "audiobook", True, 0], "renew_on_play"),
            ("after 3 renewals in a row: stop", c, [EXPIRED_V2, "audiobook", False, 3], "stop_reporting"),
            ("music keeps the old stop", c, [EXPIRED_V2, "music", False, 0], "stop_reporting"),
            ("ended: never renewed", c, [ENDED, "audiobook", False, 0], "ended"),
            ("ended while paused", c, [ENDED, "audiobook", True, 0], "ended"),
            ("ended for music too", c, [ENDED, "music", False, 0], "ended"),
            ("another 404 stops reporting", c, [MISSING_FILE, "audiobook", False, 0], "stop_reporting"),
            ("another 410 stops reporting", c, [OTHER_410, "audiobook", False, 0], "stop_reporting"),
            ("a 503 keeps the session", c, [UNAVAILABLE, "audiobook", False, 0], ""),
            ("a network failure keeps the session", c, [NETWORK, "audiobook", False, 0], ""),
            ("no answer", c, [None, "audiobook", False, 0], ""),
        ])

    def test_can_retry(self):
        c = "AudioSession_canRetry"
        check_cases(self, FILES, [
            ("after an error", c, [True, False, False], True),
            ("not when the server ended it", c, [True, True, False], False),
            ("not while closing", c, [True, False, True], False),
            ("no error, nothing to retry", c, [False, False, False], False),
        ])


if __name__ == "__main__":
    unittest.main()
