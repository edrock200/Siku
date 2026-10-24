' SPDX-License-Identifier: AGPL-3.0-or-later
' Buffering quality (Silo Android #636, BufferingQualityController.kt): lowers Auto when playback
' keeps buffering, or asks first, and lets the viewer restore it. The contract is the server repo's
' docs/design/2026-10-17-buffering-quality.md; tools/bq_vectors runs its conformance vectors
' (vectors.json, the same file the web, Apple and Android players replay) against this file.
'
' Pure BrightScript: no SceneGraph, no network, no timers of its own. The host passes the time
' (milliseconds, monotonic) to every call and runs due timers with BQ_advance(bq, now); outputs
' are queued on bq.out for the host to drain:
'   { "type": "replan", t, quality, estimateKbps, estimateSource, learnedLimit }   send a quality_change
'   { "type": "notice", t, key: "lowered" | "cant_lower" }                        a short message
'   { "type": "prompt_shown" | "undo_shown", t }                                  a pill appeared
'   { "type": "summary", t, summary }                                            a plan stopped playing
' bq.pill is "" | "prompt" | "undo" (what is on screen); BQ_pillSecondsLeft says its countdown.
'
' Ported differences: no Watch Party (never suspended), no picture in picture (never hidden), no
' start deadline (Siku has no startup stall detector, so onStartDeadlineMissed has no caller).

function BQ_const() as object
    return {
        STARTUP_GRACE_MS: 10000
        STALL_MIN_MS: 1000
        STALLS_BEFORE_TRIGGER: 2
        STALL_WINDOW_MS: 120000
        LONG_STALL_MS: 6000
        PROMPT_SECONDS: 15
        REOFFER_MIN_MS: 120000
        NO_LOWER_COOLDOWN_MS: 300000
        REARM_AFTER_UNADOPTED_MS: 60000
        MIN_ESTIMATE_KBPS: 100
    }
end function

function BQ_new(mode as string) as object
    return {
        c: BQ_const()
        mode: BQ_normalizeMode(mode)
        otherPillVisible: false
        paused: false
        transportTrouble: false
        transportTroubleEndedAt: invalid
        waitCause: ""
        pickPending: false
        current: invalid
        planSeq: 0
        answeredQuality: invalid
        cantLowerShown: false
        reofferNotBefore: invalid
        pending: invalid
        pill: ""                ' what is published: "" | "prompt" | "undo"
        activePill: ""
        deferredPill: ""
        deferredResumes: false
        promptShownAt: 0
        pillRemainingMs: 0
        pillEndsAt: invalid     ' set while the pill's timer runs
        timers: {}              ' name -> { at, seq, ... }
        timerSeq: 0
        out: []
        now: 0
        throughputKbps: 0       ' the playing plan's measured throughput so far (0 = none); BQ_setThroughput
    }
end function

' "never" | "ask" | "always" (the contract default).
function BQ_normalizeMode(mode as dynamic) as string
    m0 = LCase(BQ_str(mode))
    if m0 = "never" or m0 = "ask" then return m0
    return "always"
end function

function BQ_str(v as dynamic) as string
    if v = invalid then return ""
    t = Type(v)
    if t = "roString" or t = "String" then return v
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roLongInteger" or t = "LongInteger" then return v.ToStr()
    return ""
end function

' A plan as the controller needs it. raw: the server plan; adoptionId: unique per adoption;
' quality: the preference it was requested with ("auto" or a rung label).
function BQ_planFrom(raw as object, quality as string, adoptionId as string) as object
    delivered = 0
    if raw.effective_recipe <> invalid and Type(raw.effective_recipe) = "roAssociativeArray" then delivered = BQ_int(raw.effective_recipe.bitrate_kbps)
    if delivered <= 0 and raw.source <> invalid and Type(raw.source) = "roAssociativeArray" then delivered = BQ_int(raw.source.bitrate_kbps)
    rungs = []
    if raw.available_qualities <> invalid and Type(raw.available_qualities) = "roArray" then
        for each q in raw.available_qualities
            if q <> invalid and Type(q) = "roAssociativeArray" then rungs.Push({ label: BQ_str(q.label), kbps: BQ_int(q.bitrate_kbps) })
        end for
    end if
    noReduction = false
    if raw.degradation_warnings <> invalid and Type(raw.degradation_warnings) = "roArray" then
        for each w in raw.degradation_warnings
            if w <> invalid and Type(w) = "roAssociativeArray" and BQ_str(w.code) = "quality_reduction_unavailable" then noReduction = true
        end for
    end if
    active = invalid
    if raw.siku_reports_active_quality = true and raw.active_quality <> invalid then active = BQ_str(raw.active_quality)
    q = LCase(quality).Trim()
    if q = "" or q = "original" or q = "source" or q = "max" then q = "auto"
    return { planId: adoptionId, serverPlanId: BQ_str(raw.plan_id), deliveredKbps: delivered, quality: q, rungs: rungs, noReduction: noReduction, activeQuality: active }
end function

function BQ_int(v as dynamic) as integer
    if v = invalid then return 0
    t = Type(v)
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roLongInteger" or t = "LongInteger" then return v
    if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return Int(v)
    if t = "roString" or t = "String" then return Int(Val(v))
    return 0
end function

' ---------- Host API ----------

sub BQ_setMode(bq as object, mode as dynamic)
    bq.mode = BQ_normalizeMode(mode)
    if bq.mode = "never" then BQ_hidePill(bq)
end sub

' Runs every timer due at or before now, in deadline order, each at its own deadline.
sub BQ_advance(bq as object, now as dynamic)
    while true
        nextName = ""
        nextAt = 0
        nextSeq = 0
        for each name in bq.timers
            tm = bq.timers[name]
            if tm.at <= now and (nextName = "" or tm.at < nextAt or (tm.at = nextAt and tm.seq < nextSeq)) then
                nextName = name
                nextAt = tm.at
                nextSeq = tm.seq
            end if
        end for
        if nextName = "" then exit while
        tm = bq.timers[nextName]
        bq.timers.Delete(nextName)
        bq.now = nextAt
        BQ_fire(bq, nextName, tm)
    end while
    bq.now = now
end sub

sub BQ_fire(bq as object, name as string, tm as object)
    now = bq.now
    st = bq.current
    if name = "longStall" then
        if st <> invalid and st.sid = tm.sid and st.tracker.stallStartedAt <> invalid and st.tracker.stallStartedAt = tm.startedAt then BQ_evaluate(bq, now)
    else if name = "reevaluate" then
        if st <> invalid and st.sid = tm.sid and st.tracker.stallStartedAt <> invalid then BQ_evaluate(bq, now)
    else if name = "rearm" then
        bq.pending = invalid
        if st <> invalid then BQ_resetTracker(bq, st, now)
    else if name = "pill" then
        bq.pillRemainingMs = 0
        bq.pillEndsAt = invalid
        BQ_pillTimedOut(bq)
    end if
end sub

sub BQ_setTimer(bq as object, name as string, at as dynamic, extra = invalid as dynamic)
    bq.timerSeq = bq.timerSeq + 1
    tm = { at: at, seq: bq.timerSeq }
    if extra <> invalid then tm.Append(extra)
    bq.timers[name] = tm
end sub

sub BQ_cancelTimer(bq as object, name as string)
    if bq.timers.DoesExist(name) then bq.timers.Delete(name)
end sub

function BQ_timerActive(bq as object, name as string) as boolean
    return bq.timers.DoesExist(name)
end function

sub BQ_emit(bq as object, item as object)
    item.t = bq.now
    bq.out.Push(item)
end sub

' A higher-priority pill (Skip Intro/Recap/Credits, Up Next) is or is no longer on screen.
sub BQ_setOtherPillVisible(bq as object, visible as boolean, now as dynamic)
    bq.now = now
    bq.otherPillVisible = visible
    if visible then
        BQ_obscurePill(bq)
        return
    end if
    if bq.deferredPill = "" then return
    BQ_present(bq, bq.deferredPill, bq.deferredResumes)
end sub

' A new adoption became the playing plan (see BufferingQualityController.onPlanAdopted).
sub BQ_onPlanAdopted(bq as object, plan as object, controllerInitiated as boolean, now as dynamic, pickStillPending = false as boolean)
    bq.now = now
    c = bq.c
    if bq.current <> invalid and bq.current.plan.planId = plan.planId then return
    bq.transportTrouble = false
    settled = bq.pending
    previous = bq.current
    BQ_dropPlan(bq, now)
    reload = previous <> invalid and BQ_attemptStarted(previous)
    bq.planSeq = bq.planSeq + 1
    st = BQ_newPlanState(plan, reload, bq.planSeq)
    if previous <> invalid and not reload then st.tracker.firstWaitingAt = previous.tracker.firstWaitingAt
    bq.current = st
    if pickStillPending then
        bq.pickPending = true
    else if not controllerInitiated then
        bq.pickPending = false
    end if
    if settled = invalid then return
    if not controllerInitiated or settled.kind = "restore" then return
    delivered = plan.deliveredKbps
    noLower = plan.noReduction or (delivered > 0 and settled.fromKbps > 0 and delivered >= settled.fromKbps)
    quiet = bq.pickPending
    if noLower then
        st.action = "cant_lower"
        st.cooldownUntil = now + c.NO_LOWER_COOLDOWN_MS
        if not quiet then
            bq.cantLowerShown = true
            BQ_emit(bq, { "type": "notice", key: "cant_lower" })
        end if
    else if quiet then
        ' The viewer's pick on its way replaces this plan: it shows nothing.
    else if settled.kind = "automatic" then
        BQ_showPill(bq, "undo")
    else
        BQ_emit(bq, { "type": "notice", key: "lowered" })
    end if
end sub

function BQ_newPlanState(plan as object, replacement as boolean, sid as integer) as object
    return {
        sid: sid
        plan: plan
        replacement: replacement
        tracker: { firstPlayingAt: invalid, firstWaitingAt: invalid, stallStartedAt: invalid, stalled: false, stallEnds: [], longStallEndedAt: invalid }
        played: false
        action: "none"
        cooldownUntil: invalid
        playingSince: invalid
        playedMs: 0
        statsStallStartedAt: invalid
        stallCount: 0
        stallTotalMs: 0
        stallLongestMs: 0
    }
end function

function BQ_attemptStarted(st as object) as boolean
    return st.replacement or st.played
end function

function BQ_starting(st as object) as boolean
    return st.tracker.firstPlayingAt = invalid
end function

' The playing plan's media throughput so far in kbps (0 = not measured): the evidence a start's
' wait needs before it counts (planThroughputKbps). Reset by the host when a new plan mounts.
sub BQ_setThroughput(bq as object, kbps as integer)
    bq.throughputKbps = kbps
end sub

' Playback is running: the first frame, or a resume from waiting or pause.
sub BQ_onPlaying(bq as object, now as dynamic)
    bq.now = now
    c = bq.c
    bq.paused = false
    bq.waitCause = ""
    st = bq.current
    if st = invalid then return
    BQ_thawPill(bq)
    startWait = not BQ_attemptStarted(st)
    st.played = true
    if st.playingSince = invalid then st.playingSince = now
    tr = st.tracker
    if tr.firstPlayingAt = invalid then tr.firstPlayingAt = now
    tr.stalled = false
    if st.statsStallStartedAt <> invalid then BQ_recordStallStat(bq, st, now - st.statsStallStartedAt, true)
    st.statsStallStartedAt = invalid
    startedAt = tr.stallStartedAt
    if startedAt <> invalid then
        BQ_clearStallTiming(bq, st)
        duration = now - startedAt
        if startWait and not BQ_slowLinkEvidence(bq, st.plan) then
            ' Not shown to be the network's.
        else if duration >= c.LONG_STALL_MS then
            tr.longStallEndedAt = now
        else if duration >= c.STALL_MIN_MS then
            tr.stallEnds.Push(now)
        end if
    end if
    BQ_evaluate(bq, now)
end sub

' The player is waiting: cause "" (network), "seek", "pause", "reload" or "renderer".
sub BQ_onWaiting(bq as object, cause as string, now as dynamic)
    bq.now = now
    if cause <> "pause" then bq.paused = false
    bq.waitCause = cause
    st = bq.current
    if st = invalid then return
    if not bq.paused then BQ_thawPill(bq)
    BQ_stopPlayedClock(st, now)
    tr = st.tracker
    if st.replacement and BQ_starting(st) then
        BQ_interrupt(bq, st, now)
        return
    end if
    startWait = BQ_starting(st) and (cause = "reload" or cause = "seek")
    if cause <> "" and not startWait then
        BQ_interrupt(bq, st, now)
        return
    end if
    tr.stalled = true
    if tr.firstPlayingAt = invalid and tr.firstWaitingAt = invalid then tr.firstWaitingAt = now
    if bq.transportTrouble then return
    BQ_startStallTiming(bq, st, now)
end sub

sub BQ_onPause(bq as object, now as dynamic)
    bq.now = now
    bq.paused = true
    bq.waitCause = ""
    BQ_freezePill(bq)
    st = bq.current
    if st = invalid then return
    BQ_stopPlayedClock(st, now)
    BQ_interrupt(bq, st, now)
end sub

sub BQ_onSeek(bq as object, now as dynamic)
    bq.now = now
    st = bq.current
    if st = invalid then return
    if BQ_starting(st) then return
    BQ_stopPlayedClock(st, now)
    BQ_interrupt(bq, st, now)
end sub

sub BQ_onTransportErrorStart(bq as object, now as dynamic)
    bq.now = now
    bq.transportTrouble = true
    st = bq.current
    if st = invalid then return
    if st.tracker.stallStartedAt <> invalid then
        BQ_clearStallTiming(bq, st)
        st.statsStallStartedAt = invalid
    end if
end sub

sub BQ_onTransportErrorEnd(bq as object, now as dynamic)
    bq.now = now
    bq.transportTrouble = false
    bq.transportTroubleEndedAt = now
    st = bq.current
    if st = invalid then return
    if st.tracker.stalled and st.tracker.stallStartedAt = invalid then BQ_startStallTiming(bq, st, now)
end sub

' The controller's last replan failed or will never be adopted.
sub BQ_onReplanFailed(bq as object, now as dynamic)
    bq.now = now
    failed = bq.pending
    if failed <> invalid and failed.kind = "automatic" and failed.fromState <> invalid then failed.fromState.action = failed.actionBefore
    bq.pending = invalid
end sub

sub BQ_onQualityPickSent(bq as object, now as dynamic)
    bq.now = now
    bq.pickPending = true
    BQ_hidePill(bq)
end sub

sub BQ_onQualityPickRefused(bq as object, now as dynamic)
    bq.now = now
    if not bq.pickPending then return
    bq.pickPending = false
    BQ_evaluate(bq, now)
end sub

' A quality change the controller did not send took effect (the viewer's pick or version).
sub BQ_onViewerQualityChange(bq as object, now as dynamic)
    bq.now = now
    bq.pickPending = false
    BQ_hidePill(bq)
    bq.answeredQuality = invalid
    bq.reofferNotBefore = invalid
    bq.pending = invalid
    BQ_cancelTimer(bq, "rearm")
    if bq.current <> invalid then BQ_resetTracker(bq, bq.current, now)
end sub

' The playing plan stopped (ended, closed or failed), or a new attempt of the same title began.
sub BQ_onPlaybackStopped(bq as object, now as dynamic)
    bq.now = now
    BQ_dropPlan(bq, now)
end sub

' Different content: clears the title's answer, notice and re-offer wait too.
sub BQ_reset(bq as object, now as dynamic)
    bq.now = now
    bq.pickPending = false
    BQ_dropPlan(bq, now)
    bq.answeredQuality = invalid
    bq.cantLowerShown = false
    bq.reofferNotBefore = invalid
    bq.promptShownAt = 0
end sub

function BQ_selectLower(bq as object, now as dynamic) as boolean
    bq.now = now
    if bq.activePill <> "prompt" then return false
    st = bq.current
    if st = invalid then return false
    replan = BQ_loweringFor(bq, st.plan)
    if replan = invalid then return false
    BQ_hidePill(bq)
    BQ_sendLowering(bq, st, replan, "accepted")
    return true
end function

function BQ_selectKeep(bq as object, now as dynamic) as boolean
    bq.now = now
    if bq.activePill <> "prompt" then return false
    st = bq.current
    if st = invalid then return false
    BQ_hidePill(bq)
    bq.answeredQuality = st.plan.quality
    st.action = "kept"
    return true
end function

function BQ_selectRestore(bq as object, now as dynamic) as boolean
    bq.now = now
    if bq.activePill <> "undo" then return false
    st = bq.current
    if st = invalid then return false
    BQ_hidePill(bq)
    st.action = "restored"
    bq.answeredQuality = "auto"
    bq.pending = { kind: "restore", fromKbps: 0, fromState: invalid, actionBefore: "none" }
    BQ_startRearm(bq)
    BQ_emit(bq, { "type": "replan", quality: "auto", estimateKbps: 0, estimateSource: "", learnedLimit: "clear" })
    return true
end function

' Back while a pill shows: Keep on the prompt; the undo only hides. True when a pill took it.
function BQ_back(bq as object, now as dynamic) as boolean
    bq.now = now
    if bq.activePill = "prompt" then return BQ_selectKeep(bq, now)
    if bq.activePill = "undo" then
        BQ_hidePill(bq)
        BQ_undoEnded(bq)
        return true
    end if
    return false
end function

' The pill's countdown in whole seconds (rounded up), or 0 when none shows.
function BQ_pillSecondsLeft(bq as object, now as dynamic) as integer
    if bq.activePill = "" then return 0
    remaining = bq.pillRemainingMs
    if bq.pillEndsAt <> invalid then remaining = bq.pillEndsAt - now
    if remaining < 0 then remaining = 0
    return (remaining + 999) \ 1000
end function

' The playing plan's summary so far, or invalid without a plan.
function BQ_runningSummary(bq as object, now as dynamic) as dynamic
    if bq.current = invalid then return invalid
    return BQ_summaryOf(bq, bq.current, now)
end function

' ---------- Trigger ----------

sub BQ_evaluate(bq as object, now as dynamic)
    if bq.transportTrouble or bq.pickPending then return
    st = bq.current
    if st = invalid then return
    if not BQ_shouldTrigger(bq, st.tracker, now) then return
    if BQ_isBusy(bq) then return
    if st.cooldownUntil <> invalid and now < st.cooldownUntil then
        BQ_suppressUntil(bq, st, st.cooldownUntil, now)
        return
    end if
    plan = st.plan
    if bq.answeredQuality <> invalid and bq.answeredQuality = plan.quality then return
    if not BQ_attemptStarted(st) and not BQ_slowLinkEvidence(bq, plan) then return
    if bq.mode = "never" then
        st.action = "ignored"
        BQ_resetTracker(bq, st, now)
        return
    end if
    lowering = BQ_loweringFor(bq, plan)
    if lowering = invalid then
        BQ_showCantLower(bq, st)
        BQ_resetTracker(bq, st, now)
        return
    end if
    if plan.quality = "auto" and bq.mode = "always" then
        BQ_sendLowering(bq, st, lowering, "automatic")
        return
    end if
    if bq.reofferNotBefore <> invalid and now < bq.reofferNotBefore then
        BQ_suppressUntil(bq, st, bq.reofferNotBefore, now)
        return
    end if
    BQ_showPill(bq, "prompt")
end sub

function BQ_isBusy(bq as object) as boolean
    return bq.pending <> invalid or BQ_timerActive(bq, "rearm") or bq.activePill <> "" or bq.deferredPill <> ""
end function

' The plan's media measurably arrived more slowly than its delivered bitrate. No measurement
' (direct play over HTTP gives the Roku no segment timings) is no evidence.
function BQ_slowLinkEvidence(bq as object, plan as object) as boolean
    if plan.deliveredKbps <= 0 or bq.throughputKbps <= 0 then return false
    return bq.throughputKbps < plan.deliveredKbps
end function

sub BQ_suppressUntil(bq as object, st as object, liftAt as dynamic, now as dynamic)
    if st.tracker.stallStartedAt = invalid then return
    BQ_setTimer(bq, "reevaluate", liftAt, { sid: st.sid })
    if now > liftAt then BQ_cancelTimer(bq, "reevaluate")
end sub

' The replan that lowers the plan one step, or invalid when nothing is lower.
function BQ_loweringFor(bq as object, plan as object) as dynamic
    rungs = []
    for each r in plan.rungs
        if r.kbps > 0 then rungs.Push(r)
    end for
    rungs.SortBy("kbps", "r")
    delivered = plan.deliveredKbps
    if plan.quality = "auto" then
        if delivered <= 0 then return invalid
        lower = false
        for each r in rungs
            if r.kbps < delivered then lower = true
        end for
        if not lower then return invalid
        ' The exact integer floor of delivered x 7 / 10 (22120 gives 15484).
        estimate = (delivered * 7) \ 10
        if estimate < bq.c.MIN_ESTIMATE_KBPS then return invalid
        return { "type": "replan", quality: "auto", estimateKbps: estimate, estimateSource: "observed_rebuffer", learnedLimit: "" }
    end if
    ' Below the lower of the rung the plan names and the delivered bitrate.
    ceiling = 0
    if plan.activeQuality <> invalid then
        for each r in rungs
            if ceiling = 0 and r.label = plan.activeQuality then ceiling = r.kbps
        end for
    end if
    if delivered > 0 and (ceiling = 0 or delivered < ceiling) then ceiling = delivered
    if ceiling <= 0 then return invalid
    for each r in rungs
        if r.kbps < ceiling then return { "type": "replan", quality: r.label, estimateKbps: 0, estimateSource: "", learnedLimit: "" }
    end for
    return invalid
end function

sub BQ_sendLowering(bq as object, st as object, replan as object, kind as string)
    bq.pending = { kind: kind, fromKbps: st.plan.deliveredKbps, fromState: st, actionBefore: st.action }
    if kind = "automatic" then st.action = "lowered" else st.action = "accepted"
    BQ_startRearm(bq)
    BQ_emit(bq, replan)
end sub

sub BQ_showCantLower(bq as object, st as object)
    st.action = "cant_lower"
    if bq.cantLowerShown then return
    bq.cantLowerShown = true
    BQ_emit(bq, { "type": "notice", key: "cant_lower" })
end sub

sub BQ_startRearm(bq as object)
    BQ_setTimer(bq, "rearm", bq.now + bq.c.REARM_AFTER_UNADOPTED_MS)
end sub

' ---------- Stall tracker ----------

sub BQ_startStallTiming(bq as object, st as object, now as dynamic)
    tr = st.tracker
    startedAt = tr.stallStartedAt
    if startedAt = invalid then
        graceEnd = BQ_graceEndsAt(bq, tr, now)
        startedAt = now
        if graceEnd > now then startedAt = graceEnd
    end if
    tr.stallStartedAt = startedAt
    if st.statsStallStartedAt = invalid then st.statsStallStartedAt = startedAt
    if BQ_timerActive(bq, "longStall") then return
    BQ_setTimer(bq, "longStall", startedAt + bq.c.LONG_STALL_MS, { sid: st.sid, startedAt: startedAt })
end sub

function BQ_graceEndsAt(bq as object, tr as object, now as dynamic) as dynamic
    anchor = now
    if tr.firstWaitingAt <> invalid then
        anchor = tr.firstWaitingAt
    else if tr.firstPlayingAt <> invalid then
        anchor = tr.firstPlayingAt
    end if
    return anchor + bq.c.STARTUP_GRACE_MS
end function

sub BQ_clearStallTiming(bq as object, st as object)
    st.tracker.stallStartedAt = invalid
    BQ_cancelTimer(bq, "longStall")
    BQ_cancelTimer(bq, "reevaluate")
end sub

sub BQ_interrupt(bq as object, st as object, now as dynamic)
    st.tracker.stalled = false
    BQ_clearStallTiming(bq, st)
    if st.statsStallStartedAt <> invalid then BQ_recordStallStat(bq, st, now - st.statsStallStartedAt, false)
    st.statsStallStartedAt = invalid
end sub

sub BQ_resetTracker(bq as object, st as object, now as dynamic)
    tr = st.tracker
    tr.firstPlayingAt = now - bq.c.STARTUP_GRACE_MS
    tr.firstWaitingAt = invalid
    tr.stallEnds = []
    tr.longStallEndedAt = invalid
    BQ_clearStallTiming(bq, st)
    if tr.stalled and not bq.transportTrouble then BQ_startStallTiming(bq, st, now)
end sub

function BQ_shouldTrigger(bq as object, tr as object, now as dynamic) as boolean
    c = bq.c
    if tr.longStallEndedAt <> invalid and now - tr.longStallEndedAt < c.STALL_WINDOW_MS then return true
    if tr.stallStartedAt <> invalid and now - tr.stallStartedAt >= c.LONG_STALL_MS then return true
    kept = []
    for each e in tr.stallEnds
        if now - e < c.STALL_WINDOW_MS then kept.Push(e)
    end for
    tr.stallEnds = kept
    return kept.Count() >= c.STALLS_BEFORE_TRIGGER
end function

' ---------- Summary ----------

sub BQ_stopPlayedClock(st as object, now as dynamic)
    if st.playingSince <> invalid then
        d = now - st.playingSince
        if d > 0 then st.playedMs = st.playedMs + d
    end if
    st.playingSince = invalid
end sub

sub BQ_recordStallStat(bq as object, st as object, durationMs as dynamic, counted as boolean)
    if durationMs <= 0 then return
    if counted and durationMs >= bq.c.STALL_MIN_MS then st.stallCount = st.stallCount + 1
    st.stallTotalMs = st.stallTotalMs + durationMs
    if durationMs > st.stallLongestMs then st.stallLongestMs = durationMs
end sub

function BQ_summaryOf(bq as object, st as object, now as dynamic) as object
    playingMs = 0
    if st.playingSince <> invalid and now > st.playingSince then playingMs = now - st.playingSince
    stallMs = 0
    if st.statsStallStartedAt <> invalid and now > st.statsStallStartedAt then stallMs = now - st.statsStallStartedAt
    extra = 0
    if stallMs >= bq.c.STALL_MIN_MS then extra = 1
    longest = st.stallLongestMs
    if stallMs > longest then longest = stallMs
    return {
        planId: st.plan.serverPlanId
        adoptionId: st.plan.planId
        playedMs: st.playedMs + playingMs
        stallCount: st.stallCount + extra
        stallTotalMs: st.stallTotalMs + stallMs
        stallLongestMs: longest
        deliveredKbps: st.plan.deliveredKbps
        mode: bq.mode
        action: st.action
    }
end function

sub BQ_dropPlan(bq as object, now as dynamic)
    if bq.current <> invalid then BQ_emit(bq, { "type": "summary", summary: BQ_summaryOf(bq, bq.current, now) })
    bq.current = invalid
    bq.pending = invalid
    BQ_hidePill(bq)
    BQ_cancelTimer(bq, "longStall")
    BQ_cancelTimer(bq, "reevaluate")
    BQ_cancelTimer(bq, "rearm")
end sub

' ---------- Pill ----------

sub BQ_showPill(bq as object, kind as string)
    if bq.otherPillVisible then
        bq.deferredPill = kind
        bq.deferredResumes = false
        return
    end if
    BQ_present(bq, kind, false)
end sub

sub BQ_present(bq as object, kind as string, resume as boolean)
    bq.deferredPill = ""
    bq.deferredResumes = false
    bq.activePill = kind
    if not resume then
        bq.pillRemainingMs = bq.c.PROMPT_SECONDS * 1000
        if kind = "prompt" then bq.promptShownAt = bq.now
    end if
    BQ_publishPill(bq)
    if not bq.paused then BQ_startPillTimer(bq)
end sub

sub BQ_obscurePill(bq as object)
    kind = bq.activePill
    if kind = "" then return
    BQ_stopPillTimer(bq)
    bq.activePill = ""
    bq.deferredPill = kind
    bq.deferredResumes = true
    BQ_publishPill(bq)
end sub

sub BQ_startPillTimer(bq as object)
    BQ_cancelTimer(bq, "pill")
    bq.pillEndsAt = invalid
    if bq.pillRemainingMs <= 0 then
        BQ_pillTimedOut(bq)
        return
    end if
    bq.pillEndsAt = bq.now + bq.pillRemainingMs
    BQ_setTimer(bq, "pill", bq.pillEndsAt)
end sub

sub BQ_stopPillTimer(bq as object)
    if bq.pillEndsAt <> invalid then
        remaining = bq.pillEndsAt - bq.now
        if remaining < 0 then remaining = 0
        bq.pillRemainingMs = remaining
    end if
    bq.pillEndsAt = invalid
    BQ_cancelTimer(bq, "pill")
end sub

sub BQ_freezePill(bq as object)
    if bq.pillEndsAt = invalid then return
    BQ_stopPillTimer(bq)
    BQ_publishPill(bq)
end sub

sub BQ_thawPill(bq as object)
    if bq.activePill = "" or bq.pillEndsAt <> invalid then return
    BQ_startPillTimer(bq)
end sub

sub BQ_pillTimedOut(bq as object)
    kind = bq.activePill
    if kind = "" then return
    BQ_hidePill(bq)
    if kind = "undo" then
        BQ_undoEnded(bq)
        return
    end if
    ' The prompt withdraws without an answer: history clears, and a new trigger may offer again
    ' REOFFER_MIN_MS after it first showed.
    st = bq.current
    if st = invalid then return
    st.action = "timed_out"
    bq.reofferNotBefore = bq.promptShownAt + bq.c.REOFFER_MIN_MS
    BQ_resetTracker(bq, st, bq.now)
end sub

sub BQ_undoEnded(bq as object)
    st = bq.current
    if st = invalid or st.tracker.stallStartedAt = invalid then return
    if bq.now - st.tracker.stallStartedAt >= bq.c.LONG_STALL_MS then BQ_evaluate(bq, bq.now)
end sub

sub BQ_publishPill(bq as object)
    shown = bq.activePill
    if shown <> bq.pill then
        if shown = "prompt" then BQ_emit(bq, { "type": "prompt_shown" })
        if shown = "undo" then BQ_emit(bq, { "type": "undo_shown" })
        bq.pill = shown
    end if
end sub

sub BQ_hidePill(bq as object)
    BQ_cancelTimer(bq, "pill")
    bq.pillEndsAt = invalid
    bq.activePill = ""
    bq.deferredPill = ""
    bq.deferredResumes = false
    bq.pillRemainingMs = 0
    BQ_publishPill(bq)
end sub

' ---------- Kept step-down estimate (KeptStepDownEstimate.kt) ----------

' Applies the kept-estimate rule to one replan body right before it is sent. kept: { attempt,
' kbps } or invalid; lowering: the controller's replan output, or invalid for a replan the client
' sends for its own reasons. Returns { body, kept }.
'  - a lowering keeps its estimate, replacing any earlier one;
'  - Restore (learned_limit "clear") and a quality_change the controller did not send discard it;
'  - any other Auto replan of the same attempt without an estimate of its own carries it, with no
'    bandwidth_estimate_source (it is not a new observation).
function BQ_withKeptEstimate(body as object, kept as dynamic, lowering as dynamic) as object
    attempt = BQ_str(body.playback_attempt_id)
    observed = 0
    if lowering <> invalid then observed = lowering.estimateKbps
    discards = (lowering <> invalid and lowering.learnedLimit = "clear") or (lowering = invalid and BQ_str(body.operation) = "quality_change")
    if discards then
        if kept <> invalid and kept.attempt = attempt then kept = invalid
        return { body: body, kept: kept }
    end if
    if observed > 0 then return { body: body, kept: { attempt: attempt, kbps: observed } }
    if kept = invalid or kept.attempt <> attempt or body.bandwidth_estimate_kbps <> invalid then return { body: body, kept: kept }
    q = LCase(BQ_str(body.quality_preference))
    if q <> "auto" and q <> "original" and q <> "source" and q <> "max" and q <> "" then return { body: body, kept: kept }
    body.bandwidth_estimate_kbps = kept.kbps
    body.Delete("bandwidth_estimate_source")
    body.Delete("observed_throughput_kbps")
    return { body: body, kept: kept }
end function
