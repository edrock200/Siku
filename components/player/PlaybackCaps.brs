' Builds the protocol-v3 playback bodies (docs/api-spec.md §8.2) from what the Roku device reports.
' Everything here is "declared" evidence: the server matches the flat codec lists and never
' walks video_decode[], so we don't fabricate profile/level entries we cannot observe.
' Modeled on the web client's SV/web/src/player/client-context-v3.ts.
' SPDX-License-Identifier: AGPL-3.0-or-later

' Probes the device once and returns {codecsVideo, codecsAudio, containers, maxResolution, hdr, hdrDetails, device}.
function PlaybackCaps_probe() as object
    if m.playbackProbe <> invalid then return m.playbackProbe
    di = CreateObject("roDeviceInfo")

    codecsVideo = ["h264"]
    for each c in ["hevc", "vp9", "av1"]
        if PlaybackCaps_canDecodeVideo(di, c) then codecsVideo.Push(c)
    end for

    codecsAudio = ["aac", "mp3"]
    for each c in ["ac3", "eac3", "dts", "flac", "opus", "vorbis", "alac"]
        if PlaybackCaps_canDecodeAudio(di, c) then codecsAudio.Push(c)
    end for

    props = di.GetDisplayProperties()
    if props = invalid then props = {}
    hdr10 = props.Hdr10 = true
    hdr10plus = props.Hdr10Plus = true
    hlg = props.Hlg = true
    dolbyVision = props.DolbyVision = true
    hdr = hdr10 or hlg or dolbyVision
    dvProfiles = []
    ' Roku Dolby Vision devices decode profiles 5 and 8 (8.1 HDR10-compatible, 8.4 HLG-compatible).
    if dolbyVision then dvProfiles = [5, 8]
    hdrDetails = {
        hdr10: hdr10
        hdr10_plus: hdr10plus
        hlg: hlg
        dolby_vision_profiles: dvProfiles
    }

    mode = LCase(di.GetVideoMode())
    maxRes = "1080p"
    if Instr(1, mode, "2160") > 0 or Instr(1, mode, "4k") > 0 then maxRes = "2160p"
    if Instr(1, mode, "720") = 1 or Instr(1, mode, "480") = 1 then maxRes = "1080p" ' the box still decodes 1080p

    m.playbackProbe = {
        codecsVideo: codecsVideo
        codecsAudio: codecsAudio
        containers: ["mp4", "m4v", "mov", "mkv"]
        maxResolution: maxRes
        hdr: hdr
        hdrDetails: hdrDetails
        videoMode: mode
        device: {
            platform: "roku"
            os_version: di.GetOSVersion().major + "." + di.GetOSVersion().minor + "." + di.GetOSVersion().revision
            manufacturer: "Roku"
            model: di.GetModel()
            platform_details: {
                model_name: di.GetModelDisplayName()
                video_mode: di.GetVideoMode()
                ui_resolution: di.GetUIResolution().name
            }
        }
    }
    return m.playbackProbe
end function

function PlaybackCaps_canDecodeVideo(di as object, codec as string) as boolean
    r = di.CanDecodeVideo({ Codec: codec })
    return r <> invalid and r.Result = true
end function

function PlaybackCaps_canDecodeAudio(di as object, codec as string) as boolean
    r = di.CanDecodeAudio({ Codec: codec })
    return r <> invalid and r.Result = true
end function

' client_features we advertise. We don't implement seek_reanchor or header refresh.
function PlaybackCaps_clientFeatures() as object
    return ["playback_plan_v3"]
end function

' client_capabilities block.
function PlaybackCaps_clientCapabilities() as object
    p = PlaybackCaps_probe()
    return {
        video_evidence: "declared"
        audio_evidence: "declared"
        codecs_video: p.codecsVideo
        codecs_video_hardware: p.codecsVideo
        codecs_audio: p.codecsAudio
        containers: p.containers
        max_resolution: p.maxResolution
        hdr: p.hdr
        hdr_details: PlaybackCaps_hdrDetails()
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

function PlaybackCaps_delivery(containers as object, features as object) as object
    p = PlaybackCaps_probe()
    return {
        enabled: true
        supported_on_device: true
        containers: containers
        video_codecs: p.codecsVideo
        audio_decode_codecs: p.codecsAudio
        audio_passthrough_codecs: []
        hdr_details: PlaybackCaps_hdrDetails()
        subtitles: PlaybackCaps_subtitles()
        features: features
        transformations: []
        validated_claims: []
        auth_header_refresh: false
    }
end function

' client_playback_context block.
function PlaybackCaps_playbackContext() as object
    p = PlaybackCaps_probe()
    hdrEvidence = "unknown"
    if p.hdr then hdrEvidence = "exact"
    return {
        protocol_version: 3
        form_factor: "tv"
        app_version: App_version()
        app_channel: "sideload"
        device: p.device
        output: {
            hdr_details: PlaybackCaps_hdrDetails()
            sink_type: "hdmi"
            display: {
                hdr_evidence: hdrEvidence
                hdr_types: PlaybackCaps_hdrDetails()
            }
        }
        deliveries: {
            original_http: PlaybackCaps_delivery(p.containers, [])
            hls: PlaybackCaps_delivery(["m3u8", "hls"], ["hls"])
        }
    }
end function

' POST /api/v2/playback/start body. startPosition: invalid = server resume, 0 = start over.
function PlaybackCaps_startBody(installation as string, fileId as string, attemptId as string, startPosition as dynamic, audioTrackId as dynamic, subtitleTrackId as dynamic) as object
    body = {
        protocol_version: 3
        installation_id: installation
        file_id: fileId
        profile_id: m.global.session.profileId
        playback_attempt_id: attemptId
        client_features: PlaybackCaps_clientFeatures()
        quality_preference: PlaybackCaps_qualityPreference()
        subtitle_fidelity_preference: "compatible"
        metered: false
        progress_persistence: "server"
        client_capabilities: PlaybackCaps_clientCapabilities()
        client_playback_context: PlaybackCaps_playbackContext()
    }
    if startPosition <> invalid and startPosition >= 0 then body.start_position = startPosition
    ' playback.max_bitrate_kbps (the bandwidth half of the Quality preset; 0 = uncapped).
    cap = Settings_maxBitrateKbps()
    if cap > 0 then body.bandwidth_cap_kbps = cap
    if not Str_isEmpty(audioTrackId) then body.audio_track_id = audioTrackId
    if not Str_isEmpty(subtitleTrackId) then body.subtitle_track_id = subtitleTrackId
    return body
end function

' POST /api/v2/playback/{session}/replan body for a quality change.
function PlaybackCaps_replanBody(installation as string, attemptId as string, plan as object, operation as string, qualityPreference as string, positionSeconds as float, selectedTracks as object) as object
    di = CreateObject("roDeviceInfo")
    return {
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
end function

' playback.preferred_quality (server, profile_device scope) with the device pref as fallback.
function PlaybackCaps_qualityPreference() as string
    return Settings_quality()
end function

' The HDR block we advertise. Settings → Playback → Dolby Vision off drops the DV profiles so the
' server serves the HDR10 base layer instead (Android's DolbyVisionPolicy does the same).
function PlaybackCaps_hdrDetails() as object
    p = PlaybackCaps_probe()
    d = AA_copy(p.hdrDetails)
    if not Settings_dolbyVision() then d.dolby_vision_profiles = []
    return d
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
