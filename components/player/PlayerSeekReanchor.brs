' SPDX-License-Identifier: AGPL-3.0-or-later
' Seek re-anchoring (playback protocol v3 §5 "Copy remux over HLS" and §6 `seek_reanchor`).
' A server_remux_hls copy is served from FFmpeg's still-growing playlist: its timeline starts at
' the keyframe before the requested position (timeline_offset_seconds = stream_origin_seconds),
' seek_window_end_seconds is deliberately absent and can_seek_anywhere is false, because the
' playlist has no segments for positions FFmpeg has not reached. A seek there goes back through
' the server as a `seek_reanchor` replan, which reopens the same recipe at the new position; the
' returned plan is mounted there. The decision follows Silo Android's PlaybackTimelineSeekPolicy
' (decideSeek): a target inside the mounted transport's proven extent (from the timeline origin to
' the furthest downloaded segment, or the current position) stays a plain Video seek.
' Gated on the server advertising seek_reanchor_v1; without it every seek stays a Video seek, as
' before. Part of PlayerScreen (included from PlayerScreen.xml); seekToSource calls
' SeekReanchor_intercept. Not verified on a Roku yet: the simulator cannot play video.
'
' The lead-in (adapted from Silo-Server/silo-roku, AGPL-3.0 (source/playback/session.bs and
' source/playback/slot.bs, commit 01a0f42)): Roku treats the reanchored remux's growing EVENT
' playlist (no ENDLIST) as live. Given a PlayStart near the playlist's start (0.2-1.6 s, every
' reanchor's) it opens the load near the end of what it first reads, 4-8 s past the target, and
' cannot seek below that in the first seconds (27 of 28 reanchors on a Streaming Stick). It
' honours a PlayStart of 10 s or more once the playlist reaches past it. So a reanchor on a copy
' remux asks for its stream 10 s before the target, starts the load at the target, and hands the
' content to the Video node 1.5 s after the answer with the node stopped (14 of 14 within 1.06 s
' of the target there). A start or reload on a copy remux that Roku opens more than 3 s past its
' start is reanchored there that way, once; a lead-in load opened more than 3 s short of its
' start is sought forward to it once (SeekReanchor_checkStart). silo-roku found the lead-in opening
' at the stream's origin on a 69 Mbps 4K remux through a proxy (2026-11-01, an open item there).

sub SeekReanchor_reset()
    m.reanchorBusy = false        ' a seek_reanchor replan is in flight
    m.reanchorQueued = -1.0       ' the latest target asked for while one was in flight (-1 = none)
    m.reanchorTarget = -1.0       ' the in-flight request's target (source seconds)
    m.reanchorFromPlan = ""       ' plan_id the in-flight request re-anchors
    m.reanchorWasPaused = false
    m.reanchorBody = invalid      ' the in-flight request body (diagnostics)
    m.reanchorLeadIn = false      ' the in-flight request asked SeekReanchor_leadSeconds() before its target
    m.reanchorHolding = false     ' a lead-in answer waits for reanchorHoldTimer with the node stopped
    m.reanchorHeldPlan = invalid  ' that answer's plan
    m.startLeadIn = false         ' the mounted plan is a lead-in's: its load starts at the target
    m.startSeek = invalid         ' a start check's seek, until a reading shows where it went
    if m.reanchorHoldTimer = invalid and m.top <> invalid then
        m.reanchorHoldTimer = m.top.findNode("reanchorHoldTimer")
        if m.reanchorHoldTimer <> invalid then m.reanchorHoldTimer.observeField("fire", "SeekReanchor_onHoldTimer")
    end if
    if m.reanchorHoldTimer <> invalid then m.reanchorHoldTimer.control = "stop"
end sub

' How far before its target a copy remux's reanchor asks for its stream (silo-roku
' REANCHOR_LEAD_SECONDS). The hold is reanchorHoldTimer's duration in PlayerScreen.xml (1.5 s).
function SeekReanchor_leadSeconds() as float
    return 10.0
end function

' A server copy remux (server_remux_hls and its kin): its seeks and reloads are seek_reanchors onto
' a playlist that grows as it plays.
function SeekReanchor_isCopyRemux(plan as dynamic) as boolean
    if plan = invalid or Type(plan) <> "roAssociativeArray" then return false
    return Left(LCase(Str_orEmpty(plan.delivery)), 13) = "server_remux_"
end function

' The position a lead-in reanchor asks the server for: the target less the lead, never below 0.
function SeekReanchor_leadPosition(target as float) as float
    lead = target - SeekReanchor_leadSeconds()
    if lead < 0 then lead = 0
    return lead
end function

' What a mount's first "playing" does about where Roku opened it (source seconds): "" when it is
' within 3 s of the start; "seek_forward" for a lead-in load opened short of it; "reanchor" for a
' copy remux's other load opened past it, when a reanchor can be sent and the start is at least
' the lead in (a PlayStart under 10 s is not honoured either way); else "seek" (a local seek there).
function SeekReanchor_startAction(position as float, start as float, leadIn as boolean, copyRemux as boolean, canReanchor as boolean) as string
    slip = position - start
    if Abs(slip) <= 3 then return ""
    if slip < 0 and leadIn then return "seek_forward"
    if slip > 0 and copyRemux and not leadIn and canReanchor and start >= SeekReanchor_leadSeconds() then return "reanchor"
    return "seek"
end function

' A start check's seek landed when the position is within 3 s of the start: moving at all is not
' landing (silo-roku W0-2: a seek back from 8.0 s to 0.2 s played on from 7.96 s).
function SeekReanchor_landed(position as float, start as float) as boolean
    return Abs(position - start) <= 3
end function

' Seconds with one decimal, for the console.
function SeekReanchor_fmt(x as dynamic) as string
    v = Num_or(x, 0)
    sign = ""
    if v < 0 then
        sign = "-"
        v = -v
    end if
    t = Int(v * 10 + 0.5)
    return sign + (t \ 10).ToStr() + "." + (t mod 10).ToStr()
end function

' "" when a Video seek can serve `target` (source seconds) on the mounted plan, else why the
' server must re-anchor: outside_window, unknown_window or invalid_mapping. A missing timeline,
' or one that says nothing (no window, can_seek_anywhere absent or true), keeps the Video seek.
function SeekReanchor_decide(plan as dynamic, target as float, mountedEnd as float) as string
    if plan = invalid or Type(plan) <> "roAssociativeArray" then return ""
    tl = plan.timeline
    if tl = invalid or Type(tl) <> "roAssociativeArray" then return ""
    offset = Num_or(tl.timeline_offset_seconds, 0)
    winStart = -1.0
    winEnd = -1.0
    if tl.seek_window_start_seconds <> invalid then winStart = Num_or(tl.seek_window_start_seconds, -1)
    if tl.seek_window_end_seconds <> invalid then winEnd = Num_or(tl.seek_window_end_seconds, -1)
    if winStart >= 0 and target < winStart then return "outside_window"
    if winEnd >= 0 and target > winEnd then return "outside_window"
    complete = winStart >= 0 and winEnd >= 0
    ' Only an explicit false counts (pitfall 16: never compare a possibly missing flag with a boolean).
    seekAnywhereFalse = tl.can_seek_anywhere <> invalid and not PlaybackCaps_truthy(tl.can_seek_anywhere)
    if not complete and seekAnywhereFalse then
        if not (mountedEnd >= 0 and target >= offset and target <= mountedEnd) then return "unknown_window"
    end if
    if target - offset < 0 then return "invalid_mapping"
    return ""
end function

' Called by seekToSource with the clamped target. Returns true when it took the seek over (a
' seek_reanchor replan was sent or queued), false to let seekToSource seek the Video node.
function SeekReanchor_intercept(target as float) as boolean
    if m.plan = invalid then return false
    ' The mount's own landing seek (onVideoState, to resumeAfterStart) is always local: the plan
    ' was just anchored there.
    if m.resumeAfterStart <> invalid and Abs(target - Num_or(m.resumeAfterStart, -100)) < 1 then return false
    if not PlaybackCaps_truthy(m.plan.siku_seek_reanchor) then return false
    if m.reanchorBusy then
        ' One request at a time; the newest target follows when the answer lands.
        m.reanchorQueued = target
        m.scrubber.position = target
        Diag_log("[siku-playback] seek reanchor queued target=" + PlaybackCaps_str(Int(target)))
        return true
    end if
    mountedEnd = m.bufferedEnd
    if m.position > mountedEnd then mountedEnd = m.position
    reason = SeekReanchor_decide(m.plan, target, mountedEnd)
    if reason = "" then return false
    return SeekReanchor_send(target, reason)
end function

' Sends the seek_reanchor replan (pausing the Video node meanwhile). false when it cannot be sent.
function SeekReanchor_send(target as float, reason as string) as boolean
    inst = installationId()
    if inst = "" or m.sessionId = "" or m.plan = invalid then return false
    selected = {}
    if m.plan.selected_tracks <> invalid then selected = m.plan.selected_tracks
    body = PlaybackCaps_replanBody(inst, m.attemptId, m.plan, "seek_reanchor", m.qualityPref, target, selected)
    ' A re-anchor replays the playing recipe and keeps the attempt's intent: no quality or failure
    ' fields (omitting quality_preference keeps the session's), and no buffering-quality fields
    ' (a seek replan neither records nor clears a learned limit, and never replaces the features).
    body.Delete("quality_preference")
    body.Delete("failure")
    ' The attempt's tried routes and count go along, as on every replan.
    Recovery_decorateReplan(body, "seek_reanchor")
    ' A copy remux asks for its stream before the target; its load starts at the target (lead-in).
    m.reanchorLeadIn = SeekReanchor_isCopyRemux(m.plan)
    lead = "-"
    if m.reanchorLeadIn then
        body.position_seconds = SeekReanchor_leadPosition(target)
        lead = PlaybackCaps_str(Int(body.position_seconds))
    end if
    m.reanchorBusy = true
    m.reanchorTarget = target
    m.reanchorFromPlan = Str_orEmpty(m.plan.plan_id)
    m.reanchorWasPaused = m.isPaused
    m.reanchorBody = body
    Diag_log("[siku-playback] seek reanchor target=" + PlaybackCaps_str(Int(target)) + " reason=" + reason + " from=" + PlaybackCaps_str(Int(m.position)) + " offset=" + PlaybackCaps_str(Int(m.timelineOffset)) + " buffered_to=" + PlaybackCaps_str(Int(m.bufferedEnd)) + " lead_in=" + lead + " plan=" + m.reanchorFromPlan)
    if not m.isPaused then m.video.control = "pause"
    m.scrubber.position = target
    resetBuffered()
    setBuffering(true)
    Api_send("POST", "/api/v2/playback/" + Str_urlEncode(m.sessionId) + "/replan", body, "onSeekReanchor")
    return true
end function

sub onSeekReanchor(event as object)
    resp = Api_result(event)
    Recovery_onReplanAnswered()
    if m.closing then return
    target = m.reanchorTarget
    m.reanchorBusy = false
    ' Another replan (a track or quality change) replaced the plan meanwhile: it already mounted
    ' its own stream, so this answer is stale.
    if m.plan = invalid or Str_orEmpty(m.plan.plan_id) <> m.reanchorFromPlan then
        Diag_log("[siku-playback] seek reanchor answer dropped: the plan changed meanwhile")
        SeekReanchor_next()
        return
    end if
    if isSessionEndedByServer(resp) then
        setBuffering(false)
        leaveServerEndedSession()
        return
    end if
    problem = ""
    if not resp.ok or resp.data = invalid then
        problem = "status=" + PlaybackCaps_str(resp.status)
    else if resp.data.outcome <> "playable" or resp.data.playback_plan = invalid then
        problem = "outcome=" + Str_orEmpty(resp.data.outcome)
    else
        problem = PlaybackCaps_planProblem(resp.data)
    end if
    if problem <> "" then
        ' The current stream is still mounted where it was: carry on from there.
        Diag_log("[siku-playback] seek reanchor failed target=" + PlaybackCaps_str(Int(target)) + " " + problem)
        setBuffering(false)
        m.scrubber.position = m.position
        if not m.reanchorWasPaused then m.video.control = "resume"
        m.global.toast = Tx("Couldn't jump there on this stream")
        m.reanchorQueued = -1.0
        return
    end if
    plan = resp.data.playback_plan
    PlaybackCaps_notePlanFeatures(resp.data)
    Bufq_noteDecision(resp.data)
    print PlaybackCaps_diagLine(m.reanchorBody, plan)
    ' The server keeps the route on a re-anchor (same plan_attempt_key and delivery); log it when
    ' it did not, but play the answer either way: the server has adopted it for this session.
    sameRoute = Str_orEmpty(plan.plan_attempt_key) = Str_orEmpty(m.plan.plan_attempt_key) and Str_orEmpty(plan.delivery) = Str_orEmpty(m.plan.delivery)
    tl = plan.timeline
    origin = 0.0
    if tl <> invalid and Type(tl) = "roAssociativeArray" then origin = Num_or(tl.timeline_offset_seconds, 0)
    Diag_log("[siku-playback] seek reanchored target=" + PlaybackCaps_str(Int(target)) + " origin=" + PlaybackCaps_str(Int(origin)) + " same_route=" + PlaybackCaps_str(sameRoute) + " lead_in=" + PlaybackCaps_str(m.reanchorLeadIn))
    m.video.control = "stop"
    if m.reanchorLeadIn and m.reanchorHoldTimer <> invalid then
        ' The playlist must grow past the target before Roku first reads it (silo-roku: 12 of 12
        ' held 1.5 s opened at the target's segment; without the hold 5 of 12 opened up to 10 s
        ' short). The node stays stopped meanwhile and the reanchor counts as busy (a newer seek
        ' queues). Back during the hold closes at once: nothing waits on the stopped node.
        m.reanchorBusy = true
        m.reanchorHolding = true
        m.reanchorHeldPlan = plan
        m.position = target
        m.scrubber.position = target
        m.reanchorHoldTimer.control = "start"
        return
    end if
    SeekReanchor_mount(plan, target, false)
end sub

' The hold is over: the lead-in plan is handed to the Video node, unless the player closed or
' another replan mounted its own plan meanwhile.
sub SeekReanchor_onHoldTimer()
    if not m.reanchorHolding then return
    plan = m.reanchorHeldPlan
    m.reanchorHolding = false
    m.reanchorHeldPlan = invalid
    m.reanchorBusy = false
    if m.closing or plan = invalid then return
    if m.plan = invalid or Str_orEmpty(m.plan.plan_id) <> m.reanchorFromPlan then
        Diag_log("[siku-playback] seek reanchor hold dropped: the plan changed meanwhile")
        SeekReanchor_next()
        return
    end if
    SeekReanchor_mount(plan, m.reanchorTarget, true)
end sub

sub SeekReanchor_mount(plan as object, target as float, leadIn as boolean)
    ' "remount": the playing recipe again, only the source reloads (buffering quality keeps its plan).
    applyPlan(plan, { resumeAt: target, subtitleTrackId: Subs_selectedTrackId(), mountKind: "remount", leadIn: leadIn })
    if leadIn then Diag_log("[siku-playback] seek reanchor load target=" + SeekReanchor_fmt(target) + " origin=" + SeekReanchor_fmt(m.timelineOffset) + " play_start=" + SeekReanchor_fmt(target - m.timelineOffset))
    ' A seek made while paused stays paused: the new plan is paused again once it plays (onVideoState).
    if m.reanchorWasPaused then m.pauseAfterStart = true
    Bufq_onSeek()
    m.position = target
    m.scrubber.position = target
    if m.hud.visible then buildHudRows()
    SeekReanchor_next()
end sub

' The mount's first "playing" (onVideoState, while m.resumeAfterStart is set): Roku can open an HLS
' load away from its PlayStart. A copy remux opened late is reanchored there with a lead-in (a
' local seek never goes below where Roku opened a growing playlist); a lead-in load opened short
' is sought forward; anything else is sought there locally, as before. pausing: the mount asked to
' stay paused (a reanchor made while paused), which the reanchor keeps.
sub SeekReanchor_checkStart(pausing as boolean)
    start = Num_or(m.resumeAfterStart, 0)
    position = Num_or(m.video.position, 0) + m.timelineOffset
    leadIn = m.startLeadIn
    m.startLeadIn = false
    isCopy = SeekReanchor_isCopyRemux(m.plan)
    canReanchor = m.plan <> invalid and PlaybackCaps_truthy(m.plan.siku_seek_reanchor) and not m.reanchorBusy
    action = SeekReanchor_startAction(position, start, leadIn, isCopy, canReanchor)
    if isCopy or action <> "" then
        shown = action
        if shown = "" then shown = "landed"
        Diag_log("[siku-playback] start check start=" + SeekReanchor_fmt(start) + " position=" + SeekReanchor_fmt(position) + " lead_in=" + PlaybackCaps_str(leadIn) + " action=" + shown)
    end if
    if action = "" then
        m.resumeAfterStart = invalid
        return
    end if
    if action = "reanchor" then
        m.resumeAfterStart = invalid
        if SeekReanchor_send(start, "start_slip") then
            if pausing then m.reanchorWasPaused = true
            return
        end if
        m.resumeAfterStart = start
    end if
    ' A local seek; m.resumeAfterStart still set keeps it out of SeekReanchor_intercept.
    seekToSource(start)
    m.resumeAfterStart = invalid
    forward = false
    if action = "seek_forward" then forward = true
    m.startSeek = { target: start, forward: forward, at: Recovery_now(), buffered: false, resumed: false }
end sub

' The Video node's state while a start check's seek is unresolved: Roku reports position 0 while it
' rebuffers, so the seek is judged at the first position once it plays again, or 3 s after it.
sub SeekReanchor_onStartSeekState(st as string)
    s = m.startSeek
    if s = invalid then return
    if st = "buffering" then s.buffered = true
    if st = "playing" and s.buffered then s.resumed = true
end sub

' onVideoPosition: logs whether a start check's seek landed within 3 s of the start.
sub SeekReanchor_checkStartSeek()
    s = m.startSeek
    if s = invalid or m.video.state <> "playing" then return
    if not s.resumed and Recovery_now() - s.at < 3 then return
    m.startSeek = invalid
    position = Num_or(m.video.position, 0) + m.timelineOffset
    kind = "back"
    if s.forward then kind = "forward"
    Diag_log("[siku-playback] start seek kind=" + kind + " start=" + SeekReanchor_fmt(s.target) + " position=" + SeekReanchor_fmt(position) + " landed=" + PlaybackCaps_str(SeekReanchor_landed(position, s.target)))
end sub

' A target asked for while the request was in flight: re-anchor there now (the new mount has no
' proven extent yet, so it always goes to the server).
sub SeekReanchor_next()
    if m.reanchorQueued < 0 then return
    q = m.reanchorQueued
    m.reanchorQueued = -1.0
    if not SeekReanchor_send(q, "queued") then Diag_log("[siku-playback] seek reanchor queued target dropped: no session")
end sub
