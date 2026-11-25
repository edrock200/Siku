' SPDX-License-Identifier: AGPL-3.0-or-later
' The audio a start that names no track plays on this Roku, for the detail page's "Auto · …"
' readout (adapted from silo-roku 3ae62aa / #110, playback.options.startAudio). Siku's Auto sends
' no audio_track_id, so the server picks the track by the profile's preferences
' (effective_audio_track_index) and then, unless the viewer's saved series track decided, refines it
' for the request (silo-server playableStartAudioV3 over PreferUnconvertedAudioTrackV3): when this
' Roku would get the chosen track converted (TrueHD, DTS without passthrough, PCM), another main mix
' in the same language that plays as it is with at least the channels the conversion keeps plays
' instead (most channels, then Atmos, then codec rank). Android TV names the effective track alone:
' it plays TrueHD itself, so the two agree there; on Roku they did not (silo-roku's TCL run).
' The server decides by planning; the readout follows the declared audio codecs of the same probe a
' start sends (PlaybackCaps_reprobe's audio block, mirrored by StartAudio_device). It cannot see a
' video route that re-encodes every track (a video transcode); then the server keeps the chosen
' track and the readout may name the swap. Pure apart from StartAudio_device; tests/test_start_audio.py.
' Needs Utils.brs, Tracks.brs and SeriesChoice.brs.

' The codec family the server ranks and the probe names: ac3, eac3, truehd, dts, aac, flac, alac,
' opus, vorbis, mp3, pcm; "" when unknown.
function StartAudio_family(codec as dynamic) as string
    c = LCase(Str_orEmpty(codec).Trim())
    if c = "" then return ""
    if c = "ac3" or c = "ac-3" or c = "a52" then return "ac3"
    if c = "eac3" or c = "e-ac-3" or c = "ec-3" or c = "ec3" or c = "eac3_joc" then return "eac3"
    if c = "truehd" or c = "mlp" then return "truehd"
    if Left(c, 3) = "dts" or c = "dca" then return "dts"
    if Left(c, 3) = "aac" then return "aac"
    if Left(c, 3) = "pcm" or c = "lpcm" then return "pcm"
    return c
end function

' Whether the device plays the track as it is: its codec is declared (device.codecs), multichannel
' AAC only where the probe confirmed it.
function StartAudio_playsAsIs(t as dynamic, device as object) as boolean
    if t = invalid or Type(t) <> "roAssociativeArray" then return false
    fam = StartAudio_family(t.codec)
    if fam = "" then return false
    found = false
    for each c in Arr_or(device.codecs)
        if LCase(Str_orEmpty(c)) = fam then found = true
    end for
    if not found then return false
    if fam = "aac" and Int(Num_or(t.channels, 2)) > 2 and not Tracks_flag(device.multichannelAac) then return false
    return true
end function

' The channels a converted track keeps here: up to six where the device plays AC-3, E-AC-3 or
' multichannel AAC, else two.
function StartAudio_convertedChannels(t as object, device as object) as integer
    channels = Int(Num_or(t.channels, 2))
    ceiling = 2
    for each c in Arr_or(device.codecs)
        cc = LCase(Str_orEmpty(c))
        if cc = "ac3" or cc = "eac3" then ceiling = 6
    end for
    if Tracks_flag(device.multichannelAac) then ceiling = 6
    if channels > ceiling then return ceiling
    return channels
end function

' A main mix: not commentary, not audio description (silo-server mainAudioTrack).
function StartAudio_isMain(t as object) as boolean
    title = LCase(Str_orEmpty(t.title) + " " + Str_orEmpty(t.embedded_title))
    return Instr(1, title, "comment") = 0 and Instr(1, title, "descripti") = 0
end function

function StartAudio_isAtmos(t as object) as boolean
    detail = LCase(Str_orEmpty(t.profile) + " " + Str_orEmpty(t.layout))
    return Instr(1, detail, "atmos") > 0 or Instr(1, detail, "joc") > 0
end function

' silo-server audioCodecQualityRanks: lossless, then DTS, E-AC-3, AC-3 and AAC.
function StartAudio_codecRank(codec as dynamic) as integer
    fam = StartAudio_family(codec)
    if fam = "truehd" or fam = "flac" or fam = "alac" or fam = "pcm" then return 5
    if fam = "dts" then return 4
    if fam = "eac3" then return 3
    if fam = "ac3" then return 2
    if fam = "aac" then return 1
    return 0
end function

' silo-server betterUnconvertedAudioTrack: more channels, then Atmos, then the codec's rank.
function StartAudio_better(a as object, b as object) as boolean
    ca = Int(Num_or(a.channels, 0))
    cb = Int(Num_or(b.channels, 0))
    if ca <> cb then return ca > cb
    if StartAudio_isAtmos(a) <> StartAudio_isAtmos(b) then return StartAudio_isAtmos(a)
    return StartAudio_codecRank(a.codec) > StartAudio_codecRank(b.codec)
end function

' The track a start plays in place of `chosen` (an ordinal of tracks), or chosen itself.
function StartAudio_ordinal(tracks as object, chosen as integer, device as dynamic) as integer
    if device = invalid or Type(device) <> "roAssociativeArray" then return chosen
    if tracks.Count() < 2 or chosen < 0 or chosen >= tracks.Count() then return chosen
    base = tracks[chosen]
    if base = invalid or Type(base) <> "roAssociativeArray" then return chosen
    if StartAudio_playsAsIs(base, device) then return chosen
    lang = SeriesChoice_langKey(base.language)
    floor = StartAudio_convertedChannels(base, device)
    found = -1
    for i = 0 to tracks.Count() - 1
        t = tracks[i]
        if i <> chosen and t <> invalid and Type(t) = "roAssociativeArray" then
            if StartAudio_isMain(t) and SeriesChoice_langKey(t.language) = lang and StartAudio_playsAsIs(t, device) and Int(Num_or(t.channels, 0)) >= floor then
                if found < 0 then
                    found = i
                else if StartAudio_better(t, tracks[found]) then
                    found = i
                end if
            end if
        end if
    end for
    if found < 0 then return chosen
    return found
end function

' Whether the profile's saved series audio decided `chosen` (silo-server SavedAudioTrackChosen),
' which the server plays as saved. saved: "none" (the server holds none), "unknown" (not read, or
' the read failed), or the stored body. An unknown answer and a saved index that still points at
' the chosen track count as saved: the readout then names the effective track (fail closed).
function StartAudio_savedChose(tracks as object, saved as dynamic, chosen as integer) as boolean
    if Type(saved) = "roString" or Type(saved) = "String" then return saved <> "none"
    if saved = invalid or Type(saved) <> "roAssociativeArray" then return true
    if chosen < 0 or chosen >= tracks.Count() then return true
    sig = saved.track_signature
    if sig <> invalid and Type(sig) = "roAssociativeArray" then
        for i = 0 to tracks.Count() - 1
            if SeriesChoice_audioMatches(tracks[i], sig) then return i = chosen
        end for
    end if
    return Int(Num_or(saved.audio_track_index, -1)) = chosen
end function

' The ordinal the detail page names under Auto for version v: the effective track
' (Tracks_autoAudioOrdinal), refined as the server refines it when no saved series track decided.
function StartAudio_readoutOrdinal(v as dynamic, device as dynamic, saved as dynamic) as integer
    o = Tracks_autoAudioOrdinal(v)
    if o < 0 then return o
    tracks = Arr_or(v.audio_tracks)
    if StartAudio_savedChose(tracks, saved, o) then return o
    return StartAudio_ordinal(tracks, o, device)
end function

' What this Roku declares for audio at a start, { codecs, multichannelAac }, as
' PlaybackCaps_reprobe's audio block probes it (CanDecodeAudio decode or passthrough, the Force Dolby
' setting, AC-3 under a 5.1 output). roDeviceInfo is safe on the render thread.
function StartAudio_device() as object
    di = CreateObject("roDeviceInfo")
    codecs = ["aac", "mp3"]
    for each c in ["ac3", "eac3", "dts", "truehd", "flac", "opus", "vorbis", "alac"]
        if StartAudio_canDecode(di, { "codec": c }) or StartAudio_canDecode(di, { "codec": c, "passthru": 1 }) then codecs.Push(c)
    end for
    if Settings_forceDolbyPassthrough() then
        for each c in ["ac3", "eac3"]
            if not StartAudio_has(codecs, c) then codecs.Push(c)
        end for
    end if
    output = ""
    try
        output = LCase(Str_orEmpty(di.GetAudioOutputChannel()))
    catch e
        output = "" ' e: a simulator without the call; no 5.1 rule then
        if e = invalid then output = ""
    end try
    if output = "5.1 surround" and not StartAudio_has(codecs, "ac3") then codecs.Push("ac3")
    return { codecs: codecs, multichannelAac: StartAudio_canDecode(di, { "codec": "aac", "chcnt": 6 }) }
end function

function StartAudio_has(list as object, value as string) as boolean
    for each v in list
        if v = value then return true
    end for
    return false
end function

' PlaybackCaps_canDecodeAudio's reading of a probe (that file is the player's).
function StartAudio_canDecode(di as object, fmt as object) as boolean
    r = invalid
    try
        r = di.CanDecodeAudio(fmt)
    catch e
        r = invalid ' e: a simulator without the probe; "no" is the safe answer
        if e = invalid then r = invalid
    end try
    if r = invalid or Type(r) <> "roAssociativeArray" then return false
    if not Tracks_flag(r.Result) then return false
    if fmt.DoesExist("passthru") and r.passthru <> invalid and not Tracks_flag(r.passthru) then return false
    return true
end function
