# SPDX-License-Identifier: AGPL-3.0-or-later
"""The pure parts of PlaybackCaps.brs: what Siku declares to the server for each delivery, the
HDR block under the user's settings, quality preferences and plan validation. The device probe is
replaced by a fixture in m.playbackProbe (on a Roku it comes from roDeviceInfo)."""
import copy
import unittest

from brs import check_cases, glob

FILES = ["components/player/PlaybackCaps.brs", "components/common/Settings.brs", "components/common/Utils.brs",
         "components/common/Content.brs"]

PROBE_4K_DV = {
    "codecsVideo": ["h264", "hevc", "vp9", "av1"], "codecsAudio": ["aac", "mp3", "ac3", "eac3", "flac"],
    "passthroughAudio": ["ac3", "eac3"], "surroundAudio": ["ac3", "eac3"],
    "containers": ["mp4", "m4v", "mov", "mkv"], "maxResolution": "2160p", "decodes4K": True,
    "display": {"known": True, "hdr10": True, "hdr10Plus": False, "hlg": True, "dolbyVision": True},
    "videoMode": "2160p60", "audioChannels": 6, "videoDecode": [], "device": {"platform": "roku"},
}
PROBE_HD_SDR = copy.deepcopy(PROBE_4K_DV)
PROBE_HD_SDR.update({"codecsVideo": ["h264"], "codecsAudio": ["aac", "mp3"], "passthroughAudio": [],
                     "maxResolution": "1080p", "decodes4K": False,
                     "display": {"known": True, "hdr10": False, "hdr10Plus": False, "hlg": False, "dolbyVision": False}})


def ctx(probe=PROBE_4K_DV, items=None, prefs=None):
    return {"m": {"playbackProbe": probe}, "global": glob(items, prefs)}


def has(key, *values):
    return lambda v: all(x in v[key] for x in values)


class Declarations(unittest.TestCase):
    def test_deliveries(self):
        d = "PlaybackCaps_delivery"
        r = check_cases(self, FILES, [
            ("original declares every codec", d, [["mkv", "mp4"], []],
             lambda v: v["video_codecs"] == PROBE_4K_DV["codecsVideo"] and "eac3" in v["audio_decode_codecs"], ctx()),
            ("original claims (selected audio track, DV8 base layer)", d, [["mkv"], []],
             lambda v: sorted(v["validated_claims"]) == ["client_dv8_base_layer_fallback_v1", "client_selected_audio_track_v1"], ctx()),
            ("hls is H.264 / AAC-MP3 / SDR only (pitfall 14)", d, [["m3u8", "hls"], ["hls"], "hls"],
             lambda v: v["video_codecs"] == ["h264"] and v["audio_decode_codecs"] == ["aac", "mp3"]
             and v["audio_passthrough_codecs"] == [] and v["hdr_details"]["dolby_vision_profiles"] == []
             and v["hdr_details"]["hdr10"] is False and v["validated_claims"] == [], ctx()),
            ("progressive makes no claims", d, [["mp4"], [], "progressive"], has("validated_claims") and
             (lambda v: v["validated_claims"] == []), ctx()),
            ("never a header refresh", d, [["mkv"], []], lambda v: v["auth_header_refresh"] is False, ctx()),
            ("subtitles: text sidecars only", d, [["mkv"], []],
             lambda v: v["subtitles"]["sidecar_text"] is True and v["subtitles"]["embedded_bitmap"] is False, ctx()),
        ])
        self.assertNotIn("max_channels", r[0]["value"])

    def test_hdr(self):
        h = "PlaybackCaps_hdrDetails"
        check_cases(self, FILES, [
            ("4K DV TV: HDR10, HLG, DV 5/7/8 and 4K ceilings", h, [],
             lambda v: v["hdr10"] and v["hlg"] and not v["hdr10_plus"] and v["dolby_vision_profiles"] == [5, 7, 8]
             and v["hdr10_max_width"] == 3840 and v["hdr10_max_height"] == 2160, ctx()),
            ("profile 7 fallback drops 7", h, [], lambda v: v["dolby_vision_profiles"] == [5, 8],
             ctx(items={"player.dv_profile7_hdr10_fallback": True})),
            ("Dolby Vision off", h, [], lambda v: v["dolby_vision_profiles"] == [] and v["hdr10"],
             ctx(items={"player.dolby_vision_enabled": False})),
            ("HDR off declares nothing", h, [],
             lambda v: not (v["hdr10"] or v["hlg"] or v["hdr10_plus"]) and v["dolby_vision_profiles"] == []
             and "hdr10_max_width" not in v, ctx(items={"player.hdr_enabled": False})),
            ("SDR TV declares nothing", h, [], lambda v: not v["hdr10"] and v["dolby_vision_profiles"] == [],
             ctx(PROBE_HD_SDR)),
            ("Force HDR passthrough on an SDR 1080p box: HDR10/HLG at 1080p, never DV", h, [],
             lambda v: v["hdr10"] and v["hlg"] and v["hdr10_plus"] and v["dolby_vision_profiles"] == []
             and v["hdr10_max_width"] == 1920, ctx(PROBE_HD_SDR, prefs={"forceHdrPassthrough": True})),
        ])

    def test_quality_and_cap(self):
        q = "PlaybackCaps_videoQuality"
        check_cases(self, FILES, [
            ("original reads as auto", q, ["original"], "auto"),
            ("source reads as auto", q, [" Source "], "auto"),
            ("empty reads as auto", q, [None], "auto"),
            ("a rung is kept", q, ["1080P"], "1080p"),
            ("no cap", "PlaybackCaps_bandwidthCap", [], 0, ctx()),
            ("null cap (No limit)", "PlaybackCaps_bandwidthCap", [], 0, ctx(items={"playback.max_bitrate_kbps": None})),
            ("cap as a number", "PlaybackCaps_bandwidthCap", [], 6000, ctx(items={"playback.max_bitrate_kbps": 6000})),
            ("cap as a string", "PlaybackCaps_bandwidthCap", [], 8000, ctx(items={"playback.max_bitrate_kbps": "8000"})),
            ("tiny cap ignored", "PlaybackCaps_bandwidthCap", [], 0, ctx(items={"playback.max_bitrate_kbps": 50})),
        ])

    def test_truthy(self):
        t = "PlaybackCaps_truthy"
        check_cases(self, FILES, [(repr(v), t, [v], exp) for v, exp in [
            (True, True), (False, False), (1, True), (0, False), (2.5, True), ("true", True), (" TRUE ", True),
            ("1", True), ("yes", False), (None, False), ({}, False), ([], False)]])

    def test_plan_checks(self):
        p = "PlaybackCaps_planProblem"
        good = {"protocol_version": 3, "server_features": ["playback_plan_v3", "neutral_playback_v3_contract_v1"],
                "playback_plan": {"plan_attempt_key": "k", "stream": {"url": "http://s/x.m3u8"}}}

        def variant(**kw):
            v = copy.deepcopy(good)
            for k, val in kw.items():
                if k == "plan":
                    v["playback_plan"].update(val)
                else:
                    v[k] = val
            return v
        hls_plan = {"delivery": "server_transcode_hls", "stream": {"protocol": "hls"},
                    "selected_tracks": {"subtitle": {"id": "s3"}},
                    "subtitle": {"mode": "render", "track_id": "s3", "hls_rendition": {"group_id": "subs", "name": "English"}}}
        bad_rendition = copy.deepcopy(hls_plan)
        bad_rendition["delivery"] = "original_http"
        check_cases(self, FILES, [
            ("a good plan", p, [good], ""),
            ("no decision", p, [None], lambda v: v != ""),
            ("protocol 2", p, [variant(protocol_version=2)], lambda v: "protocol" in v),
            ("protocol as a string", p, [variant(protocol_version="3")], lambda v: v != ""),
            ("missing contract feature", p, [variant(server_features=["playback_plan_v3"])], lambda v: v != ""),
            ("no stream url", p, [variant(plan={"stream": {}})], lambda v: v != ""),
            ("header refresh needed", p, [variant(plan={"stream": {"url": "u", "header_refresh": "refresh_endpoint"}})],
             lambda v: "header refresh" in v),
            ("hls rendition accepted", "PlaybackCaps_hlsRendition", [hls_plan],
             {"group_id": "subs", "name": "English", "trackId": "s3"}),
            ("hls rendition on a direct play is refused", "PlaybackCaps_hlsRendition", [bad_rendition], {"problem": True}),
            ("no rendition", "PlaybackCaps_hlsRendition", [{"subtitle": {"mode": "off"}}], None),
        ])


if __name__ == "__main__":
    unittest.main()
