' SPDX-License-Identifier: AGPL-3.0-or-later
' The player's side of buffering quality (Silo Android #636): feeds BufferingQuality.brs from the
' Video node, sends its replans, shows its pills, and adds the buffering_quality_v1 request fields.
' Included by PlayerScreen.xml, so it runs in PlayerScreen's scope (m is the screen).
'
' Events the Roku gives us, and how they map to the controller (BufferingQualityPlayerAdapter):
'   Video state "buffering"  → waiting: "seek" after our own seek, "reload" while a newly mounted
'                              plan loads, else the network
'   Video state "playing"    → playing;  "paused" → pause;  finished / error / exit → stopped
'   downloadedSegment        → the plan's throughput (SegSize / DownloadDuration, HLS only), and
'                              the end of an outage
'   no segment for 15 s while waiting on HLS → an outage (transport_error_start), which owns the wait
' Roku reports no buffered-ahead duration at a wait's start, so a renderer wait cannot be told from
' a network wait; and a direct-played file (HTTP) gives no segment timings, so before a direct
' play first plays there is no slow-link evidence and its start wait never lowers anything.
'
' Wire (buffering-quality spec, Wire contract): requests carry bandwidth_estimate_source,
' observed_throughput_kbps and learned_limit, and buffering_quality_v1 joins client_features, only
' when the server advertises buffering_quality_v1; bandwidth_estimate_kbps is older and always goes.

sub Bufq_init()
    m.bufqPill = m.top.findNode("bufqPill")
    m.bufqBg = m.top.findNode("bufqBg")
    m.bufqTitle = m.top.findNode("bufqTitle")
    m.bufqCount = m.top.findNode("bufqCount")
    m.bufqFill = m.top.findNode("bufqFill")
    m.bufqPrimary = m.top.findNode("bufqPrimary")
    m.bufqSecondary = m.top.findNode("bufqSecondary")
    m.bufqTimer = m.top.findNode("bufqTimer")
    m.bufqClock = CreateObject("roTimespan")
    m.bufqClock.Mark()
    m.bufqTimer.observeField("fire", "Bufq_onTick")
    m.bufqPrimary.observeField("buttonSelected", "Bufq_onPrimary")
    m.bufqSecondary.observeField("buttonSelected", "Bufq_onSecondary")
    m.bq = BQ_new(Settings_bufferingQualityMode())
    m.bufqKept = invalid          ' the kept step-down estimate { attempt, kbps }
    m.bufqContent = ""            ' the title the controller's per-title state belongs to
    Bufq_resetPlayback()
    m.bufqTimer.control = "start"
end sub

' Per playback attempt (PlayerScreen.resetPlaybackState).
sub Bufq_resetPlayback()
    m.bufqAdoptSeq = 0
    m.bufqCause = "reload"        ' the next wait's cause until the mounted plan first plays
    m.bufqBytes = 0
    m.bufqMs = 0
    m.bufqLastSegmentAt = invalid
    m.bufqOutage = false
    m.bufqOther = false
    m.bufqFocused = false
    m.bufqDebugAt = invalid       ' debugBufq: when the faked play-then-stall began
    m.bufqDebugStage = 0
end sub

function Bufq_now() as integer
    return m.bufqClock.TotalMilliseconds()
end function

' The server keeps learned limits and takes the new request fields.
function Bufq_serverSupports() as boolean
    c = m.global.playbackCaps
    if c <> invalid and Type(c) = "roAssociativeArray" then
        for each f in Arr_or(c.features)
            if f = "buffering_quality_v1" then return true
        end for
    end if
    return m.bufqDecisionFeature = true
end function

' Remembers a decision's server_features (a server can advertise the feature there too).
sub Bufq_noteDecision(decision as object)
    for each f in Arr_or(decision.server_features)
        if f = "buffering_quality_v1" then m.bufqDecisionFeature = true
    end for
end sub

' ---------- Plans ----------

' A plan was mounted: a new adoption, unless it is a client-side remount of the same plan (which
' only reloads the source). kind: "start", "remount", "track" (a stored subtitle adopted), or the
' replan kind that brought it ("quality" = the viewer's pick, "bq" = the controller's own).
sub Bufq_onPlanMounted(plan as object, kind as string)
    remount = kind = "remount"
    now = Bufq_now()
    m.bufqCause = "reload"
    m.bufqBytes = 0
    m.bufqMs = 0
    m.bufqLastSegmentAt = now
    if m.bufqOutage then
        m.bufqOutage = false
        BQ_onTransportErrorEnd(m.bq, now)
    end if
    BQ_setThroughput(m.bq, 0)
    if remount then return
    if m.bufqContent <> m.itemId then
        ' Different content: the answer, the once-per-title notice and the re-offer wait go too.
        m.bufqContent = m.itemId
        BQ_reset(m.bq, now)
    end if
    BQ_setMode(m.bq, Settings_bufferingQualityMode())
    m.bufqAdoptSeq = m.bufqAdoptSeq + 1
    if kind = "quality" then BQ_onViewerQualityChange(m.bq, now)
    bqPlan = BQ_planFrom(plan, m.qualityPref, m.attemptId + ":" + m.bufqAdoptSeq.ToStr())
    BQ_onPlanAdopted(m.bq, bqPlan, kind = "bq", now)
    ' Simulator aid (deep link debugBufq=1): the simulator's Video node never plays, so the first
    ' plan of the playback is faked to play and then stall (Bufq_debugStep).
    p = m.top.params
    if p <> invalid and p.debugBufq = true and m.bufqAdoptSeq = 1 then
        m.bufqDebugAt = now
        m.bufqDebugStage = 0
    end if
    Bufq_drain()
end sub

' The replan the controller sent, or the viewer's pick, did not take effect.
sub Bufq_onReplanFailed(kind as string)
    now = Bufq_now()
    if kind = "bq" then BQ_onReplanFailed(m.bq, now)
    if kind = "quality" then BQ_onQualityPickRefused(m.bq, now)
    Bufq_drain()
end sub

sub Bufq_onQualityPickSent()
    BQ_onQualityPickSent(m.bq, Bufq_now())
    Bufq_drain()
end sub

sub Bufq_onStopped()
    BQ_onPlaybackStopped(m.bq, Bufq_now())
    Bufq_drain()
end sub

' ---------- Video events ----------

sub Bufq_onVideoState(st as string)
    now = Bufq_now()
    if st = "buffering" then
        BQ_onWaiting(m.bq, m.bufqCause, now)
    else if st = "playing" then
        m.bufqCause = ""
        BQ_onPlaying(m.bq, now)
    else if st = "paused" then
        BQ_onPause(m.bq, now)
    else if st = "finished" or st = "error" then
        BQ_onPlaybackStopped(m.bq, now)
    end if
    Bufq_drain()
end sub

sub Bufq_onSeek()
    m.bufqCause = "seek"
    BQ_onSeek(m.bq, Bufq_now())
    Bufq_drain()
end sub

' downloadedSegment: { SegSize (bytes), DownloadDuration (ms), ... } on HLS. Read loosely.
sub Bufq_onSegment(seg as object)
    now = Bufq_now()
    m.bufqLastSegmentAt = now
    if m.bufqOutage then
        m.bufqOutage = false
        BQ_onTransportErrorEnd(m.bq, now)
    end if
    size = Num_or(seg.SegSize, 0)
    if size <= 0 then size = Num_or(seg.segSize, 0)
    ms = Num_or(seg.DownloadDuration, 0)
    if ms <= 0 then ms = Num_or(seg.downloadDuration, 0)
    if size > 0 and ms > 0 then
        m.bufqBytes = m.bufqBytes + size
        m.bufqMs = m.bufqMs + ms
        BQ_setThroughput(m.bq, Int(m.bufqBytes * 8 / m.bufqMs))
    end if
    Bufq_drain()
end sub

' Every 250 ms: due controller timers, the outage rule, higher-priority pills, the countdown.
sub Bufq_onTick()
    if m.closing then return
    now = Bufq_now()
    if not m.bufqOutage and m.plan <> invalid and m.video.state = "buffering" and m.bufqLastSegmentAt <> invalid then
        isHls = LCase(Str_orEmpty(m.plan.stream.protocol)) = "hls"
        if isHls and now - m.bufqLastSegmentAt >= 15000 then
            m.bufqOutage = true
            BQ_onTransportErrorStart(m.bq, now)
        end if
    end if
    other = (m.skipGroup.visible and m.skipBtn.visible) or m.upNext.visible
    if other <> m.bufqOther then
        m.bufqOther = other
        BQ_setOtherPillVisible(m.bq, other, now)
    end if
    Bufq_debugStep(now)
    BQ_advance(m.bq, now)
    Bufq_drain()
end sub

' debugBufq: plays 0.5 s after the mount, with throughput below the plan's bitrate, then waits on
' the network 1 s later; the stall turns long once the start-up grace is over (about 16 s in).
sub Bufq_debugStep(now as integer)
    if m.bufqDebugAt = invalid then return
    if m.bufqDebugStage = 0 and now - m.bufqDebugAt >= 500 then
        m.bufqDebugStage = 1
        print "[siku-playback] debugBufq: faking playing, then a network wait"
        BQ_setThroughput(m.bq, 3000) ' below the plan's bitrate, as on a slow link
        BQ_onPlaying(m.bq, now)
    else if m.bufqDebugStage = 1 and now - m.bufqDebugAt >= 1500 then
        m.bufqDebugStage = 2
        m.bufqDebugAt = invalid
        BQ_onWaiting(m.bq, "", now)
    end if
end sub

' ---------- Outputs ----------

sub Bufq_drain()
    out = m.bq.out
    m.bq.out = []
    for each o in out
        if o.type = "replan" then
            Bufq_sendReplan(o)
        else if o.type = "notice" then
            if o.key = "lowered" then m.global.toast = "Quality lowered to stop buffering"
            if o.key = "cant_lower" then m.global.toast = "Can't lower quality for this video"
        else if o.type = "summary" then
            s = o.summary
            print "[siku-playback] buffering plan=" + Str_orEmpty(s.planId) + " played_ms=" + Str_orEmpty(s.playedMs) + " stalls=" + Str_orEmpty(s.stallCount) + " stall_ms=" + Str_orEmpty(s.stallTotalMs) + " longest_ms=" + Str_orEmpty(s.stallLongestMs) + " delivered_kbps=" + Str_orEmpty(s.deliveredKbps) + " mode=" + s.mode + " action=" + s.action
        end if
    end for
    Bufq_renderPill()
end sub

' The controller's replan: a quality_change carrying its fields.
sub Bufq_sendReplan(o as object)
    if m.plan = invalid or m.sessionId = "" then
        BQ_onReplanFailed(m.bq, Bufq_now())
        return
    end if
    extra = {}
    if o.estimateKbps > 0 then extra.bandwidth_estimate_kbps = o.estimateKbps
    if o.estimateSource <> "" then extra.bandwidth_estimate_source = o.estimateSource
    if o.estimateSource = "observed_rebuffer" and m.bq.throughputKbps > 0 then extra.observed_throughput_kbps = m.bq.throughputKbps
    if o.learnedLimit <> "" then extra.learned_limit = o.learnedLimit
    print "[siku-playback] buffering replan quality=" + o.quality + " est=" + Str_orEmpty(o.estimateKbps) + " source=" + o.estimateSource + " learned_limit=" + o.learnedLimit + " observed=" + Str_orEmpty(m.bq.throughputKbps)
    m.prevQualityPref = m.qualityPref
    m.qualityPref = o.quality
    sendReplan("quality_change", "bq", invalid, invalid, extra, o)
end sub

' Adds the buffering-quality fields to a start or replan body right before it is sent: the kept
' step-down estimate rule on replans, learned_limit "ignore" in Never mode, then the gate.
' lowering: the controller's replan output, or invalid for any other request.
sub Bufq_decorateBody(body as object, lowering as dynamic)
    if body.operation <> invalid then
        sent = BQ_withKeptEstimate(body, m.bufqKept, lowering)
        m.bufqKept = sent.kept
    else
        ' A start carries a current speed-test reading of this Roku's connection (Settings → Test
        ' speed, or the server's stored probe), so Auto can rule out a source the link clearly can't
        ' carry. Only starts: a probe is a hint, and replans never raise quality from it.
        reading = Bufq_probeReading()
        if reading <> invalid and body.bandwidth_estimate_kbps = invalid then
            body.bandwidth_estimate_kbps = reading.kbps
            body.bandwidth_estimate_source = "probe"
        end if
    end if
    if Settings_bufferingQualityMode() = "never" and body.learned_limit = invalid then body.learned_limit = "ignore"
    if Bufq_serverSupports() then
        features = Arr_or(body.client_features)
        has = false
        for each f in features
            if f = "buffering_quality_v1" then has = true
        end for
        if not has then features.Push("buffering_quality_v1")
        body.client_features = features
        if body.bandwidth_estimate_kbps = invalid then body.Delete("bandwidth_estimate_source")
        if Str_orEmpty(body.bandwidth_estimate_source) <> "observed_rebuffer" then body.Delete("observed_throughput_kbps")
    else
        body.Delete("bandwidth_estimate_source")
        body.Delete("observed_throughput_kbps")
        body.Delete("learned_limit")
    end if
end sub

' The connection speed reading Settings stored on m.global.bandwidthProbe, while it is current for
' this server ({ kbps, at, serverUrl, maxAge }), else invalid.
function Bufq_probeReading() as dynamic
    if not m.global.hasField("bandwidthProbe") then return invalid
    r = m.global.bandwidthProbe
    if r = invalid or Type(r) <> "roAssociativeArray" or r.kbps = invalid then return invalid
    if Str_orEmpty(r.serverUrl) <> Str_orEmpty(m.global.session.serverUrl) then return invalid
    age = CreateObject("roDateTime").AsSeconds() - Int(Num_or(r.at, 0))
    if age < 0 or age > Int(Num_or(r.maxAge, 604800)) then return invalid
    return r
end function

' ---------- Pill ----------

sub Bufq_renderPill()
    kind = m.bq.pill
    blocked = m.hud.visible or m.picker.visible or m.subsDialog.visible or m.upNext.visible or m.errorGroup.visible
    show = kind <> "" and not blocked
    wasFocused = m.bufqFocused and (m.bufqPrimary.hasFocus() or m.bufqSecondary.hasFocus())
    if not show then
        if m.bufqPill.visible then
            m.bufqPill.visible = false
            m.bufqFocused = false
            if wasFocused then restoreFocus()
        end if
        return
    end if
    secs = BQ_pillSecondsLeft(m.bq, Bufq_now())
    if kind = "prompt" then
        m.bufqTitle.text = "Playback keeps buffering"
        m.bufqPrimary.text = "Lower quality"
        m.bufqSecondary.text = "Keep quality"
        m.bufqSecondary.visible = true
    else
        m.bufqTitle.text = "Quality lowered to stop buffering"
        m.bufqPrimary.text = "Restore quality"
        m.bufqSecondary.visible = false
    end if
    m.bufqCount.text = secs.ToStr()
    m.bufqFill.width = Int(Bufq_cardWidth() * secs / 15)
    newlyShown = not m.bufqPill.visible or m.bufqKind <> kind
    m.bufqKind = kind
    Bufq_layout()
    m.bufqPill.visible = true
    ' The pill takes focus when it appears, unless the viewer is mid-scrub.
    if newlyShown and not m.scrubbing then
        m.bufqFocused = true
        m.bufqPrimary.setFocus(true)
    end if
end sub

function Bufq_cardWidth() as integer
    return 760
end function

sub Bufq_layout()
    w = Bufq_cardWidth()
    m.bufqBg.width = w
    x = 1920 - 64 - w
    bottom = 112
    if m.controls.visible then bottom = 400
    m.bufqPill.translation = [x, 1080 - bottom - 176]
    m.bufqCount.translation = [w - 32 - 80, 24]
    m.bufqSecondary.translation = [32 + m.bufqPrimary.width + 16, 84]
end sub

' Keys while the pill has focus: Left/Right stay inside it, Back answers it (Keep on the prompt,
' hide on the undo), Up hands focus to the player controls, OK reaches the focused button; any
' other key goes on to the player as usual.
function Bufq_handleKey(key as string) as boolean
    if not m.bufqPill.visible or not m.bufqFocused then return false
    if not m.bufqPrimary.hasFocus() and not m.bufqSecondary.hasFocus() then return false
    if key = "left" then
        m.bufqPrimary.setFocus(true)
    else if key = "right" then
        if m.bufqSecondary.visible then m.bufqSecondary.setFocus(true)
    else if key = "back" then
        BQ_back(m.bq, Bufq_now())
        Bufq_drain()
    else if key = "up" then
        m.bufqFocused = false
        if m.plan <> invalid then showControls()
    else
        ' Play/pause, Options, Down (the HUD) and the skip keys work as usual; the pill stays up
        ' and is not drawn while the HUD is open.
        m.bufqFocused = false
        return false
    end if
    return true
end function

sub Bufq_onPrimary()
    now = Bufq_now()
    if m.bq.pill = "prompt" then
        BQ_selectLower(m.bq, now)
    else if m.bq.pill = "undo" then
        BQ_selectRestore(m.bq, now)
    end if
    Bufq_drain()
end sub

sub Bufq_onSecondary()
    BQ_selectKeep(m.bq, Bufq_now())
    Bufq_drain()
end sub
