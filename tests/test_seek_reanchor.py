# SPDX-License-Identifier: AGPL-3.0-or-later
"""PlayerSeekReanchor's pure decisions: which seeks the server re-anchors, the lead-in a copy
remux's reanchor asks for (adapted from Silo-Server/silo-roku 01a0f42), and what a mount's first
"playing" does about where Roku opened the load."""
import unittest

from brs import check_cases

FILES = ["components/player/PlayerSeekReanchor.brs", "components/player/PlaybackCaps.brs", "components/common/Utils.brs"]

COPY = {"delivery": "server_remux_hls", "timeline": {"timeline_offset_seconds": 600, "seek_window_start_seconds": 600,
                                                    "can_seek_anywhere": False}}


class SeekReanchor(unittest.TestCase):
    def test_copy_remux(self):
        c = "SeekReanchor_isCopyRemux"
        check_cases(self, FILES, [
            ("a copy remux", c, [{"delivery": "server_remux_hls"}], True),
            ("its progressive kin", c, [{"delivery": "server_remux_progressive"}], True),
            ("a transcode", c, [{"delivery": "server_transcode_hls"}], False),
            ("an original", c, [{"delivery": "original_http"}], False),
            ("no delivery", c, [{}], False),
            ("no plan", c, [None], False),
        ])

    def test_lead_position(self):
        c = "SeekReanchor_leadPosition"
        check_cases(self, FILES, [
            ("10 s before the target", c, [1800.0], lambda v: abs(v - 1790) < 0.001),
            ("never below the start", c, [4.0], lambda v: v == 0),
            ("exactly the lead", c, [10.0], lambda v: v == 0),
        ])

    def test_decide(self):
        c = "SeekReanchor_decide"
        check_cases(self, FILES, [
            ("before the window", c, [COPY, 100.0, 700.0], "outside_window"),
            ("inside the proven extent", c, [COPY, 650.0, 700.0], ""),
            ("past the proven extent", c, [COPY, 900.0, 700.0], "unknown_window"),
            ("no timeline keeps the Video seek", c, [{"delivery": "server_transcode_hls"}, 900.0, 700.0], ""),
        ])

    def test_start_action(self):
        c = "SeekReanchor_startAction"
        # position, start, leadIn, copyRemux, canReanchor
        check_cases(self, FILES, [
            ("landed within 3 s", c, [1801.0, 1800.0, False, True, True], ""),
            ("a lead-in landed at its segment's start", c, [1799.0, 1800.0, True, True, True], ""),
            ("a copy remux opened late reanchors", c, [1806.0, 1800.0, False, True, True], "reanchor"),
            ("not when a reanchor cannot be sent", c, [1806.0, 1800.0, False, True, False], "seek"),
            ("not twice: a late lead-in seeks back", c, [1806.0, 1800.0, True, True, True], "seek"),
            ("not under the lead, where PlayStart is ignored anyway", c, [7.0, 0.5, False, True, True], "seek"),
            ("a lead-in opened at the stream's origin seeks forward", c, [1790.0, 1800.0, True, True, True], "seek_forward"),
            ("another load opened short seeks there", c, [1790.0, 1800.0, False, True, True], "seek"),
            ("a transcode opened late seeks back", c, [1806.0, 1800.0, False, False, True], "seek"),
        ])

    def test_landed_and_format(self):
        check_cases(self, FILES, [
            ("within 3 s landed", "SeekReanchor_landed", [1802.5, 1800.0], True),
            ("moving is not landing", "SeekReanchor_landed", [1796.0, 1800.0], False),
            ("tenths", "SeekReanchor_fmt", [1800.06], "1800.1"),
            ("zero", "SeekReanchor_fmt", [0], "0.0"),
            ("negative", "SeekReanchor_fmt", [-2.25], "-2.3"),
            ("a string number", "SeekReanchor_fmt", ["12.5"], "12.5"),
        ])


if __name__ == "__main__":
    unittest.main()
