' SPDX-License-Identifier: AGPL-3.0-or-later
' Live AI subtitle lines in the player (see components/common/AiLiveCues.brs for the server side).
' Included by PlayerScreen.xml; state lives in m.aiLive.
'
' Flow: Translate with AI → when the server serves the control socket (GET
' /api/v2/playback/sessions/control/capabilities) mint POST
' /api/v2/playback/sessions/{sid}/control/ws-ticket, open the socket in AiLiveTask, and send the
' job only once it is open (or failed, or 6 s passed): the server streams to the socket that is
' there when the job starts and replays nothing. Lines then show in aiLiveGroup, timed to the
' video, until the stored track is selected (SubtitleSuite's job poll stays the authority and
' adopts it as before). A Roku without roWebSocket (before Roku OS 16) reports "unsupported" once
' and translates as before for the rest of the player.

sub AiLive_init()
    m.aiLiveGroup = m.top.findNode("aiLiveGroup")
    m.aiLiveText = m.top.findNode("aiLiveText")
    m.aiLiveShadow = m.top.findNode("aiLiveShadow")
    m.aiLiveTimer = m.top.findNode("aiLiveTimer")
    m.aiLiveConnectTimer = m.top.findNode("aiLiveConnectTimer")
    m.aiLiveTimer.observeField("fire", "AiLive_onTick")
    m.aiLiveConnectTimer.observeField("fire", "AiLive_onConnectTimeout")
    m.aiLive = { caps: "unknown", unsupported: false, task: invalid, conn: "off", connSession: "", waitingSend: false, lastEventId: 0, clock: CreateObject("roTimespan"), logClock: CreateObject("roTimespan"), posAt: 0.0 }
    AiLive_resetJob()
end sub

' Per job: the cues and the job and live track they belong to.
sub AiLive_resetJob()
    a = m.aiLive
    a.jobId = ""
    a.trackKey = ""
    a.cues = []
    a.seen = {}
    a.buffered = []
    a.active = false
    a.userLeft = false
    a.savedIndex = -1
    a.shown = ""
    a.done = 0
    a.total = 0
    a.loggedAt = -1
    if a.logClock = invalid then a.logClock = CreateObject("roTimespan")
    a.selecting = false
    if m.aiLiveGroup <> invalid then m.aiLiveGroup.visible = false
    if m.aiLiveTimer <> invalid then m.aiLiveTimer.control = "stop"
end sub

' A new playback attempt or file (Subs_resetPlayback): the session and its socket go.
sub AiLive_resetPlayback()
    if m.aiLive = invalid then return
    AiLive_close("reset")
    m.aiLive.caps = "unknown"
    AiLive_resetJob()
end sub

' Read once per player when the AI dialog first opens.
sub AiLive_readCaps()
    a = m.aiLive
    if a = invalid or a.caps <> "unknown" or a.unsupported then return
    a.caps = "pending"
    Api_get("/api/v2/playback/sessions/control/capabilities", invalid, "AiLive_onCaps", { fileId: m.fileId })
end sub

sub AiLive_onCaps(event as object)
    resp = Api_result(event)
    if m.closing or m.aiLive = invalid then return
    if resp.ok and AiLive_capsUsable(resp.data) then
        m.aiLive.caps = "yes"
    else
        m.aiLive.caps = "no"
    end if
end sub

' Subs_aiSubmit hands the request here: connect first when that is possible, then send.
sub AiLive_submit()
    a = m.aiLive
    AiLive_deactivate(true)
    AiLive_resetJob()
    if a.waitingSend then return   ' a connect is already under way; it sends when it ends
    if m.sessionId = "" or a.caps <> "yes" or a.unsupported then
        Subs_aiSend(m.sessionId)
        return
    end if
    if a.conn = "open" and a.connSession = m.sessionId then
        Subs_aiSend(m.sessionId)
        return
    end if
    AiLive_close("replaced")
    a.conn = "minting"
    a.connSession = m.sessionId
    a.waitingSend = true
    m.aiLiveConnectTimer.control = "start"
    body = {}
    inst = installationId()
    if inst <> "" then body["installation_id"] = inst
    Api_send("POST", "/api/v2/playback/sessions/" + Str_urlEncode(m.sessionId) + "/control/ws-ticket", body, "AiLive_onTicket", { fileId: m.fileId, sessionId: m.sessionId })
end sub

sub AiLive_onTicket(event as object)
    resp = Api_result(event)
    a = m.aiLive
    if m.closing or a = invalid or a.conn <> "minting" or Str_orEmpty(resp.context.sessionId) <> a.connSession then return
    ticket = ""
    if resp.ok and Type(resp.data) = "roAssociativeArray" then ticket = Str_orEmpty(resp.data.ticket)
    url = AiLive_socketUrl(m.global.session.serverUrl, a.connSession)
    if ticket = "" or url = "" then
        a.conn = "off"
        Diag_log("[siku-playback] ai live socket failed reason=ticket status=" + Str_orEmpty(resp.status))
        AiLive_releaseSend()
        return
    end if
    task = CreateObject("roSGNode", "AiLiveTask")
    task.observeField("socketState", "AiLive_onState")
    task.observeField("event", "AiLive_onEvent")
    a.lastEventId = 0
    task.request = { url: url, protocols: AiLive_protocols(ticket), sessionId: a.connSession, fileId: m.fileId, hello: AiLive_hello(a.connSession, App_version()) }
    a.task = task
    a.conn = "connecting"
    task.control = "RUN"
end sub

sub AiLive_onState(event as object)
    a = m.aiLive
    if a = invalid or a.task = invalid or not event.getRoSGNode().isSameNode(a.task) then return
    st = event.getData()
    if Type(st) <> "roAssociativeArray" then return
    kind = Str_orEmpty(st.kind)
    reason = Str_orEmpty(st.reason)
    if kind = "open" then
        a.conn = "open"
        Diag_log("[siku-playback] ai live socket open")
        AiLive_releaseSend()
        return
    end if
    a.conn = "off"
    a.task = invalid
    if kind = "failed" then
        if reason = "unsupported" then a.unsupported = true
        Diag_log("[siku-playback] ai live socket failed reason=" + reason)
    else
        Diag_log("[siku-playback] ai live socket closed reason=" + reason)
    end if
    AiLive_releaseSend()
end sub

' The job goes out now (socket open, failed or the 6 s bound passed), if the user has not
' cancelled meanwhile.
sub AiLive_releaseSend()
    a = m.aiLive
    if not a.waitingSend then return
    a.waitingSend = false
    m.aiLiveConnectTimer.control = "stop"
    if m.closing then return
    if m.subs.ai.phase = "submitting" and m.subs.ai.request <> invalid then Subs_aiSend(m.sessionId)
end sub

sub AiLive_onConnectTimeout()
    if m.aiLive = invalid or not m.aiLive.waitingSend then return
    Diag_log("[siku-playback] ai live socket failed reason=open_timeout")
    AiLive_releaseSend()
end sub

' Subs_onAiCreated: the job the live events must name. Events that arrived before the answer are
' replayed now.
sub AiLive_onJobCreated(job as object)
    a = m.aiLive
    if a = invalid then return
    a.jobId = Str_orEmpty(job.id)
    held = a.buffered
    a.buffered = []
    for each ev in held
        AiLive_handle(ev)
    end for
end sub

sub AiLive_onEvent(event as object)
    a = m.aiLive
    if m.closing or a = invalid or a.task = invalid or not event.getRoSGNode().isSameNode(a.task) then return
    data = event.getData()
    if Type(data) <> "roAssociativeArray" or Type(data.items) <> "roArray" then return
    last = a.lastEventId
    for each ev in data.items
        if Type(ev) = "roAssociativeArray" then
            id = Int(Num_or(ev.id, 0))
            if id > a.lastEventId then
                a.lastEventId = id
                if a.jobId = "" then
                    if a.buffered.Count() < 50 then a.buffered.Push(ev)
                else
                    AiLive_handle(ev)
                end if
            end if
        end if
    end for
    ' The task may have ended meanwhile (a terminal event closes it).
    if a.lastEventId > last and a.task <> invalid then a.task.ack = a.lastEventId
end sub

sub AiLive_handle(ev as object)
    a = m.aiLive
    payload = ev.payload
    if not AiLive_matches(payload, a.jobId, a.trackKey) then return
    name = Str_orEmpty(ev.name)
    if name = "subtitle_translation_started" then
        a.trackKey = Str_orEmpty(payload.track_key)
        a.total = Int(Num_or(payload.total_cues, 0))
        Diag_log("[siku-playback] ai live started cues=" + a.total.ToStr())
        AiLive_activate()
    else if name = "subtitle_translation_cues" then
        if a.trackKey = "" then a.trackKey = Str_orEmpty(payload.track_key)
        before = a.cues.Count()
        AiLive_mergeCues(a.cues, a.seen, payload.cues, AiLive_maxCues())
        added = a.cues.Count() - before
        a.done = Int(Num_or(payload.done, a.done))
        a.total = Int(Num_or(payload.total, a.total))
        ' One line for the first batch, then at most one every 10 s.
        now = a.logClock.TotalMilliseconds()
        if a.loggedAt < 0 or now - a.loggedAt >= 10000 or (a.total > 0 and a.done >= a.total) then
            a.loggedAt = now
            Diag_log("[siku-playback] ai live cues +" + added.ToStr() + " " + a.done.ToStr() + "/" + a.total.ToStr())
        end if
        ai = m.subs.ai
        if ai.phase = "running" then
            if a.total > 0 and a.done / a.total > ai.progress then ai.progress = a.done / a.total
            ai.message = "Showing translated lines as they arrive"
            if m.subs.dialog = "ai" then Subs_renderAi()
        end if
        AiLive_activate()
        AiLive_draw()
    else if name = "subtitle_translation_completed" then
        Diag_log("[siku-playback] ai live completed")
        AiLive_close("completed")
        ' The poll adopts the stored track (which takes over from the drawn lines) without waiting
        ' for its next tick.
        if m.subs.ai.phase = "running" then Subs_onAiPoll()
    else if name = "subtitle_translation_failed" then
        Diag_log("[siku-playback] ai live failed")
        AiLive_close("failed")
        AiLive_deactivate(true)
        if m.subs.ai.phase = "running" then Subs_onAiPoll()
    end if
end sub

' The drawn lines take over from the selected subtitle (both on screen would overlap).
sub AiLive_activate()
    a = m.aiLive
    if a.active or a.userLeft then return
    a.active = true
    a.savedIndex = m.subtitleIndex
    a.selecting = true
    setSubtitle(-1)
    a.selecting = false
    a.shown = ""
    a.posAt = Num_or(m.video.position, 0)
    a.clock.Mark()
    m.aiLiveText.text = ""
    m.aiLiveShadow.text = ""
    m.aiLiveGroup.visible = true
    m.aiLiveTimer.control = "start"
end sub

' Stops drawing. restore: put back the subtitle the drawn lines replaced (the job failed or was
' cancelled); the stored track's adoption selects its own.
sub AiLive_deactivate(restore as boolean)
    a = m.aiLive
    if a = invalid or not a.active then return
    a.active = false
    m.aiLiveGroup.visible = false
    m.aiLiveTimer.control = "stop"
    if restore and m.subtitleIndex < 0 and a.savedIndex >= 0 and a.savedIndex < m.subtitleTracks.Count() then
        a.selecting = true
        setSubtitle(a.savedIndex)
        a.selecting = false
    end if
end sub

' The user picked a subtitle (or Off) in the player panel or from the phone: the drawn lines end
' for this job. Called before setSubtitle.
sub AiLive_onUserSubtitle()
    a = m.aiLive
    if a = invalid or not a.active then return
    a.userLeft = true
    AiLive_deactivate(false)
end sub

' setSubtitle: while the lines are drawn, any other selection (a replan remounting the tracks)
' keeps the native subtitle off and becomes the one restored if the job fails.
function AiLive_filterSubtitle(idx as integer) as integer
    a = m.aiLive
    if a = invalid or a.selecting or not a.active then return idx
    if idx >= 0 then a.savedIndex = idx
    return -1
end function

' The stored track is being adopted (Subs_onAdoptReplan): it takes over from the drawn lines.
sub AiLive_onAdopting()
    a = m.aiLive
    if a = invalid then return
    a.userLeft = true
    AiLive_deactivate(false)
    AiLive_close("adopted")
end sub

' The job ended on the poll's side (failed, cancelled, or adoption failed).
sub AiLive_onJobEnded()
    if m.aiLive = invalid then return
    AiLive_deactivate(true)
    AiLive_close("job_ended")
end sub

sub AiLive_close(reason as string)
    a = m.aiLive
    if a = invalid then return
    if a.waitingSend then
        a.waitingSend = false
        m.aiLiveConnectTimer.control = "stop"
    end if
    if a.task <> invalid then
        a.task.unobserveField("socketState")
        a.task.unobserveField("event")
        a.task.shutdown = true
        a.task = invalid
        Diag_log("[siku-playback] ai live socket closed reason=" + reason)
    end if
    a.conn = "off"
end sub

' onVideoPosition: the node reports once a second; the redraw timer runs between reports.
sub AiLive_onPosition()
    a = m.aiLive
    if a = invalid or not a.active then return
    a.posAt = Num_or(m.video.position, 0)
    a.clock.Mark()
    AiLive_draw()
end sub

sub AiLive_onTick()
    AiLive_draw()
end sub

sub AiLive_draw()
    a = m.aiLive
    if a = invalid or not a.active then return
    p = a.posAt
    if m.video.state = "playing" then
        since = a.clock.TotalMilliseconds() / 1000.0
        if since > 1.5 then since = 1.5
        p = p + since
    end if
    text = AiLive_textAt(a.cues, AiLive_sourceTime(p, m.timelineOffset, Subs_delayMs()))
    if text = a.shown then return
    a.shown = text
    m.aiLiveText.text = text
    m.aiLiveShadow.text = text
end sub
