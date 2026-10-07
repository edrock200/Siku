' Builds the protocol-v3 playback bodies (docs/api-spec.md §8.2) from what the Roku device reports.
' Everything here is "declared" evidence: the server matches the flat codec lists and never
' walks video_decode[], so we don't fabricate profile/level entries we cannot observe.
' Modeled on the web client's SV/web/src/player/client-context-v3.ts and the Android TV
' PlaybackCapabilityDetector (decoder facts ∩ display facts, then the user's HDR settings).
'
' What the server needs to copy audio instead of converting it (internal/playback/
' capabilities_v3.go audioEligibilityV3 and plan_v3.go deliverySupportsAudioClaimV3): under
' "declared" evidence a passthrough claim is never validated, so the source codec must be in
' codecs_audio AND in the chosen delivery's audio_decode_codecs. audio_passthrough_codecs is
' informational at this tier (a validated passthrough claim needs audio_evidence "exact",
' client_features "layout_aware_passthrough" and per-codec channel/layout entries, which Roku
' cannot attest). The Roku Video node decides decode-vs-passthrough by itself, so every codec
' CanDecodeAudio accepts (decoded or passed to the HDMI sink) goes in codecs_audio.
' SPDX-License-Identifier: AGPL-3.0-or-later

' Probes the device once. Returns {codecsVideo, codecsAudio, passthroughAudio, containers,
' maxResolution, decodes4K, display: {known, hdr10, hdr10Plus, hlg, dolbyVision}, videoMode,
' displayMode, uiResolution, audioOutput, audioChannels, audioDecodeInfo, device}.
' The user's HDR settings are applied later (PlaybackCaps_hdrDetails), never cached here.
function PlaybackCaps_probe() as object
    if m.playbackProbe <> invalid then return m.playbackProbe
    return PlaybackCaps_reprobe()
end function

' Roku asks that codec support be queried before every playback rather than cached: the answers
' change when a soundbar or receiver is switched on, or the HDMI audio mode changes. PlayerScreen
' calls this at each start; PlaybackCaps_probe() then serves the fresh result for the session.
function PlaybackCaps_reprobe() as object
    di = CreateObject("roDeviceInfo")

    ' Video decoders, probed the way Roku documents CanDecodeVideo: Codec ("mpeg4 avc", "hevc",
    ' "vp9", "av1"), Profile ("high", "main 10", "profile 2", ...) and Level ("5.1" = 4K60,
    ' "5" = 4K30, "4.1"/"4.2" = 1080p). The flat codecs_video list is what the server matches
    ' under "declared" evidence; the detailed video_decode[] entries carry the profiles, levels,
    ' bit depths and frame sizes each probe confirmed (empty lists mean "unconstrained").
    codecsVideo = []
    videoDecode = []
    decodes4K = false
    for each spec in PlaybackCaps_videoProbeSpecs()
        base = PlaybackCaps_canDecodeVideo(di, { Codec: spec.rokuCodec })
        if base or spec.codec = "h264" then
            codecsVideo.Push(spec.codec)
            entry = PlaybackCaps_probeDecoder(di, spec)
            if Num_or(entry.max_height, 0) >= 2160 then decodes4K = true
            videoDecode.Push(entry)
        end if
    end for

    ' Output facts. GetVideoMode is the video output ("1080p", "2160p", "2160p60"); GetDisplayMode /
    ' GetUIResolution describe the UI canvas, which is 1080p (or 720p) even on a 4K TV, so they
    ' must never feed max_resolution.
    videoMode = LCase(PlaybackCaps_str(di.GetVideoMode()))
    displayMode = LCase(PlaybackCaps_str(di.GetDisplayMode()))
    uiRes = ""
    ui = di.GetUIResolution()
    if ui <> invalid then uiRes = PlaybackCaps_str(ui.name)
    maxRes = "1080p"
    if decodes4K or Instr(1, videoMode, "2160") > 0 or Instr(1, videoMode, "4320") > 0 or Instr(1, videoMode, "4k") > 0 then maxRes = "2160p"
    displayType = LCase(PlaybackCaps_str(di.GetDisplayType()))
    ' The output's refresh rate, from "2160p60" / "1080p" (Roku lists 60 Hz modes without the
    ' suffix). Used for diagnostics and the decoder frame-rate ceilings.
    outputFps = 60
    pIdx = Instr(1, videoMode, "p")
    if pIdx > 0 and Len(videoMode) > pIdx then
        fps = Int(Val(Mid(videoMode, pIdx + 1)))
        if fps > 0 then outputFps = fps
    end if

    ' Audio. CanDecodeAudio answers true when the codec is decoded on the box or passed through to
    ' the HDMI device; a probe with PassThru set asks for the passthrough path specifically. Both
    ' are read loosely (the result keys are documented but a simulator may omit them).
    codecsAudio = ["aac", "mp3"]
    passthroughAudio = []
    surround = []
    for each c in ["ac3", "eac3", "dts", "truehd", "flac", "opus", "vorbis", "alac"]
        ' Lower-case quoted keys: Roku OS before 14.1 matches CanDecodeAudio keys case-sensitively.
        ok = PlaybackCaps_canDecodeAudio(di, { "codec": c })
        pt = PlaybackCaps_canDecodeAudio(di, { "codec": c, "passthru": 1 })
        if ok or pt then codecsAudio.Push(c)
        if pt then passthroughAudio.Push(c)
        if (ok or pt) and PlaybackCaps_canDecodeAudio(di, { "codec": c, "chcnt": 6 }) then surround.Push(c)
    end for
    ' Settings › Playback › Force Dolby Audio Passthrough: the viewer vouches for AC3 / E-AC3 when
    ' the HDMI capability list leaves them out (seen on device: a DV TV advertising LPCM only).
    forcedDolby = Settings_forceDolbyPassthrough()
    forcedAudio = []
    if forcedDolby then
        for each c in ["ac3", "eac3"]
            if not PlaybackCaps_has(codecsAudio, c) then
                codecsAudio.Push(c)
                forcedAudio.Push(c) ' declared only because of the setting; PlayerScreen warns when it plays
            end if
            if not PlaybackCaps_has(passthroughAudio, c) then passthroughAudio.Push(c)
            if not PlaybackCaps_has(surround, c) then surround.Push(c)
        end for
    end if
    audioOutput = PlaybackCaps_str(di.GetAudioOutputChannel())
    ' jellyfin-roku (deviceCapabilities.bs): with the system output in "5.1 surround", AC3 plays even
    ' when CanDecodeAudio reports a false negative on some receivers; assume it, as Jellyfin does.
    if LCase(audioOutput) = "5.1 surround" and not PlaybackCaps_has(codecsAudio, "ac3") then
        codecsAudio.Push("ac3")
        surround.Push("ac3")
    end if
    audioChannels = 2
    if Instr(1, audioOutput, "7.1") > 0 then
        audioChannels = 8
    else if Instr(1, audioOutput, "5.1") > 0 then
        audioChannels = 6
    end if
    decodeInfo = {}
    try
        info = di.GetAudioDecodeInfo()
        if info <> invalid and Type(info) = "roAssociativeArray" then decodeInfo = info
    catch e
        decodeInfo = {} ' e: the simulator may not implement it; "unknown" is fine
        if e = invalid then decodeInfo = {}
    end try

    props = di.GetDisplayProperties()
    display = { known: false, hdr10: false, hdr10Plus: false, hlg: false, dolbyVision: false }
    if props <> invalid and Type(props) = "roAssociativeArray" and props.Count() > 0 then
        display.known = true
        display.hdr10 = PlaybackCaps_truthy(props.Hdr10)
        display.hdr10Plus = PlaybackCaps_truthy(props.Hdr10Plus)
        display.hlg = PlaybackCaps_truthy(props.Hlg)
        display.dolbyVision = PlaybackCaps_truthy(props.DolbyVision)
    end if

    osv = di.GetOSVersion()
    osVersion = ""
    if osv <> invalid then osVersion = PlaybackCaps_str(osv.major) + "." + PlaybackCaps_str(osv.minor) + "." + PlaybackCaps_str(osv.revision)

    m.playbackProbe = {
        forcedDolby: forcedDolby
        forcedAudio: forcedAudio
        codecsVideo: codecsVideo
        videoDecode: videoDecode
        codecsAudio: codecsAudio
        passthroughAudio: passthroughAudio
        surroundAudio: surround
        containers: ["mp4", "m4v", "mov", "mkv"]
        maxResolution: maxRes
        decodes4K: decodes4K
        display: display
        videoMode: videoMode
        displayMode: displayMode
        displayType: displayType
        outputFps: outputFps
        uiResolution: uiRes
        audioOutput: audioOutput
        audioChannels: audioChannels
        audioDecodeInfo: decodeInfo
        device: {
            platform: "roku"
            os_version: osVersion
            manufacturer: "Roku"
            model: PlaybackCaps_str(di.GetModel())
            platform_details: {
                model_name: PlaybackCaps_str(di.GetModelDisplayName())
                video_mode: videoMode
                display_mode: displayMode
                display_type: displayType
                output_frame_rate: outputFps.ToStr()
                ui_resolution: uiRes
                audio_output: audioOutput
            }
        }
    }
    return m.playbackProbe
end function

' The decoders to probe: the server's codec name, Roku's CanDecodeVideo name, the profiles Roku
' documents for it (10-bit first) and the bit depth each profile implies.
function PlaybackCaps_videoProbeSpecs() as object
    return [
        { codec: "h264", rokuCodec: "mpeg4 avc", profiles: ["high", "main", "baseline"], depth10: [] }
        { codec: "hevc", rokuCodec: "hevc", profiles: ["main 10", "main"], depth10: ["main 10"] }
        { codec: "vp9", rokuCodec: "vp9", profiles: ["profile 2", "profile 0"], depth10: ["profile 2"] }
        { codec: "av1", rokuCodec: "av1", profiles: ["main"], depth10: ["main"] }
    ]
end function

' One video_decode[] entry: the profiles that pass, the highest level that passes (as the
' integer the contract uses: "5.1" → 51) and the frame size / rate that level stands for.
function PlaybackCaps_probeDecoder(di as object, spec as object) as object
    profiles = []
    depths = [8]
    for each pr in spec.profiles
        if PlaybackCaps_canDecodeVideo(di, { "codec": spec.rokuCodec, "profile": pr }) then
            profiles.Push(pr)
            for each d10 in spec.depth10
                if d10 = pr and depths.Count() = 1 then depths.Push(10)
            end for
        end if
    end for
    probeProfile = ""
    if profiles.Count() > 0 then probeProfile = profiles[0]
    ' Levels, highest first: 5.1 = 3840x2160 @ 60, 5 = 3840x2160 @ 30, 4.2 / 4.1 = 1920x1080 @ 60.
    tiers = [
        { level: "5.1", num: 51, w: 3840, h: 2160, fps: 60 }
        { level: "5", num: 50, w: 3840, h: 2160, fps: 30 }
        { level: "4.2", num: 42, w: 1920, h: 1080, fps: 60 }
        { level: "4.1", num: 41, w: 1920, h: 1080, fps: 60 }
    ]
    levels = []
    maxW = 0
    maxH = 0
    maxFps = 0
    for each t in tiers
        fmt = { "codec": spec.rokuCodec, "level": t.level }
        if probeProfile <> "" then fmt["profile"] = probeProfile
        if PlaybackCaps_canDecodeVideo(di, fmt) then
            levels.Push(t.num)
            if maxH = 0 then
                maxW = t.w
                maxH = t.h
                maxFps = t.fps
            end if
        end if
    end for
    entry = { codec: spec.codec, hardware: true, profiles: profiles, levels: levels, bit_depths: depths }
    if maxH > 0 then
        entry.max_width = maxW
        entry.max_height = maxH
        entry.max_frame_rate = maxFps
    end if
    return entry
end function

function PlaybackCaps_str(v as dynamic) as string
    if v = invalid then return ""
    if Type(v) = "roString" or Type(v) = "String" then return v
    if Type(v) = "roInt" or Type(v) = "roInteger" or Type(v) = "Integer" then return v.ToStr()
    if Type(v) = "roFloat" or Type(v) = "Float" or Type(v) = "roDouble" or Type(v) = "Double" then return Int(v).ToStr()
    if Type(v) = "roBoolean" or Type(v) = "Boolean" then
        if v then return "true"
        return "false"
    end if
    return ""
end function

function PlaybackCaps_canDecodeVideo(di as object, fmt as object) as boolean
    r = invalid
    try
        r = di.CanDecodeVideo(fmt)
    catch e
        r = invalid ' e: a simulator without the probe; "no" is the safe answer
        if e = invalid then r = invalid
    end try
    return r <> invalid and Type(r) = "roAssociativeArray" and PlaybackCaps_truthy(r.Result)
end function

function PlaybackCaps_canDecodeAudio(di as object, fmt as object) as boolean
    r = invalid
    try
        r = di.CanDecodeAudio(fmt)
    catch e
        r = invalid ' e: a simulator without the probe; "no" is the safe answer
        if e = invalid then r = invalid
    end try
    if r = invalid or Type(r) <> "roAssociativeArray" or not PlaybackCaps_truthy(r.Result) then return false
    ' A PassThru probe that the device answered by changing the passthrough flag is a "no".
    if fmt.DoesExist("passthru") and r.passthru <> invalid and not PlaybackCaps_truthy(r.passthru) then return false
    return true
end function

' true / 1 / "true" / "1" as a boolean. The device may report a flag as Boolean or Integer, and
' comparing an Integer with a Boolean throws Type Mismatch on a real Roku.
function PlaybackCaps_truthy(v as dynamic) as boolean
    t = Type(v)
    if t = "roBoolean" or t = "Boolean" then return v
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roLongInteger" or t = "LongInteger" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return v <> 0
    if t = "roString" or t = "String" then
        l = LCase(v.Trim())
        return l = "true" or l = "1"
    end if
    return false
end function

' client_features we advertise. We don't implement seek_reanchor or header refresh.
function PlaybackCaps_clientFeatures() as object
    return ["playback_plan_v3"]
end function

' client_capabilities block.
function PlaybackCaps_clientCapabilities() as object
    p = PlaybackCaps_probe()
    hd = PlaybackCaps_hdrDetails()
    return {
        video_evidence: "declared"
        audio_evidence: "declared"
        codecs_video: p.codecsVideo
        codecs_video_hardware: p.codecsVideo
        codecs_audio: p.codecsAudio
        containers: p.containers
        max_resolution: p.maxResolution
        hdr: PlaybackCaps_anyHdr(hd)
        hdr_details: hd
        audio_passthrough: PlaybackCaps_audioPassthrough()
        video_decode: p.videoDecode
    }
end function

function PlaybackCaps_anyHdr(hd as object) as boolean
    return hd.hdr10 = true or hd.hdr10_plus = true or hd.hlg = true or Arr_or(hd.dolby_vision_profiles).Count() > 0
end function

' audio_passthrough block: the codecs the HDMI path takes as a bitstream and the output's channel
' count. No per-codec entries: Roku cannot attest sink layouts, so this stays informational.
function PlaybackCaps_audioPassthrough() as object
    p = PlaybackCaps_probe()
    return {
        passthrough_codecs: p.passthroughAudio
        spatializer_enabled: false
        max_channels: p.audioChannels
        entries: []
    }
end function

function PlaybackCaps_subtitles() as object
    ' The Roku Video node renders WebVTT/SRT sidecars only; bitmap and ASS styling need a burn-in.
    return {
        sidecar_text: true
        embedded_text: false
        ass_styling: false
        embedded_bitmap: false
        sidecar_bitmap: false
        font_attachments: false
    }
end function

' One delivery class. No max_channels: the Roku downmixes or passes through by itself, and a
' channel ceiling here would make the server refuse direct play of a 5.1 file on a stereo TV.
function PlaybackCaps_delivery(containers as object, features as object, hlsRoute = false as boolean) as object
    p = PlaybackCaps_probe()
    audioCodecs = p.codecsAudio
    passthrough = p.passthroughAudio
    videoCodecs = p.codecsVideo
    hdr = PlaybackCaps_hdrDetails()
    claims = []
    if hlsRoute then
        ' Roku's HLS player does not take audio muxed into fMP4 (CMAF) segments (Roku streaming
        ' specifications: "muxing audio and video not supported for CMAF"), and Silo's HLS remux
        ' copies the video into fMP4 with the audio muxed in, so every server_remux_hls plan
        ' played silent on device (v0.1.12/13). Silo packages MPEG-TS only when it transcodes the
        ' video to H.264, so this delivery declares exactly what Roku can play from it: H.264,
        ' SDR, AAC/MP3. HEVC copies are then impossible over HLS (the server keeps them for
        ' direct play), and anything that needs a server-side change comes as an H.264 TS
        ' transcode with sound. An H.264 remux copy would still be fMP4; PlayerScreen asks the
        ' server for another route when a remux_hls plan arrives (maybeRecoverSilentRemux).
        videoCodecs = ["h264"]
        audioCodecs = []
        for each c in p.codecsAudio
            if c = "aac" or c = "mp3" then audioCodecs.Push(c)
        end for
        passthrough = []
        hdr = { hdr10: false, hdr10_plus: false, hlg: false, dolby_vision_profiles: [] }
    else
        ' A Dolby Vision profile 8 file whose DV layer the output cannot take still plays as its
        ' HDR10/HLG base layer through the ordinary HEVC decoder (what Roku does with DV8 content
        ' on a non-DV display), so the server need not strip it into a remux.
        claims.Push("client_dv8_base_layer_fallback_v1")
        ' The Video node switches audio tracks inside a direct-played MKV/MP4 (availableAudioTracks),
        ' so a non-default track chosen on the details page need not force a remux: the server
        ' keeps original_http and names the track in selected_tracks; PlayerScreen applies it.
        claims.Push("client_selected_audio_track_v1")
    end if
    return {
        enabled: true
        supported_on_device: true
        containers: containers
        video_codecs: videoCodecs
        audio_decode_codecs: audioCodecs
        audio_passthrough_codecs: passthrough
        hdr_details: hdr
        subtitles: PlaybackCaps_subtitles()
        features: features
        transformations: []
        validated_claims: claims
        auth_header_refresh: false
    }
end function

' client_playback_context block.
function PlaybackCaps_playbackContext() as object
    p = PlaybackCaps_probe()
    hd = PlaybackCaps_hdrDetails()
    sink = "local_output"
    if p.passthroughAudio.Count() > 0 then sink = "passthrough_sink"
    output = {
        hdr_details: hd
        audio_passthrough: PlaybackCaps_audioPassthrough()
        current_sink: sink
        sink_type: "hdmi"
    }
    ' The display block carries the panel's own HDR types with exact evidence when the Roku could
    ' read them (an SDR TV is then a confirmed SDR output). Without GetDisplayProperties the block
    ' is omitted and the server falls back to output.hdr_details.
    if p.display.known then
        output.display = {
            hdr_evidence: "exact"
            hdr_types: hd
        }
    end if
    return {
        protocol_version: 3
        form_factor: "tv"
        app_version: App_version()
        app_channel: "sideload"
        device: p.device
        output: output
        deliveries: {
            original_http: PlaybackCaps_delivery(p.containers, [])
            hls: PlaybackCaps_delivery(["m3u8", "hls"], ["hls"], true)
        }
    }
end function

' POST /api/v2/playback/start body. startPosition: invalid = server resume, 0 = start over.
function PlaybackCaps_startBody(installation as string, fileId as string, attemptId as string, startPosition as dynamic, audioTrackId as dynamic, subtitleTrackId as dynamic) as object
    quality = PlaybackCaps_qualityPreference()
    body = {
        protocol_version: 3
        installation_id: installation
        file_id: fileId
        profile_id: m.global.session.profileId
        playback_attempt_id: attemptId
        client_features: PlaybackCaps_clientFeatures()
        quality_preference: quality
        subtitle_fidelity_preference: "compatible"
        metered: false
        progress_persistence: "server"
        client_capabilities: PlaybackCaps_clientCapabilities()
        client_playback_context: PlaybackCaps_playbackContext()
    }
    if startPosition <> invalid and startPosition >= 0 then body.start_position = startPosition
    cap = PlaybackCaps_bandwidthCap(quality)
    if cap > 0 then body.bandwidth_cap_kbps = cap
    if not Str_isEmpty(audioTrackId) then body.audio_track_id = audioTrackId
    if not Str_isEmpty(subtitleTrackId) then body.subtitle_track_id = subtitleTrackId
    return body
end function

' POST /api/v2/playback/{session}/replan body for a quality or output change. The replan replaces
' the session's cap (the server copies bandwidth_cap_kbps from every replan), so it is sent again.
function PlaybackCaps_replanBody(installation as string, attemptId as string, plan as object, operation as string, qualityPreference as string, positionSeconds as float, selectedTracks as object, failure = invalid as dynamic) as object
    di = CreateObject("roDeviceInfo")
    body = {
        protocol_version: 3
        installation_id: installation
        client_features: PlaybackCaps_clientFeatures()
        operation: operation
        playback_attempt_id: attemptId
        replan_request_id: di.GetRandomUUID()
        failed_plan_id: Str_orEmpty(plan.plan_id)
        plan_attempt_id: di.GetRandomUUID()
        plan_attempt_key: Str_orEmpty(plan.plan_attempt_key)
        attempted_plan_keys: [Str_orEmpty(plan.plan_attempt_key)]
        attempt_count: 1
        quality_preference: qualityPreference
        position_seconds: positionSeconds
        metered: false
        selected_tracks: selectedTracks
        client_capabilities: PlaybackCaps_clientCapabilities()
        client_playback_context: PlaybackCaps_playbackContext()
    }
    cap = PlaybackCaps_bandwidthCap(qualityPreference)
    if cap > 0 then body.bandwidth_cap_kbps = cap
    if failure <> invalid then body.failure = failure
    return body
end function

' playback.max_bitrate_kbps (the bandwidth half of the Quality preset; 0 = uncapped). The server
' treats the cap as a hard ceiling that outranks "original" (ResolveQualityPolicyV3), and a cap
' inherited from the profile scope would turn "Original" into a 720p transcode, so "Original"
' (never transcode) sends no cap at all.
function PlaybackCaps_bandwidthCap(quality as string) as integer
    if LCase(quality) = "original" then return 0
    cap = Settings_maxBitrateKbps()
    if cap < 100 then return 0
    return cap
end function

' playback.preferred_quality (server, profile_device scope) with the device pref as fallback.
function PlaybackCaps_qualityPreference() as string
    return Settings_quality()
end function

' The HDR block we advertise: the display's types, then the user's choices, as Android TV's
' DolbyVisionPolicy and DisplayHdrProbe apply them:
'  - HDR off (player.hdr_enabled): nothing is HDR; the server tone-maps to SDR.
'  - Dolby Vision off: the DV profiles are dropped so the server serves the HDR10 base layer.
'  - Profile 7 HDR10 Fallback on: profile 7 is not declared, so dual-layer files come as their
'    HDR10 base layer (server strip); off declares 7 and the file plays as-is through the HEVC
'    decoder, which presents the base layer.
'  - Force HDR Passthrough: HDR10 / HDR10+ / HLG are declared even when the TV does not report
'    them (Roku's own HDR→SDR conversion then applies). Dolby Vision still needs the display's word.
function PlaybackCaps_hdrDetails() as object
    p = PlaybackCaps_probe()
    d = p.display
    force = Settings_forceHdrPassthrough()
    hdr10 = d.hdr10 or force
    hdr10plus = d.hdr10Plus or force
    hlg = d.hlg or force
    dvProfiles = []
    if d.dolbyVision and Settings_dolbyVision() then
        ' Roku Dolby Vision devices decode profiles 5 and 8 (8.1 HDR10-compatible, 8.4 HLG-compatible).
        dvProfiles = [5, 8]
        if not Settings_dvProfile7Fallback() then dvProfiles = [5, 7, 8]
    end if
    if not Settings_hdrEnabled() then
        hdr10 = false
        hdr10plus = false
        hlg = false
        dvProfiles = []
    end if
    out = {
        hdr10: hdr10
        hdr10_plus: hdr10plus
        hlg: hlg
        dolby_vision_profiles: dvProfiles
    }
    ' HDR10 ceilings are the decoder's (the server only accepts them with hdr10 true): a 4K
    ' decoder takes 3840x2160, a 1080p one 1920x1080, both at 60 fps. No Dolby Vision levels:
    ' Roku does not expose them, and an omitted list means "any level" to the server.
    if hdr10 then
        out.hdr10_max_width = 1920
        out.hdr10_max_height = 1080
        if p.decodes4K or p.maxResolution = "2160p" then
            out.hdr10_max_width = 3840
            out.hdr10_max_height = 2160
        end if
        out.hdr10_max_frame_rate = 60
    end if
    return out
end function

' Validation the Android client performs before handing a plan to the player.
function PlaybackCaps_planProblem(decision as object) as string
    if decision = invalid then return "The server sent an empty playback plan."
    if decision.protocol_version <> 3 then return "The server answered with an unsupported playback protocol."
    features = Arr_or(decision.server_features)
    hasPlan = false
    hasNeutral = false
    for each f in features
        if f = "playback_plan_v3" then hasPlan = true
        if f = "neutral_playback_v3_contract_v1" then hasNeutral = true
    end for
    if not hasPlan or not hasNeutral then return "The server's playback contract is not supported."
    plan = decision.playback_plan
    if plan = invalid then return "The server sent no playback plan."
    if Str_isEmpty(plan.plan_attempt_key) then return "The playback plan is incomplete."
    if plan.stream = invalid or Str_isEmpty(plan.stream.url) then return "The playback plan has no stream."
    if plan.stream.header_refresh = "refresh_endpoint" then return "This stream needs header refresh, which Roku can't do."
    return ""
end function

' ---------- Diagnostics ----------

' One line for the debug console (telnet 8085), printed once per start/replan:
' what we declared, what we asked for, and what the server decided.
function PlaybackCaps_diagLine(body as object, plan as object) as string
    if body = invalid then body = {}
    p = PlaybackCaps_probe()
    hd = PlaybackCaps_hdrDetails()
    dvs = []
    for each pr in Arr_or(hd.dolby_vision_profiles)
        dvs.Push(PlaybackCaps_str(pr))
    end for
    decode = []
    for each k in p.audioDecodeInfo
        decode.Push(k + "=" + PlaybackCaps_str(p.audioDecodeInfo[k]))
    end for
    vdec = []
    for each e in p.videoDecode
        frame = "size?"
        if e.max_height <> invalid then frame = PlaybackCaps_str(e.max_width) + "x" + PlaybackCaps_str(e.max_height) + "p" + PlaybackCaps_str(e.max_frame_rate)
        vdec.Push(e.codec + ":" + PlaybackCaps_join(e.profiles, "/") + "@" + PlaybackCaps_join(e.levels, "/") + " " + frame + " " + PlaybackCaps_join(e.bit_depths, "/") + "bit")
    end for
    caps = "res=" + p.maxResolution + " 4kdec=" + PlaybackCaps_str(p.decodes4K) + " mode=" + p.videoMode + " fps=" + PlaybackCaps_str(p.outputFps) + " type=" + p.displayType + " ui=" + p.uiResolution
    caps = caps + " video=" + PlaybackCaps_join(p.codecsVideo) + " decoders=[" + PlaybackCaps_join(vdec, "; ") + "] audio=" + PlaybackCaps_join(p.codecsAudio)
    caps = caps + " passthru=" + PlaybackCaps_join(p.passthroughAudio) + " surround=" + PlaybackCaps_join(p.surroundAudio)
    caps = caps + " out=" + p.audioOutput + " decodeinfo=" + PlaybackCaps_join(decode)
    caps = caps + " forcedolby=" + PlaybackCaps_str(p.forcedDolby) + " forcehdr=" + PlaybackCaps_str(Settings_forceHdrPassthrough())
    caps = caps + " display=" + PlaybackCaps_str(p.display.known) + " hdr10=" + PlaybackCaps_str(hd.hdr10) + " hdr10+=" + PlaybackCaps_str(hd.hdr10_plus) + " hlg=" + PlaybackCaps_str(hd.hlg) + " dv=" + PlaybackCaps_join(dvs)
    ' Raw display report and model, so a missing Dolby Vision or HDR flag can be traced on device.
    di = CreateObject("roDeviceInfo")
    rawDisplay = "-"
    try
        ' Only scalar fields: the AA also carries the EDID as a roByteArray, which FormatJson rejects.
        raw = di.GetDisplayProperties()
        if raw <> invalid and Type(raw) = "roAssociativeArray" then
            flat = {}
            for each k in raw
                t = Type(raw[k])
                if t = "roBoolean" or t = "Boolean" or t = "roInt" or t = "roInteger" or t = "Integer" or t = "roFloat" or t = "Float" or t = "roString" or t = "String" then flat[k] = raw[k]
            end for
            rawDisplay = FormatJson(flat)
        end if
    catch e
        rawDisplay = "-" ' e: older firmware without GetDisplayProperties
        if e = invalid then rawDisplay = "-"
    end try
    caps = caps + " model=" + PlaybackCaps_str(di.GetModel()) + " displayprops=" + rawDisplay
    if hd.hdr10_max_height <> invalid then caps = caps + " hdr10max=" + PlaybackCaps_str(hd.hdr10_max_width) + "x" + PlaybackCaps_str(hd.hdr10_max_height) + "p" + PlaybackCaps_str(hd.hdr10_max_frame_rate)
    req = "quality=" + Str_orEmpty(body.quality_preference) + " cap=" + PlaybackCaps_str(body.bandwidth_cap_kbps) + " metered=" + PlaybackCaps_str(body.metered)
    if not Str_isEmpty(body.operation) then req = req + " op=" + body.operation
    req = req + " audio_req=" + Str_orEmpty(body.audio_track_id) + " sub_req=" + Str_orEmpty(body.subtitle_track_id)
    dec = "none"
    if plan <> invalid then
        dec = "delivery=" + Str_orEmpty(plan.delivery) + " reason=" + Str_orEmpty(plan.decision_reason)
        if plan.selected_tracks <> invalid and plan.selected_tracks.audio <> invalid then dec = dec + " sel_audio=" + PlaybackCaps_str(plan.selected_tracks.audio.index)
        if plan.subtitle <> invalid then dec = dec + " sub_mode=" + Str_orEmpty(plan.subtitle.mode)
        r = plan.effective_recipe
        if r <> invalid then
            dec = dec + " recipe=" + Str_orEmpty(r.video_codec) + " " + PlaybackCaps_str(r.width) + "x" + PlaybackCaps_str(r.height) + " " + Str_orEmpty(r.dynamic_range)
            dec = dec + " " + Str_orEmpty(r.audio_codec) + " " + PlaybackCaps_str(r.audio_channels) + "ch " + PlaybackCaps_str(r.bitrate_kbps) + "kbps"
        end if
        s = plan.source
        if s <> invalid then
            dec = dec + " source=" + Str_orEmpty(s.video_codec) + " " + PlaybackCaps_str(s.width) + "x" + PlaybackCaps_str(s.height) + " " + Str_orEmpty(s.dynamic_range)
            if s.dolby_vision_profile <> invalid then dec = dec + " dv" + PlaybackCaps_str(s.dolby_vision_profile)
            dec = dec + " " + Str_orEmpty(s.audio_codec) + " " + PlaybackCaps_str(s.audio_channels) + "ch " + Str_orEmpty(s.container)
        end if
        warns = []
        for each w in Arr_or(plan.degradation_warnings)
            if w <> invalid and not Str_isEmpty(w.code) then warns.Push(w.code)
        end for
        if warns.Count() > 0 then dec = dec + " warnings=" + PlaybackCaps_join(warns)
    end if
    return "[siku-playback] caps: " + caps + " | request: " + req + " | plan: " + dec
end function

function PlaybackCaps_join(items as object, sep = "," as string) as string
    out = ""
    for each it in items
        s = PlaybackCaps_str(it)
        if s <> "" then
            if out <> "" then out = out + sep
            out = out + s
        end if
    end for
    if out = "" then return "-"
    return out
end function

' ---------- Labels for the player's info panel (TvPlayerHud / TvSubtitleChoiceLabels) ----------

' "Direct Play" / "Remux" / "Transcode" from playback_plan.delivery.
function PlaybackCaps_deliveryLabel(delivery as dynamic) as string
    d = LCase(Str_orEmpty(delivery))
    if d = "" then return ""
    if d = "original_http" then return "Direct Play"
    if Instr(1, d, "transcode") > 0 then return "Transcode"
    if Instr(1, d, "remux") > 0 then return "Remux"
    return d
end function

' Media3 codec ids / server codec names → the short names users know.
function PlaybackCaps_videoCodecLabel(codec as dynamic) as string
    c = LCase(Str_orEmpty(codec)).Trim()
    if c = "" then return ""
    if c = "h264" or c = "avc" or Left(c, 3) = "avc" then return "H.264"
    if c = "hevc" or c = "h265" or Left(c, 3) = "hev" or Left(c, 3) = "hvc" then return "HEVC"
    if Left(c, 3) = "dvh" or Left(c, 3) = "dva" or c = "dolby_vision" then return "Dolby Vision"
    if c = "av1" or Left(c, 4) = "av01" then return "AV1"
    if c = "vp9" or Left(c, 4) = "vp09" then return "VP9"
    if c = "vp8" then return "VP8"
    if c = "mpeg4" or Left(c, 4) = "mp4v" then return "MPEG-4"
    if c = "mpeg2" or c = "mpeg2video" then return "MPEG-2"
    return UCase(c)
end function

function PlaybackCaps_audioCodecLabel(codec as dynamic) as string
    c = LCase(Str_orEmpty(codec)).Trim()
    if c = "" then return ""
    if c = "aac" or c = "mp4a" or c = "mp4a-latm" then return "AAC"
    if c = "ac3" then return "AC3"
    if c = "eac3" then return "E-AC3"
    if c = "eac3-joc" then return "Atmos"
    if c = "truehd" or c = "true-hd" then return "TrueHD"
    if c = "dts" or c = "vnd.dts" then return "DTS"
    if c = "dts-hd" or c = "dts.hd" or c = "dtshd" then return "DTS-HD"
    if c = "opus" then return "Opus"
    if c = "flac" then return "FLAC"
    if c = "mp3" or c = "mpeg" or c = "mpeg-l2" then return "MP3"
    if c = "vorbis" then return "Vorbis"
    if c = "pcm" or c = "raw" or c = "wav" or Left(c, 3) = "pcm" then return "PCM"
    return UCase(c)
end function

' Channel count (and the server's layout, when it names Atmos) → "Stereo", "5.1", "7.1 Atmos".
function PlaybackCaps_channelsLabel(channels as dynamic, layout as dynamic) as string
    n = Int(Num_or(channels, 0))
    l = LCase(Str_orEmpty(layout))
    label = ""
    if n = 1 then
        label = "Mono"
    else if n = 2 then
        label = "Stereo"
    else if n = 6 then
        label = "5.1"
    else if n = 8 then
        label = "7.1"
    else if n > 0 then
        label = n.ToStr() + "ch"
    else if l = "stereo" then
        label = "Stereo"
    else if l = "mono" then
        label = "Mono"
    else if l <> "" then
        label = l
    end if
    if Instr(1, l, "atmos") > 0 or Instr(1, l, "joc") > 0 then label = Str_joinDots([label, "Atmos"], " ")
    return label
end function

' "Dolby Vision" / "HDR10+" / "HDR10" / "HLG" / "SDR" from a dynamic_range string (loose case).
function PlaybackCaps_rangeLabel(range as dynamic) as string
    r = LCase(Str_orEmpty(range)).Trim()
    if r = "" then return ""
    if r = "dolby_vision" or r = "dolbyvision" or r = "dv" then return "Dolby Vision"
    if r = "hdr10_plus" or r = "hdr10+" or r = "hdr10plus" then return "HDR10+"
    if r = "hdr10" or r = "hdr" then return "HDR10"
    if r = "hlg" then return "HLG"
    if r = "sdr" then return "SDR"
    return UCase(r)
end function

' "4K" / "1080p" / "720p" from a frame; the Android facts row says "4K" for 2160 lines.
function PlaybackCaps_resolutionLabel(width as dynamic, height as dynamic) as string
    h = Int(Num_or(height, 0))
    w = Int(Num_or(width, 0))
    if h <= 0 and w <= 0 then return ""
    if h >= 2000 or w >= 3800 then return "4K"
    if h >= 1000 or w >= 1900 then return "1080p"
    if h >= 700 or w >= 1200 then return "720p"
    if h > 0 then return h.ToStr() + "p"
    return w.ToStr() + "w"
end function

function PlaybackCaps_has(arr as object, value as string) as boolean
    for each v in arr
        if v = value then return true
    end for
    return false
end function
