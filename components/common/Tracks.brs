' Labels for file versions and their audio / subtitle tracks (docs/api-spec.md §4.4), ported from
' the Android TV app's TvPlaybackFormatting. Include with
' <script uri="pkg:/components/common/Tracks.brs" />; needs Utils.
'
' Selection identities (the server's contract):
'   version   file_id, "" = Auto
'   audio     zero-based ordinal into version.audio_tracks; id "file:<file_id>:audio:<n>"
'   subtitles the COMBINED index (external tracks first, embedded after); -1 = Off;
'             id "file:<file_id>:subtitle:<n>"
' SPDX-License-Identifier: AGPL-3.0-or-later

' ---------- Versions ----------

' "4K" / "1080p" / "720p" from a resolution string.
function Tracks_resolution(res as dynamic) as string
    r = LCase(Str_orEmpty(res))
    if r = "" then return ""
    if r = "2160p" or r = "4k" or r = "uhd" or Instr(1, r, "2160") > 0 or Instr(1, r, "3840") > 0 then return "4K"
    if Instr(1, r, "1080") > 0 then return "1080p"
    if Instr(1, r, "720") > 0 then return "720p"
    if Instr(1, r, "480") > 0 then return "480p"
    return UCase(res)
end function

function Tracks_videoCodec(codec as dynamic) as string
    c = LCase(Str_orEmpty(codec))
    if c = "" then return ""
    if c = "h264" or c = "avc" or c = "avc1" then return "H.264"
    if c = "hevc" or c = "h265" or c = "hvc1" then return "HEVC"
    if c = "av1" or c = "av01" then return "AV1"
    if c = "vp9" then return "VP9"
    if c = "mpeg2video" or c = "mpeg2" then return "MPEG-2"
    return UCase(c)
end function

function Tracks_audioCodec(codec as dynamic) as string
    c = LCase(Str_orEmpty(codec))
    if c = "" then return ""
    if c = "eac3" or c = "ec-3" or c = "e-ac-3" then return "EAC3"
    if c = "ac3" or c = "ac-3" then return "AC3"
    if c = "truehd" then return "TrueHD"
    if c = "dts-hd" or c = "dtshd" or c = "dts_hd" then return "DTS-HD"
    if c = "mp3" or c = "mp2" or c = "aac" or c = "dts" or c = "flac" or c = "opus" or c = "pcm" or c = "alac" or c = "vorbis" then return UCase(c)
    if Left(c, 4) = "pcm_" then return "PCM"
    return UCase(c)
end function

function Tracks_isDolbyVision(v as object) as boolean
    c = LCase(Str_orEmpty(v.codec_video))
    if Instr(1, c, "dvhe") > 0 or Instr(1, c, "dvh1") > 0 or Instr(1, c, "dolby") > 0 then return true
    for each t in Arr_or(v.video_tracks)
        if t <> invalid and not Str_isEmpty(t.dolby_vision) then return true
    end for
    r = LCase(Str_orEmpty(v.dynamic_range))
    return Instr(1, r, "dolby") > 0 or r = "dv"
end function

function Tracks_isHdr(v as object) as boolean
    if v.hdr = true then return true
    r = LCase(Str_orEmpty(v.dynamic_range))
    return r <> "" and r <> "sdr"
end function

' Resting value: resolution plus HDR family, e.g. "4K · DV"; "Auto" when nothing is known.
function Tracks_versionCompact(v as dynamic) as string
    if v = invalid then return "Auto"
    tokens = []
    r = Tracks_resolution(v.resolution)
    if r <> "" then tokens.Push(r)
    if Tracks_isDolbyVision(v) then
        tokens.Push("DV")
    else if Tracks_isHdr(v) then
        tokens.Push("HDR")
    end if
    if tokens.Count() = 0 then return "Auto"
    return Str_joinDots(tokens)
end function

' Menu-row title: "4K · HEVC · DV · TrueHD" / "1080p · H.264 · AAC".
function Tracks_versionShort(v as dynamic) as string
    if v = invalid then return "Auto"
    tokens = []
    r = Tracks_resolution(v.resolution)
    if r <> "" then tokens.Push(r)
    vc = Tracks_videoCodec(v.codec_video)
    if vc <> "" then tokens.Push(vc)
    if Tracks_isDolbyVision(v) then
        tokens.Push("DV")
    else if Tracks_isHdr(v) then
        tokens.Push("HDR")
    end if
    ac = Tracks_audioCodec(v.codec_audio)
    if ac = "" then
        tracks = Arr_or(v.audio_tracks)
        if tracks.Count() > 0 then ac = Tracks_audioCodec(tracks[0].codec)
    end if
    if ac <> "" then tokens.Push(ac)
    if not Str_isEmpty(v.edition_key) then tokens.Unshift(Str_orEmpty(v.edition_key))
    if tokens.Count() = 0 then return "Auto"
    return Str_joinDots(tokens)
end function

' Menu-row detail: codec · container · size.
function Tracks_versionDetail(v as object) as string
    tokens = []
    vc = Tracks_videoCodec(v.codec_video)
    if vc <> "" then tokens.Push(vc)
    if not Str_isEmpty(v.container) then tokens.Push(UCase(v.container))
    sz = Tracks_fileSize(v.file_size)
    if sz <> "" then tokens.Push(sz)
    return Str_joinDots(tokens)
end function

function Tracks_fileSize(bytes as dynamic) as string
    if bytes = invalid then return ""
    b = 0.0
    b = b + bytes
    if b < 1024 * 1024 then return ""
    gb = b / (1024.0 * 1024.0 * 1024.0)
    if gb >= 1 then
        tenths = Int(gb * 10 + 0.5)
        return (tenths \ 10).ToStr() + "." + (tenths mod 10).ToStr() + " GB"
    end if
    return Int(b / (1024.0 * 1024.0) + 0.5).ToStr() + " MB"
end function

' ---------- Languages ----------

' English name for an ISO 639 code; "" when unknown or undetermined.
function Tracks_languageName(code as dynamic) as string
    c = LCase(Str_orEmpty(code)).Trim()
    if c = "" or c = "und" or c = "zxx" or c = "mis" then return ""
    dash = Instr(1, c, "-")
    if dash > 0 then c = Left(c, dash - 1)
    names = {
        en: "English", eng: "English", es: "Spanish", spa: "Spanish", fr: "French", fra: "French", fre: "French"
        de: "German", deu: "German", ger: "German", it: "Italian", ita: "Italian", pt: "Portuguese", por: "Portuguese"
        ja: "Japanese", jpn: "Japanese", ko: "Korean", kor: "Korean", zh: "Chinese", zho: "Chinese", chi: "Chinese"
        ru: "Russian", rus: "Russian", hi: "Hindi", hin: "Hindi", ar: "Arabic", ara: "Arabic", nl: "Dutch", nld: "Dutch", dut: "Dutch"
        sv: "Swedish", swe: "Swedish", nb: "Norwegian", no: "Norwegian", nor: "Norwegian", da: "Danish", dan: "Danish"
        fi: "Finnish", fin: "Finnish", pl: "Polish", pol: "Polish", tr: "Turkish", tur: "Turkish", cs: "Czech", ces: "Czech", cze: "Czech"
        el: "Greek", ell: "Greek", gre: "Greek", he: "Hebrew", heb: "Hebrew", hu: "Hungarian", hun: "Hungarian", th: "Thai", tha: "Thai"
        vi: "Vietnamese", vie: "Vietnamese", id: "Indonesian", ind: "Indonesian", uk: "Ukrainian", ukr: "Ukrainian", ro: "Romanian", ron: "Romanian", rum: "Romanian"
        ta: "Tamil", tam: "Tamil", te: "Telugu", tel: "Telugu", fa: "Persian", fas: "Persian", per: "Persian", ms: "Malay", msa: "Malay", may: "Malay"
        tl: "Tagalog", tgl: "Tagalog", fil: "Filipino", ca: "Catalan", cat: "Catalan", bg: "Bulgarian", bul: "Bulgarian", hr: "Croatian", hrv: "Croatian"
        sr: "Serbian", srp: "Serbian", sk: "Slovak", slk: "Slovak", slo: "Slovak", sl: "Slovenian", slv: "Slovenian", lv: "Latvian", lav: "Latvian"
        lt: "Lithuanian", lit: "Lithuanian", et: "Estonian", est: "Estonian", is: "Icelandic", isl: "Icelandic", ice: "Icelandic", ga: "Irish", gle: "Irish"
        la: "Latin", lat: "Latin", bn: "Bengali", ben: "Bengali", ur: "Urdu", urd: "Urdu", sw: "Swahili", swa: "Swahili", af: "Afrikaans", afr: "Afrikaans"
    }
    n = names[c]
    if n <> invalid then return n
    if Len(c) = 2 or Len(c) = 3 then return UCase(c)
    return Str_orEmpty(code)
end function

' ---------- Audio ----------

function Tracks_channelsLabel(t as object) as string
    if not Str_isEmpty(t.layout) then return Str_orEmpty(t.layout)
    ch = t.channels
    if ch = invalid then return ""
    n = Int(ch)
    if n = 1 then return "Mono"
    if n = 2 then return "Stereo"
    if n = 6 then return "5.1"
    if n = 8 then return "7.1"
    if n <= 0 then return ""
    return n.ToStr() + " ch"
end function

' A custom title worth showing: not just the language or codec, and not a bare tag.
function Tracks_usefulTitle(title as dynamic, language as dynamic, codec as dynamic) as string
    t = Str_orEmpty(title).Trim()
    if t = "" then return ""
    lt = LCase(t)
    if lt = LCase(Str_orEmpty(language)) or lt = LCase(Tracks_languageName(language)) then return ""
    if lt = LCase(Str_orEmpty(codec)) or lt = LCase(Tracks_audioCodec(codec)) then return ""
    if Len(t) > 28 or Instr(1, t, "[") > 0 then return ""
    for each suffix in [".srt", ".ass", ".ssa", ".vtt", ".sub", ".sup", ".idx"]
        if Right(lt, Len(suffix)) = suffix then return ""
    end for
    if lt = "forced" or lt = "sdh" or lt = "cc" or lt = "hearing impaired" or lt = "default" then return ""
    return t
end function

' Menu-row title: language → useful custom title → "Track N".
function Tracks_audioTitle(t as object, ordinal as integer) as string
    n = Tracks_languageName(t.language)
    if n <> "" then return n
    u = Tracks_usefulTitle(t.title, t.language, t.codec)
    if u <> "" then return u
    return "Track " + (ordinal + 1).ToStr()
end function

' Pill-value summary: "English · EAC3 · 5.1".
function Tracks_audioSummary(t as object, ordinal as integer) as string
    tokens = [Tracks_audioTitle(t, ordinal)]
    c = Tracks_audioCodec(t.codec)
    if c <> "" then tokens.Push(c)
    ch = Tracks_channelsLabel(t)
    if ch <> "" then tokens.Push(ch)
    return Str_joinDots(tokens)
end function

' Menu-row detail: custom title · codec · channels · Default.
function Tracks_audioDetail(t as object) as string
    tokens = []
    u = Tracks_usefulTitle(t.title, t.language, t.codec)
    if u <> "" and u <> Tracks_languageName(t.language) then tokens.Push(u)
    c = Tracks_audioCodec(t.codec)
    if c <> "" then tokens.Push(c)
    ch = Tracks_channelsLabel(t)
    if ch <> "" then tokens.Push(ch)
    if t["default"] = true then tokens.Push("Default")
    return Str_joinDots(tokens)
end function

' The ordinal Auto resolves to: effective_audio_track_index → the default flag → the first track.
function Tracks_autoAudioOrdinal(v as dynamic) as integer
    if v = invalid then return -1
    tracks = Arr_or(v.audio_tracks)
    if tracks.Count() = 0 then return -1
    e = v.effective_audio_track_index
    if e <> invalid and e >= 0 and e < tracks.Count() then return Int(e)
    for i = 0 to tracks.Count() - 1
        if tracks[i]["default"] = true then return i
    end for
    return 0
end function

' ---------- Subtitles ----------

function Tracks_subtitleCodec(codec as dynamic) as string
    c = LCase(Str_orEmpty(codec))
    if c = "" then return ""
    if c = "subrip" or c = "srt" then return "SRT"
    if c = "webvtt" or c = "vtt" then return "VTT"
    if c = "ass" or c = "ssa" then return "ASS"
    if c = "hdmv_pgs_subtitle" or c = "pgs" or c = "pgssub" then return "PGS"
    if c = "dvd_subtitle" or c = "dvdsub" or c = "vobsub" then return "VobSub"
    if c = "mov_text" or c = "tx3g" then return "MP4"
    return UCase(c)
end function

function Tracks_subtitleIsSdh(t as object) as boolean
    if t.hearing_impaired = true then return true
    lt = LCase(Str_orEmpty(t.title))
    return Instr(1, lt, "sdh") > 0 or Instr(1, lt, "hearing") > 0 or Instr(1, lt, "cc") > 0
end function

function Tracks_subtitleIsForced(t as object) as boolean
    if t.forced = true then return true
    return Instr(1, LCase(Str_orEmpty(t.title)), "forced") > 0
end function

function Tracks_subtitleTitle(t as object, ordinal as integer) as string
    n = Tracks_languageName(t.language)
    if n <> "" then return n
    u = Tracks_usefulTitle(t.title, t.language, t.codec)
    if u <> "" then return u
    return "Track " + (ordinal + 1).ToStr()
end function

' Pill-value summary: "English (Forced) · SRT" / "English (SDH) · PGS".
function Tracks_subtitleSummary(t as object, ordinal as integer) as string
    name = Tracks_subtitleTitle(t, ordinal)
    if Tracks_subtitleIsSdh(t) and Instr(1, LCase(name), "sdh") = 0 and Instr(1, LCase(name), "cc") = 0 then name = name + " (SDH)"
    if Tracks_subtitleIsForced(t) and Instr(1, LCase(name), "forced") = 0 then name = name + " (Forced)"
    c = Tracks_subtitleCodec(t.codec)
    if c = "" then return name
    return name + " · " + c
end function

' Menu-row detail: custom title · codec · Forced · SDH · Default · External.
function Tracks_subtitleDetail(t as object) as string
    tokens = []
    u = Tracks_usefulTitle(t.title, t.language, t.codec)
    if u <> "" then tokens.Push(u)
    c = Tracks_subtitleCodec(t.codec)
    if c <> "" then tokens.Push(c)
    if Tracks_subtitleIsForced(t) then tokens.Push("Forced")
    if Tracks_subtitleIsSdh(t) then tokens.Push("SDH")
    if t["default"] = true then tokens.Push("Default")
    if t.external = true then tokens.Push("External")
    return Str_joinDots(tokens)
end function

' Combined selection index per catalog position: external tracks count first, embedded after.
function Tracks_subtitleCombined(tracks as object) as object
    out = []
    ext = 0
    for each t in tracks
        if t.external = true then ext = ext + 1
    end for
    e = 0
    i = ext
    for each t in tracks
        if t.external = true then
            out.Push(e)
            e = e + 1
        else
            out.Push(i)
            i = i + 1
        end if
    end for
    return out
end function

' Catalog position of a combined selection index, or -1.
function Tracks_subtitleOrdinal(tracks as object, combinedIndex as integer) as integer
    comb = Tracks_subtitleCombined(tracks)
    for i = 0 to comb.Count() - 1
        if comb[i] = combinedIndex then return i
    end for
    return -1
end function

' Track ids in the server's form.
function Tracks_audioId(fileId as string, ordinal as integer) as string
    if fileId = "" or ordinal < 0 then return ""
    return "file:" + fileId + ":audio:" + ordinal.ToStr()
end function

function Tracks_subtitleId(fileId as string, combinedIndex as integer) as string
    if fileId = "" or combinedIndex < 0 then return ""
    return "file:" + fileId + ":subtitle:" + combinedIndex.ToStr()
end function
