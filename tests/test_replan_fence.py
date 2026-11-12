# SPDX-License-Identifier: AGPL-3.0-or-later
"""The player's replan fence (PlayerReplanFence.brs): the queue keeps the newest intent per kind,
relative seeks count from where a re-anchor is going, a queued re-anchor at the spot just mounted
is dropped, and only the latest replan's answer is read. Also the live AI socket's reconnect
decisions (AiLive.brs)."""
import unittest

from brs import check_cases

FILES = ["components/player/PlayerReplanFence.brs", "components/common/Utils.brs"]
AI_FILES = ["components/player/AiLive.brs", "components/common/AiLiveCues.brs", "components/common/Utils.brs"]


class Queue(unittest.TestCase):
    def test_push(self):
        c = "ReplanFence_push"
        q1 = {"slot": "quality", "label": "720p"}
        a = {"slot": "audio", "index": 2}
        q2 = {"slot": "quality", "label": "480p"}
        check_cases(self, FILES, [
            ("into an empty queue", c, [[], q1], [q1]),
            ("no queue yet", c, [None, q1], [q1]),
            ("another kind keeps its place", c, [[q1], a], [q1, a]),
            ("the newest quality pick replaces the older", c, [[q1, a], q2], [a, q2]),
            ("bounded", c, [[{"slot": str(i)} for i in range(6)], q1], lambda v: len(v) == 6 and v[-1] == q1 and v[0] == {"slot": "1"}),
        ])


class SeekBase(unittest.TestCase):
    def test_base(self):
        c = "ReplanFence_seekBase"
        # position, reanchorBusy, inFlightTarget, queuedTarget
        check_cases(self, FILES, [
            ("nothing in flight: the position", c, [100.0, False, -1.0, -1.0], 100),
            ("a re-anchor in flight: its target", c, [100.0, True, 130.0, -1.0], 130),
            ("a queued target wins", c, [100.0, True, 130.0, 160.0], 160),
            ("a stale target after the answer is ignored", c, [100.0, False, 130.0, -1.0], 100),
            ("queued behind a replan", c, [100.0, False, -1.0, 400.0], 400),
        ])

    def test_near_mounted(self):
        c = "ReplanFence_nearMounted"
        check_cases(self, FILES, [
            ("the same spot", c, [130.0, 130.0], True),
            ("within a second", c, [130.9, 130.0], True),
            ("a second press further on", c, [160.0, 130.0], False),
            ("behind", c, [128.5, 130.0], False),
        ])


class Stale(unittest.TestCase):
    def test_stale(self):
        c = "ReplanFence_stale"
        ctx = {"attemptId": "a1", "sessionId": "s1", "seq": 4, "kind": "audio"}
        check_cases(self, FILES, [
            ("the current request", c, [ctx, "a1", "s1", 4], ""),
            ("a newer replan was sent", c, [ctx, "a1", "s1", 5], "seq"),
            ("another attempt", c, [ctx, "a2", "s1", 4], "attempt"),
            ("a renewed session", c, [ctx, "a1", "s2", 4], "attempt"),
            ("no context", c, [None, "a1", "s1", 4], "attempt"),
            ("seq as a string still compares", c, [dict(ctx, seq="4"), "a1", "s1", 4], ""),
        ])


class PlayerState(unittest.TestCase):
    def test_busy(self):
        check_cases(self, FILES, [
            ("idle", "Replan_busy", [], False, {"m": {"replanPending": False, "reanchorBusy": False, "subs": {"adoptId": ""}}}),
            ("a replan", "Replan_busy", [], True, {"m": {"replanPending": True, "reanchorBusy": False}}),
            ("a re-anchor", "Replan_busy", [], True, {"m": {"replanPending": False, "reanchorBusy": True}}),
            ("an adoption", "Replan_busy", [], True, {"m": {"replanPending": False, "reanchorBusy": False, "subs": {"adoptId": "77"}}}),
            ("a re-anchor is not another replan", "Replan_otherBusy", [], False, {"m": {"replanPending": False, "reanchorBusy": True}}),
        ])

    def test_seek_base_from_state(self):
        check_cases(self, FILES, [
            ("three presses add up", "seekBase", [], 160,
             {"m": {"position": 100.0, "reanchorBusy": True, "reanchorTarget": 130.0, "reanchorQueued": 160.0}}),
            ("before the re-anchor state exists", "seekBase", [], 42, {"m": {"position": 42.0}}),
        ])

    def test_queued_audio(self):
        check_cases(self, FILES, [
            ("shown as applying", "Replan_queuedAudioIndex", [], 3,
             {"m": {"replanQueue": [{"slot": "quality", "label": "720p"}, {"slot": "audio", "index": 3}]}}),
            ("none queued", "Replan_queuedAudioIndex", [], -1, {"m": {"replanQueue": []}}),
        ])

    def test_phone_quality_switching(self):
        f = ["components/player/PlayerRemote.brs", "components/common/Utils.brs"]
        c = "Remote_isQualitySwitching"
        check_cases(self, f, [
            ("a quality change in flight", c, [], True, {"m": {"replanPending": True, "replanKind": "quality"}}),
            ("a buffering lowering in flight", c, [], True, {"m": {"replanPending": True, "replanKind": "bq"}}),
            ("after it landed", c, [], False, {"m": {"replanPending": False, "replanKind": "quality"}}),
            ("an audio change", c, [], False, {"m": {"replanPending": True, "replanKind": "audio"}}),
        ])


class AiReconnect(unittest.TestCase):
    def test_should_reconnect(self):
        c = "AiLive_shouldReconnect"
        # kind, reason, reconnecting, jobRunning
        check_cases(self, AI_FILES, [
            ("closed by the server mid-job", c, ["closed", "closed_by_server", False, True], True),
            ("went quiet mid-job", c, ["closed", "quiet", False, True], True),
            ("job over", c, ["closed", "closed_by_server", False, False], False),
            ("shut by the player", c, ["closed", "shutdown", False, True], False),
            ("no roWebSocket", c, ["failed", "unsupported", False, True], False),
            ("wrong protocol", c, ["closed", "protocol", False, True], False),
            ("first connect failing is not retried", c, ["failed", "error", False, True], False),
            ("a reconnect that failed tries again", c, ["failed", "timeout", True, True], True),
        ])

    def test_delay(self):
        c = "AiLive_retryDelay"
        check_cases(self, AI_FILES, [
            ("first", c, [1], 2), ("second", c, [2], 4), ("third", c, [3], 8), ("fourth", c, [4], 16),
            ("spent", c, [5], 0), ("none", c, [0], 0),
        ])


if __name__ == "__main__":
    unittest.main()
