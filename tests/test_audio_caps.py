# SPDX-License-Identifier: AGPL-3.0-or-later
"""AudioCaps.brs: the audio-only start body. A WAV audiobook's codec is ffprobe's pcm_s16le and the
server matches names exactly, so a passing "pcm" probe is declared as the PCM names (Silo Android
#707), never as a bare "pcm"."""
import unittest

from brs import check_cases
from test_playback_caps import ctx

FILES = ["components/player/AudioCaps.brs", "components/player/PlaybackCaps.brs", "components/common/Settings.brs",
         "components/common/Utils.brs", "components/common/Content.brs"]


def codecs_of(delivery):
    return lambda v: v["client_playback_context"]["deliveries"][delivery]["audio_decode_codecs"]


class AudioCaps(unittest.TestCase):
    def test_wire_names(self):
        c = "AudioCaps_wireNames"
        check_cases(self, FILES, [
            ("pcm: the 16- and 24-bit integer names", c, ["pcm"], ["pcm_s16le", "pcm_s24le"]),
            ("flac as it is", c, ["flac"], ["flac"]),
            ("opus as it is", c, ["opus"], ["opus"]),
        ])

    def test_codec_list(self):
        c = "AudioCaps_codecList"
        check_cases(self, FILES, [
            ("pcm probe passed", c, [["aac", "mp3"], ["flac", "pcm"]], ["aac", "mp3", "flac", "pcm_s16le", "pcm_s24le"]),
            ("pcm probe failed", c, [["aac", "mp3"], ["flac"]], ["aac", "mp3", "flac"]),
            ("no duplicates", c, [["aac", "flac"], ["flac", "opus"]], ["aac", "flac", "opus"]),
        ])

    def test_start_body(self):
        c = "AudioCaps_startBody"
        args = ["inst-00000001", "b11", "attempt-0001", 0, "client"]
        r = check_cases(self, FILES, [
            ("no bare pcm in codecs_audio", c, args, lambda v: "pcm" not in v["client_capabilities"]["codecs_audio"], ctx()),
            ("original_http lists wav", c, args,
             lambda v: "wav" in v["client_playback_context"]["deliveries"]["original_http"]["containers"], ctx()),
            ("original_http decode list matches codecs_audio", c, args,
             lambda v: codecs_of("original_http")(v) == v["client_capabilities"]["codecs_audio"], ctx()),
        ])
        # brs-cli's roDeviceInfo decides whether the pcm probe passes; when it does, both names follow.
        listed = r[0]["value"]["client_capabilities"]["codecs_audio"]
        self.assertEqual("pcm_s16le" in listed, "pcm_s24le" in listed, listed)


if __name__ == "__main__":
    unittest.main()
