' SPDX-License-Identifier: AGPL-3.0-or-later
' One replan at a time (the player's side of Silo Android TV's mutation fence). Every request
' that replaces the plan goes to POST /playback/{session}/replan: sendReplan's track, quality,
' output, recovery and buffering changes, the seek re-anchor (PlayerSeekReanchor.brs) and the
' adoption of a stored subtitle (SubtitleSuite.brs). The server answers a replan against the plan
' it replaced, so two in flight make the second a 409 stale_playback_plan and the first answer is
' read as the second's kind. So:
'   - while one is in flight (m.replanPending, m.reanchorBusy or m.subs.adoptId), a new intent is
'     queued, the newest per kind (a second quality pick replaces the first), and sent when the
'     answer has been handled (Replan_drain);
'   - a recovery queued for a plan that is gone by then is dropped (it was about that plan);
'   - each sendReplan carries a sequence number with its kind and the state it needs (the quality
'     to fall back to, the audio pick) in the Api context, and an answer that is not the latest
'     is dropped instead of being read with another request's state.
' Seeks: a copy remux's far seek asked for while a replan is in flight waits for it the same way
' (m.reanchorQueued), and skips during a re-anchor count from where it is going (seekBase).
' Part of PlayerScreen (included from PlayerScreen.xml).

' ---------- Pure helpers (host-tested in tests/test_replan_fence.py) ----------

' The queue with `intent` added: an earlier intent of the same slot is replaced (the newest pick
' wins), the rest keep their order. At most 6 intents (one per slot in practice).
function ReplanFence_push(queue as dynamic, intent as object) as object
    out = []
    slot = Str_orEmpty(intent.slot)
    if Type(queue) = "roArray" then
        for each q in queue
            if Type(q) = "roAssociativeArray" and Str_orEmpty(q.slot) <> slot then out.Push(q)
        end for
    end if
    out.Push(intent)
    while out.Count() > 6
        out.Shift()
    end while
    return out
end function

' Where a relative seek counts from (source seconds): a queued re-anchor target, else the one in
' flight, else the position. Three quick +30 s during a re-anchor then add up to +90 s.
function ReplanFence_seekBase(position as float, reanchorBusy as boolean, inFlightTarget as float, queuedTarget as float) as float
    if queuedTarget >= 0 then return queuedTarget
    if reanchorBusy and inFlightTarget >= 0 then return inFlightTarget
    return position
end function

' A queued re-anchor target this close to the position just mounted is already served.
function ReplanFence_nearMounted(target as float, position as float) as boolean
    return Abs(target - position) <= 1.0
end function

' Why a replan answer is stale ("" when it is the current request's): "attempt" for an earlier
' attempt or session, "seq" when a newer replan was sent after it.
function ReplanFence_stale(ctx as dynamic, attemptId as string, sessionId as string, seq as integer) as string
    if ctx = invalid or Type(ctx) <> "roAssociativeArray" then return "attempt"
    if Str_orEmpty(ctx.attemptId) <> attemptId or Str_orEmpty(ctx.sessionId) <> sessionId then return "attempt"
    if Int(Num_or(ctx.seq, -1)) <> seq then return "seq"
    return ""
end function

' ---------- Player state ----------

sub Replan_reset()
    if m.replanSeq = invalid then m.replanSeq = 0   ' never reset: an old answer can't match a new number
    m.replanQueue = []
end sub

' A replan, re-anchor or subtitle adoption is in flight.
function Replan_busy() as boolean
    return Replan_otherBusy() or m.reanchorBusy = true
end function

' A replan or subtitle adoption is in flight (not counting a seek re-anchor).
function Replan_otherBusy() as boolean
    if m.replanPending = true then return true
    if m.subs <> invalid and Str_orEmpty(m.subs.adoptId) <> "" then return true
    return false
end function

' What is in flight, for the console line.
function Replan_busyWith() as string
    if m.replanPending = true then return "replan:" + Str_orEmpty(m.replanKind)
    if m.reanchorBusy = true then return "reanchor"
    if m.subs <> invalid and Str_orEmpty(m.subs.adoptId) <> "" then return "subtitle_adopt"
    return "-"
end function

' Queues an intent: { slot, ... }. planId: the plan a recovery is about ("" = any plan).
sub Replan_queue(intent as object)
    if intent.planId = invalid then intent.planId = ""
    m.replanQueue = ReplanFence_push(m.replanQueue, intent)
    Diag_log("[siku-playback] replan queued kind=" + Str_orEmpty(intent.slot) + " behind=" + Replan_busyWith() + " queued=" + m.replanQueue.Count().ToStr())
end sub

' Forgets the queue (a renewed session, a new attempt, the error screen).
sub Replan_clear(reason as string)
    if m.replanQueue <> invalid and m.replanQueue.Count() > 0 then
        Diag_log("[siku-playback] replan queue dropped reason=" + reason + " count=" + m.replanQueue.Count().ToStr())
    end if
    m.replanQueue = []
end sub

' The queued intent the audio row shows as "Applying…" (-1 = none).
function Replan_queuedAudioIndex() as integer
    if m.replanQueue = invalid then return -1
    for each q in m.replanQueue
        if Str_orEmpty(q.slot) = "audio" then return Int(Num_or(q.index, -1))
    end for
    return -1
end function

' The current plan's id ("" without one).
function Replan_planId() as string
    if m.plan = invalid or Type(m.plan) <> "roAssociativeArray" then return ""
    return Str_orEmpty(m.plan.plan_id)
end function

' Called after every replan, re-anchor and adoption answer has been handled: sends the next
' queued intent, then a seek re-anchor that waited for a replan.
sub Replan_drain()
    if m.closing or m.replanQueue = invalid then return
    if m.errorGroup <> invalid and m.errorGroup.visible then
        Replan_clear("error_shown")
        m.reanchorQueued = -1.0
        return
    end if
    guard = 0
    while m.replanQueue.Count() > 0 and not Replan_busy() and guard < 8
        guard = guard + 1
        intent = m.replanQueue.Shift()
        slot = Str_orEmpty(intent.slot)
        planId = Str_orEmpty(intent.planId)
        if planId <> "" and planId <> Replan_planId() then
            Diag_log("[siku-playback] replan queued kind=" + slot + " dropped: its plan was replaced")
        else
            Diag_log("[siku-playback] replan dequeued kind=" + slot)
            if slot = "quality" then
                if Str_orEmpty(intent.label) <> PlaybackCaps_videoQuality(m.qualityPref) then requestQualityChange(Str_orEmpty(intent.label))
            else if slot = "audio" then
                requestAudioTrackChange(Int(Num_or(intent.index, -1)))
                if m.hud.visible then buildHudRows()
            else if slot = "adopt" then
                Subs_adoptStored(Str_orEmpty(intent.storedId), Str_orEmpty(intent.origin))
            else
                sendReplan(Str_orEmpty(intent.operation), Str_orEmpty(intent.kind), intent.failure)
            end if
        end if
    end while
    if Replan_busy() or m.reanchorQueued = invalid or m.reanchorQueued < 0 then return
    ' A far seek asked for while a replan was in flight: re-anchor the new plan there, or, on a plan
    ' that does not re-anchor, land there when it starts (or seek there now).
    if m.plan <> invalid and PlaybackCaps_truthy(m.plan.siku_seek_reanchor) then
        SeekReanchor_next()
        return
    end if
    q = m.reanchorQueued
    m.reanchorQueued = -1.0
    if ReplanFence_nearMounted(q, m.position) then return
    Diag_log("[siku-playback] seek reanchor queued target=" + PlaybackCaps_str(Int(q)) + " lands as a local seek: the new plan does not re-anchor")
    if m.resumeAfterStart <> invalid then
        m.resumeAfterStart = q
        m.position = q
        m.scrubber.position = q
    else
        seekToSource(q)
    end if
end sub

' Where skip back/forward and a hold-seek count from (ReplanFence_seekBase).
function seekBase() as float
    queued = -1.0
    if m.reanchorQueued <> invalid then queued = m.reanchorQueued
    target = -1.0
    if m.reanchorTarget <> invalid then target = m.reanchorTarget
    return ReplanFence_seekBase(m.position, m.reanchorBusy = true, target, queued)
end function
