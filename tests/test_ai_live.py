# SPDX-License-Identifier: AGPL-3.0-or-later
"""Live AI subtitle cues (AiLiveCues.brs): the control socket's URL, protocols and hello, which
frames count, merging playhead-first batches, and the text on screen at a time."""
import json
import unittest

from brs import check_cases

FILES = ["components/common/AiLiveCues.brs", "components/common/Utils.brs"]


def frame(name, payload, typ="event", sid="s1"):
    return json.dumps({"type": typ, "session_id": sid, "name": name, "payload": payload})


CUES = [{"start": 10.0, "end": 12.0, "text": "Hallo"}, {"start": 11.5, "end": 13.0, "text": "Wer da?"},
        {"start": 2.0, "end": 3.0, "text": "Anfang"}]


class Socket(unittest.TestCase):
    def test_url_and_protocols(self):
        u = "AiLive_socketUrl"
        check_cases(self, FILES, [
            ("https becomes wss", u, ["https://silo.example", "abc"], "wss://silo.example/api/v2/playback/sessions/abc/control/ws"),
            ("http keeps a path prefix", u, ["http://h:8097/silo/", "a b"], "ws://h:8097/silo/api/v2/playback/sessions/a%20b/control/ws"),
            ("no session", u, ["https://h", ""], ""),
            ("not http", u, ["ftp://h", "s"], ""),
            ("protocols", "AiLive_protocols", ["T1"], "silo.playback-control.v2, silo.ticket.T1"),
        ])

    def test_hello(self):
        check_cases(self, FILES, [
            ("hello frame", "AiLive_hello", ["s1", "0.1.43"], lambda v: json.loads(v) == {
                "type": "hello", "session_id": "s1", "client": {"name": "Siku", "version": "0.1.43"}, "capabilities": {"commands": []}}),
        ])

    def test_caps(self):
        c = "AiLive_capsUsable"
        check_cases(self, FILES, [
            ("available", c, [{"available": True, "protocol": "silo.playback-control.v2"}], True),
            ("other protocol", c, [{"available": True, "protocol": "silo.playback-control.v3"}], False),
            ("not available", c, [{"available": False, "protocol": ""}], False),
            ("string flag is not a boolean", c, [{"available": "true", "protocol": "silo.playback-control.v2"}], False),
            ("missing", c, [None], False),
        ])


class Frames(unittest.TestCase):
    def test_frame_event(self):
        f = "AiLive_frameEvent"
        big = '{"type":"event","session_id":"s1","name":"subtitle_translation_cues","payload":{"session_id":"s1","file_id":42,"job_id":9007199254740993,"track_key":"k","cues":[],"done":1,"total":9}}'
        check_cases(self, FILES, [
            ("cues of this session and file", f, [frame("subtitle_translation_cues", {"session_id": "s1", "file_id": 42, "job_id": 7, "track_key": "k", "cues": CUES, "done": 3, "total": 9}), "s1", "42"],
             lambda v: v["name"] == "subtitle_translation_cues" and v["payload"]["job_id"] == "7" and len(v["payload"]["cues"]) == 3),
            ("a job id past 2^53 keeps every digit", f, [big, "s1", "42"], lambda v: v["payload"]["job_id"] == "9007199254740993"),
            ("another session", f, [frame("subtitle_translation_started", {"session_id": "s2", "file_id": 42, "job_id": 7}, sid="s2"), "s1", "42"], None),
            ("another file", f, [frame("subtitle_translation_started", {"session_id": "s1", "file_id": 43, "job_id": 7}), "s1", "42"], None),
            ("other events", f, [frame("subtitle_ready", {"session_id": "s1", "file_id": 42}), "s1", "42"], None),
            ("commands are ignored", f, [frame("subtitle_translation_started", {"session_id": "s1"}, typ="command"), "s1", "42"], None),
            ("broken json", f, ['{"type":"event","name":"subtitle_translation_cues"', "s1", "42"], None),
            ("not text", f, [5, "s1", "42"], None),
        ])

    def test_quote_ids(self):
        q = "AiLive_quoteIds"
        esc = json.dumps({"text": 'say "job_id":5'})
        check_cases(self, FILES, [
            ("numbers quoted", q, ['{"job_id": 7,"file_id":-42, "subtitle_id":9007199254740993}'], '{"job_id": "7","file_id":"-42", "subtitle_id":"9007199254740993"}'),
            ("already strings", q, ['{"job_id":"7"}'], '{"job_id":"7"}'),
            ("inside cue text untouched", q, [esc], esc),
            ("every occurrence", q, ['[{"job_id":1},{"job_id":22}]'], '[{"job_id":"1"},{"job_id":"22"}]'),
        ])

    def test_matches(self):
        m = "AiLive_matches"
        check_cases(self, FILES, [
            ("same job", m, [{"job_id": "7", "track_key": "k"}, "7", ""], True),
            ("same job and track", m, [{"job_id": "7", "track_key": "k"}, "7", "k"], True),
            ("another track", m, [{"job_id": "7", "track_key": "x"}, "7", "k"], False),
            ("another job", m, [{"job_id": "8"}, "7", ""], False),
            ("no job yet", m, [{"job_id": "7"}, "", ""], False),
        ])


class Cues(unittest.TestCase):
    def test_merge(self):
        g = "AiLive_mergeCues"
        later = [{"start": 20.0, "end": 21.0, "text": "Später"}]
        check_cases(self, FILES, [
            ("sorted by start", g, [[], {}, CUES, 100], lambda v: [c["start"] for c in v] == [2.0, 10.0, 11.5]),
            ("a batch from earlier in the file lands in order", g, [[dict(c) for c in later], {}, CUES, 100],
             lambda v: [c["text"] for c in v] == ["Anfang", "Hallo", "Wer da?", "Später"]),
            ("a cue sent twice is kept once", g, [[], {}, CUES + CUES, 100], lambda v: len(v) == 3),
            ("bad cues are skipped", g, [[], {}, [{"start": 5, "end": 4, "text": "x"}, {"start": 1, "end": 2, "text": ""}, {"start": "3", "end": "4.5", "text": "ok"}, 7], 100],
             lambda v: len(v) == 1 and v[0]["text"] == "ok"),
            ("capped", g, [[], {}, CUES, 2], lambda v: len(v) == 2),
            ("long text is cut", g, [[], {}, [{"start": 1, "end": 2, "text": "a" * 900}], 10], lambda v: len(v[0]["text"]) == 300),
            ("not a list", g, [[], {}, None, 10], []),
        ])

    def test_text_at(self):
        t = "AiLive_textAt"
        cues = sorted(CUES, key=lambda c: c["start"])
        check_cases(self, FILES, [
            ("before every cue", t, [cues, 1.0], ""),
            ("one cue", t, [cues, 2.5], "Anfang"),
            ("between cues", t, [cues, 5.0], ""),
            ("overlapping lines, in order", t, [cues, 11.8], "Hallo\nWer da?"),
            ("an ended cue is gone", t, [cues, 12.5], "Wer da?"),
            ("end is exclusive", t, [cues, 13.0], ""),
            ("nothing yet", t, [[], 4.0], ""),
        ])

    def test_source_time(self):
        s = "AiLive_sourceTime"
        check_cases(self, FILES, [
            ("timeline offset", s, [5.0, 600.0, 0], 605.0),
            ("a delay shows cues later", s, [5.0, 0.0, 500], 4.5),
        ])


if __name__ == "__main__":
    unittest.main()
