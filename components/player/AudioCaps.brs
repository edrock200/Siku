' Protocol-v3 start body for audio-only playback (music tracks and audiobook parts).
' Wraps PlaybackCaps_startBody (components/player/PlaybackCaps.brs, read-only here) and widens the
' container/codec lists with audio formats the Roku Audio node plays, without mutating the cached probe.
' Include PlaybackCaps.brs before this file.
' SPDX-License-Identifier: AGPL-3.0-or-later

function AudioCaps_containers() as object
    return ["mp3", "m4a", "m4b", "mp4", "aac", "adts", "flac", "ogg", "oga", "opus", "wav", "mka", "mkv", "mov"]
end function

function AudioCaps_audioCodecs() as object
    out = []
    for each c in PlaybackCaps_probe().codecsAudio
        out.Push(c)
    end for
    di = CreateObject("roDeviceInfo")
    for each c in ["flac", "alac", "pcm", "opus", "vorbis"]
        found = false
        for each x in out
            if x = c then found = true
        end for
        if not found then
            r = di.CanDecodeAudio({ Codec: c })
            if r <> invalid and r.Result = true then out.Push(c)
        end if
    end for
    return out
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
