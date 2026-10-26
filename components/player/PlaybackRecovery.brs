' Recovery when the Roku cannot play a plan (docs/playback-errors.md, playback-protocol-v3 §6).
' A Video node error, or a stream whose position has not moved for a bounded time, is answered
' with a failure_recovery replan before Siku gives up:
'   1. the same request again (the server skips the plan that failed and picks another route);
'   2. with Auto quality only: 1080p, then 720p, then 480p, each only when the plan's
'      available_qualities lists a rung of that class and it is below what failed.
' A quality or track the viewer chose stays fixed: no descent, only step 1. Every replan of the
' attempt carries the plan keys it has tried (attempted_plan_keys, at most 16) and attempt_count
' (failure recoveries so far, 1..8), so a Roku that fails every route reaches a terminal instead
' of cycling. The ladder is adapted from ManavA/silo-roku (AGPL-3.0): PlayerRecoverNativeFailure,
' the buffering_timeout watchdog and SiloFallbackQuality.
' Debug deep links (simulator: the Video node never plays): debugVideoError=<code> fakes that
' Roku error 4 s after each plan is mounted; debugStallSeconds=<n> sets the no-progress limit ("off" disables
' the watchdog, for long simulator runs in the player).
' SPDX-License-Identifier: AGPL-3.0-or-later

sub Recovery_init()
    m.recTimer = CreateObject("roSGNode", "Timer")
    m.recTimer.duration = 1
    m.recTimer.repeat = true
    m.top.appendChild(m.recTimer)
    m.recTimer.observeField("fire", "Recovery_onTick")
    m.recDebugTimer = CreateObject("roSGNode", "Timer")
    m.recDebugTimer.duration = 4
    m.top.appendChild(m.recDebugTimer)
    m.recDebugTimer.observeField("fire", "Recovery_onDebugError")
    m.recTimer.control = "start"
end sub

' A new playback attempt (resetPlaybackState): nothing tried yet.
'   keys: plan_attempt_keys this attempt has played; count: failure_recovery replans sent (any
'   cause); native: those sent for a Video error or a stall; inFlight: a replan answer is pending;
'   nativePending: it is a native recovery; descentPref / rungHeight: the rung this ladder chose
'   (still Auto to the ladder); still / lastPos: seconds without position movement; everPlayed:
'   the current plan reached "playing"; inventoryRetried: the empty-inventory re-read was sent.
sub Recovery_reset()
    m.rec = {
        keys: []
        count: 0
        native: 0
        inFlight: false
        nativePending: false
        descentPref: ""
        rungHeight: 0
        still: 0
        lastPos: -1.0
        everPlayed: false
        inventoryRetried: false
        lastClassification: ""
        lastRoku: invalid
    }
    if m.recDebugTimer <> invalid then m.recDebugTimer.control = "stop"
end sub

' A plan is handed to the Video node (start, replan or remount).
sub Recovery_notePlan(plan as object)
    if m.rec = invalid then Recovery_reset()
    key = Str_orEmpty(plan.plan_attempt_key)
    if key <> "" and not PlaybackCaps_has(m.rec.keys, key) then m.rec.keys.Push(key)
    m.rec.inFlight = false
    m.rec.still = 0
    m.rec.lastPos = -1.0
    m.rec.everPlayed = false
    if m.rec.nativePending then
        m.rec.nativePending = false
        print "[siku-playback] recovery " + m.rec.native.ToStr() + " mounted delivery=" + Str_orEmpty(plan.delivery) + " quality=" + PlaybackCaps_videoQuality(m.qualityPref)
    end if
    if m.recDebugTimer <> invalid and m.top.params <> invalid and PlaybackError_rokuCode(m.top.params.debugVideoError) <> invalid then
        m.recDebugTimer.control = "stop"
        m.recDebugTimer.control = "start"
    end if
end sub

' Adds the attempt's history to a replan body built by PlaybackCaps_replanBody.
sub Recovery_decorateReplan(body as object, operation as string)
    if m.rec = invalid then Recovery_reset()
    keys = []
    for each k in m.rec.keys
        keys.Push(k)
    end for
    cur = Str_orEmpty(body.plan_attempt_key)
    if cur <> "" and not PlaybackCaps_has(keys, cur) then keys.Push(cur)
    ' Keep the newest 16 (the contract's limit); a recovery is refused before it would need more.
    while keys.Count() > 16
        keys.Shift()
    end while
    if keys.Count() > 0 then body.attempted_plan_keys = keys
    if operation = "failure_recovery" or operation = "seek_failure_recovery" then m.rec.count = m.rec.count + 1
    n = m.rec.count
    if n < 1 then n = 1
    if n > 8 then n = 8
    body.attempt_count = n
    m.rec.inFlight = true
end sub

' The Video node reported an error (onVideoState), or the debug hook fakes one.
sub Recovery_onVideoError(code as dynamic, msg as string, detail as string)
    delivery = ""
    if m.plan <> invalid then delivery = Str_orEmpty(m.plan.delivery)
    ' To the debug console too: the code matters for a bug report. Only the code leaves the device.
    print "[siku-playback] video error delivery=" + delivery + " code=" + Str_orEmpty(code) + " msg=" + Recovery_scrub(msg) + " str=" + Recovery_scrub(detail)
    Recovery_fail(Recovery_classify(code), code)
end sub

' The Video node's texts can quote the stream URL (signed, with tokens): URLs are masked.
function Recovery_scrub(text as string) as string
    return CreateObject("roRegex", "[a-z][a-z0-9+.-]*://[^\s]*", "i").ReplaceAll(text, "<url>")
end function

' Roku Video errorCode → failure.classification: -1 HTTP, -2 timeout, -6 DRM; -3 (unknown),
' -4 (empty) and -5 (unsupported or undecodable media) are treated as the decoder refusing it.
function Recovery_classify(code as dynamic) as string
    c = PlaybackError_rokuCode(code)
    if c = invalid then return "decoder_failure"
    if c = -1 or c = -2 then return "network_error"
    if c = -6 then return "drm_failure"
    return "decoder_failure"
end function

' Tries the next recovery step, or shows the numbered error when none is left.
sub Recovery_fail(classification as string, rokuCode as dynamic)
    if m.closing or m.rec = invalid then return
    if m.rec.inFlight then return ' an answer that replaces this plan is on its way
    m.recDebugTimer.control = "stop"
    m.rec.lastClassification = classification
    m.rec.lastRoku = rokuCode
    ladderStep = Recovery_nextStep()
    if ladderStep = invalid then
        number = "3003"
        if m.rec.native = 0 then
            number = "3001"
            if classification = "buffering_timeout" then number = "3002"
        end if
        m.video.control = "stop"
        PlaybackError_show(number, { reason: classification, rokuCode: rokuCode })
        return
    end if
    m.rec.native = m.rec.native + 1
    m.rec.nativePending = true
    if ladderStep.quality <> "" then
        m.prevQualityPref = m.qualityPref
        m.qualityPref = ladderStep.quality
        m.rec.descentPref = ladderStep.quality
        m.rec.rungHeight = ladderStep.height
    end if
    nextCount = m.rec.count + 1
    print "[siku-playback] recovery " + m.rec.native.ToStr() + " classification=" + classification + " quality=" + PlaybackCaps_videoQuality(m.qualityPref) + " attempt_count=" + nextCount.ToStr()
    m.video.control = "stop"
    msg = "Roku Video node failure"
    roku = PlaybackError_rokuCode(rokuCode)
    if roku <> invalid then msg = "Roku Video node error " + roku.ToStr()
    if classification = "buffering_timeout" then msg = "Playback position did not move"
    sendReplan("failure_recovery", "native", { classification: classification, message: msg })
end sub

' The next step of the ladder: { quality: "" (same request) or a rung label, height }, or invalid.
function Recovery_nextStep() as dynamic
    if m.plan = invalid or m.sessionId = "" or installationId() = "" then return invalid
    if m.rec.count >= 8 then return invalid
    keys = m.rec.keys.Count()
    cur = Str_orEmpty(m.plan.plan_attempt_key)
    if cur <> "" and not PlaybackCaps_has(m.rec.keys, cur) then keys = keys + 1
    if keys > 16 then return invalid
    if m.rec.native = 0 then return { quality: "", height: 0 }
    if not Recovery_autoQuality() then return invalid
    limit = Recovery_deliveredHeight()
    if limit <= 0 then limit = 100000
    if m.rec.rungHeight > 0 and m.rec.rungHeight < limit then limit = m.rec.rungHeight
    for each h in [1080, 720, 480]
        if h < limit then
            label = Recovery_advertisedRung(h)
            if label <> "" then return { quality: label, height: h }
        end if
    end for
    return invalid
end function

' Auto, or a rung this ladder chose while the viewer was on Auto.
function Recovery_autoQuality() as boolean
    if PlaybackCaps_videoQuality(m.qualityPref) = "auto" then return true
    return m.rec.descentPref <> "" and Str_orEmpty(m.qualityPref) = m.rec.descentPref
end function

' The frame height the failed plan delivered (the encode's, else the source's), 0 when unknown.
function Recovery_deliveredHeight() as integer
    h = 0
    r = m.plan.effective_recipe
    if r <> invalid and Type(r) = "roAssociativeArray" then h = Int(Num_or(r.height, 0))
    if h <= 0 and m.plan.source <> invalid and Type(m.plan.source) = "roAssociativeArray" then h = Int(Num_or(m.plan.source.height, 0))
    return h
end function

' An available_qualities label of that class: "<h>p-medium", else "<h>p", else any rung of it.
function Recovery_advertisedRung(h as integer) as string
    want = h.ToStr() + "p"
    found = []
    for each q in Arr_or(m.plan.available_qualities)
        if q <> invalid and Type(q) = "roAssociativeArray" and not PlaybackCaps_truthy(q.preserves_source) then
            l = LCase(Str_orEmpty(q.label))
            qh = Int(Num_or(q.height, 0))
            if qh <= 0 then qh = Int(Val(l))
            if l <> "" and l <> "original" and qh = h then found.Push(l)
        end if
    end for
    if PlaybackCaps_has(found, want + "-medium") then return want + "-medium"
    if PlaybackCaps_has(found, want) then return want
    if found.Count() > 0 then return found[0]
    return ""
end function

' Every replan answer clears the in-flight mark (a refused one too).
sub Recovery_onReplanAnswered()
    if m.rec <> invalid then m.rec.inFlight = false
end sub

' onReplan's failure path for a native recovery: true when handled here. A terminal answer tries
' the next rung (the server may still serve a lower quality); a lost session or a failed request
' ends the ladder.
function Recovery_takeFailedReplan(resp as object) as boolean
    if m.replanKind <> "native" then return false
    m.rec.nativePending = false
    setBuffering(false)
    cls = Str_orEmpty(m.rec.lastClassification)
    if resp.status = 404 or resp.status = 410 then
        PlaybackError_show("3004", { rokuCode: m.rec.lastRoku, reason: cls })
        return true
    end if
    d = resp.data
    if resp.ok and Type(d) = "roAssociativeArray" and Str_orEmpty(d.outcome) <> "playable" then
        reason = ""
        if d.terminal <> invalid and Type(d.terminal) = "roAssociativeArray" then reason = Str_orEmpty(d.terminal.reason)
        print "[siku-playback] recovery " + m.rec.native.ToStr() + " answered outcome=" + Str_orEmpty(d.outcome) + " reason=" + reason
        if reason <> "" then m.rec.lastClassification = reason
        if Recovery_nextStep() <> invalid then
            Recovery_fail(cls, m.rec.lastRoku)
            return true
        end if
        PlaybackError_show("3003", { rokuCode: m.rec.lastRoku, reason: m.rec.lastClassification })
        return true
    end if
    print "[siku-playback] recovery " + m.rec.native.ToStr() + " replan failed status=" + Str_orEmpty(resp.status)
    PlaybackError_show("3003", { rokuCode: m.rec.lastRoku, reason: cls })
    return true
end function

' Watchdog, once a second: a stream that is buffering or "playing" without its position moving
' for 60 s (120 s before the plan first played, including a Video node still in "none") is a
' buffering_timeout. Paused, seeking, a pending replan, the error dialog and Up Next after the
' end all hold the clock.
sub Recovery_onTick()
    if m.rec = invalid then return
    st = Str_orEmpty(m.video.state)
    if st = "playing" then m.rec.everPlayed = true
    held = m.closing or m.finished or m.plan = invalid or m.sessionId = "" or m.rec.inFlight or m.errorGroup.visible or m.isPaused or m.scrubbing
    if not held then held = HoldSeek_active()
    ' "none" counts only before the plan first played: content was handed over and never started.
    moving = st = "buffering" or st = "playing" or (st = "none" and not m.rec.everPlayed)
    if not held and m.top.params <> invalid and LCase(Str_orEmpty(m.top.params.debugStallSeconds)) = "off" then held = true
    if held or not moving then
        m.rec.still = 0
        m.rec.lastPos = -1.0
        return
    end if
    vidPos = Num_or(m.video.position, 0)
    if m.rec.lastPos < 0 or Abs(vidPos - m.rec.lastPos) > 0.25 then
        m.rec.lastPos = vidPos
        m.rec.still = 0
        return
    end if
    m.rec.still = m.rec.still + 1
    limit = 60
    if not m.rec.everPlayed then limit = 120
    if m.top.params <> invalid then
        dbg = Int(Num_or(m.top.params.debugStallSeconds, 0))
        if dbg > 0 then limit = dbg
    end if
    if m.rec.still < limit then return
    m.rec.still = 0
    print "[siku-playback] no progress for " + limit.ToStr() + " s state=" + st + " played=" + PlaybackCaps_str(m.rec.everPlayed)
    Recovery_fail("buffering_timeout", invalid)
end sub

' debugVideoError=<code>: the simulator's Video node never plays or fails, so this fakes the
' Roku error on each mounted plan to walk the ladder against the mock.
sub Recovery_onDebugError()
    if m.closing or m.plan = invalid or m.errorGroup.visible then return
    code = PlaybackError_rokuCode(m.top.params.debugVideoError)
    if code = invalid then return
    print "[siku-playback] debugVideoError: faking Roku error " + code.ToStr()
    Recovery_onVideoError(code, "debug", "debugVideoError")
end sub

' Empty inventory: the item is read once more before "no playable file" (a catalog that was
' still being written, or a stale cache). True when the fresh read was sent.
function Recovery_rereadInventory() as boolean
    if m.rec = invalid then Recovery_reset()
    if m.rec.inventoryRetried then return false
    m.rec.inventoryRetried = true
    print "[siku-playback] no playable file in the item's inventory; reading it once more"
    p = m.top.params
    q = { image_size: "medium" }
    if p <> invalid and not Str_isEmpty(p.fileId) then q.file_id = Str_orEmpty(p.fileId)
    Api_get("/api/v2/watch/" + Str_urlEncode(m.itemId), q, "onWatch")
    return true
end function
