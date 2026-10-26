# SPDX-License-Identifier: AGPL-3.0-or-later
"""Subs_autoChoice: the profile's Off / Auto / Always subtitle choice resolved client-side
(a port of Silo Android's AutoSubtitleResolver). -2 = leave as is, -1 = off, else a track index."""
import unittest

from brs import check_cases, glob

FILES = ["components/player/SubtitleSuite.brs", "components/common/Settings.brs", "components/common/Utils.brs",
         "components/common/Content.brs"]


def track(lang, forced=False, sdh=False, source="embedded", codec="subrip", label="", stored=""):
    return {"language": lang, "forced": forced, "hearingImpaired": sdh, "source": source, "codec": codec,
            "rawLabel": label, "storedId": stored}


EN = track("eng")
EN_SDH = track("eng", sdh=True)
EN_FORCED = track("en", forced=True)
FR = track("fre")
FR_EXT = track("fr", source="external")
DE_FORCED = track("ger", forced=True)


def ctx(tracks, mode="auto", lang="en", forced=True, watch=None, carried=None):
    m = {"subtitleTracks": tracks, "watch": watch or {}}
    if carried is not None:
        m["carriedSubtitle"] = carried
    return {"m": m, "global": glob({"playback.subtitle_mode": mode, "playback.subtitle_language": lang,
                                     "playback.show_forced_subtitles": forced})}


class AutoChoice(unittest.TestCase):
    def test_cases(self):
        c = "Subs_autoChoice"
        check_cases(self, FILES, [
            ("no tracks: nothing to do", c, ["en"], -2, ctx([])),
            # Auto: subtitles only when the audio is not in the wanted language.
            ("auto, foreign audio: wanted language", c, ["ja"], 0, ctx([EN, FR])),
            ("auto, foreign audio: plain before SDH", c, ["ja"], 1, ctx([EN_SDH, EN])),
            ("auto, foreign audio: SDH before forced", c, ["ja"], 1, ctx([EN_FORCED, EN_SDH])),
            ("auto, audio already in the language: off", c, ["eng"], -1, ctx([FR, EN])),
            ("auto, audio in the language: its forced track", c, ["en-US"], 1, ctx([EN, EN_FORCED])),
            ("auto, audio in the language, forced off: off", c, ["en"], -1, ctx([EN, EN_FORCED], forced=False)),
            ("auto, no track in the language: a forced one", c, ["ja"], 1, ctx([FR, DE_FORCED])),
            ("auto, no track and no forced: leave", c, ["ja"], -2, ctx([FR])),
            ("auto, no language preference: leave", c, ["ja"], -2, ctx([EN, FR], lang="")),
            # Always.
            ("always, audio in the language still shows it", c, ["en"], 0, ctx([EN, FR], mode="always")),
            ("always, no language: best of any", c, ["en"], 1, ctx([FR_EXT, EN], mode="always", lang="")),
            ("always, embedded before external", c, ["ja"], 1, ctx([FR_EXT, FR], mode="always", lang="fra")),
            # Off.
            ("off: nothing", c, ["ja"], -1, ctx([EN, FR], mode="off")),
            ("off: the forced track in the audio's language", c, ["de"], 1, ctx([EN, DE_FORCED], mode="off")),
            ("off, forced disabled: nothing", c, ["de"], -1, ctx([EN, DE_FORCED], mode="off", forced=False)),
            ("off, unknown audio language: nothing", c, ["und"], -1, ctx([DE_FORCED], mode="off")),
            # The title's effective values override the profile settings.
            ("watch detail mode beats the setting", c, ["ja"], -1,
             ctx([EN], watch={"effective_subtitle_mode": "Off"})),
            ("watch detail language beats the setting", c, ["ja"], 1,
             ctx([EN, FR], watch={"effective_subtitle_language": "fr"})),
            # A remembered series pick (signature) is selected outright, even a forced one.
            ("series signature selects its track", c, ["en"], 1,
             ctx([EN, EN_FORCED], watch={"effective_subtitle_track_signature": {
                 "source": "embedded", "language": "eng", "codec": "subrip", "forced": True, "hearing_impaired": False}})),
            ("signature breaks ties within the language", c, ["ja"], 1,
             ctx([EN, EN_SDH], watch={"effective_subtitle_track_signature": {
                 "source": "external", "language": "en", "codec": "ass", "hearing_impaired": True}})),
            ("signature ignored when subtitles are off", c, ["ja"], -1,
             ctx([EN], mode="off", watch={"effective_subtitle_track_signature": {
                 "source": "embedded", "language": "en", "codec": "subrip"}})),
            ("carried pick beats the watch signature", c, ["ja"], 0,
             ctx([FR, EN], carried={"signature": {"source": "embedded", "language": "fr", "codec": "subrip"}},
                 watch={"effective_subtitle_track_signature": {"source": "embedded", "language": "en", "codec": "subrip"}})),
            # Server values with loose shapes.
            ("mode with spaces and capitals", c, ["ja"], 0, ctx([EN], mode=" Always ")),
            ("show_forced not a boolean falls back to the setting", c, ["en"], 1,
             ctx([EN, EN_FORCED], watch={"effective_show_forced_subtitles": "yes"})),
        ])

    def test_lang_key(self):
        check_cases(self, FILES, [
            ("eng", "Subs_autoLangKey", ["eng"], "en"),
            ("pt-BR", "Subs_autoLangKey", ["pt-BR"], "pt"),
            ("zh_Hant", "Subs_autoLangKey", ["zh_Hant"], "zh"),
            ("und", "Subs_autoLangKey", ["und"], ""),
            ("null", "Subs_autoLangKey", [None], ""),
            ("ger", "Subs_autoLangKey", [" GER "], "de"),
        ])


if __name__ == "__main__":
    unittest.main()
