' Audio player for music queues and audiobooks. See AudioPlayerScreen.xml for the params contract.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.audio = m.top.findNode("audio")
    m.focusSink = m.top.findNode("focusSink")
    m.backdrop = m.top.findNode("backdrop")
    m.main = m.top.findNode("main")
    m.coverImage = m.top.findNode("coverImage")
    m.coverIcon = m.top.findNode("coverIcon")
    m.eyebrow = m.top.findNode("eyebrow")
    m.titleLabel = m.top.findNode("npTitle")
    m.line2 = m.top.findNode("line2")
    m.line3 = m.top.findNode("line3")
    m.trackBar = m.top.findNode("trackBar")
    m.fillBar = m.top.findNode("fillBar")
    m.ticks = m.top.findNode("ticks")
    m.elapsed = m.top.findNode("elapsed")
    m.remaining = m.top.findNode("remaining")
    m.statusLabel = m.top.findNode("statusLabel")
    m.prevBtn = m.top.findNode("prevBtn")
    m.backBtn = m.top.findNode("backBtn")
    m.playBtn = m.top.findNode("playBtn")
    m.fwdBtn = m.top.findNode("fwdBtn")
    m.nextBtn = m.top.findNode("nextBtn")
    m.listBtn = m.top.findNode("listBtn")
    m.sleepBtn = m.top.findNode("sleepBtn")
    m.spinner = m.top.findNode("spinner")
    m.errorGroup = m.top.findNode("errorGroup")
    m.errorLabel = m.top.findNode("errorLabel")
    m.retryBtn = m.top.findNode("retryBtn")
    m.errorCloseBtn = m.top.findNode("errorCloseBtn")
    m.panel = m.top.findNode("panel")
    m.progressTimer = m.top.findNode("progressTimer")
    m.sleepTimer = m.top.findNode("sleepTimer")
    m.stopTimeout = m.top.findNode("stopTimeout")
    m.refreshTimeout = m.top.findNode("refreshTimeout")

    m.di = CreateObject("roDeviceInfo")
    m.barW = 884
    m.started = false
    m.closing = false
    m.closed = false
    m.mode = ""
    m.queue = []
    m.qIndex = 0
    m.item = invalid
    m.timeline = invalid
    m.trackIdx = -1
    m.contentId = ""
    m.sessionId = ""
    m.sessionFile = ""
    m.sequence = 0
    m.stopId = ""
    m.attemptId = ""
    m.loadGen = 0
    m.pending = invalid
    m.retriedInstall = false
    m.timelineOffset = 0.0
    m.fileDuration = 0.0
    m.localPos = 0.0
    m.globalPos = 0.0
    m.isPaused = false
    m.ended = false
    m.pendingSeek = -1.0
    m.waitingForToken = false
    m.chapterIdx = -1
    m.sleepMode = "off"
    m.sleepRemaining = 0
    m.sleepChapterEnd = -1.0
    m.panelKind = ""
    m.zone = "transport"
    m.tIndex = 2
    m.uIndex = 0

    m.audio.observeField("state", "onAudioState")
    m.audio.observeField("position", "onAudioPosition")
    m.audio.observeField("duration", "onAudioDuration")
    m.progressTimer.observeField("fire", "onProgressTick")
    m.sleepTimer.observeField("fire", "onSleepTick")
    m.stopTimeout.observeField("fire", "finishClose")
    m.refreshTimeout.observeField("fire", "onTokenRefreshed")

    m.prevBtn.observeField("buttonSelected", "onPrev")
    m.backBtn.observeField("buttonSelected", "onSkipBack")
    m.playBtn.observeField("buttonSelected", "togglePlay")
    m.fwdBtn.observeField("buttonSelected", "onSkipForward")
    m.nextBtn.observeField("buttonSelected", "onNext")
    m.listBtn.observeField("buttonSelected", "openListPanel")
    m.sleepBtn.observeField("buttonSelected", "openSleepPanel")
    m.listBtn.observeField("width", "layoutUtility")
    m.sleepBtn.observeField("width", "layoutUtility")
    m.retryBtn.observeField("buttonSelected", "retry")
    m.errorCloseBtn.observeField("buttonSelected", "exitPlayer")
    m.panel.observeField("chosen", "onPanelChosen")
    m.panel.observeField("dismissed", "closePanel")
    layoutTransport()
end sub

' ---------- Lifecycle ----------

sub onScreenShown()
    if not m.started then
        m.started = true
        m.focusSink.setFocus(true)
        startPipeline()
        return
    end if
    restoreFocus()
end sub

sub startPipeline()
    p = m.top.params
    if p = invalid then p = {}
    m.errorGroup.visible = false
    m.spinner.visible = true
    q = Arr_or(p.queue)
    if q.Count() > 0 then
        setupQueue(q, p)
        playQueueIndex(m.qIndex, startParam(p))
        return
    end if
    m.contentId = Str_orEmpty(p.itemId)
    if m.contentId = "" then
        showError("Nothing to play.")
        return
    end if
    Api_get("/api/v2/catalog/items/" + Str_urlEncode(m.contentId), { image_size: "large" }, "onItem")
end sub

' Covered or removed without going through Back (e.g. a stack reset): stop playback.
sub onScreenHidden()
    if m.closing then return
    syncBookProgress()
    m.closing = true
    m.global.homeDirty = true
    m.sleepTimer.control = "stop"
    m.audio.control = "stop"
    stopSession(false)
end sub

sub retry()
    m.errorGroup.visible = false
    m.retriedInstall = false
    if m.mode = "audiobook" and m.timeline <> invalid then
        seekGlobal(m.globalPos, true)
    else if m.mode = "music" and m.queue.Count() > 0 then
        playQueueIndex(m.qIndex, m.localPos)
    else
        startPipeline()
    end if
end sub

' Numeric params.startPosition, or -1 when absent.
function startParam(p as object) as float
    v = p.startPosition
    if v = invalid then return -1.0
    t = Type(v)
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" or t = "roLongInteger" or t = "LongInteger" then
        if v >= 0 then return v * 1.0
    end if
    return -1.0
end function

sub onItem(event as object)
    resp = Api_result(event)
    if m.closing then return
    if not resp.ok or resp.data = invalid then
        showError(Api_errorText(resp))
        return
    end if
    it = resp.data
    hint = LCase(Str_orEmpty(m.top.params.itemType))
    kind = Audio_itemType(it)
    if kind = "audiobook" or (kind = "" and hint = "audiobook") then
        setupAudiobook(it)
    else
        ' A single track (or other audio item): a one-entry queue.
        setupQueue([it], m.top.params)
        playQueueIndex(0, startParam(m.top.params))
    end if
end sub

' ---------- Music queue ----------

sub setupQueue(q as object, p as object)
    m.mode = "music"
    m.queue = []
    for each e in q
        entry = Audio_queueEntry(e)
        if entry.contentId <> "" or entry.fileId <> "" then m.queue.Push(entry)
    end for
    if m.queue.Count() = 0 then
        showError("Nothing to play.")
        return
    end if
    idx = 0
    if p.index <> invalid then idx = Int(p.index)
    if idx < 0 or idx >= m.queue.Count() then idx = 0
    if p.shuffle = true then
        first = m.queue[idx]
        rest = []
        for i = 0 to m.queue.Count() - 1
            if i <> idx then rest.Push(m.queue[i])
        end for
        for i = rest.Count() - 1 to 1 step -1
            j = Rnd(i + 1) - 1
            tmp = rest[i]
            rest[i] = rest[j]
            rest[j] = tmp
        end for
        m.queue = [first]
        m.queue.Append(rest)
        idx = 0
    end if
    m.qIndex = idx
    m.eyebrow.text = "NOW PLAYING"
    m.listBtn.text = "Up Next"
    m.listBtn.iconUri = "pkg:/images/icons/list.png"
    m.backBtn.iconUri = "pkg:/images/icons/rewind.png"
    m.fwdBtn.iconUri = "pkg:/images/icons/forward.png"
    m.coverIcon.uri = "pkg:/images/icons/music.png"
end sub

sub playQueueIndex(idx as integer, startAt as float)
    if m.mode <> "music" or idx < 0 or idx >= m.queue.Count() then return
    ' Retire the outgoing track first so its stop reports where it actually was.
    stopSession(true)
    m.qIndex = idx
    m.ended = false
    e = m.queue[idx]
    m.fileDuration = e.durationSeconds
    m.localPos = 0.0
    if startAt > 0 then m.localPos = startAt
    m.globalPos = m.localPos
    showMusicInfo()
    if e.fileId = "" then
        ' Resolve the file through the catalog item.
        m.loadGen = m.loadGen + 1
        Api_get("/api/v2/catalog/items/" + Str_urlEncode(e.contentId), { image_size: "large" }, "onTrackItem", { gen: m.loadGen, index: idx, startAt: startAt })
        return
    end if
    startFile(e.fileId, startAt, "server")
end sub

sub onTrackItem(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if m.closing or ctx = invalid or ctx.gen <> m.loadGen then return
    e = m.queue[ctx.index]
    if resp.ok and resp.data <> invalid then
        it = resp.data
        fileId = ""
        ud = it.user_data
        versions = Arr_or(it.versions)
        if ud <> invalid and not Str_isEmpty(ud.last_file_id) then
            for each v in versions
                if Str_orEmpty(v.file_id) = ud.last_file_id then fileId = ud.last_file_id
            end for
        end if
        if fileId = "" and versions.Count() > 0 then fileId = Str_orEmpty(versions[0].file_id)
        if fileId = "" then fileId = Str_orEmpty(it.file_id)
        e.fileId = fileId
        if e.title = "" then e.title = Str_orEmpty(it.title)
        if e.posterUrl = "" then e.posterUrl = Str_orEmpty(it.poster_url)
        if e.artist = "" then e.artist = Audio_queueEntry(it).artist
        if e.album = "" then e.album = Audio_queueEntry(it).album
        if e.durationSeconds <= 0 and versions.Count() > 0 then e.durationSeconds = AudioTimeline_num(versions[0].duration)
        m.queue[ctx.index] = e
        showMusicInfo()
    end if
    if e.fileId = "" then
        trackFailed("This track has no playable file.")
        return
    end if
    startFile(e.fileId, ctx.startAt, "server")
end sub

sub showMusicInfo()
    e = m.queue[m.qIndex]
    title = e.title
    if title = "" then title = "Unknown track"
    m.titleLabel.text = title
    m.line2.text = e.artist
    m.line3.text = e.album
    m.line3.color = "0xEDEDEDBF"
    n = m.queue.Count()
    if n > 1 then m.eyebrow.text = "NOW PLAYING · " + (m.qIndex + 1).ToStr() + " OF " + n.ToStr() else m.eyebrow.text = "NOW PLAYING"
    setCover(e.posterUrl)
    m.ticks.removeChildrenIndex(m.ticks.getChildCount(), 0)
    m.prevBtn.opacity = 1.0
    if m.qIndex < n - 1 then m.nextBtn.opacity = 1.0 else m.nextBtn.opacity = 0.4
    m.main.visible = true
    m.spinner.visible = false
    layoutInfo()
    updateProgressUi()
    if m.focusSink.hasFocus() then restoreFocus()
end sub

' A track that can't play: say so inline and keep the player up; Next / the Up Next panel move on.
sub trackFailed(msg as string)
    m.spinner.visible = false
    m.statusLabel.text = msg
    m.isPaused = true
    m.playBtn.iconUri = "pkg:/images/icons/play.png"
end sub

' ---------- Audiobook ----------

sub setupAudiobook(it as object)
    m.mode = "audiobook"
    m.item = it
    m.contentId = Str_orEmpty(it.content_id)
    ab = it.audiobook
    if ab = invalid then ab = {}
    ud = it.user_data
    if ud = invalid then ud = {}
    m.timeline = AudioTimeline_build(it.versions, ab.total_duration_seconds, Str_orEmpty(ud.last_file_id))
    if m.timeline = invalid then
        ' No tagged parts: fall back to the first file as a single-part book.
        versions = Arr_or(it.versions)
        if versions.Count() = 0 then
            showError("No playable audiobook file is available.")
            return
        end if
        v = versions[0]
        dur = AudioTimeline_partDuration(v)
        chapters = []
        for each ch in Arr_or(v.chapters)
            chapters.Push({ index: chapters.Count(), title: Str_orEmpty(ch.title), start: AudioTimeline_num(ch.start_seconds), "end": AudioTimeline_num(ch.end_seconds), trackIndex: 0 })
        end for
        m.timeline = { tracks: [{ index: 0, fileId: Str_orEmpty(v.file_id), duration: dur, offset: 0.0 }], chapters: chapters, total: dur, isSingle: true }
    end if

    m.eyebrow.text = "AUDIOBOOK"
    authors = []
    for each a in Arr_or(ab.authors)
        authors.Push(Str_orEmpty(a.name))
    end for
    if authors.Count() = 0 then
        for each a in Arr_or(ab.narrators)
            authors.Push(Str_orEmpty(a.name))
        end for
    end if
    m.titleLabel.text = Str_orEmpty(it.title)
    m.line2.text = Str_joinDots(authors, ", ")
    m.line3.color = "0xEDEDEDFF"
    m.listBtn.text = "Chapters"
    m.listBtn.iconUri = "pkg:/images/icons/chapters.png"
    m.listBtn.visible = m.timeline.chapters.Count() > 1
    m.backBtn.iconUri = "pkg:/images/icons/rewind_30.png"
    m.fwdBtn.iconUri = "pkg:/images/icons/forward.png"
    m.coverIcon.uri = "pkg:/images/icons/audiobook.png"
    setCover(Str_orEmpty(it.poster_url))
    drawChapterTicks()
    m.main.visible = true
    m.spinner.visible = false
    layoutInfo()
    layoutUtility()
    if m.focusSink.hasFocus() then restoreFocus()

    ' Start: explicit whole-book position, else the stored resume point (TvAudiobookDetailHero rules).
    startAt = startParam(m.top.params)
    if startAt < 0 then
        startAt = 0.0
        posSec = AudioTimeline_num(ud.position_seconds)
        if posSec > 0 and posSec < m.timeline.total - 5 then startAt = posSec
    end if
    seekGlobal(startAt, true)
end sub

sub drawChapterTicks()
    m.ticks.removeChildrenIndex(m.ticks.getChildCount(), 0)
    if m.timeline = invalid or m.timeline.total <= 0 then return
    chapters = m.timeline.chapters
    if chapters.Count() <= 1 then return
    for i = 1 to chapters.Count() - 1
        x = Int(m.barW * (chapters[i].start / m.timeline.total))
        r = m.ticks.createChild("Rectangle")
        r.translation = [x, 0]
        r.width = 2
        r.height = 12
        r.color = "0x00000073"
    end for
end sub

' Moves the book to a whole-book time: a seek within the loaded part, or a new part session.
sub seekGlobal(t as float, forceStart as boolean)
    tl = m.timeline
    if tl = invalid then return
    if t < 0 then t = 0
    if tl.total > 0 and t > tl.total then t = tl.total
    idx = AudioTimeline_trackIndexAt(tl, t)
    tr = tl.tracks[idx]
    localT = AudioTimeline_localTime(tr, t)
    m.ended = false
    m.globalPos = t
    if not forceStart and idx = m.trackIdx and m.sessionId <> "" then
        seekLocal(localT)
    else
        stopSession(true)
        m.trackIdx = idx
        m.fileDuration = tr.duration
        m.localPos = localT
        startFile(tr.fileId, localT, "client")
    end if
    updateProgressUi()
end sub

' Whole-book progress (furthest-wins on the server): POST /api/v2/sync/progress.
sub syncBookProgress()
    if m.mode <> "audiobook" or m.contentId = "" or m.timeline = invalid then return
    if m.globalPos <= 0 then return
    body = { items: [{ media_item_id: m.contentId, position_ms: Int(m.globalPos * 1000), duration_ms: Int(m.timeline.total * 1000) }] }
    Api_send("POST", "/api/v2/sync/progress", body, "onSynced")
end sub

sub onSynced(event as object)
    resp = Api_result(event)
    if not resp.ok then print "[AudioPlayer] sync/progress "; resp.status
end sub

' ---------- Sessions ----------

' Retires the current session and starts one for fileId at a file-local position.
sub startFile(fileId as string, localStart as float, persistence as string)
    stopSession(true)
    m.audio.control = "stop"
    m.loadGen = m.loadGen + 1
    m.attemptId = m.di.GetRandomUUID()
    m.retriedInstall = false
    m.pending = { fileId: fileId, localStart: localStart, persistence: persistence, gen: m.loadGen }
    ' The centered spinner is for the first load only; afterwards the status line says it.
    m.spinner.visible = not m.main.visible
    m.statusLabel.text = "Loading…"
    ensureFreshToken()
end sub

' The Audio node can't refresh headers mid-stream: refresh first when the token is about to expire.
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

function installationId() as string
    c = cachedCaps()
    if c = invalid then return ""
    return c.installation_id
end function

sub fetchCapabilities()
    if cachedCaps() <> invalid then
        sendStart()
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
    sendStart()
end sub

sub sendStart()
    pd = m.pending
    if pd = invalid or m.closing then return
    body = AudioCaps_startBody(installationId(), pd.fileId, m.attemptId, pd.localStart, pd.persistence)
    Api_send("POST", "/api/v2/playback/start", body, "onStart", { gen: pd.gen, fileId: pd.fileId })
end sub

sub onStart(event as object)
    resp = Api_result(event)
    ctx = resp.context
    stale = m.closing or ctx = invalid or ctx.gen <> m.loadGen
    if stale then
        ' Superseded (seek / skip / close while in flight): release the session we no longer need.
        if resp.ok and resp.data <> invalid and not Str_isEmpty(resp.data.session_id) then
            inst = installationId()
            body = { installation_id: inst, stop_id: m.di.GetRandomUUID() }
            Api_send("DELETE", "/api/v2/playback/" + Str_urlEncode(resp.data.session_id), body, "onStopped")
        end if
        return
    end if
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
        failFile(Api_errorText(resp))
        return
    end if
    d = resp.data
    if d.outcome <> "playable" then
        msg = ""
        if d.terminal <> invalid then msg = Str_orEmpty(d.terminal.message)
        if msg = "" then msg = "This can't be played right now."
        failFile(msg)
        return
    end if
    problem = PlaybackCaps_planProblem(d)
    if problem <> "" then
        failFile(problem)
        return
    end if
    m.sessionId = Str_orEmpty(d.session_id)
    if m.sessionId = "" then m.sessionId = Str_orEmpty(d.playback_plan.session_id)
    m.sessionFile = ctx.fileId
    m.sequence = 0
    m.stopId = ""
    m.pending = invalid
    applyPlan(d.playback_plan)
end sub

' A failed start: fatal for an audiobook, a skippable track for music.
sub failFile(msg as string)
    m.pending = invalid
    if m.mode = "music" and m.queue.Count() > 1 then
        trackFailed(msg)
    else
        showError(msg)
    end if
end sub

sub applyPlan(plan as object)
    s = m.global.session
    stream = plan.stream
    tl = plan.timeline
    if tl = invalid then tl = {}
    m.timelineOffset = 0.0
    if tl.timeline_offset_seconds <> invalid then m.timelineOffset = AudioTimeline_num(tl.timeline_offset_seconds)
    if plan.source <> invalid then
        srcDur = AudioTimeline_num(plan.source.duration_seconds)
        if srcDur > 0 then setFileDuration(srcDur)
    end if

    url = Url_resolve(stream.url)
    content = CreateObject("roSGNode", "ContentNode")
    content.Url = url
    content.Title = m.titleLabel.text
    fmt = AudioCaps_streamFormat(stream, url)
    if fmt <> "" then content.StreamFormat = fmt
    headers = ["Authorization:Bearer " + s.accessToken]
    if stream.headers <> invalid then
        for each k in stream.headers
            headers.Push(k + ":" + Str_orEmpty(stream.headers[k]))
        end for
    end if
    content.HttpHeaders = headers
    if LCase(Left(url, 5)) = "https" then content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    if m.fileDuration > 0 then content.Length = Int(m.fileDuration)
    playerStart = AudioTimeline_num(tl.player_start_seconds)
    m.pendingSeek = -1.0
    if playerStart > 0 then
        content.PlayStart = Int(playerStart)
        ' Some firmware ignores PlayStart on Audio: seek once playback begins if we're far off.
        m.pendingSeek = playerStart
    end if
    print "[AudioPlayer] playing "; url; " fmt "; fmt
    m.audio.content = content
    m.audio.control = "play"
    m.isPaused = false
    m.playBtn.iconUri = "pkg:/images/icons/pause.png"
    m.progressTimer.control = "start"
end sub

' Keeps the timeline in step when the plan reports a real file duration (single-file fallback).
sub setFileDuration(d as float)
    m.fileDuration = d
    if m.mode = "audiobook" and m.timeline <> invalid and m.timeline.tracks.Count() = 1 then
        tr = m.timeline.tracks[0]
        if tr.duration <= 0 then
            tr.duration = d
            if m.timeline.total < d then m.timeline.total = d
            drawChapterTicks()
        end if
    else if m.mode = "music" then
        e = m.queue[m.qIndex]
        if e.durationSeconds <= 0 then
            e.durationSeconds = d
            m.queue[m.qIndex] = e
        end if
    end if
end sub

sub onProgressTick()
    if m.isPaused then return
    sendProgress()
    syncBookProgress()
end sub

sub sendProgress()
    if m.sessionId = "" or m.closing then return
    inst = installationId()
    if inst = "" then return
    m.sequence = m.sequence + 1
    body = { installation_id: inst, sequence: m.sequence, position: m.localPos, is_paused: m.isPaused }
    Api_send("POST", "/api/v2/playback/" + Str_urlEncode(m.sessionId) + "/progress", body, "onProgressResult", { sid: m.sessionId })
end sub

sub onProgressResult(event as object)
    resp = Api_result(event)
    if (resp.status = 404 or resp.status = 410) and resp.context <> invalid and resp.context.sid = m.sessionId then
        ' The session ended on the server; stop reporting.
        m.sessionId = ""
    end if
end sub

' DELETE the current session with a final file-local sample. Safe to call twice.
sub stopSession(retiring as boolean)
    if m.sessionId = "" then return
    inst = installationId()
    sid = m.sessionId
    m.sessionId = ""
    m.progressTimer.control = "stop"
    if inst = "" then return
    if m.stopId = "" then m.stopId = m.di.GetRandomUUID()
    m.sequence = m.sequence + 1
    body = { installation_id: inst, stop_id: m.stopId, sequence: m.sequence, position: m.localPos, is_paused: true }
    cb = "onRetired"
    if not retiring then cb = "onStopped"
    Api_send("DELETE", "/api/v2/playback/" + Str_urlEncode(sid), body, cb)
    m.stopId = ""
end sub

sub onRetired(event as object)
    Api_result(event)
end sub

sub onStopped(event as object)
    Api_result(event)
    if m.closing then finishClose()
end sub

sub exitPlayer()
    if m.closing then return
    syncBookProgress()
    m.closing = true
    m.global.homeDirty = true
    m.sleepTimer.control = "stop"
    m.audio.control = "stop"
    hadSession = m.sessionId <> ""
    stopSession(false)
    if hadSession then
        m.stopTimeout.control = "start"
    else
        finishClose()
    end if
end sub

sub finishClose()
    if m.closed then return
    m.closed = true
    m.stopTimeout.control = "stop"
    Nav_close()
end sub

sub showError(msg as string)
    m.spinner.visible = false
    m.progressTimer.control = "stop"
    m.panel.visible = false
    m.errorLabel.text = msg
    m.errorGroup.visible = true
    m.retryBtn.setFocus(true)
end sub

' ---------- Audio node ----------

sub onAudioState()
    st = m.audio.state
    print "[AudioPlayer] state "; st
    if st = "buffering" then
        m.spinner.visible = false
        m.statusLabel.text = "Buffering…"
    else if st = "playing" then
        m.spinner.visible = false
        m.statusLabel.text = ""
        m.isPaused = false
        m.playBtn.iconUri = "pkg:/images/icons/pause.png"
        if m.pendingSeek > 0 then
            target = m.pendingSeek
            m.pendingSeek = -1.0
            if Abs(m.audio.position - (target - m.timelineOffset)) > 3 then m.audio.seek = target - m.timelineOffset
        end if
    else if st = "paused" then
        m.spinner.visible = false
        m.isPaused = true
        m.statusLabel.text = "Paused"
        m.playBtn.iconUri = "pkg:/images/icons/play.png"
        sendProgress()
        syncBookProgress()
    else if st = "finished" then
        onFinished()
    else if st = "error" then
        msg = Str_orEmpty(m.audio.errorMsg)
        if msg = "" then msg = "This could not be played."
        print "[AudioPlayer] audio error "; m.audio.errorCode; " "; msg
        m.progressTimer.control = "stop"
        if m.mode = "music" then
            stopSession(true)
            trackFailed(msg)
        else
            showError(msg)
        end if
    end if
end sub

sub onAudioDuration()
    d = m.audio.duration
    if d > 0 and m.fileDuration <= 0 then setFileDuration(d * 1.0)
end sub

sub onAudioPosition()
    if m.sessionId = "" then return
    m.localPos = m.audio.position + m.timelineOffset
    if m.mode = "audiobook" and m.timeline <> invalid and m.trackIdx >= 0 then
        m.globalPos = m.timeline.tracks[m.trackIdx].offset + m.localPos
        if m.sleepMode = "chapter" and m.sleepChapterEnd > 0 and m.globalPos >= m.sleepChapterEnd then
            sleepNow()
        end if
    else
        m.globalPos = m.localPos
    end if
    updateProgressUi()
end sub

sub onFinished()
    if m.ended then return
    if m.mode = "audiobook" then
        tl = m.timeline
        if m.trackIdx >= 0 and m.trackIdx < tl.tracks.Count() - 1 then
            ' Next part: a new session (playback is not gapless across parts, as on Android).
            m.localPos = tl.tracks[m.trackIdx].duration
            seekGlobal(tl.tracks[m.trackIdx + 1].offset, true)
            return
        end if
        ' End of book: park at the total, final sync, keep the screen up.
        m.ended = true
        m.globalPos = tl.total
        m.localPos = tl.tracks[m.trackIdx].duration
        syncBookProgress()
        stopSession(true)
        m.isPaused = true
        m.statusLabel.text = "Finished"
        m.playBtn.iconUri = "pkg:/images/icons/replay.png"
        updateProgressUi()
        return
    end if
    ' Music: auto-advance; the end of the queue (or a "End of track" sleep timer) stops.
    if m.sleepMode = "track" then
        m.ended = true
        stopSession(true)
        setSleep("off")
        m.isPaused = true
        m.playBtn.iconUri = "pkg:/images/icons/play.png"
        m.statusLabel.text = "Sleep timer ended"
        return
    end if
    if m.qIndex < m.queue.Count() - 1 then
        playQueueIndex(m.qIndex + 1, 0)
    else
        m.ended = true
        exitPlayer()
    end if
end sub

' ---------- UI ----------

sub setCover(u as string)
    url = Url_resolve(u)
    m.coverImage.uri = url
    m.backdrop.uri = url
end sub

' Stacks title (1–2 lines) and the two lines under it.
sub layoutInfo()
    th = Int(m.titleLabel.boundingRect().height)
    if th < 70 then th = 70
    y = 278 + th + 14
    m.line2.translation = [0, y]
    m.line3.translation = [0, y + 58]
end sub

function transportButtons() as object
    return [m.prevBtn, m.backBtn, m.playBtn, m.fwdBtn, m.nextBtn]
end function

sub layoutTransport()
    x = 0
    for each b in transportButtons()
        s = b.size
        b.translation = [x, Int((128 - s) / 2)]
        x = x + s + 28
    end for
end sub

function utilityButtons() as object
    out = []
    for each b in [m.listBtn, m.sleepBtn]
        if b.visible then out.Push(b)
    end for
    return out
end function

sub layoutUtility()
    x = 0
    for each b in utilityButtons()
        b.translation = [x, 0]
        x = x + b.width + 16
    end for
end sub

sub updateProgressUi()
    total = 0.0
    cur = 0.0
    if m.mode = "audiobook" and m.timeline <> invalid then
        total = m.timeline.total
        cur = m.globalPos
        ci = AudioTimeline_chapterAt(m.timeline.chapters, cur)
        if ci <> m.chapterIdx then
            m.chapterIdx = ci
            if ci >= 0 then
                ch = m.timeline.chapters[ci]
                n = m.timeline.chapters.Count()
                label = ch.title
                if n > 1 then label = label + "  ·  " + (ci + 1).ToStr() + " of " + n.ToStr()
                m.line3.text = label
            else if m.timeline.tracks.Count() > 1 then
                m.line3.text = "Part " + (m.trackIdx + 1).ToStr() + " of " + m.timeline.tracks.Count().ToStr()
            end if
        end if
        if m.chapterIdx < 0 and m.timeline.tracks.Count() > 1 and m.trackIdx >= 0 then
            m.line3.text = "Part " + (m.trackIdx + 1).ToStr() + " of " + m.timeline.tracks.Count().ToStr()
        end if
    else
        total = m.fileDuration
        cur = m.localPos
    end if
    if cur < 0 then cur = 0
    if total > 0 and cur > total then cur = total
    frac = 0.0
    if total > 0 then frac = cur / total
    m.fillBar.width = Int(m.barW * frac)
    m.fillBar.visible = m.fillBar.width >= 6
    m.elapsed.text = Time_clock(cur)
    if total > 0 then m.remaining.text = "-" + Time_clock(total - cur) else m.remaining.text = "--:--"
end sub

' ---------- Transport ----------

sub togglePlay()
    if m.ended then
        ' Replay: the book from the start, or the queue's last track again.
        if m.mode = "audiobook" then
            seekGlobal(0, true)
        else
            playQueueIndex(m.qIndex, 0)
        end if
        return
    end if
    st = m.audio.state
    if st = "paused" then
        m.audio.control = "resume"
    else if st = "playing" or st = "buffering" then
        m.audio.control = "pause"
    else if m.sessionId = "" and m.pending = invalid then
        ' Stopped or failed: start again where we were.
        retry()
    end if
end sub

function skipBackSeconds() as integer
    if m.mode = "audiobook" then return 30
    return 10
end function

sub onSkipBack()
    skipBy(-skipBackSeconds())
end sub

sub onSkipForward()
    skipBy(30)
end sub

sub skipBy(delta as integer)
    if m.mode = "audiobook" then
        seekGlobal(m.globalPos + delta, false)
    else
        seekLocal(m.localPos + delta)
    end if
end sub

' Seek inside the current file (file-local seconds).
sub seekLocal(t as float)
    if m.sessionId = "" then return
    if t < 0 then t = 0
    if m.fileDuration > 0 and t > m.fileDuration - 1 then t = m.fileDuration - 1
    m.audio.seek = t - m.timelineOffset
    m.localPos = t
    if m.mode = "audiobook" and m.trackIdx >= 0 then
        m.globalPos = m.timeline.tracks[m.trackIdx].offset + t
    else
        m.globalPos = t
    end if
    updateProgressUi()
end sub

sub onPrev()
    if m.mode = "audiobook" then
        chapters = m.timeline.chapters
        if chapters.Count() = 0 then
            seekGlobal(0, false)
            return
        end if
        ci = AudioTimeline_chapterAt(chapters, m.globalPos)
        ' Restart the chapter when more than 3 s in, otherwise go to the previous one.
        if ci > 0 and m.globalPos - chapters[ci].start < 3 then ci = ci - 1
        if ci < 0 then ci = 0
        seekGlobal(chapters[ci].start, false)
        syncBookProgress()
    else
        if m.localPos > 3 or m.qIndex = 0 then
            if m.sessionId <> "" then seekLocal(0) else playQueueIndex(m.qIndex, 0)
        else
            playQueueIndex(m.qIndex - 1, 0)
        end if
    end if
end sub

sub onNext()
    if m.mode = "audiobook" then
        chapters = m.timeline.chapters
        ci = AudioTimeline_chapterAt(chapters, m.globalPos)
        if ci >= 0 and ci < chapters.Count() - 1 then
            seekGlobal(chapters[ci + 1].start, false)
            syncBookProgress()
        end if
    else if m.qIndex < m.queue.Count() - 1 then
        playQueueIndex(m.qIndex + 1, 0)
    end if
end sub

' ---------- Panels ----------

sub openListPanel()
    rows = []
    if m.mode = "audiobook" then
        cur = AudioTimeline_chapterAt(m.timeline.chapters, m.globalPos)
        for i = 0 to m.timeline.chapters.Count() - 1
            ch = m.timeline.chapters[i]
            rows.Push({ id: i.ToStr(), title: ch.title, number: (i + 1).ToStr(), trailing: Time_clock(ch.start), isCurrent: i = cur })
        end for
        openPanel("chapters", "Chapters", rows)
    else
        for i = 0 to m.queue.Count() - 1
            e = m.queue[i]
            trailing = ""
            if e.durationSeconds > 0 then trailing = Time_clock(e.durationSeconds)
            rows.Push({ id: i.ToStr(), title: e.title, number: (i + 1).ToStr(), subtitle: e.artist, trailing: trailing, isCurrent: i = m.qIndex })
        end for
        openPanel("queue", "Up Next", rows)
    end if
end sub

sub openSleepPanel()
    opts = [{ id: "off", title: "Off" }, { id: "15", title: "15 minutes" }, { id: "30", title: "30 minutes" }, { id: "60", title: "60 minutes" }]
    if m.mode = "audiobook" then
        if m.timeline.chapters.Count() > 0 then opts.Push({ id: "chapter", title: "End of chapter" })
    else
        opts.Push({ id: "track", title: "End of track" })
    end if
    for each o in opts
        o.isCurrent = o.id = m.sleepMode
    end for
    openPanel("sleep", "Sleep timer", opts)
end sub

sub openPanel(kind as string, title as string, rows as object)
    m.panelKind = kind
    m.panel.title = title
    m.panel.rows = rows
    m.panel.visible = true
    m.panel.setFocus(true)
end sub

sub closePanel()
    m.panel.visible = false
    m.panelKind = ""
    restoreFocus()
end sub

sub onPanelChosen()
    id = m.panel.chosen
    kind = m.panelKind
    closePanel()
    if kind = "chapters" then
        i = Int(Val(id))
        if i >= 0 and i < m.timeline.chapters.Count() then
            seekGlobal(m.timeline.chapters[i].start, false)
            syncBookProgress()
        end if
    else if kind = "queue" then
        i = Int(Val(id))
        if i >= 0 and i < m.queue.Count() and i <> m.qIndex then playQueueIndex(i, 0)
    else if kind = "sleep" then
        setSleep(id)
    end if
end sub

' ---------- Sleep timer ----------

sub setSleep(mode as string)
    m.sleepMode = mode
    m.sleepChapterEnd = -1.0
    m.sleepTimer.control = "stop"
    if mode = "15" or mode = "30" or mode = "60" then
        m.sleepRemaining = Int(Val(mode)) * 60
        m.sleepTimer.control = "start"
    else if mode = "chapter" then
        ci = AudioTimeline_chapterAt(m.timeline.chapters, m.globalPos)
        if ci >= 0 then
            ch = m.timeline.chapters[ci]
            m.sleepChapterEnd = ch["end"]
            if m.sleepChapterEnd <= ch.start then
                if ci < m.timeline.chapters.Count() - 1 then m.sleepChapterEnd = m.timeline.chapters[ci + 1].start else m.sleepChapterEnd = m.timeline.total
            end if
        end if
    end if
    updateSleepLabel()
end sub

sub updateSleepLabel()
    t = "Sleep Timer"
    if m.sleepMode = "chapter" then
        t = "Sleep: End of chapter"
    else if m.sleepMode = "track" then
        t = "Sleep: End of track"
    else if m.sleepMode <> "off" then
        mins = Int((m.sleepRemaining + 59) / 60)
        t = "Sleep: " + mins.ToStr() + " min"
    end if
    if m.sleepBtn.text <> t then m.sleepBtn.text = t
end sub

sub onSleepTick()
    if m.isPaused then return
    m.sleepRemaining = m.sleepRemaining - 1
    if m.sleepRemaining <= 0 then
        sleepNow()
        return
    end if
    updateSleepLabel()
end sub

sub sleepNow()
    setSleep("off")
    if m.audio.state = "playing" or m.audio.state = "buffering" then m.audio.control = "pause"
    m.global.toast = "Sleep timer ended"
end sub

' ---------- Focus and keys ----------

sub restoreFocus()
    if m.errorGroup.visible then
        m.retryBtn.setFocus(true)
    else if m.panel.visible then
        m.panel.setFocus(true)
    else if not m.main.visible then
        m.focusSink.setFocus(true)
    else if m.zone = "utility" and utilityButtons().Count() > 0 then
        btns = utilityButtons()
        if m.uIndex >= btns.Count() then m.uIndex = 0
        btns[m.uIndex].setFocus(true)
    else
        m.zone = "transport"
        transportButtons()[m.tIndex].setFocus(true)
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then
        if m.panel.visible then
            closePanel()
        else
            exitPlayer()
        end if
        return true
    end if
    if m.errorGroup.visible then
        if key = "left" then m.retryBtn.setFocus(true)
        if key = "right" then m.errorCloseBtn.setFocus(true)
        return true
    end if
    if key = "play" then
        togglePlay()
        return true
    else if key = "rewind" or key = "replay" then
        onSkipBack()
        return true
    else if key = "fastforward" then
        onSkipForward()
        return true
    else if key = "options" then
        if m.listBtn.visible then openListPanel()
        return true
    end if
    if not m.main.visible then return true
    if key = "left" or key = "right" then
        if m.zone = "utility" then
            btns = utilityButtons()
            if key = "left" and m.uIndex > 0 then m.uIndex = m.uIndex - 1
            if key = "right" and m.uIndex < btns.Count() - 1 then m.uIndex = m.uIndex + 1
        else
            if key = "left" and m.tIndex > 0 then m.tIndex = m.tIndex - 1
            if key = "right" and m.tIndex < 4 then m.tIndex = m.tIndex + 1
        end if
        restoreFocus()
        return true
    else if key = "down" then
        if utilityButtons().Count() > 0 then m.zone = "utility"
        restoreFocus()
        return true
    else if key = "up" then
        m.zone = "transport"
        restoreFocus()
        return true
    end if
    return false
end function
