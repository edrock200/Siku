' Protocol-v3 start body for audio-only playback (music tracks and audiobook parts).
' Wraps PlaybackCaps_startBody (components/player/PlaybackCaps.brs, read-only here) and widens the
' container/codec lists with audio formats the Roku Audio node plays, without mutating the cached probe.
' Include PlaybackCaps.brs before this file.
' SPDX-License-Identifier: AGPL-3.0-or-later

function AudioCaps_containers() as object
    return ["mp3", "m4a", "m4b", "mp4", "aac", "adts", "flac", "ogg", "oga", "opus", "wav", "mka", "mkv", "mov"]
end function

function AudioCaps_audioCodecs() as object
    passing = []
    di = CreateObject("roDeviceInfo")
    for each c in ["flac", "alac", "pcm", "opus", "vorbis"]
        if PlaybackCaps_canDecodeAudio(di, { "codec": c }) then passing.Push(c)
    end for
    return AudioCaps_codecList(PlaybackCaps_probe().codecsAudio, passing)
end function

' The video probe's audio codecs, then the wire names of each extra probe that passed.
function AudioCaps_codecList(base as object, passing as object) as object
    out = []
    for each c in base
        out.Push(c)
    end for
    for each c in passing
        for each name in AudioCaps_wireNames(c)
            if not PlaybackCaps_has(out, name) then out.Push(name)
        end for
    end for
    return out
end function

' The codec names the server matches for a CanDecodeAudio probe name. The server names a source's
' codec as ffprobe does and matches the list exactly, so a bare "pcm" never matched a WAV file
' (pcm_s16le) and a WAV audiobook had no route (Silo Android #707: the audio-only planner
' direct-plays only a listed codec, and the progressive remux is off by default). Roku lists WAV
' (LPCM) among its audio formats and answers the "pcm" probe; 16- and 24-bit integer PCM are
' declared, as silo-roku does (pcm_s16le played as an original on a Roku TV); 8-bit, 32-bit and
' float PCM, which Android also lists, stay out without Roku evidence.
function AudioCaps_wireNames(probe as string) as object
    if probe = "pcm" then return ["pcm_s16le", "pcm_s24le"]
    return [probe]
end function

' persistence: "server" (music: the server keeps resume/scrobbles) or "client" (audiobook parts:
' part-local positions must never become the book's position; whole-book progress goes through
' POST /api/v2/sync/progress). startPosition is part-local seconds; invalid = server resume.
function AudioCaps_startBody(installation as string, fileId as string, attemptId as string, startPosition as dynamic, persistence as string) as object
    body = PlaybackCaps_startBody(installation, fileId, attemptId, startPosition, invalid, invalid)
    body.progress_persistence = persistence
    ' Android's audiobook player asks for the original stream (QUALITY_ORIGINAL_V3).
    body.quality_preference = "original"
    containers = AudioCaps_containers()
    codecs = AudioCaps_audioCodecs()

    caps = body.client_capabilities
    caps.codecs_audio = codecs
    caps.containers = containers

    ctx = body.client_playback_context
    deliveries = {}
    for each k in ctx.deliveries
        d = AA_copy(ctx.deliveries[k])
        d.audio_decode_codecs = codecs
        if k = "original_http" then d.containers = containers
        deliveries[k] = d
    end for
    ctx.deliveries = deliveries
    return body
end function

' Roku StreamFormat for a plan stream.
function AudioCaps_streamFormat(stream as object, url as string) as string
    proto = LCase(Str_orEmpty(stream.protocol))
    container = LCase(Str_orEmpty(stream.container))
    mime = LCase(Str_orEmpty(stream.mime_type))
    if proto = "hls" or Instr(1, LCase(url), ".m3u8") > 0 then return "hls"
    if container = "mp3" or mime = "audio/mpeg" then return "mp3"
    if container = "flac" or mime = "audio/flac" then return "flac"
    if container = "wav" or mime = "audio/wav" then return "wav"
    ' No documented StreamFormat for Ogg: leave it empty and let the firmware sniff the stream.
    if container = "ogg" or container = "oga" or container = "opus" then return ""
    if container = "mka" or container = "mkv" or container = "matroska" then return "mka"
    if container = "aac" or container = "adts" then return "es.aac-adts"
    ' m4a / m4b / mp4 / mov audio
    return "mp4"
end function
