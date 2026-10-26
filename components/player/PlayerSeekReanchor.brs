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

sub SeekReanchor_reset()
    m.reanchorBusy = false        ' a seek_reanchor replan is in flight
    m.reanchorQueued = -1.0       ' the latest target asked for while one was in flight (-1 = none)
    m.reanchorTarget = -1.0       ' the in-flight request's target (source seconds)
    m.reanchorFromPlan = ""       ' plan_id the in-flight request re-anchors
    m.reanchorWasPaused = false
    m.reanchorBody = invalid      ' the in-flight request body (diagnostics)
end sub

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
        print "[siku-playback] seek reanchor queued target=" + PlaybackCaps_str(Int(target))
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
    m.reanchorBusy = true
    m.reanchorTarget = target
    m.reanchorFromPlan = Str_orEmpty(m.plan.plan_id)
    m.reanchorWasPaused = m.isPaused
    m.reanchorBody = body
    print "[siku-playback] seek reanchor target=" + PlaybackCaps_str(Int(target)) + " reason=" + reason + " from=" + PlaybackCaps_str(Int(m.position)) + " offset=" + PlaybackCaps_str(Int(m.timelineOffset)) + " buffered_to=" + PlaybackCaps_str(Int(m.bufferedEnd)) + " plan=" + m.reanchorFromPlan
    if not m.isPaused then m.video.control = "pause"
    m.scrubber.position = target
    resetBuffered()
    setBuffering(true)
    Api_send("POST", "/api/v2/playback/" + Str_urlEncode(m.sessionId) + "/replan", body, "onSeekReanchor")
    return true
end function

sub onSeekReanchor(event as object)
    resp = Api_result(event)
    if m.closing then return
    target = m.reanchorTarget
    m.reanchorBusy = false
    ' Another replan (a track or quality change) replaced the plan meanwhile: it already mounted
    ' its own stream, so this answer is stale.
    if m.plan = invalid or Str_orEmpty(m.plan.plan_id) <> m.reanchorFromPlan then
        print "[siku-playback] seek reanchor answer dropped: the plan changed meanwhile"
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
        print "[siku-playback] seek reanchor failed target=" + PlaybackCaps_str(Int(target)) + " " + problem
        setBuffering(false)
        m.scrubber.position = m.position
        if not m.reanchorWasPaused then m.video.control = "resume"
        m.global.toast = "Couldn't jump there on this stream"
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
    print "[siku-playback] seek reanchored target=" + PlaybackCaps_str(Int(target)) + " origin=" + PlaybackCaps_str(Int(origin)) + " same_route=" + PlaybackCaps_str(sameRoute)
    m.video.control = "stop"
    ' "remount": the playing recipe again, only the source reloads (buffering quality keeps its plan).
    applyPlan(plan, { resumeAt: target, subtitleTrackId: Subs_selectedTrackId(), mountKind: "remount" })
    Bufq_onSeek()
    m.position = target
    m.scrubber.position = target
    if m.hud.visible then buildHudRows()
    SeekReanchor_next()
end sub

' A target asked for while the request was in flight: re-anchor there now (the new mount has no
' proven extent yet, so it always goes to the server).
sub SeekReanchor_next()
    if m.reanchorQueued < 0 then return
    q = m.reanchorQueued
    m.reanchorQueued = -1.0
    if not SeekReanchor_send(q, "queued") then print "[siku-playback] seek reanchor queued target dropped: no session"
end sub
