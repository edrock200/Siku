# SPDX-License-Identifier: AGPL-3.0-or-later
"""A buffering step-down claims a slow link only with slow-transfer evidence (Silo Android #1011;
components/player/BufferingQuality.brs BQ_loweringFor and BQ_claimForRequest). The lowering still
goes out on any counted stall, but bandwidth_estimate_source observed_rebuffer (which the server keeps
as this device's learned limit for 24 hours) and observed_throughput_kbps go only when the plan's media
measurably arrived more slowly than its delivered bitrate, only with the reading they rest on, and never
on a server transcode, where Roku's segment download time includes the wait for the encoder."""
import unittest

from brs import check_cases

FILES = ["components/player/BufferingQuality.brs"]


def bq(kbps):
    return {"c": {"MIN_ESTIMATE_KBPS": 100}, "throughputKbps": kbps}


PLAN = {"deliveredKbps": 63000, "quality": "auto", "rungs": [{"label": "1080p", "kbps": 20000}, {"label": "720p", "kbps": 8000}],
        "activeQuality": None}


def lowering(source):
    return lambda v: v is not None and v["quality"] == "auto" and v["estimateKbps"] == 44100 and v["estimateSource"] == source


class Lowering(unittest.TestCase):
    """Silo Android's BufferingQualityControllerTest 'claims a slow link only with measured slow transfer'."""

    def test_cases(self):
        c = "BQ_loweringFor"
        check_cases(self, FILES, [
            ("slow transfer measured: observed_rebuffer", c, [bq(2000), PLAN], lowering("observed_rebuffer")),
            ("no transfer timed: the step-down goes unsourced", c, [bq(0), PLAN], lowering("")),
            ("media arriving above the delivered bitrate: unsourced", c, [bq(80000), PLAN], lowering("")),
            ("a pinned rung lowers to the next rung, never sourced", c,
             [bq(2000), dict(PLAN, quality="1080p", activeQuality="1080p")],
             lambda v: v["quality"] == "720p" and v["estimateSource"] == ""),
        ])


class Claim(unittest.TestCase):
    def test_cases(self):
        c = "BQ_claimForRequest"
        check_cases(self, FILES, [
            ("a claim with its reading on a copy remux", c, ["observed_rebuffer", 2000, 63000, "server_remux_hls"],
             {"source": "observed_rebuffer", "observedKbps": 2000, "reason": ""}),
            ("the reading is gone at send (a new mount reset the meter)", c, ["observed_rebuffer", 0, 63000, "server_remux_hls"],
             {"source": "", "observedKbps": 0, "reason": "no_reading"}),
            ("a server transcode: encoder waits are in Roku's timings", c, ["observed_rebuffer", 2000, 63000, "server_transcode_hls"],
             {"source": "", "observedKbps": 0, "reason": "server_encodes"}),
            ("the reading is no longer below the bitrate", c, ["observed_rebuffer", 70000, 63000, "server_remux_hls"],
             {"source": "", "observedKbps": 0, "reason": "not_slow"}),
            ("no claim stays no claim", c, ["", 2000, 63000, "server_remux_hls"], {"source": "", "observedKbps": 0, "reason": ""}),
            ("loose numbers", c, ["observed_rebuffer", "2000", "63000", "SERVER_REMUX_HLS"],
             {"source": "observed_rebuffer", "observedKbps": 2000, "reason": ""}),
        ])


if __name__ == "__main__":
    unittest.main()
