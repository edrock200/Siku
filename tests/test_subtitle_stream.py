# SPDX-License-Identifier: AGPL-3.0-or-later
"""Subtitles drawn from the stream (Silo Android #770, adapted from Silo-Server/silo-roku):
every embedded text track as an HLS rendition (hls_subtitle_renditions_all_v1), named the way Roku
numbers renditions (the playlist's DEFAULT first), an MKV original's own tracks (mkv/<id>,
native_embedded_limitations_v1), and tracks the server cannot show at all (Silo Android #776)."""
import copy
import unittest

from brs import check_cases, glob

FILES = ["components/player/SubtitleSelect.brs", "components/player/SubtitleSuite.brs", "components/player/PlaybackCaps.brs",
         "components/common/Tracks.brs", "components/common/Settings.brs", "components/common/Utils.brs",
         "components/common/Content.brs", "components/common/Session.brs"]

URL = "http://silo.example:8097/api/v2/stream/s1/subtitles/0.vtt?file_id=52&token=acc"


def row(i, lang, label, codec="subrip", source="embedded", **extra):
    r = {"track_id": "file:52:subtitle:%d" % i, "combined_index": i, "source": source, "codec": codec, "language": lang,
         "label": label, "delivery": "sidecar", "url": "/api/v2/stream/s1/subtitles/%d.vtt?file_id=52" % i}
    r.update(extra)
    return r


def rend(name, index, group="subs"):
    return {"group_id": group, "name": name, "index": index}


INVENTORY = [row(0, "eng", "English", codec="srt", source="external"),
             row(1, "eng", "English", hls_rendition=rend("English", 1)),
             row(2, "eng", "English SDH", hls_rendition=rend("English SDH", 2)),
             row(3, "zho", "Chinese", hls_rendition=rend("Chinese", 3)),
             row(4, "ara", "Arabic", hls_rendition=rend("Arabic", 4))]
HLS_PLAN = {"delivery": "server_transcode_hls", "stream": {"protocol": "hls", "container": "hls"},
            "subtitle": {"mode": "render", "track_id": "file:52:subtitle:3", "inventory": INVENTORY,
                         "hls_rendition": {"group_id": "subs", "name": "Chinese", "index": 3}}}
HLS_OFF = copy.deepcopy(HLS_PLAN)
HLS_OFF["subtitle"] = {"mode": "off", "inventory": INVENTORY}

NATIVE_INV = [row(0, "eng", "English", codec="srt", source="external"),
              row(1, "eng", "English", container_track_id="3", native_selectable=True),
              row(2, "spa", "Español", container_track_id="4"),
              row(3, "fre", "French", container_track_id="05", native_selectable=True)]
MKV_PLAN = {"delivery": "original_http", "stream": {"protocol": "http_progressive", "container": "mkv"},
            "subtitle": {"mode": "render", "track_id": "file:52:subtitle:1", "inventory": NATIVE_INV,
                         "embedded": {"stream_index": 2, "container_track_id": "3"}}}
MP4_PLAN = copy.deepcopy(MKV_PLAN)
MP4_PLAN["stream"]["container"] = "mp4"

# Roku's listing on the TCL (2026-11-01 run P1): Chinese DEFAULT is webvtt/1, the others follow.
LISTED = [{"TrackName": "webvtt/1", "Description": "Chinese", "Language": "zh"},
          {"TrackName": "webvtt/2", "Description": "English", "Language": "en"},
          {"TrackName": "webvtt/3", "Description": "English SDH", "Language": "en"},
          {"TrackName": "webvtt/4", "Description": "Arabic", "Language": "ar"},
          {"TrackName": "/tmp/x/" + URL, "Description": "English", "Language": "eng"},
          {"TrackName": "eia608/1", "Description": "", "Language": "en"}]
NO_DESC = [{"TrackName": "webvtt/1", "Language": "zh"}, {"TrackName": "webvtt/2", "Language": "en"},
           {"TrackName": "webvtt/3", "Language": "eng"}, {"TrackName": "webvtt/4", "Language": "ara"}]
NAMES = {"Chinese": True, "English": True, "English SDH": True, "Arabic": True}


def server(*features):
    return {"m": {}, "global": dict(glob(), playbackCaps={"features": list(features), "deliveries": []})}


class RenditionNames(unittest.TestCase):
    def test_roku_place(self):
        f = "Subs_rokuPlace"
        check_cases(self, FILES, [
            ("no DEFAULT: the n-th", f, [3, 0], 3),
            ("the DEFAULT is 1", f, [4, 4], 1),
            ("before the DEFAULT moves up", f, [1, 4], 2),
            ("before the DEFAULT moves up (3rd)", f, [3, 4], 4),
            ("after the DEFAULT keeps its place", f, [5, 4], 5),
        ])

    def test_rendition_name(self):
        f = "Subs_renditionName"
        check_cases(self, FILES, [
            ("by NAME (Description)", f, [LISTED, "Arabic", 4, "ara", NAMES, False], {"name": "webvtt/4", "by": "name"}),
            ("a sidecar with the same Description never matches", f, [LISTED, "English", 2, "eng", NAMES, True],
             {"name": "webvtt/2", "by": "name"}),
            ("no Description: Roku's number in the row's language", f, [NO_DESC, "Arabic", 4, "ara", NAMES, False],
             {"name": "webvtt/4", "by": "index"}),
            ("no Description, language shared: ambiguous", f, [NO_DESC, "English SDH", 3, "eng", NAMES, True],
             {"name": "webvtt/3", "by": "ambiguous"}),
            ("the number lists another language: unlisted", f, [NO_DESC, "Arabic", 2, "ara", NAMES, False],
             {"name": "", "by": "unlisted"}),
            ("the number's Description names another rendition", f,
             [[{"TrackName": "webvtt/2", "Description": "Chinese", "Language": "ar"}], "Arabic", 2, "ara", NAMES, False],
             {"name": "", "by": "unlisted"}),
            ("nothing listed yet", f, [None, "Arabic", 4, "ara", NAMES, False], {"name": "", "by": "unlisted"}),
            ("no language: no number", f, [NO_DESC, "Arabic", 4, "und", NAMES, False], {"name": "", "by": "unlisted"}),
        ])

    def test_stream_track_names(self):
        tracks = [{"trackId": "a", "url": URL}, {"trackId": "b", "url": "", "streamName": "mkv/3"}]
        check_cases(self, FILES, [
            ("mkv/3 is not mkv/30", "Subs_isTrack", ["mkv/30", "mkv/3"], False),
            ("mkv/3 is mkv/3", "Subs_isTrack", ["mkv/3", "mkv/3"], True),
            ("webvtt/1 is not webvtt/10", "Subs_isTrack", ["webvtt/10", "webvtt/1"], False),
            ("a sidecar still matches by containment", "Subs_isTrack", ["/tmp/x/" + URL, URL], True),
            ("stream track found by its name", "Subs_trackIndexOf", [tracks, "mkv/3"], 1),
            ("stream track logged with its id", "Subs_nameForLog", [tracks, "mkv/3"], "mkv/3(b)"),
            ("drawn: the selected native track plays", "Subs_drawn", ["mkv/3", "mkv/3", "mkv/3"], True),
            ("not drawn: another native track plays", "Subs_drawn", ["mkv/3", "mkv/3", "mkv/30"], False),
            ("roku lists mkv/3", "Subs_listsName", [[{"TrackName": "mkv/3"}], "mkv/3"], True),
            ("roku lists only mkv/30", "Subs_listsName", [[{"TrackName": "mkv/30"}], "mkv/3"], False),
        ])

    def test_preselect_and_hold(self):
        native = {"trackId": "n", "url": "", "native": "mkv/4"}
        allr = {"trackId": "r", "url": "", "allRend": True, "renditionIndex": 3, "rendition": "Chinese"}
        single = {"trackId": "s", "url": "", "allRend": False, "renditionIndex": 0, "rendition": "Subtitles"}
        sidecar = {"trackId": "c", "url": URL}
        check_cases(self, FILES, [
            ("native opens on mkv/N", "Subs_preselectName", [native, 0], "mkv/4"),
            ("the plan's own rendition opens on webvtt/1", "Subs_preselectName", [allr, 3], "webvtt/1"),
            ("another rendition by Roku's number", "Subs_preselectName", [allr, 4], "webvtt/4"),
            ("no DEFAULT (plan Off): the n-th", "Subs_preselectName", [allr, 0], "webvtt/3"),
            ("a sidecar opens on nothing", "Subs_preselectName", [sidecar, 3], ""),
            ("a single plan rendition opens on the DEFAULT", "Subs_preselectName", [single, 0], ""),
            ("no pick", "Subs_preselectName", [None, 0], ""),
            ("a sidecar beside renditions holds", "Subs_holdsUntilChecked", [sidecar, "", True], True),
            ("a sidecar alone does not", "Subs_holdsUntilChecked", [sidecar, "", False], False),
            ("a preselected rendition does not", "Subs_holdsUntilChecked", [allr, "webvtt/1", True], False),
            ("a rendition without a preselect holds", "Subs_holdsUntilChecked", [allr, "", True], True),
            ("Off does not", "Subs_holdsUntilChecked", [None, "", True], False),
            ("held captions stay hidden until the check", "Subs_captionsSuppressed", [False, False, False, True], True),
            ("after the check the hold is over", "Subs_captionsSuppressed", [False, False, True, True], False),
        ])


class PlanReading(unittest.TestCase):
    def test_renditions(self):
        f = "PlaybackCaps_rowRendition"
        dup = copy.deepcopy(HLS_PLAN)
        dup["subtitle"]["inventory"][2]["hls_rendition"]["name"] = "English"
        burn = copy.deepcopy(HLS_PLAN)
        burn["subtitle"]["mode"] = "burn_in"
        direct = copy.deepcopy(HLS_PLAN)
        direct["delivery"] = "original_http"
        bad = copy.deepcopy(HLS_PLAN)
        bad["subtitle"]["inventory"][4]["hls_rendition"]["index"] = 0
        check_cases(self, FILES, [
            ("a row's rendition", f, [HLS_PLAN, INVENTORY[4]], {"group_id": "subs", "name": "Arabic", "index": 4}),
            ("a sidecar row has none", f, [HLS_PLAN, INVENTORY[0]], None),
            ("a duplicated name keeps its sidecar", f, [dup, dup["subtitle"]["inventory"][1]], None),
            ("burn-in: none", f, [burn, INVENTORY[4]], None),
            ("not HLS: none", f, [direct, INVENTORY[4]], None),
            ("index 0 is refused", f, [bad, bad["subtitle"]["inventory"][4]], None),
            ("DEFAULT is the plan's own", "PlaybackCaps_defaultRenditionIndex", [HLS_PLAN], 3),
            ("Off has no DEFAULT", "PlaybackCaps_defaultRenditionIndex", [HLS_OFF], 0),
        ])

    def test_native(self):
        check_cases(self, FILES, [
            ("canonical id", "PlaybackCaps_nativeName", ["4"], "mkv/4"),
            ("leading zero refused", "PlaybackCaps_nativeName", ["04"], ""),
            ("not a number", "PlaybackCaps_nativeName", ["4a"], ""),
            ("integer id", "PlaybackCaps_nativeName", [12], "mkv/12"),
            ("missing", "PlaybackCaps_nativeName", [None], ""),
            ("the plan's own on an MKV original", "PlaybackCaps_nativeSubtitleName", [MKV_PLAN], "mkv/3"),
            ("an MP4 original lists no text track", "PlaybackCaps_nativeSubtitleName", [MP4_PLAN], ""),
            ("an HLS plan has none", "PlaybackCaps_nativeSubtitleName", [HLS_PLAN], ""),
            ("a native_selectable row", "PlaybackCaps_nativeRowName", [MKV_PLAN, NATIVE_INV[1]], "mkv/3"),
            ("a row the server does not mark", "PlaybackCaps_nativeRowName", [MKV_PLAN, NATIVE_INV[2]], ""),
            ("a non-canonical id", "PlaybackCaps_nativeRowName", [MKV_PLAN, NATIVE_INV[3]], ""),
            ("an external row", "PlaybackCaps_nativeRowName", [MKV_PLAN, NATIVE_INV[0]], ""),
            ("not on MP4", "PlaybackCaps_nativeRowName", [MP4_PLAN, NATIVE_INV[1]], ""),
        ])

    def test_unplayable(self):
        f = "Tracks_subtitleUnplayable"
        check_cases(self, FILES, [
            ("flagged by the server", f, [row(1, "fre", "French", codec="webvtt", unplayable=True)], True),
            ("an older server: embedded with no codec", f, [row(1, "fre", "French", codec="")], True),
            ("codec missing altogether", f, [{"track_id": "t", "source": "embedded"}], True),
            ("a downloaded track without a codec still plays", f, [row(1, "fre", "French", codec="", source="downloaded")], False),
            ("an ordinary embedded track", f, [row(1, "eng", "English")], False),
            ("flag as a string", f, [row(1, "fre", "French", unplayable="true")], True),
            ("flag false", f, [row(1, "fre", "French", unplayable=False)], False),
            ("catalog: embedded without a codec", f, [{"index": 2, "language": "fre", "codec": "", "external": False}], True),
            ("catalog: no external field is embedded", f, [{"index": 2, "language": "fre"}], True),
            ("catalog: external without a codec", f, [{"index": 0, "language": "fre", "codec": "", "external": True}], False),
            ("catalog: SRT", f, [{"index": 0, "language": "eng", "codec": "srt", "external": False}], False),
            ("nothing", f, [None], False),
        ])

    def test_unplayable_never_mounted(self):
        ctx = {"m": {"timelineOffset": 0}, "global": glob()}
        check_cases(self, FILES, [
            ("a flagged sidecar row is not built", "Subs_buildTrack", [row(5, "fre", "French", codec="webvtt", unplayable=True)], None, ctx),
            ("a codec-less embedded row is not built", "Subs_buildTrack", [row(5, "fre", "French", codec="")], None, ctx),
            ("an ordinary row is", "Subs_buildTrack", [row(1, "eng", "English", url=URL)], lambda v: v["trackId"] == "file:52:subtitle:1", ctx),
        ])


class Negotiation(unittest.TestCase):
    def test_features(self):
        f = "PlaybackCaps_clientFeatures"
        check_cases(self, FILES, [
            ("an older server: neither", f, [],
             lambda v: "hls_subtitle_renditions_all_v1" not in v and "embedded_subtitles_v1" not in v, server()),
            ("every-track renditions advertised", f, [], lambda v: "hls_subtitle_renditions_all_v1" in v and "hls_subtitle_renditions_v1" in v,
             server("hls_subtitle_renditions_all_v1")),
            ("native limitations advertised", f, [], lambda v: "embedded_subtitles_v1" in v, server("native_embedded_limitations_v1")),
            ("embedded_subtitles_v1 alone is not enough", f, [], lambda v: "embedded_subtitles_v1" not in v, server("embedded_subtitles_v1")),
        ])

    def test_native_entry(self):
        f = "PlaybackCaps_subtitles"
        entry = {"container": "mkv", "codecs": ["subrip"], "track_identity": "container_track_id", "ass_styling": False,
                 "font_attachments": False, "limitations": ["forced_unlisted", "hidden_track_preemption", "literal_override_tags"]}
        check_cases(self, FILES, [
            ("original_http on a server with the limitations", f, ["original"],
             lambda v: v["native_embedded"] == [entry] and v["embedded_text"] is False, server("native_embedded_limitations_v1")),
            ("never on hls", f, ["hls"], lambda v: "native_embedded" not in v, server("native_embedded_limitations_v1")),
            ("not on an older server", f, ["original"], lambda v: "native_embedded" not in v, server()),
        ])


if __name__ == "__main__":
    unittest.main()
