# SPDX-License-Identifier: AGPL-3.0-or-later
"""SubtitleSelect.brs: a sidecar is selected by the TrackName Roku lists for it, checked once after
the content settles, captions are hidden under the controls, and a first-time embedded extraction is
waited for (adapted from silo-roku's sidecars.bs and its hardware runs)."""
import unittest

from brs import check_cases

FILES = ["components/player/SubtitleSelect.brs", "components/common/Utils.brs"]

U1 = "http://silo.example:8097/api/v2/stream/s1/subtitles/1.vtt?file_id=52&token=acc"
U2 = "http://silo.example:8097/api/v2/stream/s1/subtitles/0.vtt?file_id=52&token=acc"
LISTED = [{"TrackName": "eia608/1"}, {"TrackName": "/tmp/plugin/X/" + U2}, {"TrackName": "/tmp/plugin/X/" + U1},
          {"TrackName": "mkv/3"}]
TRACKS = [{"trackId": "file:52:subtitle:0", "url": U2}, {"trackId": "file:52:subtitle:1", "url": U1}]


class Selection(unittest.TestCase):
    def test_listed_name(self):
        f = "Subs_listedName"
        check_cases(self, FILES, [
            ("the listed name that contains the url", f, [LISTED, U1], "/tmp/plugin/X/" + U1),
            ("the exact name wins", f, [LISTED + [{"TrackName": U1}], U1], U1),
            ("not listed yet", f, [[{"TrackName": "mkv/3"}], U1], ""),
            ("no list", f, [None, U1], ""),
            ("no url (a rendition)", f, [LISTED, ""], ""),
        ])

    def test_drawn(self):
        f = "Subs_drawn"
        check_cases(self, FILES, [
            ("selected and playing", f, [U1, "/tmp/x/" + U1, U1], True),
            ("selected, nothing reported playing", f, [U1, U1, ""], True),
            ("the file's own track plays (run 20)", f, [U1, U1, "mkv/3"], False),
            ("the old sidecar still plays (run 17)", f, [U1, U1, "/tmp/x/" + U2], False),
            ("not selected", f, [U1, "", ""], False),
        ])

    def test_track_index_and_log_names(self):
        check_cases(self, FILES, [
            ("ours by listed name", "Subs_trackIndexOf", [TRACKS, "/tmp/x/" + U1], 1),
            ("a container track is not ours", "Subs_trackIndexOf", [TRACKS, "mkv/3"], -1),
            ("empty", "Subs_trackIndexOf", [TRACKS, ""], -1),
            ("ours logs by track id", "Subs_nameForLog", [TRACKS, "/tmp/x/" + U2], "sidecar:file:52:subtitle:0"),
            ("a foreign url is masked", "Subs_nameForLog", [TRACKS, "http://other/x.vtt?token=zzz"], "url"),
            ("roku's own name is kept", "Subs_nameForLog", [TRACKS, "mkv/3"], "mkv/3"),
            ("nothing", "Subs_nameForLog", [TRACKS, ""], "none"),
        ])

    def test_captions(self):
        f = "Subs_captionsSuppressed"
        check_cases(self, FILES, [
            ("controls up", f, [True, False, True], True),
            ("panel up", f, [False, True, True], True),
            ("nothing up", f, [False, False, True], False),
            ("content still settling", f, [True, False, False], False),
        ])

    def test_ready_check(self):
        o = "http://silo.example:8097"
        f = "Subs_needsReadyCheck"
        check_cases(self, FILES, [
            ("embedded sidecar on the server", f, [{"source": "embedded", "url": U1, "rendition": ""}, o], True),
            ("external sidecar", f, [{"source": "external", "url": U1}, o], False),
            ("a rendition", f, [{"source": "embedded", "url": "", "rendition": "Subtitles"}, o], False),
            ("another host", f, [{"source": "embedded", "url": "http://cdn.example/a.vtt"}, o], False),
            ("a host that only starts like the origin", f, [{"source": "embedded", "url": o + "0/api/v2/x.vtt"}, o], False),
            ("no origin", f, [{"source": "embedded", "url": U1}, ""], False),
            ("fast answer", "Subs_readyAction", [True, 1200], "ready"),
            ("slow answer remounts", "Subs_readyAction", [True, 65000], "reload"),
            ("threshold", "Subs_readyAction", [True, 8000], "reload"),
            ("failed", "Subs_readyAction", [False, 300000], "failed"),
        ])


if __name__ == "__main__":
    unittest.main()
