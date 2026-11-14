' SPDX-License-Identifier: AGPL-3.0-or-later
'
' Card overlays, the pure part: the badges painted on a card's artwork (4K, Dolby Vision, a rating)
' that the profile's ui.card_overlays document, or the server's default from
' GET /api/v2/settings/overlay-config, chooses. Silo's Android TV app draws them on posters,
' landscape cards and episode stills (android-shared common/overlays, shared overlays/
' OverlayRegistry.kt incl. #816's combined resolution_hdr_audio badge); this file follows the
' server's contract as the web client and Silo's own Roku app read it: every registry badge, the
' seven presets (plate and band included), style overrides, three corners and two edge rails, the
' caps, combined-badge suppression and uploaded images. Siku only reads the document.
' Adapted from Silo-Server/silo-roku, AGPL-3.0 (components/overlays/overlays.bs, commit e8244ee).
'
' Used on the render thread (ShellScreen settles the document, CardOverlayState.brs) and in
' OverlayArtTask, which draws the badges (OverlayDraw.brs); self-contained so both can include it.
' Lengths are the web's, in px at the 185 px reference poster width, times the card's overlay scale
' (Silo Android #912, CardOverlay_scaleFor in CardOverlayKeys.brs): a poster's width over 185, a
' wide card's (landscape, episode still) Poster Size multiplier 0.86 / 1 / 1.2, times the text
' factor (1 on Roku). Badge text is sized in exact pixels from it. Wide cards draw at 1 on a
' Standard card as Silo's Roku app and the web do (Android TV's TvCardOverlayScale 0.7 dp, 1.4 px,
' made a busy "rails" layout overlap on a 202 px card).

function Ovl_referenceWidth() as float
    return 185.0
end function

' A corner draws at most this many badges and a rail one more; the rest are dropped.
function Ovl_maxCorner() as integer
    return 3
end function

function Ovl_maxRail() as integer
    return 4
end function

' An uploaded image that replaces a whole badge is this many times the text badge's height.
function Ovl_valueImageScale() as float
    return 1.6
end function

function Ovl_documentKey() as string
    return "ui.card_overlays"
end function

function Ovl_enabledKey() as string
    return "ui.card_overlays_enabled"
end function

function Ovl_imagePath() as string
    return "/api/v2/overlay-images/"
end function

' ---------- Small helpers (no Utils.brs in every scope that includes this) ----------

function Ovl_isStr(v as dynamic) as boolean
    t = Type(v)
    return t = "String" or t = "roString"
end function

function Ovl_isNum(v as dynamic) as boolean
    return Instr(1, "|Integer|roInt|roInteger|LongInteger|roLongInteger|Float|roFloat|Double|roDouble|", "|" + Type(v) + "|") > 0
end function

function Ovl_isBool(v as dynamic) as boolean
    t = Type(v)
    return t = "Boolean" or t = "roBoolean"
end function

function Ovl_isTrue(v as dynamic) as boolean
    if not Ovl_isBool(v) then return false
    return v
end function

function Ovl_isObj(v as dynamic) as boolean
    return Type(v) = "roAssociativeArray"
end function

' A string as it is, a number or Boolean as text, anything else "".
function Ovl_text(v as dynamic) as string
    if Ovl_isStr(v) then return v
    if Ovl_isNum(v) or Ovl_isBool(v) then return v.ToStr()
    return ""
end function

' A server number (or a number sent as text, skill pitfall 6) as a float; invalid for none.
function Ovl_num(v as dynamic) as dynamic
    if Ovl_isNum(v) then return v * 1.0
    if Ovl_isStr(v) then
        t = v.Trim()
        if t = "" then return invalid
        c = Left(t, 1)
        if (c >= "0" and c <= "9") or c = "-" or c = "." then return Val(t)
    end if
    return invalid
end function

' Whether list holds value, comparing strings with strings only.
function Ovl_has(list as object, value as dynamic) as boolean
    if not Ovl_isStr(value) then return false
    for each item in list
        if Ovl_isStr(item) and item = value then return true
    end for
    return false
end function

function Ovl_isNone(v as dynamic) as boolean
    t = Type(v)
    return t = "Invalid" or t = "roInvalid" or t = "<uninitialized>"
end function

' ---------- The registry ----------

' Every badge in the web registry's order, the default order within a position:
' { id, position, enabled, icon, iconCapable, accent, sourceMark }. Built once per thread.
function Ovl_registry() as object
    if m.ovlRegistry <> invalid then return m.ovlRegistry
    defs = []
    ' tech
    defs.Push(Ovl_entry("resolution", "top-left", true, "monitor", true))
    defs.Push(Ovl_entry("hdr", "top-left", true, "", true))
    defs.Push(Ovl_entry("resolution_hdr", "top-left", false, "", true))
    defs.Push(Ovl_entry("resolution_hdr_audio", "top-left", false, "", true))
    defs.Push(Ovl_entry("audio", "top-left", true, "", true))
    defs.Push(Ovl_entry("audio_channels", "top-left", false, "volume", true))
    defs.Push(Ovl_entry("video_codec", "top-left", false, "film", true))
    defs.Push(Ovl_entry("container", "bottom-left", false, "", false))
    defs.Push(Ovl_entry("aspect_ratio", "bottom-right", false, "layout", true))
    defs.Push(Ovl_entry("release_type", "bottom-left", true, "", false))
    defs.Push(Ovl_entry("edition", "bottom-left", false, "", false))
    defs.Push(Ovl_entry("multi_audio", "bottom-right", false, "languages", true))
    defs.Push(Ovl_entry("multi_sub", "bottom-right", false, "subtitles", true))
    ' ratings
    defs.Push(Ovl_rating("rating_imdb", "#f5c518", "IMDb"))
    defs.Push(Ovl_rating("rating_tmdb", "#01b4e4", "TMDB"))
    defs.Push(Ovl_rating("rating_rt", "#fa320a", "RT"))
    defs.Push(Ovl_rating("rating_rt_audience", "#fa6400", "RT Audience"))
    defs.Push(Ovl_entry("content_rating", "bottom-right", false, "shield", true))
    defs.Push(Ovl_entry("advisory_age", "bottom-right", false, "users", true))
    ' metadata
    defs.Push(Ovl_entry("year", "bottom-left", false, "", false))
    defs.Push(Ovl_entry("runtime", "bottom-left", false, "clock", true))
    defs.Push(Ovl_entry("original_language", "bottom-left", false, "globe", true))
    defs.Push(Ovl_entry("studio", "bottom-right", false, "building", true))
    defs.Push(Ovl_entry("network", "bottom-right", false, "tv", true))
    ' ribbons
    defs.Push(Ovl_entry("show_status", "right-edge", false, "tv", true))
    defs.Push(Ovl_entry("request_status", "top-left", true, "", true))
    m.ovlRegistry = defs
    return defs
end function

function Ovl_entry(id as string, position as string, enabled as boolean, icon as string, iconCapable as boolean) as object
    return { id: id, position: position, enabled: enabled, icon: icon, iconCapable: iconCapable, accent: "", sourceMark: "" }
end function

function Ovl_rating(id as string, accent as string, mark as string) as object
    e = Ovl_entry(id, "left-edge", false, "", false)
    e.accent = accent
    e.sourceMark = mark
    return e
end function

function Ovl_positions() as object
    return ["top-left", "bottom-left", "bottom-right", "left-edge", "right-edge"]
end function

function Ovl_isKnownId(v as dynamic) as boolean
    if not Ovl_isStr(v) then return false
    for each e in Ovl_registry()
        if e.id = v then return true
    end for
    return false
end function

' ---------- What a badge shows ----------

' The words the labels use, in the interface language ("CC" stays as it is).
function Ovl_words() as object
    return { multiAudio: Tx("Multi-Audio"), subtitles: "CC", returning: Tx("Returning"), ended: Tx("Ended"), cancelled: Tx("Cancelled"), upcoming: Tx("Upcoming") }
end function

' The badge's label for data, or "" when the card has no value for it.
function Ovl_label(id as string, data as object, copy as object) as string
    if id = "resolution" then return Ovl_prettyResolution(data.resolution)
    if id = "resolution_hdr" then
        res = Ovl_prettyResolution(data.resolution)
        if res = "" then return ""
        return Ovl_joined([res, Ovl_compactHdr(data.hdr)])
    end if
    if id = "resolution_hdr_audio" then return Ovl_joined([Ovl_prettyResolution(data.resolution), Ovl_compactHdr(data.hdr), Ovl_text(data.audio)])
    if id = "multi_audio" then
        if Ovl_isTrue(data.multi_audio) then return copy.multiAudio
        return ""
    end if
    if id = "multi_sub" then
        if Ovl_isTrue(data.multi_sub) then return copy.subtitles
        return ""
    end if
    if id = "rating_imdb" then return Ovl_ratingLabel("IMDb", Ovl_outOfTen(data.rating_imdb))
    if id = "rating_tmdb" then return Ovl_ratingLabel("TMDB", Ovl_outOfTen(data.rating_tmdb))
    if id = "rating_rt" then return Ovl_ratingLabel("RT", Ovl_percent(data.rating_rt_critic))
    if id = "rating_rt_audience" then return Ovl_ratingLabel("RT Audience", Ovl_percent(data.rating_rt_audience))
    if id = "advisory_age" then
        n = Ovl_num(data.advisory_age)
        if n <> invalid and n > 0 then return Int(n).ToStr() + "+"
        return ""
    end if
    if id = "year" then
        n = Ovl_num(data.year)
        if n <> invalid and n > 0 then return Int(n).ToStr()
        return ""
    end if
    if id = "runtime" then return Ovl_runtimeText(data.runtime)
    if id = "original_language" then return Ovl_languageText(data.original_language)
    if id = "show_status" then return Ovl_showStatusText(data.show_status, copy)
    return Ovl_text(data[id])
end function

' The score a rating badge shows without its mark ("7.8", "93%"), "" otherwise.
function Ovl_score(id as string, data as object) as string
    if id = "rating_imdb" then return Ovl_outOfTen(data.rating_imdb)
    if id = "rating_tmdb" then return Ovl_outOfTen(data.rating_tmdb)
    if id = "rating_rt" then return Ovl_percent(data.rating_rt_critic)
    if id = "rating_rt_audience" then return Ovl_percent(data.rating_rt_audience)
    return ""
end function

' The key a valueImages entry matches: the value as the API sends it, "" for a badge that takes none.
function Ovl_valueKey(id as string, data as object) as string
    if id = "resolution_hdr" then
        if Ovl_text(data.resolution) = "" then return ""
        return Ovl_joined([Ovl_text(data.resolution), Ovl_text(data.hdr)])
    end if
    if id = "resolution_hdr_audio" then return Ovl_joined([Ovl_text(data.resolution), Ovl_text(data.hdr), Ovl_text(data.audio)])
    if id = "show_status" then return Ovl_showStatusKey(data.show_status)
    if Ovl_has(["resolution", "hdr", "audio", "audio_channels", "video_codec", "container", "aspect_ratio", "release_type", "edition", "content_rating", "original_language", "studio", "network"], id) then return Ovl_text(data[id])
    return ""
end function

' The icon a badge draws for data (its value's own, else its static one), "" for none. hdr10, hdr,
' atmos and av1 are wordmarks: their text is the mark (Ovl_wordmark).
function Ovl_iconFor(e as object, data as object) as string
    id = e.id
    if id = "hdr" then
        hdr = Ovl_text(data.hdr)
        if Instr(1, hdr, "DV") > 0 then return "dolby-vision"
        if hdr = "HDR10" then return "hdr10"
        if hdr = "HDR" then return "hdr"
        return ""
    end if
    if id = "resolution_hdr" or id = "resolution_hdr_audio" then
        if Instr(1, Ovl_text(data.hdr), "DV") > 0 then return "dolby-vision"
        return ""
    end if
    if id = "audio" then
        audio = Ovl_text(data.audio)
        if audio = "" then return ""
        ' "TrueHD Atmos" still takes the mark (OverlayRegistry.audioIcon).
        if Instr(1, LCase(audio), "atmos") > 0 then return "atmos"
        return "volume"
    end if
    if id = "video_codec" then
        codec = Ovl_text(data.video_codec)
        if codec = "" then return ""
        if codec = "AV1" then return "av1"
        return "film"
    end if
    if id = "request_status" then return Ovl_text(data.request_status_icon)
    return e.icon
end function

' A wordmark icon's text: drawn as bold text, and a label that says the same is left out.
function Ovl_wordmark(icon as string) as string
    if icon = "hdr" then return "HDR"
    if icon = "hdr10" then return "HDR10"
    if icon = "atmos" then return "ATMOS"
    if icon = "av1" then return "AV1"
    return ""
end function

' "4K" / "8K" for UHD, "1080p" for a line count, else the value in capitals.
function Ovl_prettyResolution(value as dynamic) as string
    t = Ovl_text(value).Trim()
    lo = LCase(t)
    if lo = "" then return ""
    if lo = "2160p" or lo = "4k" or lo = "uhd" then return "4K"
    if lo = "4320p" or lo = "8k" then return "8K"
    if Len(lo) > 1 and Right(lo, 1) = "p" and Ovl_isDigits(Left(lo, Len(lo) - 1)) then return lo
    return UCase(t)
end function

function Ovl_isDigits(t as string) as boolean
    if t = "" then return false
    for i = 1 to Len(t)
        c = Mid(t, i, 1)
        if c < "0" or c > "9" then return false
    end for
    return true
end function

' The dynamic range in a combined badge: any Dolby Vision is "DV", HDR10+ keeps its name,
' anything else "HDR".
function Ovl_compactHdr(value as dynamic) as string
    hdr = Ovl_text(value)
    if hdr = "" then return ""
    if Instr(1, hdr, "DV") > 0 then return "DV"
    if Instr(1, hdr, "HDR10+") > 0 then return "HDR10+"
    return "HDR"
end function

function Ovl_ratingLabel(mark as string, value as string) as string
    if value = "" then return ""
    return mark + " " + value
end function

' A score out of 10 to one decimal ("7.8"), "" for none.
function Ovl_outOfTen(value as dynamic) as string
    n = Ovl_num(value)
    if n = invalid then return ""
    tenths = Int(n * 10 + 0.5)
    sign = ""
    if tenths < 0 then
        sign = "-"
        tenths = -tenths
    end if
    return sign + (tenths \ 10).ToStr() + "." + (tenths mod 10).ToStr()
end function

' A score out of 100 as a percentage ("93%"), "" for none.
function Ovl_percent(value as dynamic) as string
    n = Ovl_num(value)
    if n = invalid then return ""
    return Int(n + 0.5).ToStr() + "%"
end function

' "2h 43m", "43m", or "" for none.
function Ovl_runtimeText(minutes as dynamic) as string
    n = Ovl_num(minutes)
    if n = invalid or n <= 0 then return ""
    whole = Int(n)
    h = whole \ 60
    rest = whole mod 60
    if h > 0 then return TxF("{0}h {1}m", [h, rest])
    return TxF("{0}m", [rest])
end function

' The language's English name ("English"), the code in capitals when unknown, "" for none.
function Ovl_languageText(value as dynamic) as string
    raw = Ovl_text(value).Trim()
    code = LCase(raw).Replace("_", "-")
    dash = Instr(1, code, "-")
    if dash > 0 then code = Left(code, dash - 1)
    if code = "" or code = "und" then return ""
    folded = { ara: "ar", bul: "bg", chi: "zh", zho: "zh", ces: "cs", cze: "cs", dan: "da", deu: "de", ger: "de", ell: "el", gre: "el", eng: "en", spa: "es", fin: "fi", fra: "fr", fre: "fr", heb: "he", hin: "hi", hrv: "hr", hun: "hu", ind: "id", ita: "it", jpn: "ja", kor: "ko", msa: "ms", may: "ms", nld: "nl", dut: "nl", nor: "no", nob: "no", fas: "fa", per: "fa", pol: "pl", por: "pt", ron: "ro", rum: "ro", rus: "ru", slk: "sk", slo: "sk", slv: "sl", swe: "sv", tam: "ta", tel: "te", tha: "th", tur: "tr", ukr: "uk", vie: "vi" }
    if folded[code] <> invalid then code = folded[code]
    names = {
        ar: Tx("Arabic"), bg: Tx("Bulgarian"), bn: Tx("Bengali"), cs: Tx("Czech"), da: Tx("Danish"), de: Tx("German"), el: Tx("Greek"), en: Tx("English")
        es: Tx("Spanish"), fa: Tx("Persian"), fi: Tx("Finnish"), fr: Tx("French"), he: Tx("Hebrew"), hi: Tx("Hindi"), hr: Tx("Croatian"), hu: Tx("Hungarian")
        id: Tx("Indonesian"), it: Tx("Italian"), ja: Tx("Japanese"), ko: Tx("Korean"), ms: Tx("Malay"), nl: Tx("Dutch"), no: Tx("Norwegian"), pl: Tx("Polish")
        pt: Tx("Portuguese"), ro: Tx("Romanian"), ru: Tx("Russian"), sk: Tx("Slovak"), sl: Tx("Slovenian"), sv: Tx("Swedish"), ta: Tx("Tamil"), te: Tx("Telugu")
        th: Tx("Thai"), tr: Tx("Turkish"), uk: Tx("Ukrainian"), vi: Tx("Vietnamese"), zh: Tx("Chinese")
    }
    if names[code] <> invalid then return names[code]
    return UCase(raw)
end function

' The status the contract's value keys use: Returning, Ended, Cancelled or Upcoming, else the value
' as sent, "" for none.
function Ovl_showStatusKey(value as dynamic) as string
    ' Matched as sent, untrimmed, as the web and Silo Android #882 do.
    status = Ovl_text(value)
    lo = LCase(status)
    if lo = "" then return ""
    if Ovl_has(["returning", "returning series", "continuing", "in_production", "in production"], lo) then return "Returning"
    if lo = "ended" then return "Ended"
    if lo = "cancelled" or lo = "canceled" then return "Cancelled"
    if lo = "upcoming" or lo = "planned" then return "Upcoming"
    return status
end function

function Ovl_showStatusText(value as dynamic, copy as object) as string
    status = Ovl_showStatusKey(value)
    if status = "Returning" then return copy.returning
    if status = "Ended" then return copy.ended
    if status = "Cancelled" then return copy.cancelled
    if status = "Upcoming" then return copy.upcoming
    return status
end function

function Ovl_joined(parts as object) as string
    out = ""
    for each p in parts
        if p <> "" then
            if out <> "" then out = out + " "
            out = out + p
        end if
    end for
    return out
end function

' ---------- The document ----------

' The built-in document: the classic look and each badge's defaults.
function Ovl_defaults() as object
    return { preset: "classic", style: invalid, order: [], items: Ovl_items(invalid) }
end function

function Ovl_presetIds() as object
    return ["minimal", "classic", "vibrant", "pill", "square", "plate", "band"]
end function

' A complete document from the stored value (an object, JSON text, or invalid), as the web's
' parseOverlayPrefs reads it: a v1 document (badges by id) migrates, an unknown preset is classic,
' a stored top-right badge moves to the right-edge rail, an invalid field is dropped.
' { preset, style (Ovl_parseStyle, or invalid), order (ids), items: { <id>: { enabled, position,
' accent ("" for the badge's own), showIcon (invalid: the preset's), image ("" for none),
' valueImages ({ <key>: ref } or invalid) } } }.
function Ovl_parse(raw as dynamic) as object
    parsed = raw
    if Ovl_isStr(raw) then
        if raw = "" then return Ovl_defaults()
        parsed = ParseJson(raw)
    end if
    if not Ovl_isObj(parsed) then return Ovl_defaults()
    v2 = false
    n = Ovl_num(parsed.version)
    if Ovl_isNum(parsed.version) and n = 2 then v2 = true
    if Ovl_isStr(parsed.preset) and Ovl_isObj(parsed.items) then v2 = true
    if not v2 then return { preset: "classic", style: invalid, order: [], items: Ovl_items(parsed) }
    preset = "classic"
    if Ovl_has(Ovl_presetIds(), parsed.preset) then preset = parsed.preset
    order = []
    if Type(parsed.order) = "roArray" then
        for each id in parsed.order
            if Ovl_isKnownId(id) and not Ovl_has(order, id) then order.Push(id)
        end for
    end if
    src = invalid
    if Ovl_isObj(parsed.items) then src = parsed.items
    return { preset: preset, style: Ovl_parseStyle(parsed.style), order: order, items: Ovl_items(src) }
end function

function Ovl_items(src as dynamic) as object
    out = {}
    for each e in Ovl_registry()
        base = { enabled: e.enabled, position: e.position, accent: "", showIcon: invalid, image: "", valueImages: invalid }
        patch = invalid
        if Ovl_isObj(src) then patch = src[e.id]
        if Ovl_isObj(patch) then
            if Ovl_isBool(patch.enabled) then base.enabled = patch.enabled
            position = patch.position
            if Ovl_isStr(position) and position = "top-right" then position = "right-edge"
            if Ovl_has(Ovl_positions(), position) then base.position = position
            if Ovl_isHex(patch.accentColor, 6) then base.accent = patch.accentColor
            if Ovl_isBool(patch.showIcon) then base.showIcon = patch.showIcon
            if Ovl_isImageRef(patch.image) then base.image = patch.image
            base.valueImages = Ovl_parseValueImages(patch.valueImages)
        end if
        out[e.id] = base
    end for
    return out
end function

function Ovl_parseValueImages(v as dynamic) as dynamic
    if not Ovl_isObj(v) then return invalid
    out = {}
    out.SetModeCaseSensitive()
    count = 0
    for each k in v
        if count >= 32 then exit for
        if Len(k) > 0 and Len(k) <= 64 and Ovl_isImageRef(v[k]) then
            out[k] = v[k]
            count = count + 1
        end if
    end for
    if count = 0 then return invalid
    return out
end function

' The style overrides the contract accepts, each invalid field dropped; invalid for none.
function Ovl_parseStyle(v as dynamic) as dynamic
    if not Ovl_isObj(v) then return invalid
    st = {}
    if Ovl_isNum(v.size) then
        if v.size >= 0.75 and v.size <= 2 then st.size = v.size * 1.0
    end if
    if Ovl_has(["pill", "rounded", "square"], v.shape) then st.shape = v.shape
    if Ovl_isHex(v.background, 8) then st.background = v.background
    if Ovl_isHex(v.textColor, 6) then st.textColor = v.textColor
    if Ovl_isHex(v.borderColor, 8) then st.borderColor = v.borderColor
    if Ovl_isNum(v.borderWidth) then
        if v.borderWidth = Int(v.borderWidth) and v.borderWidth >= 0 and v.borderWidth <= 3 then st.borderWidth = Int(v.borderWidth)
    end if
    if Ovl_has(["regular", "semibold", "extrabold"], v.fontWeight) then st.fontWeight = v.fontWeight
    if Ovl_isBool(v.uppercase) then st.uppercase = v.uppercase
    if Ovl_isBool(v.shadow) then st.shadow = v.shadow
    if st.Count() = 0 then return invalid
    return st
end function

' "#" and digits hex digits.
function Ovl_isHex(v as dynamic, digits as integer) as boolean
    if not Ovl_isStr(v) then return false
    if Len(v) <> digits + 1 or Left(v, 1) <> "#" then return false
    for i = 2 to Len(v)
        if Instr(1, "0123456789abcdefABCDEF", Mid(v, i, 1)) = 0 then return false
    end for
    return true
end function

' An uploaded image's reference: 64 lowercase hex digits and ".webp".
function Ovl_isImageRef(v as dynamic) as boolean
    if not Ovl_isStr(v) then return false
    if Len(v) <> 69 or Right(v, 5) <> ".webp" then return false
    for i = 1 to 64
        if Instr(1, "0123456789abcdef", Mid(v, i, 1)) = 0 then return false
    end for
    return true
end function

' Whether a and b hold the same values (settled documents and image lists), compared without
' serializing them.
function Ovl_same(a as dynamic, b as dynamic) as boolean
    if Type(a) = "roAssociativeArray" then
        if Type(b) <> "roAssociativeArray" then return false
        if a.Count() <> b.Count() then return false
        for each k in a
            if not b.DoesExist(k) then return false
            if not Ovl_same(a[k], b[k]) then return false
        end for
        return true
    end if
    if Type(a) = "roArray" then
        if Type(b) <> "roArray" then return false
        if a.Count() <> b.Count() then return false
        for i = 0 to a.Count() - 1
            if not Ovl_same(a[i], b[i]) then return false
        end for
        return true
    end if
    if Ovl_isNone(a) then return Ovl_isNone(b)
    if Ovl_isStr(a) then return Ovl_isStr(b) and a = b
    if Ovl_isNum(a) then return Ovl_isNum(b) and a = b
    if Ovl_isBool(a) then return Ovl_isBool(b) and a = b
    return false
end function

' The document without image references the server no longer lists (listed: { <ref>: {...} }), so
' a deleted image costs no request.
function Ovl_withoutUnlisted(prefs as object, listed as object) as object
    for each id in prefs.items
        it = prefs.items[id]
        if it.image <> "" and not listed.DoesExist(it.image) then it.image = ""
        if it.valueImages <> invalid then
            kept = {}
            kept.SetModeCaseSensitive()
            for each k in it.valueImages
                if listed.DoesExist(it.valueImages[k]) then kept[k] = it.valueImages[k]
            end for
            it.valueImages = invalid
            if kept.Count() > 0 then it.valueImages = kept
        end if
    end for
    return prefs
end function

' The badges a combined badge already shows (OverlayRegistry.combinedBadges): hidden while it is on.
function Ovl_suppressed(prefs as object) as object
    hidden = {}
    if Ovl_isOn(prefs, "resolution_hdr_audio") then
        for each id in ["resolution", "hdr", "audio", "resolution_hdr"]
            hidden[id] = true
        end for
    end if
    if Ovl_isOn(prefs, "resolution_hdr") then
        hidden.resolution = true
        hidden.hdr = true
    end if
    return hidden
end function

' The enabled badges at a position, combined badges hiding the badges they already show, in the
' document's order and then the registry's.
function Ovl_placed(prefs as object, position as string) as object
    hidden = Ovl_suppressed(prefs)
    out = []
    for each e in Ovl_registry()
        it = prefs.items[e.id]
        if it <> invalid then
            if it.enabled and it.position = position and not hidden.DoesExist(e.id) then out.Push(e)
        end if
    end for
    if prefs.order.Count() = 0 then return out
    ranked = []
    for each e in out
        rank = 999
        for i = 0 to prefs.order.Count() - 1
            if prefs.order[i] = e.id then
                rank = i
                exit for
            end if
        end for
        ' Equal ranks keep the registry's order: SortBy is not stable.
        ranked.Push({ k: rank * 1000 + ranked.Count(), e: e })
    end for
    ranked.SortBy("k")
    sorted = []
    for each w in ranked
        sorted.Push(w.e)
    end for
    return sorted
end function

function Ovl_isOn(prefs as object, id as string) as boolean
    it = prefs.items[id]
    if it = invalid then return false
    return it.enabled = true
end function

' ---------- Resolving a card's badges ----------

' A badge for data under the document and look, or invalid when the card has no value for it:
' { id, label, accent, icon, image, valueImage, valueKey, sourceMark, score } finished by Ovl_finish.
function Ovl_badge(e as object, data as object, look as object, cfg as dynamic, copy as object) as dynamic
    labelText = Ovl_label(e.id, data, copy)
    if labelText = "" then return invalid
    icon = Ovl_iconFor(e, data)
    showIcon = look.preferIcon
    if cfg <> invalid then
        if Ovl_isBool(cfg.showIcon) then showIcon = cfg.showIcon
    end if
    if not (e.iconCapable and icon <> "" and showIcon) then icon = ""
    accent = e.accent
    if e.id = "request_status" and Ovl_isTrue(data.request_status_attention) then accent = "#f59e0b"
    image = ""
    valueImage = ""
    k = Ovl_valueKey(e.id, data)
    if cfg <> invalid then
        if cfg.accent <> "" then accent = cfg.accent
        image = cfg.image
        if k <> "" and cfg.valueImages <> invalid then
            if cfg.valueImages.DoesExist(k) then valueImage = cfg.valueImages[k]
        end if
    end if
    points = Ovl_score(e.id, data)
    mark = ""
    if e.sourceMark <> "" and points <> "" then mark = e.sourceMark
    b = { id: e.id, label: labelText, accent: accent, icon: icon, image: image, valueImage: valueImage, valueKey: k, sourceMark: mark, score: points }
    return Ovl_finish(b, look, false)
end function

' What a badge draws without (image false) or with its uploaded icon image: chip (a rating's mark
' on an accent chip, the plate look's), txt (the label, only the score beside an image or chip,
' "" when a wordmark says it), scoreOnly (a bare score never truncates), markText (the wordmark).
function Ovl_finish(b as object, look as object, image as boolean) as object
    b.chip = ""
    if not image and look.sourceChips and b.sourceMark <> "" then b.chip = b.sourceMark
    b.scoreOnly = (image or b.chip <> "") and b.score <> ""
    b.markText = ""
    if not image then b.markText = Ovl_wordmark(b.icon)
    if b.scoreOnly then
        b.txt = b.score
    else if b.markText <> "" and LCase(b.markText) = LCase(b.label.Trim()) then
        b.txt = ""
    else
        b.txt = b.label
    end if
    if look.uppercase then
        b.txt = UCase(b.txt)
        b.chip = UCase(b.chip)
    end if
    return b
end function

' The card's badges at each position, capped: { topLeft, bottomLeft, bottomRight, leftEdge, rightEdge }.
function Ovl_resolve(prefs as object, data as object, look as object, copy as object) as object
    out = {}
    groups = [["topLeft", "top-left", Ovl_maxCorner()], ["bottomLeft", "bottom-left", Ovl_maxCorner()], ["bottomRight", "bottom-right", Ovl_maxCorner()], ["leftEdge", "left-edge", Ovl_maxRail()], ["rightEdge", "right-edge", Ovl_maxRail()]]
    for each g in groups
        list = []
        for each e in Ovl_placed(prefs, g[1])
            if list.Count() >= g[2] then exit for
            b = Ovl_badge(e, data, look, prefs.items[e.id], copy)
            if b <> invalid then list.Push(b)
        end for
        out[g[0]] = list
    end for
    return out
end function

' Where the two bottom corners' badges go (Silo Android #882 OverlayLayoutMath.bottomRows, the web's
' BottomRows): one row per level counted from the bottom, so the shorter corner lines up with the
' bottom and a badge shares its width only with the badge at the same height in the other corner.
' A pair that fits (left + gap + right <= available) shares its line, both aligned to its bottom; a
' pair that does not wraps, the left badge on a line above the right one, which stays at the end.
' lw/lh and rw/rh are each corner's badge widths and heights, top to bottom, measured against
' available. Gives { lx, ly, rx, ry, h }: each badge's offset from the block's top-left, and the
' block's height.
function Ovl_bottomLayout(lw as object, lh as object, rw as object, rh as object, available as float, gap as float, stackGap as float) as object
    lc = lw.Count()
    rc = rw.Count()
    out = { lx: [], ly: [], rx: [], ry: [], h: 0.0 }
    for i = 0 to lc - 1
        out.lx.Push(0.0)
        out.ly.Push(0.0)
    end for
    for i = 0 to rc - 1
        out.rx.Push(0.0)
        out.ry.Push(0.0)
    end for
    levels = lc
    if rc > levels then levels = rc
    y = 0.0
    for level = 0 to levels - 1
        if level > 0 then y = y + stackGap
        l = lc - levels + level
        r = rc - levels + level
        if l >= 0 and r >= 0 and not Ovl_fitsOneLine(lw[l], rw[r], available, gap) then
            out.lx[l] = 0.0
            out.ly[l] = y
            y = y + lh[l] + stackGap
            out.rx[r] = available - rw[r]
            out.ry[r] = y
            y = y + rh[r]
        else
            lineHeight = 0.0
            if l >= 0 then lineHeight = lh[l]
            if r >= 0 and rh[r] > lineHeight then lineHeight = rh[r]
            if l >= 0 then
                out.lx[l] = 0.0
                out.ly[l] = y + lineHeight - lh[l]
            end if
            if r >= 0 then
                out.rx[r] = available - rw[r]
                out.ry[r] = y + lineHeight - rh[r]
            end if
            y = y + lineHeight
        end if
    end for
    out.h = y
    return out
end function

' Whether a left and a right bottom badge share one row.
function Ovl_fitsOneLine(leftWidth as float, rightWidth as float, available as float, gap as float) as boolean
    return leftWidth + gap + rightWidth <= available + 0.01
end function

' How far a card's bottom badges sit from its bottom edge, in px, for shape at scale k (Silo Android
' #882 overlayInsets): a poster the edge inset (8), a landscape card 24 (Android TV's Wide variant)
' and an episode still 12 (its side inset). Over a progress bar (Silo Android #902) a poster or
' landscape row lifts one edge step more (8) and an episode still's row goes to the bar's
' clearance; either way it ends at least `clearance` px up (WatchProgress_metrics: the bar's
' inset, height and a gap), because the bar keeps its size on small cards. A wide card's inset never
' drops below its size at scale 1 (Silo Android #912), so Compact cards' badges still clear the title
' or bar along their bottom.
function Ovl_bottomInset(shape as string, k as float, progress as boolean, clearance as float) as float
    if (shape = "landscape" or shape = "episode") and k < 1 then k = 1.0
    edge = 8 * k
    base = edge
    if shape = "landscape" then base = 24 * k
    if shape = "episode" then base = 12 * k
    if not progress then return base
    lifted = base + edge
    if shape = "episode" then lifted = base
    if lifted < clearance then lifted = clearance
    return lifted
end function

' How far the top badge row stops short of the right edge (Silo Android #882: EDGE_INSET +
' WATCH_STATUS_RESERVE on posters): the watch-status corner's inset and size and an edge gap (8 at
' scale k), or just the edge inset on a card that draws no status (checkSize 0).
function Ovl_topRowEnd(checkInset as float, checkSize as float, k as float) as float
    if checkSize <= 0 then return 8 * k
    return checkInset + checkSize + 8 * k
end function

' How many of a band's marks (widths in px, in order) fit whole in width with gap around a divider
' (dividerWidth) before each after the first: at least one, which may then truncate.
function Ovl_bandFit(widths as object, width as float, gap as float, dividerWidth as float) as integer
    if widths.Count() = 0 then return 0
    used = widths[0]
    count = 1
    for i = 1 to widths.Count() - 1
        used = used + 2 * gap + dividerWidth + widths[i]
        if used > width + 0.5 then exit for
        count = count + 1
    end for
    return count
end function

' ---------- Looks ----------

' A preset's look (web presets.ts) with the style's overrides (style.ts), at the reference width:
' { id, band, sourceChips, weight, uppercase, tracking (letter spacing, a share of the font size:
' Tailwind tracking-wide 0.025, minimal's and square's tracking-widest 0.1), fontSize, padX, padY, radius (-1 a capsule),
' borderWidth, accentLeft, textShadow, boxShadow, iconSize, iconGap, preferIcon, stackGap,
' strategy ("bg" | "border" | "text"), fill, textColor, borderColor, solid, styled }.
function Ovl_lookOf(preset as string, st as dynamic) as object
    out = Ovl_presetLook(preset)
    out.fill = ""
    out.textColor = ""
    out.borderColor = ""
    out.solid = ""
    out.styled = false
    if not Ovl_isObj(st) then return out
    sc = 1.0
    if Ovl_isNum(st.size) then sc = st.size
    for each k in ["fontSize", "padX", "padY", "iconSize", "iconGap", "stackGap"]
        out[k] = out[k] * sc
    end for
    weight = Ovl_text(st.fontWeight)
    if weight = "regular" then out.weight = 400
    if weight = "semibold" then out.weight = 600
    if weight = "extrabold" then out.weight = 800
    if Ovl_isBool(st.uppercase) then out.uppercase = st.uppercase
    shape = Ovl_text(st.shape)
    if shape = "pill" then out.radius = -1
    if shape = "rounded" then out.radius = 6
    if shape = "square" then out.radius = 2
    if Ovl_isNum(st.borderWidth) then out.borderWidth = st.borderWidth
    if Ovl_isBool(st.shadow) then
        if not st.shadow then out.boxShadow = invalid
        if st.shadow and out.boxShadow = invalid then out.boxShadow = { x: 0, y: 2, blur: 6, color: "#00000059" }
    end if
    background = Ovl_text(st.background)
    alpha = 0.0
    if background <> "" then alpha = Ovl_parseColor(background).a
    bw = 0
    if Ovl_isNum(st.borderWidth) then bw = st.borderWidth
    ' A framed badge gets padding; bare text would run to the frame.
    if alpha > 0 or bw > 0 then
        if out.padX < out.fontSize * 0.6 then out.padX = out.fontSize * 0.6
        if out.padY < out.fontSize * 0.2 then out.padY = out.fontSize * 0.2
    end if
    ' From half opacity the fill, not the artwork, is behind the text.
    if alpha >= 0.5 then
        out.solid = background
        out.textShadow = invalid
    end if
    out.fill = background
    out.textColor = Ovl_text(st.textColor)
    out.borderColor = Ovl_text(st.borderColor)
    out.styled = background <> "" or out.textColor <> "" or out.borderColor <> "" or Ovl_isNum(st.borderWidth)
    return out
end function

function Ovl_presetLook(preset as string) as object
    shadow = { x: 0, y: 1, blur: 2, color: "#000000D9" }
    if preset = "minimal" then
        out = Ovl_preLook(preset, 600, 9, 4, 0, 8, 0, 10, 4, false, 2, "text", shadow, invalid)
        out.tracking = 0.1
        return out
    end if
    if preset = "vibrant" then return Ovl_preLook(preset, 700, 10, 8, 2, 10, 0, 12, 4, true, 4, "bg", invalid, { x: 0, y: 1, blur: 2, color: "#00000040" })
    if preset = "pill" then return Ovl_preLook(preset, 600, 10, 10, 4, -1, 1, 12, 4, true, 4, "bg", invalid, invalid)
    if preset = "square" then
        out = Ovl_preLook(preset, 700, 9, 6, 2, 8, 0, 10, 4, false, 2, "border", invalid, invalid)
        out.accentLeft = 2
        out.tracking = 0.1
        return out
    end if
    if preset = "plate" then
        out = Ovl_preLook(preset, 800, 12, 7, 4, 6, 1, 13, 5, true, 4, "border", invalid, { x: 0, y: 2, blur: 6, color: "#00000059" })
        out.sourceChips = true
        return out
    end if
    if preset = "band" then
        out = Ovl_preLook(preset, 800, 12.5, 0, 1, 0, 0, 13, 3, false, 7, "text", { x: 0, y: 1, blur: 3, color: "#000000BF" }, invalid)
        out.band = true
        return out
    end if
    return Ovl_preLook("classic", 600, 10, 8, 2, -1, 1, 11, 4, false, 4, "bg", invalid, invalid)
end function

function Ovl_preLook(id as string, weight as integer, fontSize as float, padX as float, padY as float, radius as float, borderWidth as float, iconSize as float, iconGap as float, preferIcon as boolean, stackGap as float, strategy as string, textShadow as dynamic, boxShadow as dynamic) as object
    return { id: id, band: false, sourceChips: false, weight: weight, uppercase: true, tracking: 0.025, fontSize: fontSize, padX: padX, padY: padY, radius: radius, borderWidth: borderWidth, accentLeft: 0, textShadow: textShadow, boxShadow: boxShadow, iconSize: iconSize, iconGap: iconGap, preferIcon: preferIcon, stackGap: stackGap, strategy: strategy }
end function

' Whether a look's rail badges sit flush against the card's edge as tabs: a filled look's do; bare
' text (minimal, band) keeps the corner inset.
function Ovl_flushRails(look as object) as boolean
    return not look.band and look.id <> "minimal"
end function

' A badge's colours under look for its accent ("" for none), "#RRGGBBAA" or "" for none:
' { fill, ink, border, accentLeft }. The preset's badgeStyle, then the style's colours over it.
function Ovl_paint(look as object, accent as string) as object
    id = look.id
    hasAccent = accent <> ""
    out = { fill: "", ink: "#FFFFFFFF", border: "", accentLeft: "" }
    if id = "minimal" or id = "band" then
        out.ink = "#FFFFFFD9"
        if id = "band" then out.ink = "#FFFFFFFF"
        if hasAccent then out.ink = Ovl_opaque(accent)
    else if id = "classic" then
        out.fill = "#00000099"
        if hasAccent then out.fill = Ovl_mix(accent, 0.28, "#00000099")
        out.border = "#FFFFFF26"
    else if id = "vibrant" then
        out.fill = "#DCDCDCF2"
        out.ink = "#000000FF"
        if hasAccent then
            out.fill = Ovl_opaque(accent)
            out.ink = "#FFFFFFFF"
        end if
    else if id = "pill" then
        out.fill = "#14141EB3"
        if hasAccent then out.fill = Ovl_mix(accent, 0.20, "#14141EB3")
        out.border = "#FFFFFF26"
    else if id = "square" then
        out.fill = "#000000CC"
        if hasAccent then
            out.ink = Ovl_opaque(accent)
            out.accentLeft = Ovl_opaque(accent)
        end if
    else if id = "plate" then
        out.fill = "#000000B8"
        out.border = "#FFFFFF1A"
        if hasAccent then out.border = Ovl_mix(accent, 0.45, "#00000000")
    end if
    if not look.styled then return out
    strategy = look.strategy
    accentText = false
    if hasAccent and strategy = "text" then
        accentText = look.solid = ""
        if not accentText then accentText = Ovl_contrast(accent, look.solid) >= 3
    end if
    accentFill = hasAccent and (strategy = "bg" or (strategy = "text" and not accentText))
    if look.fill <> "" then
        out.fill = look.fill
        if accentFill then out.fill = Ovl_mix(accent, 0.30, look.fill)
    end if
    ink = look.textColor
    if ink = "" and look.solid <> "" then ink = Ovl_readableOn(look.solid)
    if ink <> "" and not accentText then out.ink = Ovl_opaque(ink)
    if look.borderColor <> "" and not (hasAccent and strategy = "border") then out.border = look.borderColor
    ' A border the preset does not colour takes the text's colour, as CSS's currentColor does.
    if look.borderWidth > 0 and out.border = "" then out.border = out.ink
    return out
end function

' ---------- Colours ----------

' "#RRGGBB" or "#RRGGBBAA" as { r, g, b, a }, channels 0 to 1.
function Ovl_parseColor(hex as string) as object
    out = { r: 0.0, g: 0.0, b: 0.0, a: 1.0 }
    if Len(hex) < 7 then return out
    out.r = Val(Mid(hex, 2, 2), 16) / 255.0
    out.g = Val(Mid(hex, 4, 2), 16) / 255.0
    out.b = Val(Mid(hex, 6, 2), 16) / 255.0
    if Len(hex) >= 9 then out.a = Val(Mid(hex, 8, 2), 16) / 255.0
    return out
end function

function Ovl_hexOf(c as object) as string
    out = "#"
    for each ch in [c.r, c.g, c.b, c.a]
        v = Int(ch * 255 + 0.5)
        if v < 0 then v = 0
        if v > 255 then v = 255
        out = out + Ovl_hex2(v)
    end for
    return out
end function

function Ovl_hex2(v as integer) as string
    digits = "0123456789ABCDEF"
    return Mid(digits, (v \ 16) + 1, 1) + Mid(digits, (v mod 16) + 1, 1)
end function

function Ovl_opaque(hex as string) as string
    return UCase(Left(hex, 7)) + "FF"
end function

' CSS's color-mix(in srgb, a share, b): premultiplied interpolation.
function Ovl_mix(a as string, share as float, b as string) as string
    x = Ovl_parseColor(a)
    y = Ovl_parseColor(b)
    alpha = x.a * share + y.a * (1 - share)
    if alpha <= 0 then return "#00000000"
    out = { a: alpha }
    for each k in ["r", "g", "b"]
        out[k] = (x[k] * x.a * share + y[k] * y.a * (1 - share)) / alpha
    end for
    return Ovl_hexOf(out)
end function

function Ovl_luminance(hex as string) as float
    c = Ovl_parseColor(hex)
    total = 0.0
    weights = { r: 0.2126, g: 0.7152, b: 0.0722 }
    for each k in ["r", "g", "b"]
        ch = c[k]
        if ch <= 0.03928 then
            ch = ch / 12.92
        else
            ch = ((ch + 0.055) / 1.055) ^ 2.4
        end if
        total = total + weights[k] * ch
    end for
    return total
end function

' The WCAG contrast ratio of two colours, ignoring alpha.
function Ovl_contrast(a as string, b as string) as float
    x = Ovl_luminance(a)
    y = Ovl_luminance(b)
    if x < y then
        t = x
        x = y
        y = t
    end if
    return (x + 0.05) / (y + 0.05)
end function

' Black or white, whichever reads better on a colour.
function Ovl_readableOn(hex as string) as string
    if Ovl_luminance(hex) > 0.4 then return "#000000"
    return "#FFFFFF"
end function

' ---------- Reading the document ----------

' The uploaded images a parsed document draws, each once: badge icons and value images.
function Ovl_usedImages(prefs as dynamic) as object
    refs = []
    if not Ovl_isObj(prefs) then return refs
    if not Ovl_isObj(prefs.items) then return refs
    for each id in prefs.items
        it = prefs.items[id]
        found = [it.image]
        if Ovl_isObj(it.valueImages) then
            for each k in it.valueImages
                found.Push(it.valueImages[k])
            end for
        end if
        for each ref in found
            if Ovl_isImageRef(ref) and not Ovl_has(refs, ref) then refs.Push(ref)
        end for
    end for
    return refs
end function

' The profile's own choices from Siku's settings snapshot items ({ key: { value, source, scope } }):
' { document (invalid unless the profile chose one), enabled (invalid unless the profile chose) }.
' A value counts as the profile's only when its source says so; the server's default comes from
' the overlay config.
function Ovl_profileValues(items as dynamic) as object
    out = { document: invalid, enabled: invalid }
    if not Ovl_isObj(items) then return out
    for each pair in [[Ovl_documentKey(), "document"], [Ovl_enabledKey(), "enabled"]]
        it = items[pair[0]]
        if Ovl_isObj(it) then
            src = it.scope
            if not Ovl_isStr(src) or src = "" then src = it.source
            own = not Ovl_isStr(src) or src = "" or src = "profile"
            if own then
                if pair[1] = "document" and not Ovl_isNone(it.value) then out.document = it.value
                if pair[1] = "enabled" and Ovl_isBool(it.value) then out.enabled = it.value
            end if
        end if
    end for
    return out
end function

' What cards draw from the profile's values (Ovl_profileValues, or invalid) and the overlay config
' (invalid without it): { enabled, prefs, images ({ <ref>: { width, height } }) }. The profile's
' choice wins, then the server's default; without either badges are on in the classic look.
function Ovl_settle(values as dynamic, config as dynamic) as object
    images = {}
    images.SetModeCaseSensitive()
    enabled = true
    defaultDoc = invalid
    if Ovl_isObj(config) then
        if Ovl_isBool(config.enabled) then enabled = config.enabled
        defaultDoc = config.defaults
        if Type(config.images) = "roArray" then
            for each img in config.images
                if Ovl_isObj(img) then
                    if Ovl_isImageRef(img.ref) then images[img.ref] = { width: img.width, height: img.height }
                end if
            end for
        end if
    end if
    doc = defaultDoc
    if Ovl_isObj(values) then
        if Ovl_isBool(values.enabled) then enabled = values.enabled
        if not Ovl_isNone(values.document) then doc = values.document
    end if
    return { enabled: enabled, prefs: Ovl_withoutUnlisted(Ovl_parse(doc), images), images: images }
end function

' How many badges a document turns on (for the console line).
function Ovl_enabledCount(prefs as dynamic) as integer
    if not Ovl_isObj(prefs) then return 0
    n = 0
    hidden = Ovl_suppressed(prefs)
    for each e in Ovl_registry()
        if Ovl_isOn(prefs, e.id) and not hidden.DoesExist(e.id) then n = n + 1
    end for
    return n
end function
