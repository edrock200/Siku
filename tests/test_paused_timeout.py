# SPDX-License-Identifier: AGPL-3.0-or-later
"""PlaybackServerEnd.brs (Silo Android #1043, silo-roku #107): a 410 playback_session_paused_timeout
ends the session like an administrator's playback_session_ended, with its own notice; every video
start and replan advertises paused_timeout_v1, audio starts do not."""
import unittest

from brs import check_cases
from test_playback_caps import ctx

FILES = ["components/player/PlaybackServerEnd.brs", "components/common/Utils.brs"]
CAPS_FILES = ["components/player/PlaybackServerEnd.brs", "components/player/AudioCaps.brs",
              "components/player/PlaybackCaps.brs", "components/common/Settings.brs",
              "components/common/Utils.brs", "components/common/Content.brs"]


def resp(status, code="", title=""):
    return {"ok": False, "status": status, "error": {"code": code, "title": title}}


PAUSED = resp(410, "playback_session_paused_timeout", "Playback session paused too long")
ADMIN = resp(410, "playback_session_ended", "An administrator ended this playback session")
NOTICE = "Playback stopped because it was paused for too long."
ADMIN_NOTICE = "An administrator ended this playback session."


class Reason(unittest.TestCase):
    def test_reason(self):
        f = "PlaybackEnd_reason"
        check_cases(self, FILES, [
            ("paused past the limit", f, [PAUSED], "paused_timeout"),
            ("an administrator's stop", f, [ADMIN], "session_ended"),
            ("a string status", f, [dict(PAUSED, status="410")], "paused_timeout"),
            ("the type on another status is not an end", f, [dict(PAUSED, status=409)], ""),
            ("another 410", f, [resp(410, "gone")], ""),
            ("a 404 (expired: renewed, not ended)", f, [resp(404, "not_found", "Playback session not found")], ""),
            ("no error body", f, [{"ok": False, "status": 410}], ""),
            ("an error that is not an object", f, [{"ok": False, "status": 410, "error": "x"}], ""),
            ("no answer", f, [None], ""),
            ("a success", f, [{"ok": True, "status": 200}], ""),
        ])

    def test_notice(self):
        f = "PlaybackEnd_notice"
        check_cases(self, FILES, [
            ("paused timeout: its own notice", f, ["paused_timeout"], NOTICE),
            ("administrator: the admin wording", f, ["session_ended"], ADMIN_NOTICE),
            ("unknown falls back to the admin wording", f, [""], ADMIN_NOTICE),
        ])

    def test_without_feature(self):
        f = "PlaybackEnd_withoutFeature"
        check_cases(self, FILES, [
            ("taken out, order kept", f, [["playback_plan_v3", "paused_timeout_v1", "seek_reanchor_v1"]],
             ["playback_plan_v3", "seek_reanchor_v1"]),
            ("nothing to take out", f, [["playback_plan_v3"]], ["playback_plan_v3"]),
            ("no list", f, [None], []),
        ])

    def test_audio_session_ended(self):
        files = ["components/player/AudioSessionRecovery.brs"] + FILES
        check_cases(self, files, [
            ("audio: a paused timeout is an end too", "AudioSession_isEnded", [PAUSED], True),
            ("audio: never renewed", "AudioSession_progressAction", [PAUSED, "audiobook", True, 0], "ended"),
        ])


class Advertised(unittest.TestCase):
    def test_video_start_and_replan(self):
        plan = {"plan_id": "p1", "plan_attempt_key": "k1"}
        check_cases(self, CAPS_FILES, [
            ("every video start", "PlaybackCaps_startBody", ["inst-1", "42", "att-1", 0, "", ""],
             lambda v: "paused_timeout_v1" in v["client_features"], ctx()),
            ("every replan", "PlaybackCaps_replanBody", ["inst-1", "att-1", plan, "failure_recovery", "auto", 12.0, {}],
             lambda v: "paused_timeout_v1" in v["client_features"], ctx()),
            ("seek reanchor too", "PlaybackCaps_replanBody", ["inst-1", "att-1", plan, "seek_reanchor", "auto", 12.0, {}],
             lambda v: "paused_timeout_v1" in v["client_features"], ctx()),
            ("once only", "PlaybackCaps_clientFeatures", [], lambda v: v.count("paused_timeout_v1") == 1, ctx()),
        ])

    def test_audio_start(self):
        check_cases(self, CAPS_FILES, [
            ("audiobook start does not ask", "AudioCaps_startBody", ["inst-1", "b11", "att-1", 0, "client"],
             lambda v: "paused_timeout_v1" not in v["client_features"] and "playback_plan_v3" in v["client_features"], ctx()),
            ("music start does not ask", "AudioCaps_startBody", ["inst-1", "t1", "att-1", 0, "server"],
             lambda v: "paused_timeout_v1" not in v["client_features"], ctx()),
        ])


if __name__ == "__main__":
    unittest.main()
