# SPDX-License-Identifier: AGPL-3.0-or-later
"""Card overlays, the pure part (components/common/Overlays.brs; the card data in Content.brs):
labels, the document parser, the registry's placement with combined-badge suppression, caps, the
shared bottom row, looks and colours, and how the profile's values and the server's overlay config
settle. Cases follow Silo's OverlayRegistryTest / OverlaySchemaTest and Silo-Server/silo-roku's
tests/catalog/overlays.spec.bs (AGPL-3.0)."""
import json
import unittest

from brs import check_cases as _check_cases

FILES = ["components/common/Overlays.brs", "tests/overlays_io.brs", "components/common/Utils.brs"]
CONTENT = ["components/common/Content.brs", "components/common/Utils.brs", "components/common/Overlays.brs", "tests/overlays_io.brs"]
REF = "a" * 63 + "1.webp"
COPY = {"multiAudio": "Multi-Audio", "subtitles": "CC", "returning": "Returning", "ended": "Ended",
        "cancelled": "Cancelled", "upcoming": "Upcoming"}


def low(v):
    """Keys in lower case: dot assignment lower-cases a key in brs-cli results (skill pitfall 15)."""
    if isinstance(v, dict):
        return {k.lower(): low(x) for k, x in v.items()}
    if isinstance(v, list):
        return [low(x) for x in v]
    return v


def check_cases(test, files, cases):
    """check_cases comparing results with their keys in lower case; lambdas read lower-case keys."""
    out = []
    for c in cases:
        c = list(c)
        exp = c[3]
        if callable(exp):
            c[3] = (lambda f: (lambda v: f(low(v))))(exp)
        else:
            c[3] = (lambda e: (lambda v: low(v) == low(e)))(exp)
        out.append(tuple(c))
    return _check_cases(test, files, out)


def doc(items, preset="classic", order=None, style=None):
    d = {"version": 2, "preset": preset, "order": order or [], "items": items}
    if style is not None:
        d["style"] = style
    return d


def ids(v):
    return [e["id"] for e in v]


def badge_ids(groups):
    return {k: [b["id"] for b in v] for k, v in groups.items()}


class Labels(unittest.TestCase):
    def test_resolution_and_hdr(self):
        check_cases(self, FILES, [
            ("2160p is 4K", "Ovl_prettyResolution", ["2160p"], "4K"),
            ("uhd is 4K", "Ovl_prettyResolution", ["UHD"], "4K"),
            ("8k", "Ovl_prettyResolution", ["4320p"], "8K"),
            ("line count kept", "Ovl_prettyResolution", ["1080P"], "1080p"),
            ("other in capitals", "Ovl_prettyResolution", ["sd"], "SD"),
            ("none", "Ovl_prettyResolution", [None], ""),
            ("dv compact", "Ovl_compactHdr", ["DV HDR10"], "DV"),
            ("hdr10+ kept", "Ovl_compactHdr", ["HDR10+"], "HDR10+"),
            ("hlg is HDR", "Ovl_compactHdr", ["HLG"], "HDR"),
        ])

    def test_labels(self):
        f = "Ovl_label"
        check_cases(self, FILES, [
            ("combined res hdr", f, ["resolution_hdr", {"resolution": "2160p", "hdr": "DV"}, COPY], "4K DV"),
            ("combined res hdr needs a resolution", f, ["resolution_hdr", {"hdr": "DV"}, COPY], ""),
            ("#816 combined res hdr audio", f, ["resolution_hdr_audio", {"resolution": "2160p", "hdr": "DV", "audio": "Atmos"}, COPY], "4K DV Atmos"),
            ("#816 without a resolution keeps the audio", f, ["resolution_hdr_audio", {"audio": "TrueHD"}, COPY], "TrueHD"),
            ("imdb one decimal", f, ["rating_imdb", {"rating_imdb": 7.84}, COPY], "IMDb 7.8"),
            ("imdb as text (pitfall 6)", f, ["rating_imdb", {"rating_imdb": "8"}, COPY], "IMDb 8.0"),
            ("rt percent", f, ["rating_rt", {"rating_rt_critic": 92.6}, COPY], "RT 93%"),
            ("runtime", f, ["runtime", {"runtime": 163}, COPY], "2h 43m"),
            ("runtime minutes", f, ["runtime", {"runtime": 43}, COPY], "43m"),
            ("language", f, ["original_language", {"original_language": "fra"}, COPY], "French"),
            ("unknown language", f, ["original_language", {"original_language": "xx"}, COPY], "XX"),
            ("status normalised", f, ["show_status", {"show_status": "Returning Series"}, COPY], "Returning"),
            ("status canceled", f, ["show_status", {"show_status": "canceled"}, COPY], "Cancelled"),
            ("multi audio", f, ["multi_audio", {"multi_audio": True}, COPY], "Multi-Audio"),
            ("subtitles", f, ["multi_sub", {"multi_sub": True}, COPY], "CC"),
            ("advisory age", f, ["advisory_age", {"advisory_age": 16}, COPY], "16+"),
            ("year", f, ["year", {"year": 1995}, COPY], "1995"),
            ("plain field", f, ["release_type", {"release_type": "REMUX"}, COPY], "REMUX"),
            ("missing value", f, ["release_type", {}, COPY], ""),
        ])

    def test_icons_and_keys(self):
        check_cases(self, FILES, [
            ("dv mark", "Ovl_iconFor", [{"id": "hdr", "icon": ""}, {"hdr": "DV"}], "dolby-vision"),
            ("hdr10 wordmark", "Ovl_iconFor", [{"id": "hdr", "icon": ""}, {"hdr": "HDR10"}], "hdr10"),
            ("hlg has none", "Ovl_iconFor", [{"id": "hdr", "icon": ""}, {"hdr": "HLG"}], ""),
            ("truehd atmos takes the mark", "Ovl_iconFor", [{"id": "audio", "icon": ""}, {"audio": "TrueHD Atmos"}], "atmos"),
            ("other audio a speaker", "Ovl_iconFor", [{"id": "audio", "icon": ""}, {"audio": "EAC3"}], "volume"),
            ("av1 wordmark", "Ovl_iconFor", [{"id": "video_codec", "icon": "film"}, {"video_codec": "AV1"}], "av1"),
            ("static icon", "Ovl_iconFor", [{"id": "runtime", "icon": "clock"}, {"runtime": 90}], "clock"),
            ("value key combined", "Ovl_valueKey", ["resolution_hdr_audio", {"resolution": "4K", "hdr": "DV", "audio": "Atmos"}], "4K DV Atmos"),
            ("value key status", "Ovl_valueKey", ["show_status", {"show_status": "continuing"}], "Returning"),
            ("ratings take none", "Ovl_valueKey", ["rating_imdb", {"rating_imdb": 8}], ""),
        ])


class Document(unittest.TestCase):
    def test_parse(self):
        f = "Ovl_parse"
        check_cases(self, FILES, [
            ("nothing is the built-in document", f, [None],
             lambda v: v["preset"] == "classic" and v["items"]["resolution"]["enabled"] and not v["items"]["year"]["enabled"]),
            ("unknown preset is classic", f, [doc({}, preset="neon")], lambda v: v["preset"] == "classic"),
            ("plate and band are presets", f, [doc({}, preset="band")], lambda v: v["preset"] == "band"),
            ("json text", f, [json.dumps(doc({"year": {"enabled": True}}, preset="pill"))],
             lambda v: v["preset"] == "pill" and v["items"]["year"]["enabled"]),
            ("v1 migrates", f, [{"year": {"enabled": True, "position": "bottom-right"}}],
             lambda v: v["preset"] == "classic" and v["items"]["year"]["position"] == "bottom-right"),
            ("top-right moves to the right rail", f, [doc({"rating_imdb": {"enabled": True, "position": "top-right"}})],
             lambda v: v["items"]["rating_imdb"]["position"] == "right-edge"),
            ("bad position keeps the default", f, [doc({"year": {"position": "middle"}})],
             lambda v: v["items"]["year"]["position"] == "bottom-left"),
            ("bad accent dropped", f, [doc({"year": {"accentColor": "red"}})], lambda v: v["items"]["year"]["accent"] == ""),
            ("accent kept", f, [doc({"year": {"accentColor": "#12abEF"}})], lambda v: v["items"]["year"]["accent"] == "#12abEF"),
            ("order: known ids once", f, [doc({}, order=["year", "nope", "year", "hdr"])], lambda v: v["order"] == ["year", "hdr"]),
            ("image ref", f, [doc({"year": {"image": REF, "valueImages": {"1995": REF, "x": "bad"}}})],
             lambda v: v["items"]["year"]["image"] == REF and v["items"]["year"]["valueimages"] == {"1995": REF}),
            ("not an image ref", f, [doc({"year": {"image": "x.webp"}})], lambda v: v["items"]["year"]["image"] == ""),
            ("style fields checked", f, [doc({}, style={"size": 1.5, "shape": "blob", "background": "#000000CC", "borderWidth": 4, "uppercase": False})],
             lambda v: v["style"] == {"size": 1.5, "background": "#000000CC", "uppercase": False}),
            ("style too small dropped", f, [doc({}, style={"size": 0.5})], lambda v: v["style"] is None),
        ])

    def test_placement(self):
        f = "Ovl_placed"
        base = "Ovl_parse"
        check_cases(self, FILES, [
            ("defaults: resolution, hdr, audio, request status", "Ovl_placedOf", [None, "top-left"],
             ["resolution", "hdr", "audio", "request_status"]),
            ("#816 combined hides resolution, hdr, audio and resolution_hdr", "Ovl_placedOf",
             [doc({"resolution_hdr_audio": {"enabled": True}, "resolution_hdr": {"enabled": True}}), "top-left"],
             ["resolution_hdr_audio", "request_status"]),
            ("resolution_hdr hides resolution and hdr", "Ovl_placedOf", [doc({"resolution_hdr": {"enabled": True}}), "top-left"],
             ["resolution_hdr", "audio", "request_status"]),
            ("order first, then the registry", "Ovl_placedOf", [doc({}, order=["audio", "request_status"]), "top-left"],
             ["audio", "request_status", "resolution", "hdr"]),
            ("bottom left", "Ovl_placedOf", [doc({"year": {"enabled": True}}), "bottom-left"], ["release_type", "year"]),
        ])
        del f, base

    def test_resolve_caps(self):
        many = {k: {"enabled": True, "position": "left-edge"} for k in
                ["rating_imdb", "rating_tmdb", "rating_rt", "rating_rt_audience", "year"]}
        many.update({k: {"enabled": True, "position": "top-left"} for k in ["audio_channels", "video_codec"]})
        data = {"rating_imdb": 8.1, "rating_tmdb": 7.5, "rating_rt_critic": 90, "rating_rt_audience": 80, "year": 2001,
                "resolution": "4K", "hdr": "DV", "audio": "Atmos", "audio_channels": "7.1", "video_codec": "HEVC"}
        check_cases(self, FILES, [
            ("corner capped at 3, rail at 4", "Ovl_resolveIds", [doc(many), data],
             lambda v: v["topleft"] == ["resolution", "hdr", "audio"] and v["leftedge"] == ["rating_imdb", "rating_tmdb", "rating_rt", "rating_rt_audience"]),
            ("a badge without a value takes no place", "Ovl_resolveIds", [doc(many), {"audio_channels": "5.1"}],
             lambda v: v["topleft"] == ["audio_channels"] and v["leftedge"] == []),
        ])

    def test_band(self):
        check_cases(self, FILES, [
            ("band fits two", "Ovl_bandFit", [[40, 40, 40], 100, 4, 1], 2),
            ("band keeps one that is too wide", "Ovl_bandFit", [[300], 100, 4, 1], 1),
            ("band empty", "Ovl_bandFit", [[], 100, 4, 1], 0),
        ])


class Looks(unittest.TestCase):
    def test_looks(self):
        check_cases(self, FILES, [
            ("classic capsule", "Ovl_lookOf", ["classic", None], lambda v: v["radius"] == -1 and v["fontsize"] == 10 and not v["styled"]),
            ("band look", "Ovl_lookOf", ["band", None], lambda v: v["band"] and v["weight"] == 800),
            ("plate chips", "Ovl_lookOf", ["plate", None], lambda v: v["sourcechips"]),
            ("style size scales", "Ovl_lookOf", ["classic", {"size": 2}], lambda v: v["fontsize"] == 20 and v["padx"] == 16),
            ("solid fill drops the text shadow", "Ovl_lookOf", ["minimal", {"background": "#000000CC"}],
             lambda v: v["solid"] == "#000000CC" and v["textshadow"] is None and v["padx"] >= 9 * 0.6),
            ("square shape", "Ovl_lookOf", ["pill", {"shape": "square"}], lambda v: v["radius"] == 2),
            ("shadow off", "Ovl_lookOf", ["plate", {"shadow": False}], lambda v: v["boxshadow"] is None),
        ])

    def test_paint(self):
        f = "Ovl_paintOf"
        check_cases(self, FILES, [
            ("classic plain", f, ["classic", None, ""], {"fill": "#00000099", "ink": "#FFFFFFFF", "border": "#FFFFFF26", "accentLeft": ""}),
            ("vibrant accent", f, ["vibrant", None, "#f5c518"], lambda v: v["fill"] == "#F5C518FF" and v["ink"] == "#FFFFFFFF"),
            ("square accent stripe", f, ["square", None, "#fa320a"], lambda v: v["accentleft"] == "#FA320AFF" and v["ink"] == "#FA320AFF"),
            ("minimal accent text", f, ["minimal", None, "#01b4e4"], lambda v: v["ink"] == "#01B4E4FF" and v["fill"] == ""),
            ("style text colour", f, ["classic", {"textColor": "#ff0000"}, ""], lambda v: v["ink"] == "#FF0000FF"),
            ("border takes the text colour", f, ["vibrant", {"borderWidth": 2}, ""], lambda v: v["border"] == v["ink"]),
            ("readable text on a light solid", f, ["minimal", {"background": "#FFFFFFFF"}, ""], lambda v: v["ink"] == "#000000FF"),
        ])

    def test_colours(self):
        check_cases(self, FILES, [
            ("mix", "Ovl_mix", ["#f5c518", 0.28, "#00000099"], lambda v: v.startswith("#") and len(v) == 9),
            ("mix nothing", "Ovl_mix", ["#00000000", 0.5, "#00000000"], "#00000000"),
            ("opaque", "Ovl_opaque", ["#abcdef80"], "#ABCDEFFF"),
            ("readable on white", "Ovl_readableOn", ["#FFFFFF"], "#000000"),
            ("readable on black", "Ovl_readableOn", ["#000000"], "#FFFFFF"),
            ("contrast black white", "Ovl_contrast", ["#000000", "#FFFFFF"], lambda v: abs(v - 21) < 0.01),
            ("hex", "Ovl_hexOf", [{"r": 1, "g": 0.5, "b": 0, "a": 1}], "#FF8000FF"),
        ])


class Settling(unittest.TestCase):
    def test_profile_values(self):
        f = "Ovl_profileValues"
        mine = doc({"year": {"enabled": True}})
        check_cases(self, FILES, [
            ("profile document and choice", f, [{"ui.card_overlays": {"value": mine, "source": "profile", "scope": "profile"},
                                                "ui.card_overlays_enabled": {"value": False, "source": "profile", "scope": "profile"}}],
             {"document": mine, "enabled": False}),
            ("defaults are not the profile's", f, [{"ui.card_overlays": {"value": None, "source": "default", "scope": ""},
                                                   "ui.card_overlays_enabled": {"value": None, "source": "default", "scope": ""}}],
             {"document": None, "enabled": None}),
            ("an older server without the keys", f, [{}], {"document": None, "enabled": None}),
        ])

    def test_settle(self):
        f = "Ovl_settle"
        server = {"enabled": True, "defaults": json.dumps(doc({"year": {"enabled": True}}, preset="band")),
                  "images": [{"ref": REF, "width": 10, "height": 4}]}
        check_cases(self, FILES, [
            ("nothing: on, built-in classic", f, [None, None], lambda v: v["enabled"] and v["prefs"]["preset"] == "classic"),
            ("server default document (JSON text)", f, [None, server],
             lambda v: v["enabled"] and v["prefs"]["preset"] == "band" and v["prefs"]["items"]["year"]["enabled"]),
            ("server off", f, [None, {"enabled": False}], lambda v: not v["enabled"]),
            ("profile on beats server off", f, [{"document": None, "enabled": True}, {"enabled": False}], lambda v: v["enabled"]),
            ("profile off beats server on", f, [{"document": None, "enabled": False}, server], lambda v: not v["enabled"]),
            ("profile document wins", f, [{"document": doc({}, preset="pill"), "enabled": None}, server],
             lambda v: v["prefs"]["preset"] == "pill"),
            ("listed images kept", f, [{"document": doc({"year": {"image": REF}}), "enabled": None}, server],
             lambda v: v["prefs"]["items"]["year"]["image"] == REF and REF in v["images"]),
            ("unlisted images dropped", f, [{"document": doc({"year": {"image": REF}}), "enabled": None}, {"enabled": True}],
             lambda v: v["prefs"]["items"]["year"]["image"] == ""),
            ("used images", "Ovl_usedImages", [{"items": {"a": {"image": REF, "valueImages": {"4K": REF}}, "b": {"image": "", "valueImages": None}}}], [REF]),
            ("same documents", "Ovl_same", [doc({"year": {"enabled": True}}), doc({"year": {"enabled": True}})], True),
            ("different documents", "Ovl_same", [doc({"year": {"enabled": True}}), doc({"year": {"enabled": False}})], False),
            ("count with suppression", "Ovl_enabledCountOf", [doc({"resolution_hdr_audio": {"enabled": True}})], 3),
        ])


class CardData(unittest.TestCase):
    def test_data(self):
        f = "Content_overlayData"
        card = {"type": "movie", "overlay_summary": {"resolution": "4K", "hdr": "DV", "audio": "", "multi_audio": True, "multi_sub": None},
                "rating_imdb": 8.3, "rating_tmdb": "7.1", "year": 1995, "runtime": 170, "content_rating": "R",
                "studios": ["", " Warner "], "networks": None, "show_status": None}
        check_cases(self, CONTENT, [
            ("summary, ratings and metadata", f, [card],
             {"resolution": "4K", "hdr": "DV", "multi_audio": True, "rating_imdb": 8.3, "rating_tmdb": 7.1, "year": 1995,
              "runtime": 170, "content_rating": "R", "studio": "Warner"}),
            ("episode's best file", f, [{"type": "episode", "runtime": 48, "files": [
                {"resolution": "720p", "codec_video": "h264", "audio_channels": 2},
                {"resolution": "4k", "codec_video": "hevc", "hdr": True, "audio_channels": 6, "container": "mkv"}]}],
             {"resolution": "4k", "video_codec": "hevc", "hdr": "HDR", "audio_channels": "5.1", "container": "mkv", "runtime": 48}),
            ("last played file first", f, [{"files": [{"resolution": "4k"}], "user_data": {"last_resolution": "1080p", "last_hdr": False}}],
             {"resolution": "1080p"}),
            ("nothing", f, [{"type": "movie"}], {}),
        ])

    def test_key_and_left(self):
        check_cases(self, CONTENT, [
            ("key is stable whatever the order", "Content_overlayKeyPair", [{"a": "1", "b": 2}, {"b": 2, "a": "1"}], True),
            ("key differs with the data", "Content_overlayKeyPair", [{"a": "1"}, {"a": "2"}], False),
            ("no data no key", "Content_overlayKey", [{}], ""),
            ("started series", "Content_episodesLeft", [{"user_data": {"watched_count": 3, "unplayed_count": 5}}], 5),
            ("untouched series", "Content_episodesLeft", [{"user_data": {"watched_count": 0, "unplayed_count": 8}}], 0),
            ("finished series", "Content_episodesLeft", [{"user_data": {"played": True, "watched_count": 8, "unplayed_count": 0}}], 0),
            ("counts as text", "Content_episodesLeft", [{"user_state": {"watched_count": "2", "unplayed_count": "4"}}], 4),
        ])


if __name__ == "__main__":
    unittest.main()
