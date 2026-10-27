# SPDX-License-Identifier: AGPL-3.0-or-later
"""Roku voice transport commands: parsing, strict `duration` validation, seek targets
(components/common/VoiceTransport.brs) and the answer main.brs sends (source/MainEvents.brs).
Cases adapted from ManavA/silo-roku, AGPL-3.0 (tests/test_voice_transport.py)."""
import unittest

from brs import check_cases

VOICE = ["components/common/VoiceTransport.brs"]
MAIN = ["source/MainEvents.brs"]


def seek(direction, duration):
    return {"type": "transport", "command": "seek", "direction": direction, "duration": duration}


class Parse(unittest.TestCase):
    def test_commands(self):
        p = "Voice_parse"
        play = {"action": "play", "delta": 0, "toStart": False}
        check_cases(self, VOICE, [
            ("play", p, [{"command": "play"}, 10, 30], play),
            ("resume is play", p, [{"command": "resume"}, 10, 30], play),
            ("upper case", p, [{"command": "PAUSE"}, 10, 30], {"action": "pause", "delta": 0, "toStart": False}),
            ("stop", p, [{"command": "stop"}, 10, 30], {"action": "stop", "delta": 0, "toStart": False}),
            ("forward uses the forward skip", p, [{"command": "forward"}, 10, 30], {"action": "seek", "delta": 30, "toStart": False}),
            ("rewind uses the back skip", p, [{"command": "rewind"}, 15, 30], {"action": "seek", "delta": -15, "toStart": False}),
            ("replay uses the back skip", p, [{"command": "replay"}, 10, 30], {"action": "seek", "delta": -10, "toStart": False}),
            ("start over", p, [{"command": "startover"}, 10, 30], {"action": "seek", "delta": 0, "toStart": True}),
            ("seek forward", p, [seek("forward", "90"), 10, 30], {"action": "seek", "delta": 90, "toStart": False}),
            ("seek backward", p, [seek("backward", "45"), 10, 30], {"action": "seek", "delta": -45, "toStart": False}),
            ("seek with a number", p, [seek("forward", 20), 10, 30], {"action": "seek", "delta": 20, "toStart": False}),
            ("next is not handled", p, [{"command": "next"}, 10, 30], None),
            ("no command", p, [{}, 10, 30], None),
            ("not an object", p, ["pause", 10, 30], None),
            ("command not text", p, [{"command": 5}, 10, 30], None),
            ("seek sideways", p, [seek("sideways", "30"), 10, 30], None),
            ("seek without direction", p, [{"command": "seek", "duration": "30"}, 10, 30], None),
            ("seek 3x", p, [seek("forward", "3x"), 10, 30], None),
            ("seek negative", p, [seek("forward", "-5"), 10, 30], None),
            ("seek exponent", p, [seek("forward", "1e9"), 10, 30], None),
            ("seek decimal", p, [seek("forward", "1.5"), 10, 30], None),
            ("seek empty", p, [seek("forward", ""), 10, 30], None),
            ("seek zero", p, [seek("forward", "0"), 10, 30], None),
            ("seek too long", p, [seek("forward", "1234567"), 10, 30], None),
            ("seek padded", p, [seek("forward", " 30"), 10, 30], None),
            ("seek huge number", p, [seek("forward", 99999999), 10, 30], None),
            ("seek missing duration", p, [{"command": "seek", "direction": "forward"}, 10, 30], None),
        ])

    def test_targets(self):
        t = "Voice_target"
        check_cases(self, VOICE, [
            ("inside", t, [60.0, 30, False, 600.0], {"target": 90, "status": "success"}),
            ("back past the start", t, [20.0, -30, False, 600.0], {"target": 0, "status": "success.seek-start"}),
            ("past the end", t, [590.0, 30, False, 600.0], {"target": 599, "status": "success.seek-end"}),
            ("start over", t, [300.0, 0, True, 600.0], {"target": 0, "status": "success"}),
            ("unknown duration", t, [60.0, 30, False, 0.0], None),
        ])

    def test_feedback_and_log(self):
        check_cases(self, VOICE, [
            ("forward chip", "Voice_feedback", [60.0, 90.0], "+30s"),
            ("back chip", "Voice_feedback", [60.0, 50.0], "-10s"),
            ("no movement", "Voice_feedback", [0.0, 0.0], ""),
            ("log pause", "Voice_describe", [{"command": "pause"}], "command=pause"),
            ("log seek", "Voice_describe", [seek("backward", "30")], "command=seek direction=backward duration=30"),
            ("log bad seek", "Voice_describe", [seek("up", "x")], "command=seek direction=up duration=invalid"),
            ("log never prints odd text", "Voice_describe", [{"command": "http://x/?t=secret"}], "command=other"),
            ("debug seek back", "Voice_debugInfo", ["seek:-90"],
             {"type": "transport", "id": "debug", "command": "seek", "direction": "backward", "duration": "90"}),
            ("debug pause", "Voice_debugInfo", ["pause"], {"type": "transport", "id": "debug", "command": "pause"}),
        ])


class Answer(unittest.TestCase):
    def test_is_transport(self):
        f = "MainEvents_isTransport"
        check_cases(self, MAIN, [
            ("transport", f, [{"type": "transport", "command": "pause"}], True),
            ("deep link", f, [{"contentId": "movie:x", "mediaType": "movie"}], False),
            ("type not text", f, [{"type": 1}], False),
            ("not an object", f, [None], False),
        ])

    def test_response(self):
        f = "MainEvents_transportResponse"
        check_cases(self, MAIN, [
            ("success keeps the id", f, [{"id": 42}, {"status": "success"}], {"id": 42, "status": "success"}),
            ("string id", f, [{"id": "0042"}, {"status": "success.seek-end"}], {"id": "0042", "status": "success.seek-end"}),
            ("refused", f, [{"id": 7}, {"status": "error.generic"}], {"id": 7, "status": "error.generic"}),
            ("unknown status is an error", f, [{"id": 7}, {"status": "great"}], {"id": 7, "status": "error.generic"}),
            ("no answer is an error", f, [{"id": 7}, None], {"id": 7, "status": "error.generic"}),
            ("no id", f, [{}, {"status": "success"}], {"status": "success"}),
        ])


if __name__ == "__main__":
    unittest.main()
