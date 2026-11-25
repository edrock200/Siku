# SPDX-License-Identifier: AGPL-3.0-or-later
"""Track picks made in the player and what Auto plays (adapted from silo-roku 3ae62aa / #110).

StartAudio.brs: the detail page's "Auto · …" names the audio a start that names no track plays on
this Roku. The server picks the effective track, then (unless the saved series track decided)
swaps one this request would convert for a same-language main mix it plays as it is with at least
the channels the conversion keeps (silo-server PreferUnconvertedAudioTrackV3: most channels, then
Atmos, then codec rank; commentary and audio description never).

SeriesChoice.brs: a player pick bumps a counter the detail page compares when it shows again
(SeriesChoice_savedSince), and a direct-played file's Roku track list maps to the catalog by
position only when it cannot be another track (SeriesChoice_directAudioOrdinal)."""
import unittest

from brs import check_cases

FILES = ["components/common/StartAudio.brs", "components/common/SeriesChoice.brs",
         "components/common/Tracks.brs", "components/common/Utils.brs"]

ROKU = {"codecs": ["aac", "mp3", "ac3", "eac3"], "multichannelAac": False}       # no TrueHD, no DTS
STEREO = {"codecs": ["aac", "mp3"], "multichannelAac": False}                     # AAC stereo only
TRUEHD_OK = {"codecs": ["aac", "mp3", "ac3", "eac3", "truehd"], "multichannelAac": False}


def tr(codec, channels, lang="eng", title="English", **kw):
    t = {"codec": codec, "channels": channels, "language": lang, "title": title}
    t.update(kw)
    return t


THD = tr("truehd", 8, layout="7.1", profile="Dolby TrueHD + Dolby Atmos", default=True)
EAC3 = tr("eac3", 6, layout="5.1")
AC3 = tr("ac3", 6, layout="5.1")
AAC2 = tr("aac", 2)
SPA = tr("aac", 2, lang="spa", title="Español")
COMM = tr("ac3", 6, title="Commentary")


def version(tracks, effective=None):
    v = {"file_id": "43", "audio_tracks": tracks}
    if effective is not None:
        v["effective_audio_track_index"] = effective
    return v


class StartAudio(unittest.TestCase):
    def test_swap(self):
        f = "StartAudio_ordinal"
        check_cases(self, FILES, [
            ("TrueHD default swaps for the E-AC-3 5.1 beside it", f, [[THD, EAC3, SPA], 0, ROKU], 1),
            ("a device that plays TrueHD keeps it", f, [[THD, EAC3], 0, TRUEHD_OK], 0),
            ("a track that plays as it is stays", f, [[EAC3, THD], 0, ROKU], 0),
            ("another language never replaces it", f, [[THD, tr("eac3", 6, lang="spa")], 0, ROKU], 0),
            ("commentary never replaces the main mix", f, [[THD, COMM], 0, ROKU], 0),
            ("audio description never either", f, [[THD, tr("eac3", 6, title="Audio Description")], 0, ROKU], 0),
            ("more channels first: E-AC-3 5.1 over AAC 2.0", f, [[THD, AAC2, EAC3], 0, ROKU], 2),
            ("same channels: E-AC-3 outranks AC-3", f, [[THD, AC3, EAC3], 0, ROKU], 2),
            ("same channels: Atmos first", f, [[THD, EAC3, tr("eac3", 6, layout="5.1(side)", profile="Dolby Digital Plus + Dolby Atmos")], 0, ROKU], 2),
            ("a stereo track never replaces a 5.1 conversion", f, [[THD, AAC2], 0, ROKU], 0),
            ("a stereo-only Roku: the conversion keeps two, AAC 2.0 plays as is", f, [[THD, EAC3, AAC2], 0, STEREO], 2),
            ("multichannel AAC counts only where probed", f, [[THD, tr("aac", 6)], 0, ROKU], 0),
            ("multichannel AAC where probed", f, [[THD, tr("aac", 6)], 0, dict(ROKU, multichannelAac=True)], 1),
            ("eng and en are one language", f, [[THD, tr("eac3", 6, lang="en")], 0, ROKU], 1),
            ("one track: nothing to refine", f, [[THD], 0, ROKU], 0),
            ("no device facts: the effective track", f, [[THD, EAC3], 0, None], 0),
            ("channels as strings", f, [[tr("truehd", "8"), tr("eac3", "6")], 0, ROKU], 1),
            ("chosen out of range", f, [[THD, EAC3], 5, ROKU], 5),
        ])

    def test_saved(self):
        f = "StartAudio_savedChose"
        sig = {"language": "eng", "title": "English", "codec": "truehd", "layout": "7.1", "channels": 8}
        check_cases(self, FILES, [
            ("none stored: the server refines", f, [[THD, EAC3], "none", 0], False),
            ("unknown: fail closed, the effective track", f, [[THD, EAC3], "unknown", 0], True),
            ("a saved signature naming the chosen track decides", f, [[THD, EAC3], {"audio_track_index": 0, "track_signature": sig}, 0], True),
            ("a saved signature naming another track: refined", f,
             [[THD, EAC3], {"audio_track_index": 1, "track_signature": dict(sig, codec="eac3", layout="5.1", channels=6)}, 0], False),
            ("a saved index on the chosen track decides", f, [[THD, EAC3], {"audio_track_index": 0}, 0], True),
            ("a saved index elsewhere: refined", f, [[THD, EAC3], {"audio_track_index": 1}, 0], False),
        ])

    def test_readout(self):
        f = "StartAudio_readoutOrdinal"
        check_cases(self, FILES, [
            ("no saved track: Auto names E-AC-3", f, [version([THD, EAC3, SPA]), ROKU, "none"], 1),
            ("effective index decides the start point", f, [version([SPA, THD, EAC3], effective=1), ROKU, "none"], 2),
            ("the saved series track plays as saved", f, [version([THD, EAC3], effective=0), ROKU, {"audio_track_index": 0}], 0),
            ("not read yet: the effective track", f, [version([THD, EAC3]), ROKU, "unknown"], 0),
            ("no tracks", f, [version([]), ROKU, "none"], -1),
        ])

    def test_family(self):
        f = "StartAudio_family"
        check_cases(self, FILES, [
            ("E-AC-3 spellings", f, ["E-AC-3"], "eac3"),
            ("ec-3", f, ["ec-3"], "eac3"),
            ("AC-3", f, ["AC-3"], "ac3"),
            ("DTS-HD MA", f, ["dts-hd ma"], "dts"),
            ("pcm", f, ["pcm_s24le"], "pcm"),
            ("unknown", f, [None], ""),
        ])


SESSION = {"serverUrl": "http://silo.example:8097", "profileId": "p1", "accessToken": "acc"}
IDENT = "http://silo.example:8097|p1"


def mark(audio=0, subtitle=0, key="show", identity=IDENT):
    return {"identity": identity, "key": key, "audio": audio, "subtitle": subtitle}


class PlayerSaves(unittest.TestCase):
    def test_saved_since(self):
        f = "SeriesChoice_savedSince"
        check_cases(self, FILES, [
            ("nothing saved", f, [mark(), mark()], {"audio": False, "subtitle": False}),
            ("an audio pick", f, [mark(), mark(audio=1)], {"audio": True, "subtitle": False}),
            ("a subtitle pick", f, [mark(audio=2), mark(audio=2, subtitle=1)], {"audio": False, "subtitle": True}),
            ("both", f, [mark(1, 1), mark(2, 3)], {"audio": True, "subtitle": True}),
            ("another series", f, [mark(), mark(1, 1, key="other")], {"audio": False, "subtitle": False}),
            ("another profile", f, [mark(), mark(1, 1, identity="x|p2")], {"audio": False, "subtitle": False}),
            ("no mark before (first show)", f, [None, mark(1, 1)], {"audio": False, "subtitle": False}),
        ])

    def test_marks(self):
        g = {"session": dict(SESSION), "playerTrackSaves": {IDENT + "|audio|show": 2, "other|p9|audio|show": 7}}
        check_cases(self, FILES, [
            ("counts for this identity and key", "SeriesChoice_playerSaveMark", ["show"], mark(audio=2), {"global": g}),
            ("no key", "SeriesChoice_playerSaveMark", [""], None, {"global": g}),
            ("signed out", "SeriesChoice_playerSaveMark", ["show"], None, {"global": {"session": {}}}),
        ])

    def test_direct_audio(self):
        f = "SeriesChoice_directAudioOrdinal"
        cat = [tr("eac3", 6), tr("aac", 2, lang="spa")]
        check_cases(self, FILES, [
            ("same list: the position is the track", f, [cat, [{"Language": "eng"}, {"Language": "spa"}], 1], 1),
            ("Roku lists no language", f, [cat, [{"Language": ""}, {}], 1], 1),
            ("a reordered list is refused", f, [cat, [{"Language": "spa"}, {"Language": "eng"}], 1], -1),
            ("a list that dropped a track is refused", f, [cat, [{"Language": "eng"}], 0], -1),
            ("out of range", f, [cat, [{"Language": "eng"}, {"Language": "spa"}], 2], -1),
        ])


if __name__ == "__main__":
    unittest.main()
