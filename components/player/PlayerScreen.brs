' Video player: v3 sequenced playback pipeline, custom controls, HUD, skip markers and Up Next.
' See PlayerScreen.xml for the contract and docs/api-spec.md §8 for the protocol.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.video = m.top.findNode("video")
    m.videoFrame = m.top.findNode("videoFrame")
    m.focusSink = m.top.findNode("focusSink")
    m.bufferingGroup = m.top.findNode("bufferingGroup")
    m.bufferSpinner = m.top.findNode("bufferSpinner")
    m.feedbackGroup = m.top.findNode("feedbackGroup")
    m.feedbackLabel = m.top.findNode("feedbackLabel")
    m.controls = m.top.findNode("controls")
    m.titleLabel = m.top.findNode("titleLabel")
    m.epTag = m.top.findNode("epTag")
    m.scrubber = m.top.findNode("scrubber")
    m.transport = m.top.findNode("transport")
    m.skipBackBtn = m.top.findNode("skipBackBtn")
    m.playPauseBtn = m.top.findNode("playPauseBtn")
    m.skipFwdBtn = m.top.findNode("skipFwdBtn")
    m.upNextBtn = m.top.findNode("upNextBtn")
    m.subtitlesBtn = m.top.findNode("subtitlesBtn")
    m.tuneBtn = m.top.findNode("tuneBtn")
    m.closeBtn = m.top.findNode("closeBtn")
    m.skipGroup = m.top.findNode("skipGroup")
    m.skipBtn = m.top.findNode("skipBtn")
    m.skippedCaption = m.top.findNode("skippedCaption")
    m.hud = m.top.findNode("hud")
    m.hudTabsGroup = m.top.findNode("hudTabs")
    m.hudBg = m.top.findNode("hudBg")
    m.hudRing = m.top.findNode("hudRing")
    m.hudRowsGroup = m.top.findNode("hudRows")
    m.upNext = m.top.findNode("upNext")
    m.unEyebrow = m.top.findNode("unEyebrow")
    m.unSeries = m.top.findNode("unSeries")
    m.unEpisode = m.top.findNode("unEpisode")
    m.unMeta = m.top.findNode("unMeta")
    m.unOverview = m.top.findNode("unOverview")
    m.unPlayBtn = m.top.findNode("unPlayBtn")
    m.unPickBtn = m.top.findNode("unPickBtn")
    m.unKeepBtn = m.top.findNode("unKeepBtn")
    m.unBackBtn = m.top.findNode("unBackBtn")
    m.unStopBtn = m.top.findNode("unStopBtn")
    m.unScope = m.top.findNode("unScope")
    m.unScopeBg = m.top.findNode("unScopeBg")
    m.unScopeLabel = m.top.findNode("unScopeLabel")
    m.errorGroup = m.top.findNode("errorGroup")
    m.errorLabel = m.top.findNode("errorLabel")
    m.retryBtn = m.top.findNode("retryBtn")
    m.errorCloseBtn = m.top.findNode("errorCloseBtn")
    m.picker = m.top.findNode("picker")
    m.progressTimer = m.top.findNode("progressTimer")
    m.hideTimer = m.top.findNode("hideTimer")
    m.feedbackTimer = m.top.findNode("feedbackTimer")
    m.countdownTimer = m.top.findNode("countdownTimer")
    m.holdTimer = m.top.findNode("holdTimer")
    m.refreshTimeout = m.top.findNode("refreshTimeout")
    m.stopTimeout = m.top.findNode("stopTimeout")
    m.captionTimer = m.top.findNode("captionTimer")

    m.di = CreateObject("roDeviceInfo")
    m.started = false
    m.autoAdvances = 0   ' consecutive Up Next countdowns that played by themselves (Still Watching Prompt)
    ' The running shuffle this player plays picks from ({id, latest, exhausted}); invalid outside a
    ' shuffle. It outlives resetPlaybackState() because it spans every chained pick.
    m.shuffle = invalid
    m.upNextButtons = []
    resetPlaybackState()

    m.video.observeField("state", "onVideoState")
    m.video.observeField("position", "onVideoPosition")
    m.video.observeField("duration", "onVideoDuration")
    m.progressTimer.observeField("fire", "onProgressTick")
    m.hideTimer.observeField("fire", "hideControls")
    m.feedbackTimer.observeField("fire", "hideFeedback")
    m.countdownTimer.observeField("fire", "onCountdownTick")
    m.holdTimer.observeField("fire", "onHoldTick")
    m.refreshTimeout.observeField("fire", "onTokenRefreshed")
    m.stopTimeout.observeField("fire", "finishClose")
    m.captionTimer.observeField("fire", "hideCaption")

    m.skipBackBtn.observeField("buttonSelected", "onSkipBack")
    m.playPauseBtn.observeField("buttonSelected", "togglePlay")
    m.skipFwdBtn.observeField("buttonSelected", "onSkipForward")
    m.upNextBtn.observeField("buttonSelected", "onUpNextButton")
    m.subtitlesBtn.observeField("buttonSelected", "onSubtitlesButton")
    m.tuneBtn.observeField("buttonSelected", "onTuneButton")
    m.closeBtn.observeField("buttonSelected", "exitPlayer")
    m.skipBtn.observeField("buttonSelected", "onSkipPill")
    m.unPlayBtn.observeField("buttonSelected", "onPlayNowButton")
    m.unPickBtn.observeField("buttonSelected", "pickAnother")
    m.unKeepBtn.observeField("buttonSelected", "keepWatching")
    m.unBackBtn.observeField("buttonSelected", "exitPlayer")
    m.unStopBtn.observeField("buttonSelected", "stopShuffling")
    m.retryBtn.observeField("buttonSelected", "retry")
    m.errorCloseBtn.observeField("buttonSelected", "exitPlayer")
    m.picker.observeField("chosen", "onPickerChosen")
    m.picker.observeField("dismissed", "onPickerDismissed")
    Subs_init()
end sub

' State for one playback attempt (reset again when Up Next chains to another episode).
sub resetPlaybackState()
    m.watch = invalid
    m.fileId = ""
    m.version = invalid
    m.plan = invalid
    m.sessionId = ""
    m.sequence = 0
    m.stopId = ""
    m.attemptId = m.di.GetRandomUUID()
    m.retriedInstall = false
    m.timelineOffset = 0.0
    m.duration = 0.0
    m.position = 0.0
    m.isPaused = false
    m.markers = []
    m.chapters = []
    m.subtitleTracks = []
    m.subtitleIndex = -1
    m.pendingSubtitleTrackId = ""
    m.qualityPref = PlaybackCaps_qualityPreference()
    m.skipShownFor = ""
    m.autoSkipped = {}
    m.activeMarker = invalid
    m.nextEpisode = invalid
    m.nextIsEpisode = true
    m.seriesTitle = ""
    m.shuffleRefreshed = false
    m.shuffleAdvancing = false
    m.shufflePicking = false
    m.forceSubtitlesOff = false
    m.upNextShown = false
    m.upNextDismissed = false
    m.countdown = -1
    m.scrubbing = false
    m.scrubPos = 0.0
    m.holdTicks = 0
    m.controlsZone = "transport"
    m.transportIndex = 1
    m.hudTab = 0
    m.hudFocus = "tabs"
    m.hudRow = 0
    m.hudRows = []
    m.hudTabs = []
    m.hudChoices = []
    m.pickerKind = ""
    m.closing = false
    m.finished = false
    m.resumeAfterStart = invalid
    m.watchBackTarget = invalid
    m.waitingForToken = false
    if m.subs <> invalid then Subs_resetPlayback()
end sub

' ---------- Lifecycle ----------

sub onScreenShown()
    if not m.started then
        m.started = true
        startPipeline()
        return
    end if
    restoreFocus()
end sub

sub restoreFocus()
    if m.errorGroup.visible then
        m.retryBtn.setFocus(true)
    else if m.picker.visible then
        m.picker.setFocus(true)
    else if m.subsDialog.visible then
        m.subsDialog.setFocus(true)
    else if m.upNext.visible then
        focusUpNext()
    else if m.hud.visible then
        focusHud()
    else if m.controls.visible then
        focusControls()
    else if m.skipGroup.visible and m.skipBtn.visible then
        m.skipBtn.setFocus(true)
    else
        m.focusSink.setFocus(true)
    end if
end sub

' ---------- Pipeline ----------

sub startPipeline()
    p = m.top.params
    if p = invalid then p = {}
    m.itemId = Str_orEmpty(p.itemId)
    ' A shuffle pick: remember the shuffle (and the Shuffle the start returned, so the first pick's
    ' `next` is known without another read).
    if not Str_isEmpty(p.shuffleId) then
        if m.shuffle = invalid or m.shuffle.id <> p.shuffleId then m.shuffle = { id: Str_orEmpty(p.shuffleId), latest: p.shuffle, exhausted: false }
    end if
    m.forceSubtitlesOff = p.subtitleTrackIndex <> invalid and p.subtitleTrackIndex = -1
    m.errorGroup.visible = false
    setBuffering(true)
    m.focusSink.setFocus(true)
    m.titleLabel.text = Str_orEmpty(p.title)
    if m.itemId = "" then
        showError("Nothing to play.")
        return
    end if
    Api_get("/api/v2/watch/" + Str_urlEncode(m.itemId), { image_size: "medium" }, "onWatch")
end sub

sub retry()
    m.errorGroup.visible = false
    stopSession()
    m.video.control = "stop"
    resetPlaybackState()
    startPipeline()
end sub

sub onWatch(event as object)
    resp = Api_result(event)
    if m.closing then return
    if not resp.ok or resp.data = invalid then
        showError(Api_errorText(resp))
        return
    end if
    w = resp.data
    m.watch = w
    p = m.top.params
    if Str_isEmpty(m.titleLabel.text) then m.titleLabel.text = Str_orEmpty(w.title)
    m.isEpisode = LCase(Str_orEmpty(w.type)) = "episode"
    m.seriesTitle = Str_orEmpty(w.series_title)
    if m.isEpisode then
        tag = Content_seShort(w.season_number, w.episode_number).Replace(" · ", "·")
        if m.seriesTitle <> "" then
            m.titleLabel.text = m.seriesTitle
            m.epTag.text = Str_joinDots([tag, w.title])
        else
            m.epTag.text = tag
        end if
    else
        m.epTag.text = ""
    end if
    m.epTag.visible = m.epTag.text <> ""

    ' Choose the file: explicit param, the user's last file, the default variant, else the first version.
    versions = Arr_or(w.versions)
    fileId = Str_orEmpty(p.fileId)
    if fileId = "" and w.user_data <> invalid then fileId = Str_orEmpty(w.user_data.last_file_id)
    if fileId <> "" then
        ok = false
        for each v in versions
            if Str_orEmpty(v.file_id) = fileId then ok = true
        end for
        if not ok then fileId = ""
    end if
    if fileId = "" then
        for each pv in Arr_or(w.playback_variants)
            if fileId = "" and not Str_isEmpty(pv.default_file_id) then fileId = Str_orEmpty(pv.default_file_id)
        end for
    end if
    if fileId = "" and versions.Count() > 0 then fileId = Str_orEmpty(versions[0].file_id)
    if fileId = "" then
        showError("This title has no playable file.")
        return
    end if
    m.fileId = fileId
    m.version = invalid
    for each v in versions
        if Str_orEmpty(v.file_id) = fileId then m.version = v
    end for
    collectMarkers()
    if m.version <> invalid then m.chapters = Arr_or(m.version.chapters)
    m.scrubber.markers = m.markers
    m.scrubber.chapters = m.chapters
    if m.version <> invalid and m.version.duration_seconds <> invalid then m.duration = m.version.duration_seconds
    if m.duration = 0 and w.user_data <> invalid and w.user_data.duration_seconds <> invalid then m.duration = w.user_data.duration_seconds
    m.scrubber.duration = m.duration

    if m.shuffle <> invalid then
        ' A shuffle replaces the series order: the server names what plays next.
        resolveShuffleNext()
    else if m.isEpisode then
        resolveNextEpisode()
    end if
    ensureFreshToken()
end sub

' Markers in {kind, start, end} form; marker_segments preferred, then per-version and top-level fields.
sub collectMarkers()
    out = []
    w = m.watch
    segs = []
    if m.version <> invalid then segs = Arr_or(m.version.marker_segments)
    if segs.Count() > 0 then
        for each s in segs
            if s.start_seconds <> invalid and s.end_seconds <> invalid then
                out.Push({ kind: LCase(Str_orEmpty(s.kind)), start: s.start_seconds * 1.0, "end": s.end_seconds * 1.0 })
            end if
        end for
    else
        for each kind in ["intro", "recap", "credits"]
            mk = invalid
            if m.version <> invalid and m.version[kind] <> invalid then mk = m.version[kind]
            if mk = invalid then mk = w[kind]
            if mk <> invalid then
                s = mk.start_seconds
                e = mk.end_seconds
                if s = invalid then s = mk.start
                if e = invalid then e = mk["end"]
                if s <> invalid and e <> invalid then out.Push({ kind: kind, start: s * 1.0, "end": e * 1.0 })
            end if
        end for
    end if
    m.markers = out
end sub

' Refresh the token first when it is about to expire: the Video node can't refresh headers mid-stream.
sub ensureFreshToken()
    s = m.global.session
    if not Str_isEmpty(s.refreshToken) and s.expiresAt > 0 and s.expiresAt - Time_nowSeconds() < 300 then
        auth = m.global.authTask
        if auth <> invalid then
            m.waitingForToken = true
            auth.observeField("generation", "onTokenRefreshed")
            m.refreshTimeout.control = "start"
            auth.refreshRequest = { token: s.accessToken }
            return
        end if
    end if
    fetchCapabilities()
end sub

sub onTokenRefreshed()
    if m.waitingForToken <> true then return
    m.waitingForToken = false
    m.refreshTimeout.control = "stop"
    auth = m.global.authTask
    if auth <> invalid then auth.unobserveField("generation")
    if m.closing then return
    fetchCapabilities()
end sub

function cachedCaps() as dynamic
    if not m.global.hasField("playbackCaps") then return invalid
    c = m.global.playbackCaps
    if c = invalid or Str_isEmpty(c.installation_id) then return invalid
    return c
end function

sub fetchCapabilities()
    c = cachedCaps()
    if c <> invalid then
        startSession(c.installation_id)
        return
    end if
    Api_get("/api/v2/playback/capabilities", invalid, "onCapabilities")
end sub

sub onCapabilities(event as object)
    resp = Api_result(event)
    if m.closing then return
    if not resp.ok or resp.data = invalid then
        showError(Api_errorText(resp))
        return
    end if
    caps = resp.data
    hasV3 = false
    for each v in Arr_or(caps.protocol_versions)
        if v = 3 then hasV3 = true
    end for
    hasSeq = false
    for each f in Arr_or(caps.features)
        if f = "sequenced_progress_v1" then hasSeq = true
    end for
    if caps.state <> "available" or caps.allowed <> true or not hasV3 or not hasSeq or Str_isEmpty(caps.installation_id) then
        showError("Playback isn't available on this server.")
        return
    end if
    entry = { installation_id: caps.installation_id, features: Arr_or(caps.features), fetchedAt: Time_nowSeconds() }
    if m.global.hasField("playbackCaps") then
        m.global.playbackCaps = entry
    else
        m.global.addFields({ playbackCaps: entry })
    end if
    startSession(caps.installation_id)
end sub

function installationId() as string
    c = cachedCaps()
    if c = invalid then return ""
    return c.installation_id
end function

sub startSession(installation as string)
    p = m.top.params
    startPos = invalid
    if p.startPosition <> invalid then
        spv = p.startPosition
        if (Type(spv) = "roInt" or Type(spv) = "Integer" or Type(spv) = "roFloat" or Type(spv) = "Float" or Type(spv) = "Double" or Type(spv) = "roDouble") and spv >= 0 then startPos = spv * 1.0
    end if
    ' Rewind on Resume (Settings → Playback → Episodes): back up a few seconds when continuing a
    ' partly watched title. Only when the caller passed the resume position; a server-side resume
    ' (no start_position) cannot be adjusted here.
    if startPos <> invalid and startPos > 0 then
        rewind = Settings_resumeRewindSeconds()
        if rewind > 0 then
            startPos = startPos - rewind
            if startPos < 0 then startPos = 0
        end if
    end if
    ' Track choices from the detail page, as ids ("file:<id>:audio:<n>" / "file:<id>:subtitle:<n>").
    ' Indexes are turned into ids for the file that actually plays; ids for another file are dropped,
    ' Off (-1) and Auto send nothing so the profile preference applies. Never send -1.
    audioId = Str_orEmpty(p.audioTrackId)
    if audioId = "" and p.audioTrackIndex <> invalid and p.audioTrackIndex >= 0 then audioId = Tracks_audioId(m.fileId, Int(p.audioTrackIndex))
    subId = Str_orEmpty(p.subtitleTrackId)
    if subId = "" and p.subtitleTrackIndex <> invalid and p.subtitleTrackIndex >= 0 then subId = Tracks_subtitleId(m.fileId, Int(p.subtitleTrackIndex))
    prefix = "file:" + m.fileId + ":"
    if audioId <> "" and Left(audioId, Len(prefix)) <> prefix then audioId = ""
    if subId <> "" and Left(subId, Len(prefix)) <> prefix then subId = ""
    body = PlaybackCaps_startBody(installation, m.fileId, m.attemptId, startPos, audioId, subId)
    Api_send("POST", "/api/v2/playback/start", body, "onStart")
end sub

sub onStart(event as object)
    resp = Api_result(event)
    if m.closing then return
    if resp.status = 409 and not m.retriedInstall then
        ' installation_changed: refetch capabilities once and start a fresh attempt.
        m.retriedInstall = true
        m.attemptId = m.di.GetRandomUUID()
        if m.global.hasField("playbackCaps") then m.global.playbackCaps = {}
        fetchCapabilities()
        return
    end if
    if resp.status = 426 then
        showError("This server needs an update before it can stream to Roku.")
        return
    end if
    if not resp.ok or resp.data = invalid then
        showError(Api_errorText(resp))
        return
    end if
    d = resp.data
    if d.outcome <> "playable" then
        msg = ""
        if d.terminal <> invalid then msg = Str_orEmpty(d.terminal.message)
        if msg = "" then msg = "This title can't be played right now."
        showError(msg)
        return
    end if
    problem = PlaybackCaps_planProblem(d)
    if problem <> "" then
        showError(problem)
        return
    end if
    m.sessionId = Str_orEmpty(d.session_id)
    if m.sessionId = "" then m.sessionId = Str_orEmpty(d.playback_plan.session_id)
    m.sequence = 0
    m.stopId = ""
    applyPlan(d.playback_plan)
end sub

' Hands a plan to the Video node (also used after a replan, and to remount the same plan).
' opts: { resumeAt: source seconds to continue from, subtitleTrackId: the track to select ("" = off) }.
sub applyPlan(plan as object, opts = invalid as dynamic)
    if opts = invalid then opts = {}
    m.plan = plan
    s = m.global.session
    stream = plan.stream
    tl = plan.timeline
    if tl = invalid then tl = {}
    m.timelineOffset = 0.0
    if tl.timeline_offset_seconds <> invalid then m.timelineOffset = tl.timeline_offset_seconds * 1.0
    if plan.source <> invalid and plan.source.duration_seconds <> invalid and plan.source.duration_seconds > 0 then
        m.duration = plan.source.duration_seconds * 1.0
        m.scrubber.duration = m.duration
    end if

    content = CreateObject("roSGNode", "ContentNode")
    url = Url_resolve(stream.url)
    content.Url = url
    content.Title = m.titleLabel.text
    fmt = "mp4"
    proto = LCase(Str_orEmpty(stream.protocol))
    container = LCase(Str_orEmpty(stream.container))
    if proto = "hls" or Instr(1, LCase(url), ".m3u8") > 0 then
        fmt = "hls"
    else if container = "mkv" or container = "matroska" then
        fmt = "mkv"
    else if container = "mp4" or container = "m4v" or container = "mov" then
        fmt = "mp4"
    else if container <> "" then
        fmt = container
    end if
    content.StreamFormat = fmt
    headers = ["Authorization: Bearer " + s.accessToken]
    if stream.headers <> invalid then
        for each k in stream.headers
            headers.Push(k + ": " + Str_orEmpty(stream.headers[k]))
        end for
    end if
    content.HttpHeaders = headers
    if LCase(Left(url, 5)) = "https" then content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    if m.duration > 0 then content.Length = Int(m.duration)
    m.resumeAfterStart = invalid
    if opts.resumeAt <> invalid then
        ' Continue where we were (a replan or a subtitle remount); the server may already have
        ' anchored player_start_seconds there, and onVideoState seeks if it didn't.
        startAt = opts.resumeAt - m.timelineOffset
        if startAt > 0 then content.PlayStart = Int(startAt)
        m.resumeAfterStart = opts.resumeAt
    else if tl.player_start_seconds <> invalid and tl.player_start_seconds > 0 then
        content.PlayStart = Int(tl.player_start_seconds)
    end if

    ' Subtitles: only WebVTT/SRT sidecars can be rendered by the Video node (Subs_buildTrack adds
    ' the `token=` fallback and the timestamp_offset for the timeline offset and the viewer's delay).
    m.subtitleTracks = []
    m.subtitleIndex = -1
    tracks = []
    subInv = []
    if plan.subtitle <> invalid then subInv = Arr_or(plan.subtitle.inventory)
    m.subs.subtitleInventory = subInv
    for each t in subInv
        track = Subs_buildTrack(t)
        if track <> invalid then
            m.subtitleTracks.Push(track)
            tracks.Push({ Language: track.language, TrackName: track.url, Description: track.label })
        end if
    end for
    if tracks.Count() > 0 then content.SubtitleTracks = tracks

    ' Default subtitle: the caller's choice (a remount keeps the current track), else what the plan
    ' selected, if we can render it.
    m.pendingSubtitleTrackId = ""
    if opts.subtitleTrackId <> invalid then
        m.pendingSubtitleTrackId = Str_orEmpty(opts.subtitleTrackId)
    else if m.forceSubtitlesOff then
        ' The detail page chose "Off · Start without subtitles".
    else if plan.subtitle <> invalid and Str_orEmpty(plan.subtitle.mode) <> "off" and plan.selected_tracks <> invalid and plan.selected_tracks.subtitle <> invalid then
        m.pendingSubtitleTrackId = Str_orEmpty(plan.selected_tracks.subtitle.id)
    end if

    m.video.content = content
    m.video.control = "play"
    setBuffering(true)
    m.progressTimer.control = "start"
    updateHudQualityLabel()
    ' Follow the syncable subtitles of this file (their timing and running sync jobs).
    if not m.subs.syncLoaded then Subs_syncReload()
end sub

' Fetches the mounted sidecar again (a delay change or new server timing): the Video node keeps the
' cues it parsed, so the same plan is remounted at the current position with the same track.
sub remountSubtitles()
    if m.plan = invalid or m.closing then return
    keepId = Subs_selectedTrackId()
    resumeAt = m.position
    m.video.control = "stop"
    applyPlan(m.plan, { resumeAt: resumeAt, subtitleTrackId: keepId })
end sub

' ---------- Video events ----------

sub onVideoState()
    st = m.video.state
    if st = "buffering" then
        setBuffering(true)
    else if st = "playing" then
        setBuffering(false)
        m.isPaused = false
        m.playPauseBtn.iconUri = "pkg:/images/icons/pause.png"
        if m.resumeAfterStart <> invalid then
            ' Only when PlayStart didn't land us there already.
            if Abs(m.video.position + m.timelineOffset - m.resumeAfterStart) > 3 then seekToSource(m.resumeAfterStart)
            m.resumeAfterStart = invalid
        end if
        if m.pendingSubtitleTrackId <> "" then
            for i = 0 to m.subtitleTracks.Count() - 1
                if m.subtitleTracks[i].trackId = m.pendingSubtitleTrackId then setSubtitle(i)
            end for
            m.pendingSubtitleTrackId = ""
        end if
    else if st = "paused" then
        m.isPaused = true
        m.playPauseBtn.iconUri = "pkg:/images/icons/play.png"
        sendProgress()
    else if st = "finished" then
        onFinished()
    else if st = "error" then
        msg = Str_orEmpty(m.video.errorMsg)
        if msg = "" then msg = Str_orEmpty(m.video.errorStr)
        if msg = "" then msg = "The video could not be played."
        if m.video.errorCode <> invalid and m.video.errorCode <> 0 then msg = msg + " (" + Str_orEmpty(m.video.errorCode) + ")"
        showError(msg)
    end if
end sub

sub onVideoDuration()
    if m.duration <= 0 and m.video.duration > 0 then
        m.duration = m.video.duration
        m.scrubber.duration = m.duration
    end if
end sub

sub onVideoPosition()
    if m.plan = invalid then return
    m.position = m.video.position + m.timelineOffset
    if not m.scrubbing then m.scrubber.position = m.position
    checkMarkers()
    checkUpNext()
end sub

function sourcePosition() as float
    return m.position
end function

sub seekToSource(seconds as float)
    if seconds < 0 then seconds = 0
    if m.duration > 0 and seconds > m.duration - 1 then seconds = m.duration - 1
    m.video.seek = seconds - m.timelineOffset
    m.position = seconds
    m.scrubber.position = seconds
end sub

sub onFinished()
    if m.finished then return
    m.finished = true
    m.progressTimer.control = "stop"
    if m.upNextDismissed then
        exitPlayer()
        return
    end if
    if (m.isEpisode or m.shuffle <> invalid) and m.nextEpisode <> invalid then
        if not m.upNext.visible then showUpNext()
        if m.countdown < 0 and m.shuffle = invalid then
            ' No auto-play: wait for the user on the overlay.
            m.unEyebrow.text = "FINISHED"
        end if
        return
    end if
    if m.shuffle <> invalid then
        ' Nothing else in the shuffle can play: the card shows Finished with Stop shuffling.
        if not m.upNext.visible then showUpNext() else renderUpNext()
        return
    end if
    exitPlayer()
end sub

' ---------- Progress and stop ----------

sub onProgressTick()
    if m.isPaused then return
    sendProgress()
end sub

sub sendProgress()
    if m.sessionId = "" or m.closing then return
    inst = installationId()
    if inst = "" then return
    m.sequence = m.sequence + 1
    body = { installation_id: inst, sequence: m.sequence, position: m.position, is_paused: m.isPaused }
    Api_send("POST", "/api/v2/playback/" + Str_urlEncode(m.sessionId) + "/progress", body, "onProgressResult")
end sub

sub onProgressResult(event as object)
    resp = Api_result(event)
    if resp.status = 404 or resp.status = 410 then
        ' The session is gone on the server; stop reporting.
        m.sessionId = ""
    end if
end sub

' DELETE the session with a final sample. Safe to call twice.
sub stopSession()
    if m.sessionId = "" then return
    inst = installationId()
    sid = m.sessionId
    m.sessionId = ""
    m.progressTimer.control = "stop"
    if inst = "" then return
    if m.stopId = "" then m.stopId = m.di.GetRandomUUID()
    m.sequence = m.sequence + 1
    body = { installation_id: inst, stop_id: m.stopId, sequence: m.sequence, position: m.position, is_paused: true }
    Api_send("DELETE", "/api/v2/playback/" + Str_urlEncode(sid), body, "onStopped")
end sub

sub onStopped(event as object)
    Api_result(event)
    if m.closing then finishClose()
end sub

sub exitPlayer()
    if m.closing then return
    m.closing = true
    m.global.homeDirty = true
    m.countdownTimer.control = "stop"
    m.holdTimer.control = "stop"
    m.hideTimer.control = "stop"
    m.subsSyncTimer.control = "stop"
    m.subsAiTimer.control = "stop"
    hadSession = m.sessionId <> ""
    m.video.control = "stop"
    m.video.visible = false
    stopSession()
    if hadSession then
        m.stopTimeout.control = "start"
    else
        finishClose()
    end if
end sub

' Covered or removed without going through Back (e.g. a stack reset after the session
' expired): stop the video and close the server playback session.
sub onScreenHidden()
    if m.closing then return
    m.closing = true
    m.closed = true
    m.global.homeDirty = true
    m.countdownTimer.control = "stop"
    m.holdTimer.control = "stop"
    m.hideTimer.control = "stop"
    m.subsSyncTimer.control = "stop"
    m.subsAiTimer.control = "stop"
    m.video.control = "stop"
    stopSession()
end sub

sub finishClose()
    if m.closed = true then return
    m.closed = true
    m.stopTimeout.control = "stop"
    Nav_close()
end sub

' Shows or hides the buffering overlay. The spinner's own `visible` is toggled too, so its
' repeating Animation stops while video plays (hiding only the parent would leave it running).
sub setBuffering(on as boolean)
    m.bufferingGroup.visible = on
    m.bufferSpinner.visible = on
end sub

sub showError(msg as string)
    setBuffering(false)
    m.controls.visible = false
    m.hud.visible = false
    m.skipGroup.visible = false
    m.progressTimer.control = "stop"
    m.errorLabel.text = msg
    m.errorGroup.visible = true
    m.retryBtn.setFocus(true)
end sub

' ---------- Transport ----------

sub togglePlay()
    st = m.video.state
    if st = "paused" then
        m.video.control = "resume"
    else if st = "playing" or st = "buffering" then
        m.video.control = "pause"
    end if
    rearmHide()
end sub

' player.video_skip_back/forward_seconds (profile setting, revision 9) with the device pref as fallback.
function skipBackSeconds() as integer
    return Settings_skipBackSeconds()
end function

function skipForwardSeconds() as integer
    return Settings_skipForwardSeconds()
end function

sub onSkipBack()
    skipBy(-skipBackSeconds())
end sub

sub onSkipForward()
    skipBy(skipForwardSeconds())
end sub

sub skipBy(delta as integer)
    if m.plan = invalid then return
    seekToSource(m.position + delta)
    if delta < 0 then
        showFeedback("-" + Abs(delta).ToStr() + "s")
    else
        showFeedback("+" + delta.ToStr() + "s")
    end if
    rearmHide()
end sub

sub showFeedback(text as string)
    m.feedbackLabel.text = text
    m.feedbackGroup.visible = true
    m.feedbackTimer.control = "stop"
    m.feedbackTimer.control = "start"
end sub

sub hideFeedback()
    m.feedbackGroup.visible = false
end sub

' ---------- Controls overlay ----------

function transportButtons() as object
    out = []
    for each b in [m.skipBackBtn, m.playPauseBtn, m.skipFwdBtn, m.upNextBtn, m.subtitlesBtn, m.tuneBtn, m.closeBtn]
        if b.visible then out.Push(b)
    end for
    return out
end function

sub layoutTransport()
    ' Left group at x 0; right group right-aligned at 1600.
    x = 1600
    for each b in [m.closeBtn, m.tuneBtn, m.subtitlesBtn, m.upNextBtn]
        if b.visible then
            x = x - 88
            b.translation = [x, 0]
            x = x - 10
        end if
    end for
end sub

sub showControls()
    ' A shuffle offers no sequential next on the transport row.
    m.upNextBtn.visible = m.nextEpisode <> invalid and m.shuffle = invalid
    layoutTransport()
    m.controls.visible = true
    positionSkipPill()
    focusControls()
    rearmHide()
end sub

sub focusControls()
    if m.controlsZone = "scrubber" then
        m.scrubber.setFocus(true)
    else if m.controlsZone = "skip" and m.skipGroup.visible then
        m.skipBtn.setFocus(true)
    else
        m.controlsZone = "transport"
        btns = transportButtons()
        if m.transportIndex >= btns.Count() then m.transportIndex = 0
        if btns.Count() > 0 then btns[m.transportIndex].setFocus(true)
    end if
end sub

sub hideControls()
    if m.scrubbing then
        ' Don't hide mid-scrub; just re-arm.
        rearmHide()
        return
    end if
    m.controls.visible = false
    m.hideTimer.control = "stop"
    positionSkipPill()
    if not m.hud.visible and not m.upNext.visible and not m.errorGroup.visible and not m.picker.visible and not m.subsDialog.visible then
        if m.skipGroup.visible and m.skipBtn.visible then
            m.skipBtn.setFocus(true)
        else
            m.focusSink.setFocus(true)
        end if
    end if
end sub

sub rearmHide()
    if not m.controls.visible then return
    m.hideTimer.control = "stop"
    m.hideTimer.control = "start"
end sub

sub onSubtitlesButton()
    openPicker("subtitle")
end sub

sub onTuneButton()
    openHud(0)
end sub

sub onUpNextButton()
    if m.nextEpisode = invalid or m.shuffle <> invalid then return
    m.upNextDismissed = false
    showUpNext()
end sub

' Scrubber: Left/Right nudge ±10 s; holding accelerates; OK commits.
sub beginScrub()
    if not m.scrubbing then
        m.scrubbing = true
        m.scrubPos = m.position
        m.scrubber.scrubPosition = m.scrubPos
        m.scrubber.scrubbing = true
    end if
end sub

sub nudgeScrub(direction as integer)
    beginScrub()
    m.holdDirection = direction
    m.holdTicks = 0
    m.scrubber.rateLabel = ""
    applyScrubDelta(direction * 10)
    m.holdTimer.control = "start"
    rearmHide()
end sub

sub onHoldTick()
    m.holdTicks = m.holdTicks + 1
    stepSec = 10
    rate = ""
    if m.holdTicks > 12 then
        stepSec = 120
        rate = "8x"
    else if m.holdTicks > 6 then
        stepSec = 60
        rate = "4x"
    else if m.holdTicks > 2 then
        stepSec = 30
        rate = "2x"
    end if
    m.scrubber.rateLabel = rate
    applyScrubDelta(m.holdDirection * stepSec)
    rearmHide()
end sub

sub applyScrubDelta(delta as integer)
    p = m.scrubPos + delta
    if p < 0 then p = 0
    if m.duration > 0 and p > m.duration then p = m.duration
    m.scrubPos = p
    m.scrubber.scrubPosition = p
end sub

sub endHold()
    m.holdTimer.control = "stop"
    m.scrubber.rateLabel = ""
end sub

sub commitScrub()
    endHold()
    if m.scrubbing then
        m.scrubbing = false
        m.scrubber.scrubbing = false
        seekToSource(m.scrubPos)
    end if
    rearmHide()
end sub

sub cancelScrub()
    endHold()
    m.scrubbing = false
    m.scrubber.scrubbing = false
    m.scrubber.position = m.position
end sub

' ---------- Skip intro / credits ----------

function markerLabel(kind as string) as string
    if kind = "credits" then return "Skip Credits"
    if kind = "recap" then return "Skip Recap"
    return "Skip Intro"
end function

sub checkMarkers()
    ' playback.intro_skip_mode (never | ask | always) and playback.auto_skip_credits, from the server.
    mode = Settings_introSkipMode()
    skipCredits = Settings_autoSkipCredits()
    active = invalid
    for each mk in m.markers
        if mk.kind <> "preview" and m.position >= mk.start and m.position < mk["end"] - 1 then active = mk
    end for
    if active = invalid then
        if m.activeMarker <> invalid and m.watchBackTarget = invalid then hideSkipPill()
        m.activeMarker = invalid
        return
    end if
    key = active.kind + ":" + Str_orEmpty(active.start)
    m.activeMarker = active
    if mode = "never" and not (active.kind = "credits" and skipCredits) then return
    if (mode = "always" and active.kind <> "credits") or (active.kind = "credits" and skipCredits) then
        if m.autoSkipped[key] <> true then
            m.autoSkipped[key] = true
            seekToSource(active["end"])
            showSkippedCaption(active)
        end if
        return
    end if
    if m.skipShownFor <> key then
        m.skipShownFor = key
        m.skipBtn.text = markerLabel(active.kind)
        m.skipBtn.visible = true
        m.skippedCaption.visible = false
        m.skipGroup.visible = true
        positionSkipPill()
        if not m.controls.visible and not m.hud.visible and not m.upNext.visible and not m.picker.visible and not m.subsDialog.visible then
            m.skipBtn.setFocus(true)
        end if
    end if
end sub

sub showSkippedCaption(mk as object)
    kindText = "Intro skipped"
    if mk.kind = "recap" then kindText = "Recap skipped"
    m.skippedCaption.text = kindText
    m.skippedCaption.visible = true
    m.skipBtn.text = "Watch Intro"
    if mk.kind = "recap" then m.skipBtn.text = "Watch Recap"
    m.skipBtn.visible = true
    m.skipGroup.visible = true
    m.skipShownFor = "watch:" + Str_orEmpty(mk.start)
    m.watchBackTarget = mk.start
    positionSkipPill()
    if not m.controls.visible and not m.hud.visible and not m.upNext.visible and not m.picker.visible and not m.subsDialog.visible then m.skipBtn.setFocus(true)
    m.captionTimer.control = "start"
end sub

sub hideCaption()
    if m.skippedCaption.visible then hideSkipPill()
end sub

sub hideSkipPill()
    hadFocus = m.skipBtn.hasFocus()
    m.skipGroup.visible = false
    m.skippedCaption.visible = false
    m.watchBackTarget = invalid
    m.skipShownFor = ""
    if hadFocus then
        if m.controls.visible then
            m.controlsZone = "transport"
            focusControls()
        else
            m.focusSink.setFocus(true)
        end if
    end if
end sub

sub positionSkipPill()
    bottom = 112
    if m.controls.visible then bottom = 400
    w = m.skipBtn.width
    x = 1920 - 64 - w
    y = 1080 - bottom - 72
    m.skipBtn.translation = [x, y]
    m.skippedCaption.translation = [1920 - 64 - 400, y - 40]
end sub

sub onSkipPill()
    if m.watchBackTarget <> invalid then
        seekToSource(m.watchBackTarget)
        m.captionTimer.control = "stop"
        hideSkipPill()
        return
    end if
    if m.activeMarker <> invalid then
        seekToSource(m.activeMarker["end"])
    end if
    hideSkipPill()
    rearmHide()
end sub

' ---------- Next episode (docs/api-spec.md §8.6) ----------

sub resolveNextEpisode()
    w = m.watch
    sid = Str_orEmpty(w.series_id)
    if sid = "" or w.season_number = invalid or w.episode_number = invalid then return
    m.nextSeriesId = sid
    m.nextPool = []
    m.nextPending = 0
    Api_get("/api/v2/catalog/series/" + Str_urlEncode(sid) + "/seasons", { include_artwork: "false" }, "onNextSeasons")
end sub

sub onNextSeasons(event as object)
    resp = Api_result(event)
    if m.closing or not resp.ok or resp.data = invalid then return
    cur = Int(m.watch.season_number)
    seasons = Arr_or(resp.data.items)
    toLoad = [cur]
    ' The next regular season (never specials unless we're already in specials).
    nextNum = invalid
    for each s in seasons
        n = s.season_number
        if n <> invalid and n > cur and (n <> 0) then
            if nextNum = invalid or n < nextNum then nextNum = n
        end if
    end for
    if nextNum <> invalid then toLoad.Push(Int(nextNum))
    m.nextPending = toLoad.Count()
    for each n in toLoad
        Api_get("/api/v2/catalog/series/" + Str_urlEncode(m.nextSeriesId) + "/seasons/" + n.ToStr() + "/episodes", { image_size: "medium" }, "onNextEpisodes")
    end for
end sub

sub onNextEpisodes(event as object)
    resp = Api_result(event)
    m.nextPending = m.nextPending - 1
    if resp.ok and resp.data <> invalid then
        for each ep in Arr_or(resp.data.items)
            m.nextPool.Push(ep)
        end for
    end if
    if m.nextPending > 0 then return
    cs = Int(m.watch.season_number)
    ce = Int(m.watch.episode_number)
    best = invalid
    for each ep in m.nextPool
        sn = ep.season_number
        en = ep.episode_number
        if sn <> invalid and en <> invalid then
            if sn > cs or (sn = cs and en > ce) then
                if best = invalid or sn < best.season_number or (sn = best.season_number and en < best.episode_number) then best = ep
            end if
        end if
    end for
    m.nextEpisode = best
    m.nextIsEpisode = true
    if m.controls.visible then
        m.upNextBtn.visible = best <> invalid
        layoutTransport()
    end if
end sub

' ---------- Shuffle (shuffle-api-v2.md "Player rules") ----------

function shufflePath() as string
    return "/api/v2/shuffles/" + Str_urlEncode(m.shuffle.id)
end function

' Records a shuffle response: a success replaces the last pick; 409 means nothing in the scope
' can play any more; other failures keep the last pick.
sub shuffleRecord(resp as object)
    if m.shuffle = invalid then return
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" then
        m.shuffle.latest = resp.data
        m.shuffle.exhausted = false
    else if resp.status = 409 then
        m.shuffle.exhausted = true
    end if
end sub

' The advance that started this item already returned its next pick; otherwise read the shuffle.
sub resolveShuffleNext()
    sh = m.shuffle
    if sh = invalid then return
    if sh.latest <> invalid and sh.latest.current <> invalid and Str_orEmpty(sh.latest.current.content_id) = m.itemId then
        publishShuffleNext()
        return
    end if
    Api_get(shufflePath(), { image_size: "large" }, "onShuffleRead", { forItem: m.itemId })
end sub

sub onShuffleRead(event as object)
    resp = Api_result(event)
    if m.closing or m.shuffle = invalid then return
    if resp.context <> invalid and resp.context.forItem <> m.itemId then return
    shuffleRecord(resp)
    publishShuffleNext()
end sub

' Publishes the shuffle's pick after the item playing, or the finished state when there is none.
sub publishShuffleNext()
    sh = m.shuffle
    if sh = invalid then return
    nxt = invalid
    if not sh.exhausted then nxt = Shuffle_nextAfter(sh.latest, m.itemId)
    m.nextEpisode = nxt
    m.nextIsEpisode = nxt <> invalid and LCase(Str_orEmpty(nxt.type)) = "episode"
    if m.upNext.visible then
        renderUpNext()
        if nxt = invalid then
            m.countdownTimer.control = "stop"
            m.countdown = -1
        else if m.finished and m.countdown < 0 and autoPlayNext() then
            ' A new pick at the end restarts the countdown.
            startCountdown()
        end if
    end if
end sub

' Up Next "Play Now" / countdown in a shuffle: move the shuffle past the item that played and play
' the returned `current` from the beginning. The server moves on only while that item is still
' current, so a repeated press plays the same pick.
sub advanceShuffle()
    if m.shuffle = invalid or m.nextEpisode = invalid then return
    if m.shuffleAdvancing or m.shufflePicking then return
    m.shuffleAdvancing = true
    m.countdownTimer.control = "stop"
    m.countdown = -1
    m.unPlayBtn.text = "Play Now"
    Api_send("POST", shufflePath() + "/advance", { from_content_id: m.itemId }, "onShuffleAdvanced", { forItem: m.itemId })
end sub

sub onShuffleAdvanced(event as object)
    resp = Api_result(event)
    m.shuffleAdvancing = false
    if m.closing or m.shuffle = invalid then return
    if resp.context <> invalid and resp.context.forItem <> m.itemId then return
    shuffleRecord(resp)
    if resp.ok and resp.data <> invalid and resp.data.current <> invalid then
        cur = resp.data.current
        playInPlace({ itemId: Str_orEmpty(cur.content_id), title: Str_orEmpty(cur.title), itemType: Str_orEmpty(cur.type), startPosition: 0, shuffleId: m.shuffle.id })
    else if m.shuffle.exhausted then
        publishShuffleNext()
    else
        m.global.toast = "Couldn't continue the shuffle."
    end if
end sub

' Up Next "Pick Another": the server replaces the announced pick.
sub pickAnother()
    sh = m.shuffle
    if sh = invalid or sh.latest = invalid or sh.latest["next"] = invalid then return
    if m.shufflePicking or m.shuffleAdvancing then return
    m.shufflePicking = true
    m.unPickBtn.text = "Picking…"
    Api_send("POST", shufflePath() + "/skip", { next_content_id: Str_orEmpty(sh.latest["next"].content_id) }, "onShufflePicked", { forItem: m.itemId })
end sub

sub onShufflePicked(event as object)
    resp = Api_result(event)
    m.shufflePicking = false
    m.unPickBtn.text = "Pick Another"
    if m.closing or m.shuffle = invalid then return
    if resp.context <> invalid and resp.context.forItem <> m.itemId then return
    shuffleRecord(resp)
    if not resp.ok and not m.shuffle.exhausted then
        m.global.toast = "Couldn't pick another."
        return
    end if
    publishShuffleNext()
end sub

' Up Next "Stop shuffling": ends the shuffle on the server and leaves the player, back to where
' the shuffle started. (Back keeps the shuffle on the server.)
sub stopShuffling()
    sh = m.shuffle
    if sh = invalid then return
    m.shuffle = invalid
    m.nextEpisode = invalid
    m.countdownTimer.control = "stop"
    Api_fire("DELETE", "/api/v2/shuffles/" + Str_urlEncode(sh.id))
    exitPlayer()
end sub

sub checkUpNext()
    if (not m.isEpisode and m.shuffle = invalid) or m.nextEpisode = invalid or m.upNextShown or m.upNextDismissed then return
    if m.duration <= 0 then return
    ' playback.next_up_prompt_seconds: how long before the end the card appears (0 = at the end).
    trigger = m.duration - Settings_nextUpPromptSeconds()
    for each mk in m.markers
        if mk.kind = "credits" and mk.start < trigger and mk.start > m.duration * 0.5 then trigger = mk.start
    end for
    if m.position >= trigger then showUpNext()
end sub

' playback.auto_play_next (server, profile_device scope) with the device pref as fallback.
function autoPlayNext() as boolean
    return Settings_autoPlayNext()
end function

' Still Watching Prompt (Settings → Playback → Episodes): after N consecutive auto-advances the Up
' Next card waits for a key instead of counting down. 0 = never. Device-local, like Android TV.
function stillWatchingDue() as boolean
    threshold = Settings_passoutThreshold()
    if threshold <= 0 then return false
    if m.autoAdvances = invalid then m.autoAdvances = 0
    return m.autoAdvances >= threshold
end function

sub startCountdown()
    m.countdown = 10
    m.unPlayBtn.text = "Play Now · " + m.countdown.ToStr()
    m.countdownTimer.control = "stop"
    m.countdownTimer.control = "start"
end sub

sub showUpNext()
    if m.nextEpisode = invalid and m.shuffle = invalid then return
    m.upNextShown = true
    hideControlsNow()
    m.hud.visible = false
    m.skipGroup.visible = false
    ' Shrink the video into a 16:9 pane on the left.
    m.video.width = 880
    m.video.height = 495
    m.video.translation = [160, 292]
    m.videoFrame.width = 896
    m.videoFrame.height = 511
    m.videoFrame.translation = [152, 284]
    m.videoFrame.visible = true

    if m.nextEpisode <> invalid and autoPlayNext() and not stillWatchingDue() then
        startCountdown()
    else
        if stillWatchingDue() then m.autoAdvances = 0
        m.countdown = -1
        m.unPlayBtn.text = "Play Now"
    end if
    renderUpNext()
    m.upNext.visible = true
    m.upNextIndex = 0
    focusUpNext()
    ' As the card opens, read the shuffle again so the server can replace a pick that can no longer play.
    if m.shuffle <> invalid and not m.shuffleRefreshed then
        m.shuffleRefreshed = true
        Api_get(shufflePath(), { image_size: "large" }, "onShuffleRead", { forItem: m.itemId })
    end if
end sub

' Fills the Up Next panel from m.nextEpisode (a next episode, or a shuffle's random pick).
sub renderUpNext()
    ep = m.nextEpisode
    sh = m.shuffle
    scopeLabel = ""
    if sh <> invalid then scopeLabel = Shuffle_scopeLabel(sh.latest)
    m.unScope.visible = scopeLabel <> ""
    if scopeLabel <> "" then
        m.unScopeLabel.text = "Shuffling " + scopeLabel
        m.unScopeLabel.width = 0
        w = Int(Label_width(m.unScopeLabel)) + 48 + 16
        if w > 640 then w = 640
        m.unScopeLabel.width = w - 48 - 16
        m.unScopeBg.width = w
    end if

    if ep = invalid then
        ' Nothing follows.
        if m.finished then m.unEyebrow.text = "FINISHED" else m.unEyebrow.text = "MORE TO WATCH"
        m.unSeries.visible = false
        if m.finished then m.unEpisode.text = "End of playback" else m.unEpisode.text = "Almost finished"
        m.unMeta.text = ""
        if sh <> invalid then m.unOverview.text = "Nothing else in this shuffle can play." else m.unOverview.text = "No next episode is available."
    else
        if sh <> invalid then
            m.unEyebrow.text = "UP NEXT AT RANDOM"
        else if m.finished and m.countdown >= 0 then
            m.unEyebrow.text = "PLAYING NEXT"
        else
            m.unEyebrow.text = "UP NEXT"
        end if
        title = Str_orEmpty(ep.title)
        if m.nextIsEpisode then
            series = Str_orEmpty(ep.series_title)
            if series = "" then series = m.seriesTitle
            m.unSeries.text = series
            m.unSeries.visible = series <> ""
            tag = Content_seShort(ep.season_number, ep.episode_number).Replace(" · ", "·")
            if title = "" then title = "Next Episode"
            m.unEpisode.text = Str_joinDots([tag, title], "  ")
        else
            ' A shuffled movie has no series line; its own title heads the panel.
            m.unSeries.visible = false
            m.unEpisode.text = title
        end if
        meta = ""
        if ep.runtime <> invalid and ep.runtime > 0 then meta = Str_orEmpty(Int(ep.runtime)) + " min"
        m.unMeta.text = meta
        m.unOverview.text = Str_orEmpty(ep.overview)
    end if
    m.unPlayBtn.visible = ep <> invalid
    m.unPickBtn.visible = sh <> invalid and ep <> invalid
    m.unKeepBtn.visible = not m.finished
    m.unStopBtn.visible = sh <> invalid
    layoutUpNextButtons()
end sub

' Stacks the visible buttons; the list drives Up/Down on the overlay.
sub layoutUpNextButtons()
    btns = []
    for each b in [m.unPlayBtn, m.unPickBtn, m.unKeepBtn, m.unBackBtn, m.unStopBtn]
        if b.visible then btns.Push(b)
    end for
    y = 420
    stepY = 94
    if btns.Count() > 3 then
        y = 400
        stepY = 86
    end if
    for each b in btns
        b.translation = [0, y]
        y = y + stepY
    end for
    m.upNextButtons = btns
    if m.upNextIndex = invalid or m.upNextIndex >= btns.Count() then m.upNextIndex = 0
end sub

sub focusUpNext()
    if m.upNextButtons.Count() = 0 then layoutUpNextButtons()
    if m.upNextButtons.Count() = 0 then return
    if m.upNextIndex >= m.upNextButtons.Count() then m.upNextIndex = 0
    m.upNextButtons[m.upNextIndex].setFocus(true)
end sub

sub onCountdownTick()
    if not m.upNext.visible then
        m.countdownTimer.control = "stop"
        return
    end if
    m.countdown = m.countdown - 1
    if m.countdown <= 0 then
        m.countdownTimer.control = "stop"
        if m.autoAdvances = invalid then m.autoAdvances = 0
        m.autoAdvances = m.autoAdvances + 1
        playNext()
        return
    end if
    m.unPlayBtn.text = "Play Now · " + m.countdown.ToStr()
end sub

sub restoreVideoPane()
    m.video.width = 1920
    m.video.height = 1080
    m.video.translation = [0, 0]
    m.videoFrame.visible = false
end sub

sub keepWatching()
    m.countdownTimer.control = "stop"
    m.upNext.visible = false
    m.upNextDismissed = true
    restoreVideoPane()
    if m.finished then
        exitPlayer()
        return
    end if
    m.focusSink.setFocus(true)
end sub

' Play Now pressed by hand: the viewer is still watching, so the auto-advance count starts over.
sub onPlayNowButton()
    m.autoAdvances = 0
    playNext()
end sub

sub playNext()
    ep = m.nextEpisode
    if ep = invalid then return
    if m.shuffle <> invalid then
        advanceShuffle()
        return
    end if
    playInPlace({ itemId: Str_orEmpty(ep.content_id), title: Str_orEmpty(ep.title) })
end sub

' Replaces the mounted item in place with another one, from the beginning.
sub playInPlace(newParams as object)
    m.countdownTimer.control = "stop"
    m.upNext.visible = false
    restoreVideoPane()
    stopSession()
    m.video.control = "stop"
    m.video.visible = true
    m.top.params = newParams
    resetPlaybackState()
    m.scrubber.position = 0
    m.scrubber.duration = 0
    m.scrubber.markers = []
    m.scrubber.chapters = []
    m.playPauseBtn.iconUri = "pkg:/images/icons/pause.png"
    startPipeline()
end sub

sub hideControlsNow()
    m.controls.visible = false
    m.hideTimer.control = "stop"
    cancelScrub()
end sub

' ---------- HUD ----------

function hudTabNames() as object
    names = ["Info", "Video", "Audio", "Subtitles"]
    if m.chapters.Count() > 0 then names.Push("Chapters")
    return names
end function

sub openHud(tabIndex as integer)
    hideControlsNow()
    m.skipGroup.visible = false
    names = hudTabNames()
    if tabIndex < 0 then tabIndex = 0
    if tabIndex >= names.Count() then tabIndex = names.Count() - 1
    m.hudTab = tabIndex
    m.hudTabsGroup.removeChildrenIndex(m.hudTabsGroup.getChildCount(), 0)
    m.hudTabs = []
    x = 0
    for i = 0 to names.Count() - 1
        chip = m.hudTabsGroup.createChild("DetailChip")
        chip.text = names[i]
        chip.height = 76
        chip.padX = 36
        chip.fontSize = 27
        chip.translation = [x, 0]
        chip.selected = (i = tabIndex)
        x = x + chip.width + 12
        m.hudTabs.Push(chip)
    end for
    m.hudTabsGroup.translation = [Int((1920 - x + 12) / 2), 100]
    buildHudRows()
    m.hudFocus = "tabs"
    m.hudRow = 0
    m.hud.visible = true
    focusHud()
    if names[tabIndex] = "Subtitles" then Subs_onPaneShown()
end sub

sub closeHud()
    m.hud.visible = false
    m.picker.visible = false
    if m.skipShownFor <> "" then m.skipGroup.visible = true
    m.focusSink.setFocus(true)
end sub

sub focusHud()
    if m.hudFocus = "rows" and m.hudRows.Count() > 0 then
        if m.hudRow >= m.hudRows.Count() then m.hudRow = m.hudRows.Count() - 1
        applyHudRowFocus()
        m.focusSink.setFocus(true)
    else
        m.hudFocus = "tabs"
        applyHudRowFocus()
        if m.hudTabs.Count() > 0 then m.hudTabs[m.hudTab].setFocus(true)
    end if
end sub

sub selectHudTab(i as integer)
    if i < 0 or i >= m.hudTabs.Count() then return
    m.hudTab = i
    for j = 0 to m.hudTabs.Count() - 1
        m.hudTabs[j].selected = (j = i)
    end for
    m.hudTabs[i].setFocus(true)
    buildHudRows()
    tabNames = hudTabNames()
    if tabNames[i] = "Subtitles" then Subs_onPaneShown()
end sub

function currentAudioName() as string
    cur = m.video.audioTrack
    for each t in Arr_or(m.video.availableAudioTracks)
        if Str_orEmpty(t.Track) = Str_orEmpty(cur) then return audioTrackLabel(t)
    end for
    tracks = Arr_or(m.video.availableAudioTracks)
    if tracks.Count() > 0 then return audioTrackLabel(tracks[0])
    return "Default"
end function

function audioTrackLabel(t as object) as string
    n = Str_orEmpty(t.Name)
    l = Str_orEmpty(t.Language)
    if n <> "" and l <> "" and LCase(n) <> LCase(l) then return n + " (" + l + ")"
    if n <> "" then return n
    if l <> "" then return l
    return "Track"
end function

function currentSubtitleName() as string
    if m.pendingSubtitleTrackId <> "" then
        ' Chosen, but the player hasn't started yet (a remount or a fresh plan): "Label · Applying…".
        for each t in m.subtitleTracks
            if t.trackId = m.pendingSubtitleTrackId then return t.label + " · Applying…"
        end for
    end if
    if m.subtitleIndex < 0 or m.subtitleIndex >= m.subtitleTracks.Count() then return "Off"
    return m.subtitleTracks[m.subtitleIndex].label
end function

function qualityLabel() as string
    q = m.qualityPref
    if q = "" or q = "auto" then return "Auto"
    return q
end function

sub updateHudQualityLabel()
    tabNames = hudTabNames()
    if m.hud.visible and tabNames[m.hudTab] = "Video" then buildHudRows()
end sub

' Rows: [{id, label, value, actionable}]
function hudRowSpecs() as object
    names = hudTabNames()
    tabName = names[m.hudTab]
    rows = []
    if tabName = "Info" then
        rows.Push({ id: "np", label: "Now Playing", value: m.titleLabel.text, actionable: false })
        if m.epTag.text <> "" then rows.Push({ id: "ep", label: "Episode", value: m.epTag.text, actionable: false })
        route = ""
        if m.plan <> invalid then
            route = Str_orEmpty(m.plan.delivery)
            r = m.plan.effective_recipe
            if r <> invalid then
                bits = []
                if not Str_isEmpty(r.video_codec) then bits.Push(UCase(r.video_codec))
                if r.height <> invalid then bits.Push(Str_orEmpty(r.height) + "p")
                if not Str_isEmpty(r.audio_codec) then bits.Push(UCase(r.audio_codec))
                if not Str_isEmpty(r.audio_layout) then bits.Push(r.audio_layout)
                route = Str_joinDots([route, Str_joinDots(bits, " ")])
            end if
        end if
        if route <> "" then rows.Push({ id: "route", label: "Stream", value: route, actionable: false })
        if m.version <> invalid then
            vbits = []
            if not Str_isEmpty(m.version.resolution) then vbits.Push(m.version.resolution)
            if not Str_isEmpty(m.version.container) then vbits.Push(UCase(m.version.container))
            if m.version.hdr = true then vbits.Push("HDR")
            if vbits.Count() > 0 then rows.Push({ id: "file", label: "Source file", value: Str_joinDots(vbits), actionable: false })
        end if
    else if tabName = "Video" then
        rows.Push({ id: "quality", label: "Quality", value: qualityLabel(), actionable: true })
        auto = "On"
        if not autoPlayNext() then auto = "Off"
        rows.Push({ id: "autoplay", label: "Auto-play next", value: auto, actionable: true })
        if m.plan <> invalid and m.plan.effective_recipe <> invalid and not Str_isEmpty(m.plan.effective_recipe.dynamic_range) then
            rows.Push({ id: "range", label: "Dynamic range", value: UCase(m.plan.effective_recipe.dynamic_range), actionable: false })
        end if
    else if tabName = "Audio" then
        rows.Push({ id: "audio", label: "Track", value: currentAudioName(), actionable: true })
        if m.plan <> invalid and m.plan.effective_recipe <> invalid then
            r = m.plan.effective_recipe
            if not Str_isEmpty(r.audio_codec) then rows.Push({ id: "acodec", label: "Codec", value: UCase(r.audio_codec), actionable: false })
            if r.audio_channels <> invalid then rows.Push({ id: "ach", label: "Channels", value: Str_orEmpty(r.audio_channels), actionable: false })
        end if
    else if tabName = "Subtitles" then
        rows.Push({ id: "subtitle", label: "Track", value: currentSubtitleName(), actionable: true })
        if m.subtitleTracks.Count() = 0 then rows.Push({ id: "nosub", label: "No text subtitles for this stream", value: "", actionable: false })
        ' Delay, Timing (Sync to audio / Reset timing), Search subtitles, Translate with AI.
        Subs_appendHudRows(rows)
    else if tabName = "Chapters" then
        for i = 0 to m.chapters.Count() - 1
            ch = m.chapters[i]
            t = Str_orEmpty(ch.title)
            if t = "" then t = "Chapter " + (i + 1).ToStr()
            rows.Push({ id: "chapter:" + i.ToStr(), label: t, value: Time_clock(ch.start_seconds), actionable: true })
        end for
        if rows.Count() = 0 then rows.Push({ id: "noch", label: "No chapters in this title", value: "", actionable: false })
    end if
    return rows
end function

sub buildHudRows()
    m.hudRowsGroup.removeChildrenIndex(m.hudRowsGroup.getChildCount(), 0)
    m.hudRows = []
    specs = hudRowSpecs()
    m.hudSpecs = specs
    rowW = 1440 - 80
    rowH = 68
    y = 0
    maxRows = 8
    n = specs.Count()
    if n > maxRows then n = maxRows
    for i = 0 to n - 1
        spec = specs[i]
        row = m.hudRowsGroup.createChild("Group")
        row.translation = [0, y]
        bg = row.createChild("Poster")
        bg.id = "bg"
        bg.uri = "pkg:/images/ui/r14.9.png"
        bg.width = rowW
        bg.height = rowH
        bg.blendColor = "0xEDEDEDFF"
        bg.visible = false
        lbl = row.createChild("Label")
        lbl.id = "label"
        lbl.text = spec.label
        lbl.translation = [24, 0]
        lbl.width = 560
        lbl.height = rowH
        lbl.vertAlign = "center"
        lbl.color = "0xEDEDEDFF"
        lf = CreateObject("roSGNode", "Font")
        lf.uri = "pkg:/fonts/Inter-medium.otf"
        lf.size = 27
        if spec.muted = true then
            ' A detail line under a row (the Timing row's progress, result or note): full width, quieter.
            lbl.width = rowW - 48
            lbl.color = "0xEDEDED8C"
            if not Str_isEmpty(spec.color) then lbl.color = spec.color
            lf.uri = "pkg:/fonts/Inter-regular.otf"
            lf.size = 23
        end if
        lbl.font = lf
        val = row.createChild("Label")
        val.id = "value"
        val.text = spec.value
        val.translation = [600, 0]
        val.width = rowW - 600 - 24 - 48
        val.height = rowH
        val.vertAlign = "center"
        val.horizAlign = "right"
        val.color = "0xEDEDEDBF"
        vf = CreateObject("roSGNode", "Font")
        vf.uri = "pkg:/fonts/Inter-regular.otf"
        vf.size = 27
        val.font = vf
        chev = row.createChild("Poster")
        chev.id = "chevron"
        chev.uri = "pkg:/images/icons/chevron_right.png"
        chev.width = 36
        chev.height = 36
        chev.translation = [rowW - 24 - 36, (rowH - 36) / 2]
        chev.blendColor = "0xEDEDED9E"
        chev.visible = spec.actionable = true
        m.hudRows.Push(row)
        y = y + rowH + 4
    end for
    h = y + 80
    if h < 312 then h = 312
    m.hudBg.height = h
    m.hudRing.height = h
    if m.hudRow >= m.hudRows.Count() then m.hudRow = 0
    applyHudRowFocus()
end sub

sub applyHudRowFocus()
    for i = 0 to m.hudRows.Count() - 1
        row = m.hudRows[i]
        f = (m.hudFocus = "rows" and i = m.hudRow)
        Node_find(row, "bg").visible = f
        if f then
            Node_find(row, "label").color = "0x000000FF"
            Node_find(row, "value").color = "0x000000CC"
            Node_find(row, "chevron").blendColor = "0x000000FF"
        else
            Node_find(row, "label").color = "0xEDEDEDFF"
            Node_find(row, "value").color = "0xEDEDEDBF"
            Node_find(row, "chevron").blendColor = "0xEDEDED9E"
        end if
    end for
end sub

sub activateHudRow()
    if m.hudSpecs = invalid or m.hudRow >= m.hudSpecs.Count() then return
    spec = m.hudSpecs[m.hudRow]
    id = Str_orEmpty(spec.id)
    if id = "audio" then
        openPicker("audio")
    else if id = "subtitle" then
        openPicker("subtitle")
    else if id = "quality" then
        openPicker("quality")
    else if id = "autoplay" then
        p = AA_copy(m.global.prefs)
        p.autoPlayNext = not (p.autoPlayNext <> false)
        Prefs_save(p)
        buildHudRows()
    else if Subs_activateHudRow(id) then
        ' Handled by the subtitle suite.
    else if Left(id, 8) = "chapter:" then
        idx = Int(Val(Mid(id, 9)))
        if idx >= 0 and idx < m.chapters.Count() then
            seekToSource(m.chapters[idx].start_seconds * 1.0)
            closeHud()
        end if
    end if
end sub

' ---------- Pickers ----------

sub openPicker(kind as string)
    m.pickerKind = kind
    acts = []
    m.hudChoices = []
    if kind = "audio" then
        tracks = Arr_or(m.video.availableAudioTracks)
        cur = Str_orEmpty(m.video.audioTrack)
        for i = 0 to tracks.Count() - 1
            t = tracks[i]
            acts.Push({ id: i.ToStr(), label: audioTrackLabel(t), checked: Str_orEmpty(t.Track) = cur or (cur = "" and i = 0) })
        end for
        if acts.Count() = 0 then acts.Push({ id: "-1", label: "Default", checked: true })
        m.picker.title = "Audio"
    else if kind = "subtitle" then
        acts.Push({ id: "-1", label: "Off", checked: m.subtitleIndex < 0 })
        for i = 0 to m.subtitleTracks.Count() - 1
            ' The detail line is the track's sync status ("Syncing… 40%", "Synced +2.3 s"), when it has one.
            acts.Push({ id: i.ToStr(), label: m.subtitleTracks[i].label, checked: i = m.subtitleIndex, detail: Subs_trackStatus(m.subtitleTracks[i]) })
        end for
        m.picker.title = "Subtitles"
    else if kind = "quality" then
        acts.Push({ id: "auto", label: "Auto", checked: m.qualityPref = "auto" or m.qualityPref = "" })
        if m.plan <> invalid then
            for each q in Arr_or(m.plan.available_qualities)
                l = Str_orEmpty(q.label)
                if l <> "" then
                    text = l
                    if q.height <> invalid and LCase(l) <> Str_orEmpty(q.height) + "p" then text = l + " · " + Str_orEmpty(q.height) + "p"
                    acts.Push({ id: l, label: text, checked: LCase(m.qualityPref) = LCase(l) })
                end if
            end for
        end if
        m.picker.title = "Quality"
    end if
    m.picker.actions = acts
    m.picker.visible = true
    m.picker.setFocus(true)
    m.hideTimer.control = "stop"
end sub

sub onPickerDismissed()
    m.picker.visible = false
    afterPicker()
end sub

sub afterPicker()
    if m.hud.visible then
        buildHudRows()
        focusHud()
    else if m.controls.visible then
        focusControls()
        rearmHide()
    else
        m.focusSink.setFocus(true)
    end if
end sub

sub onPickerChosen()
    id = m.picker.chosen
    m.picker.visible = false
    kind = m.pickerKind
    if kind = "audio" then
        idx = Int(Val(id))
        tracks = Arr_or(m.video.availableAudioTracks)
        if idx >= 0 and idx < tracks.Count() then m.video.audioTrack = tracks[idx].Track
    else if kind = "subtitle" then
        setSubtitle(Int(Val(id)))
    else if kind = "quality" then
        if LCase(id) <> LCase(m.qualityPref) then requestQualityChange(id)
    else if kind = "subtiming" then
        Subs_timingChosen(id)
    end if
    afterPicker()
end sub

sub setSubtitle(idx as integer)
    if idx < 0 or idx >= m.subtitleTracks.Count() then
        m.subtitleIndex = -1
        m.video.subtitleTrack = ""
        m.video.globalCaptionMode = "Off"
    else
        m.subtitleIndex = idx
        m.video.globalCaptionMode = "On"
        m.video.subtitleTrack = m.subtitleTracks[idx].url
    end if
end sub

' Quality change: replan and hand the new plan to the player at the current position.
sub requestQualityChange(label as string)
    if m.plan = invalid or m.sessionId = "" then return
    inst = installationId()
    if inst = "" then return
    m.qualityPref = label
    selected = {}
    if m.plan.selected_tracks <> invalid then selected = m.plan.selected_tracks
    body = PlaybackCaps_replanBody(inst, m.attemptId, m.plan, "quality_change", label, m.position, selected)
    setBuffering(true)
    Api_send("POST", "/api/v2/playback/" + Str_urlEncode(m.sessionId) + "/replan", body, "onReplan")
end sub

sub onReplan(event as object)
    resp = Api_result(event)
    if m.closing then return
    if not resp.ok or resp.data = invalid or resp.data.outcome <> "playable" or resp.data.playback_plan = invalid then
        setBuffering(false)
        m.global.toast = "Couldn't change the quality"
        if m.plan <> invalid then m.qualityPref = PlaybackCaps_qualityPreference()
        return
    end if
    plan = resp.data.playback_plan
    if PlaybackCaps_planProblem(resp.data) <> "" then
        setBuffering(false)
        m.global.toast = "Couldn't change the quality"
        return
    end if
    resumeAt = m.position
    m.video.control = "stop"
    applyPlan(plan, { resumeAt: resumeAt, subtitleTrackId: Subs_selectedTrackId() })
end sub

' ---------- Keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then
        if (key = "left" or key = "right") and m.scrubbing then endHold()
        return false
    end if
    if m.closing then return true
    if m.errorGroup.visible then
        if key = "back" then
            exitPlayer()
            return true
        else if key = "left" or key = "right" then
            if m.retryBtn.hasFocus() then m.errorCloseBtn.setFocus(true) else m.retryBtn.setFocus(true)
            return true
        end if
        return true
    end if
    if m.picker.visible or m.subsDialog.visible then return true
    if m.upNext.visible then return handleUpNextKey(key)
    if m.hud.visible then return handleHudKey(key)
    if key = "play" then
        togglePlay()
        return true
    end if
    if m.controls.visible then return handleControlsKey(key)
    return handleCleanKey(key)
end function

function handleUpNextKey(key as string) as boolean
    btns = m.upNextButtons
    if key = "down" then
        if m.upNextIndex < btns.Count() - 1 then m.upNextIndex = m.upNextIndex + 1
        focusUpNext()
        m.countdownTimer.control = "stop"
        m.unPlayBtn.text = "Play Now"
        m.countdown = -1
    else if key = "up" then
        if m.upNextIndex > 0 then m.upNextIndex = m.upNextIndex - 1
        focusUpNext()
    else if key = "back" then
        keepWatching()
    end if
    return true
end function

function handleHudKey(key as string) as boolean
    if key = "back" then
        closeHud()
        return true
    end if
    if m.hudFocus = "tabs" then
        if key = "left" then
            selectHudTab(m.hudTab - 1)
        else if key = "right" then
            selectHudTab(m.hudTab + 1)
        else if key = "down" then
            if m.hudRows.Count() > 0 then
                m.hudFocus = "rows"
                m.hudRow = 0
                focusHud()
            end if
        else if key = "up" then
            closeHud()
        end if
        return true
    end if
    ' Rows
    if key = "up" then
        if m.hudRow > 0 then
            m.hudRow = m.hudRow - 1
            applyHudRowFocus()
        else
            m.hudFocus = "tabs"
            focusHud()
        end if
    else if key = "down" then
        if m.hudRow < m.hudRows.Count() - 1 then
            m.hudRow = m.hudRow + 1
            applyHudRowFocus()
        end if
    else if key = "OK" then
        activateHudRow()
    end if
    return true
end function

function handleControlsKey(key as string) as boolean
    rearmHide()
    if key = "back" then
        cancelScrub()
        hideControls()
        return true
    end if
    zone = m.controlsZone
    if m.skipBtn.hasFocus() and m.skipGroup.visible then zone = "skip"
    if zone = "scrubber" then
        if key = "left" then
            nudgeScrub(-1)
        else if key = "right" then
            nudgeScrub(1)
        else if key = "OK" then
            commitScrub()
        else if key = "down" then
            cancelScrub()
            m.controlsZone = "transport"
            focusControls()
        else if key = "up" then
            if m.skipGroup.visible and m.skipBtn.visible then
                cancelScrub()
                m.controlsZone = "skip"
                m.skipBtn.setFocus(true)
            end if
        else if key = "rewind" or key = "replay" then
            onSkipBack()
        else if key = "fastforward" then
            onSkipForward()
        end if
        return true
    else if zone = "skip" then
        if key = "down" then
            m.controlsZone = "scrubber"
            focusControls()
        end if
        return true
    end if
    ' Transport row
    btns = transportButtons()
    if key = "left" then
        if m.transportIndex > 0 then
            m.transportIndex = m.transportIndex - 1
            btns[m.transportIndex].setFocus(true)
        end if
    else if key = "right" then
        if m.transportIndex < btns.Count() - 1 then
            m.transportIndex = m.transportIndex + 1
            btns[m.transportIndex].setFocus(true)
        end if
    else if key = "up" then
        m.controlsZone = "scrubber"
        focusControls()
    else if key = "down" then
        hideControls()
    else if key = "rewind" or key = "replay" then
        onSkipBack()
    else if key = "fastforward" then
        onSkipForward()
    else if key = "options" then
        openHud(1)
    else if key = "OK" then
        ' A focused button handles OK itself; this is the fallthrough when none is focused.
        focusControls()
    end if
    return true
end function

function handleCleanKey(key as string) as boolean
    if key = "back" then
        if m.skipGroup.visible and m.skipBtn.hasFocus() then
            hideSkipPill()
            return true
        end if
        exitPlayer()
        return true
    else if key = "left" or key = "rewind" or key = "replay" then
        onSkipBack()
        return true
    else if key = "right" or key = "fastforward" then
        onSkipForward()
        return true
    else if key = "down" then
        openHud(2)
        return true
    else if key = "options" then
        openHud(1)
        return true
    else if key = "up" or key = "OK" then
        if m.plan <> invalid then showControls()
        return true
    end if
    return false
end function
