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
' A dropped connection is not a failed route: a Video error whose code or text says the media
' connection failed (Roku's -1/-2, or -3/-5 quoting "Transfer error", "zero length playlist",
' "Errors seen on all bitrates ... last_err:961", resets and timeouts) reconnects the same route
' with a no-op track_change replan, at once and then after 1, 2, 4, 8 and 15 s, for up to 2 minutes
' from the first error; only then does the failure_recovery ladder above take over (which excludes
' the route on the server). Adapted from Silo-Server/silo-roku, AGPL-3.0
' (source/playback/video.bs TRANSPORT_PATTERN, source/playback/recovery.bs decide/reconnectDelayMs),
' device-proven there in hardware runs 14 and 15 (docs/hardware-evidence.md).
' Debug deep links (simulator: the Video node never plays): debugVideoError=<code> fakes that
' Roku error 4 s after each plan is mounted (net = a dropped connection, -5 "Errors seen on all
' bitrates:last_err:961"; drop = -3 "mpr zero length playlist"; large = -3 "mpr playlist file is too
' large"; a ":N" suffix fakes it on the first N plans only, so a reconnect can succeed);
' debugStallSeconds=<n> sets the no-progress limit ("off" disables the watchdog, for long
' simulator runs in the player).
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
    m.reconnectTimer = CreateObject("roSGNode", "Timer")
    m.reconnectTimer.duration = 1
    m.top.appendChild(m.reconnectTimer)
    m.reconnectTimer.observeField("fire", "Recovery_onReconnectTimer")
    m.recClock = CreateObject("roTimespan")
    m.recDebugFaked = 0   ' plans the debugVideoError hook has failed (its ":N" limit)
    m.recTimer.control = "start"
end sub

' A new playback attempt (resetPlaybackState): nothing tried yet.
'   keys: plan_attempt_keys this attempt has played; count: failure_recovery replans sent (any
'   cause); native: those sent for a Video error or a stall; inFlight: a replan answer is pending;
'   nativePending: it is a native recovery; descentPref / rungHeight: the rung this ladder chose
'   (still Auto to the ladder); still / lastPos: seconds without position movement; everPlayed:
'   the current plan reached "playing"; inventoryRetried: the empty-inventory re-read was sent;
'   errorSeen: the current plan reported a Video error (a "finished" after it is not the end);
'   outageAt: seconds (recClock) the current connection outage began, -1 when none; tries:
'   reconnects sent in it; waiting: a reconnect is scheduled; outagePaused: the viewer had paused
'   when it began; outageSpent: an outage of this attempt used up its 2 minutes without a plan
'   playing, so the next dropped connection goes to the ladder at once.
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
        errorSeen: false
        outageAt: -1.0
        tries: 0
        waiting: false
        outagePaused: false
        outageSpent: false
        attemptPlayed: false
    }
    if m.recDebugTimer <> invalid then m.recDebugTimer.control = "stop"
    if m.reconnectTimer <> invalid then m.reconnectTimer.control = "stop"
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
    m.rec.errorSeen = false
    ' A new plan replaces the one a reconnect was scheduled for.
    m.rec.waiting = false
    if m.reconnectTimer <> invalid then m.reconnectTimer.control = "stop"
    if m.rec.outageAt >= 0 then Diag_log("[siku-playback] reconnect " + m.rec.tries.ToStr() + " mounted delivery=" + Str_orEmpty(plan.delivery))
    if m.rec.nativePending then
        m.rec.nativePending = false
        Diag_log("[siku-playback] recovery " + m.rec.native.ToStr() + " mounted delivery=" + Str_orEmpty(plan.delivery) + " quality=" + PlaybackCaps_videoQuality(m.qualityPref))
    end if
    if m.recDebugTimer <> invalid and m.top.params <> invalid and Recovery_debugSpec(m.top.params.debugVideoError) <> invalid then
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

' The Video node reported an error (onVideoState), or the debug hook fakes one. info is the
' node's errorInfo ({ category, dbgmsg, errcode, ... } on newer Roku OS), or invalid.
sub Recovery_onVideoError(code as dynamic, msg as string, detail as string, info = invalid as dynamic)
    delivery = ""
    if m.plan <> invalid then delivery = Str_orEmpty(m.plan.delivery)
    kind = Recovery_errorKind(code, msg, detail, info)
    ' To the debug console too: the code matters for a bug report. Only the code leaves the device.
    Diag_log("[siku-playback] video error delivery=" + delivery + " code=" + Str_orEmpty(code) + " kind=" + kind + " msg=" + Recovery_scrub(msg) + " str=" + Recovery_scrub(detail))
    if m.rec <> invalid then m.rec.errorSeen = true
    if Recovery_playlistTooLarge(msg, detail, info) then
        ' Roku refuses an HLS playlist over 4 MiB (4,194,304 bytes; silo-roku hardware run 2, H2).
        Diag_log("[siku-playback] playlist too large: Roku refuses HLS playlists over 4 MiB delivery=" + delivery + " define=" + PlaybackCaps_str(PlaybackCaps_defineNegotiable()))
    end if
    classification = Recovery_classify(code)
    if kind = "network" or kind = "server" then
        classification = "network_error"
        if Recovery_reconnectAllowed(kind) and Recovery_reconnect(code) then return
    end if
    Recovery_fail(classification, code)
end sub

' What a Video error says failed: "network" (the media connection: Roku's -1/-2, an "http" or
' "network" errorInfo category without a status, or a transport message), "server" (the media
' answered 5xx), "http" (it answered another 4xx/3xx status, or Roku says an HTTP error without
' one), or "media" (anything else: the decoder, the format, unknown). The HTTP status decides
' first: Roku reports a refused segment as -5 with the status only in its text. Adapted from
' Silo-Server/silo-roku, AGPL-3.0 (source/playback/video.bs failure/transportFailed/httpStatus).
function Recovery_errorKind(code as dynamic, msg as dynamic, detail as dynamic, info = invalid as dynamic) as string
    texts = [Str_orEmpty(detail), Str_orEmpty(msg)]
    category = ""
    if info <> invalid and Type(info) = "roAssociativeArray" then
        texts.Push(Str_orEmpty(info.dbgmsg))
        category = LCase(Str_orEmpty(info.category))
    end if
    status = Recovery_httpStatus(texts, info)
    if status >= 500 then return "server"
    if status >= 400 then return "http"
    if Recovery_mentions("http response code said error", texts) then return "http"
    c = PlaybackError_rokuCode(code)
    if c <> invalid and (c = -1 or c = -2) then return "network"
    if category = "http" or category = "network" then return "network"
    pattern = "\btransfer error:(?!\s*http response code said error)|zero length playlist|errors seen on all bitrates|\blast_?err(?:or)?:-?[1-9]|connection (?:reset|refused|closed)|reset by peer|couldn'?t (?:connect|resolve)|timeout was reached|timed out|server returned nothing"
    if Recovery_mentions(pattern, texts) then return "network"
    return "media"
end function

' Whether pattern (case-insensitive) matches any of texts.
function Recovery_mentions(pattern as string, texts as object) as boolean
    re = CreateObject("roRegex", pattern, "i")
    for each t in texts
        if t <> "" and re.IsMatch(t) then return true
    end for
    return false
end function

' The HTTP status a Video error reports, or 0: errorInfo's errcode for the "http" category, else
' a status Roku quotes as "last_err:<n>" or "response code:(<url>):<n>", else "http ... <n>".
function Recovery_httpStatus(texts as object, info as dynamic) as integer
    if info <> invalid and Type(info) = "roAssociativeArray" and LCase(Str_orEmpty(info.category)) = "http" then
        e = Int(Num_or(info.errcode, 0))
        if e >= 100 and e <= 599 then return e
    end if
    for each pattern in ["\blast_?err(?:or)?:([1-5][0-9][0-9])\b", "\bresponse code:(?:\([^)]*\):)?([1-5][0-9][0-9])\b", "\bhttp(?!s?://)(?:/[0-9.]+)?[^0-9]{0,16}?\b([1-5][0-9][0-9])\b"]
        re = CreateObject("roRegex", pattern, "i")
        for each t in texts
            if t <> "" then
                found = re.Match(t)
                if found.Count() >= 2 then return Int(Val(found[1]))
            end if
        end for
    end for
    return 0
end function

' Roku's "mpr playlist file is too large." (an HLS media playlist over 4 MiB).
function Recovery_playlistTooLarge(msg as dynamic, detail as dynamic, info = invalid as dynamic) as boolean
    texts = [Str_orEmpty(detail), Str_orEmpty(msg)]
    if info <> invalid and Type(info) = "roAssociativeArray" then texts.Push(Str_orEmpty(info.dbgmsg))
    return Recovery_mentions("playlist file is too large", texts)
end function

' A dropped connection reconnects; a 5xx from the media only once this attempt has shown a frame
' (before that it is the route refusing, which the ladder handles). Never twice in one attempt
' after an outage ran out without a plan playing.
function Recovery_reconnectAllowed(kind as string) as boolean
    if m.rec = invalid or m.rec.outageSpent then return false
    if kind = "network" then return true
    return kind = "server" and (m.rec.attemptPlayed = true or m.rec.outageAt >= 0)
end function

' Seconds before reconnect try n (1-based): at once, then 1, 2, 4, 8 and 15 s (silo-roku
' reconnectDelayMs: 1 s doubling to a 15 s cap, its first try immediate).
function Recovery_reconnectDelay(tries as integer) as float
    if tries <= 1 then return 0.0
    d = 1.0
    n = 2
    while n < tries
        d = d * 2
        if d >= 15 then return 15.0
        n = n + 1
    end while
    return d
end function

' The outage's budget: reconnects stop this many seconds after the first dropped connection.
function Recovery_reconnectBudget() as integer
    return 120
end function

function Recovery_now() as float
    return m.recClock.TotalMilliseconds() / 1000.0
end function

' True while an outage is being reconnected (the buffering label says so).
function Recovery_reconnecting() as boolean
    if m.rec = invalid then return false
    return m.rec.outageAt >= 0
end function

' Schedules the next reconnect of the current route; false when the outage's 2 minutes are used up
' (or nothing can be replanned), so the caller falls back to the failure_recovery ladder.
function Recovery_reconnect(code as dynamic) as boolean
    if m.closing or m.rec = invalid or m.plan = invalid or m.sessionId = "" or installationId() = "" then return false
    now = Recovery_now()
    delivery = Str_orEmpty(m.plan.delivery)
    if m.rec.outageAt < 0 then
        m.rec.outageAt = now
        m.rec.tries = 0
        m.rec.outagePaused = m.isPaused
        Diag_log("[siku-playback] connection lost code=" + Str_orEmpty(code) + " delivery=" + delivery + "; reconnecting for up to " + Recovery_reconnectBudget().ToStr() + " s")
    end if
    elapsed = now - m.rec.outageAt
    if elapsed >= Recovery_reconnectBudget() then
        Diag_log("[siku-playback] reconnect gave up after " + Int(elapsed).ToStr() + " s tries=" + m.rec.tries.ToStr() + "; asking for another route")
        m.rec.outageAt = -1.0
        m.rec.waiting = false
        m.rec.outageSpent = true
        return false
    end if
    m.rec.lastRoku = code
    m.rec.tries = m.rec.tries + 1
    delay = Recovery_reconnectDelay(m.rec.tries)
    if delay > Recovery_reconnectBudget() - elapsed then delay = Recovery_reconnectBudget() - elapsed
    if delay < 0.1 then delay = 0.1
    m.recDebugTimer.control = "stop"
    m.video.control = "stop"
    setBuffering(true)
    m.bufferLabel.text = Tx("Reconnecting")
    m.rec.waiting = true
    Diag_log("[siku-playback] reconnect " + m.rec.tries.ToStr() + " in " + Str(delay).Trim() + " s")
    m.reconnectTimer.control = "stop"
    m.reconnectTimer.duration = delay
    m.reconnectTimer.control = "start"
    return true
end function

' The scheduled reconnect: a no-op track_change for the same tracks at the current position. It
' excludes nothing (no attempted keys, attempt_count 1), so the server may answer the same route.
sub Recovery_onReconnectTimer()
    if m.rec = invalid or not m.rec.waiting or m.closing then return
    if m.errorGroup.visible then
        m.rec.waiting = false
        return
    end if
    ' Another replan is on its way (the viewer's pick, a re-anchor): wait for it. Its plan replaces
    ' the failed one, and a dropped connection on that plan continues this outage.
    if m.rec.inFlight or m.replanPending or m.reanchorBusy = true then
        m.reconnectTimer.duration = 1
        m.reconnectTimer.control = "start"
        return
    end if
    m.rec.waiting = false
    sendReplan("track_change", "reconnect")
end sub

' The current plan reached "playing": it has played (a later "finished" is real), and an outage
' it was reconnecting from is over.
sub Recovery_notePlaying()
    if m.rec = invalid then return
    m.rec.everPlayed = true
    m.rec.attemptPlayed = true
    m.rec.outageSpent = false
    if m.rec.outageAt >= 0 then
        Diag_log("[siku-playback] reconnected after " + Int(Recovery_now() - m.rec.outageAt).ToStr() + " s tries=" + m.rec.tries.ToStr())
        m.rec.outageAt = -1.0
        m.rec.tries = 0
        m.bufferLabel.text = Tx("Buffering")
    end if
end sub

' The Video node's "finished" is the end of the title only for a plan that played and is still
' current: Roku also reports it right after an error (silo-roku hardware evidence, harness defect
' 3), and a replan, reconnect or re-anchor is about to replace the plan. "" when it is the end,
' else the reason it is ignored (for the console line).
function Recovery_finishedRefusal() as string
    if m.rec = invalid then return ""
    if m.rec.errorSeen then return "after_error"
    if m.rec.inFlight or m.replanPending = true then return "replanning"
    if m.rec.waiting or m.rec.outageAt >= 0 then return "reconnecting"
    if m.reanchorBusy = true then return "reanchoring"
    if not m.rec.everPlayed then return "never_played"
    return ""
end function

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
    m.reconnectTimer.control = "stop"
    m.rec.waiting = false
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
    Diag_log("[siku-playback] recovery " + m.rec.native.ToStr() + " classification=" + classification + " quality=" + PlaybackCaps_videoQuality(m.qualityPref) + " attempt_count=" + nextCount.ToStr())
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
    if m.replanKind = "reconnect" then return Recovery_takeFailedReconnect(resp)
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
        Diag_log("[siku-playback] recovery " + m.rec.native.ToStr() + " answered outcome=" + Str_orEmpty(d.outcome) + " reason=" + reason)
        if reason <> "" then m.rec.lastClassification = reason
        if Recovery_nextStep() <> invalid then
            Recovery_fail(cls, m.rec.lastRoku)
            return true
        end if
        PlaybackError_show("3003", { rokuCode: m.rec.lastRoku, reason: m.rec.lastClassification })
        return true
    end if
    Diag_log("[siku-playback] recovery " + m.rec.native.ToStr() + " replan failed status=" + Str_orEmpty(resp.status))
    PlaybackError_show("3003", { rokuCode: m.rec.lastRoku, reason: cls })
    return true
end function

' A reconnect's replan failed. Unreachable server (no answer, 5xx, a proxy's error page): try
' again on the schedule. A lost session: a new one at the position (renewSession). A terminal
' answer or the budget used up: the failure_recovery ladder.
function Recovery_takeFailedReconnect(resp as object) as boolean
    Diag_log("[siku-playback] reconnect " + m.rec.tries.ToStr() + " answered status=" + Str_orEmpty(resp.status))
    if (resp.status = 404 or resp.status = 410) and renewSession("reconnect") then return true
    if resp.status = 404 or resp.status = 410 then
        setBuffering(false)
        m.rec.outageAt = -1.0
        PlaybackError_show("3004", { rokuCode: m.rec.lastRoku, reason: "network_error" })
        return true
    end if
    ' The server answered (a terminal, or a plan the client must refuse): not a connection problem.
    answered = resp.ok and Type(resp.data) = "roAssociativeArray"
    if not answered and Recovery_reconnect(m.rec.lastRoku) then return true
    m.rec.outageAt = -1.0
    m.rec.outageSpent = true
    Recovery_fail("network_error", m.rec.lastRoku)
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
    held = m.closing or m.finished or m.plan = invalid or m.sessionId = "" or m.rec.inFlight or m.rec.waiting or m.errorGroup.visible or m.isPaused or m.scrubbing
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
    Diag_log("[siku-playback] no progress for " + limit.ToStr() + " s state=" + st + " played=" + PlaybackCaps_str(m.rec.everPlayed))
    Recovery_fail("buffering_timeout", invalid)
end sub

' debugVideoError=<code>: the simulator's Video node never plays or fails, so this fakes the
' Roku error on each mounted plan to walk the ladder against the mock.
sub Recovery_onDebugError()
    if m.closing or m.plan = invalid or m.errorGroup.visible then return
    spec = Recovery_debugSpec(m.top.params.debugVideoError)
    if spec = invalid then return
    if spec.limit > 0 and m.recDebugFaked >= spec.limit then return
    m.recDebugFaked = m.recDebugFaked + 1
    Diag_log("[siku-playback] debugVideoError: faking Roku error " + spec.code.ToStr())
    Recovery_onVideoError(spec.code, "debug", spec.text)
end sub

' debugVideoError's value: a Roku code ("-5"), net (a dropped connection: -5 "Errors seen on all
' bitrates:last_err:961"), drop (-3 "mpr zero length playlist") or large (-3 "mpr playlist file is
' too large."), with an optional ":N" (only the first N plans fail). { code, text, limit } or invalid.
function Recovery_debugSpec(value as dynamic) as dynamic
    v = LCase(Str_orEmpty(value)).Trim()
    if v = "" then return invalid
    limit = 0
    colon = Instr(1, v, ":")
    if colon > 0 then
        limit = Int(Val(Mid(v, colon + 1)))
        v = Left(v, colon - 1)
    end if
    if v = "net" then return { code: -5, text: "buffer:loop:demux:Errors seen on all bitrates:last_err:961", limit: limit }
    if v = "drop" then return { code: -3, text: "reader pick stream error:bad:mpr zero length playlist", limit: limit }
    if v = "large" then return { code: -3, text: "reader pick stream error:bad:mpr playlist file is too large.", limit: limit }
    code = PlaybackError_rokuCode(v)
    if code = invalid then return invalid
    return { code: code, text: "debugVideoError", limit: limit }
end function

' Empty inventory: the item is read once more before "no playable file" (a catalog that was
' still being written, or a stale cache). True when the fresh read was sent.
function Recovery_rereadInventory() as boolean
    if m.rec = invalid then Recovery_reset()
    if m.rec.inventoryRetried then return false
    m.rec.inventoryRetried = true
    Diag_log("[siku-playback] no playable file in the item's inventory; reading it once more")
    p = m.top.params
    q = { image_size: "medium" }
    if p <> invalid and not Str_isEmpty(p.fileId) then q.file_id = Str_orEmpty(p.fileId)
    Api_get("/api/v2/watch/" + Str_urlEncode(m.itemId), q, "onWatch")
    return true
end function
