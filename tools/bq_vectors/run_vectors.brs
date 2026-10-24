' SPDX-License-Identifier: AGPL-3.0-or-later
' Replays the buffering-quality conformance vectors (silo-server
' docs/design/schemas/buffering-quality/v1/vectors.json, vendored by Silo Android as
' shared/src/commonTest/resources/playback/buffering-quality/v1/vectors.json) against
' components/player/BufferingQuality.brs, the way Silo Android's BufferingQualityVectorsTest does.
' Run it with tools/bq_vectors.py, which copies vectors.json next to it as pkg:/vectors.json.

sub Main()
    d = ParseJson(ReadAsciiFile("pkg:/vectors.json"))
    if d = invalid then
        print "BQ-VECTORS: cannot read pkg:/vectors.json"
        return
    end if
    defaultMode = d.defaults.mode
    failed = 0
    total = 0
    for each cs in d.cases
        total = total + 1
        problem = BQV_runCase(cs, defaultMode)
        if problem <> "" then
            failed = failed + 1
            print "BQ-VECTORS FAIL " + cs.name + ": " + problem
        end if
    end for
    print "BQ-VECTORS RESULT " + (total - failed).ToStr() + " of " + total.ToStr() + " cases passed"
end sub

function BQV_runCase(cs as object, defaultMode as string) as string
    mode = defaultMode
    if cs.mode <> invalid then mode = cs.mode
    bq = BQ_new(mode)
    BQ_setThroughput(bq, 1) ' the vectors carry no throughput: every plan's media arrive below its bitrate
    ctx = { outputs: [], summaries: [], attempt: 1, kept: invalid, adoptedQuality: "auto" }
    for each ev in cs.events
        BQ_advance(bq, ev.t)
        BQV_drain(bq, ctx)
        BQV_apply(bq, ctx, ev)
        BQV_drain(bq, ctx)
    end for
    BQ_advance(bq, cs.until)
    BQV_drain(bq, ctx)
    want = BQV_canon(cs.expect)
    got = BQV_canon(ctx.outputs)
    if want <> got then return "outputs" + Chr(10) + "  expected: " + want + Chr(10) + "  actual:   " + got
    if cs.buffering_action <> invalid then
        BQ_onPlaybackStopped(bq, cs.until)
        BQV_drain(bq, ctx)
        for each planId in cs.buffering_action
            action = ""
            for each sm in ctx.summaries
                if sm.adoptionId = planId then action = sm.action
            end for
            if action <> cs.buffering_action[planId] then return "buffering_action for " + planId + ": expected " + cs.buffering_action[planId] + ", got '" + action + "'"
        end for
    end if
    return ""
end function

sub BQV_apply(bq as object, ctx as object, ev as object)
    t = ev.t
    kind = ev.type
    if kind = "plan_adopted" then
        p = ev.plan
        rungs = []
        for each q in BQV_arr(p.available_qualities)
            kbps = 0
            if q.bitrate_kbps <> invalid then kbps = q.bitrate_kbps
            rungs.Push({ label: q.label, kbps: kbps })
        end for
        noReduction = false
        for each w in BQV_arr(p.degradation_warnings)
            if w = "quality_reduction_unavailable" then noReduction = true
        end for
        delivered = 0
        if p.delivered_kbps <> invalid then delivered = p.delivered_kbps
        plan = { planId: p.plan_id, serverPlanId: p.plan_id, deliveredKbps: delivered, quality: p.quality, rungs: rungs, noReduction: noReduction, activeQuality: p.active_quality }
        ctx.adoptedQuality = p.quality
        initiated = true
        if ev.controllerInitiated <> invalid then initiated = ev.controllerInitiated
        BQ_onPlanAdopted(bq, plan, initiated, t)
    else if kind = "client_replan" then
        BQV_sendClient(ctx, ev.operation, t, true)
    else if kind = "quality_changed" then
        BQ_onViewerQualityChange(bq, t)
        BQV_sendClient(ctx, "quality_change", t, false)
    else if kind = "new_attempt" then
        BQ_onPlaybackStopped(bq, t)
        ctx.attempt = ctx.attempt + 1
    else if kind = "pick_sent" then
        BQ_onQualityPickSent(bq, t)
    else if kind = "pick_refused" then
        BQ_onQualityPickRefused(bq, t)
    else if kind = "playing" then
        BQ_onPlaying(bq, t)
    else if kind = "waiting" then
        cause = ""
        if ev.cause <> invalid then cause = ev.cause
        BQ_onWaiting(bq, cause, t)
    else if kind = "pause" then
        BQ_onPause(bq, t)
    else if kind = "seek" then
        BQ_onSeek(bq, t)
    else if kind = "transport_error_start" then
        BQ_onTransportErrorStart(bq, t)
    else if kind = "transport_error_end" then
        BQ_onTransportErrorEnd(bq, t)
    else if kind = "replan_failed" then
        BQ_onReplanFailed(bq, t)
    else if kind = "select_lower" then
        BQ_selectLower(bq, t)
    else if kind = "select_keep" then
        BQ_selectKeep(bq, t)
    else if kind = "select_restore" then
        BQ_selectRestore(bq, t)
    else if kind = "back" then
        BQ_back(bq, t)
    else if kind = "pill_obscured" then
        BQ_setOtherPillVisible(bq, true, t)
    else if kind = "pill_unobscured" then
        BQ_setOtherPillVisible(bq, false, t)
    else
        print "BQ-VECTORS unknown event " + kind
    end if
end sub

' The controller's outputs as vector outputs; its replans go through the kept-estimate rule.
sub BQV_drain(bq as object, ctx as object)
    for each o in bq.out
        if o.type = "replan" then
            body = { playback_attempt_id: "attempt-" + ctx.attempt.ToStr(), operation: "quality_change", quality_preference: o.quality }
            if o.estimateKbps > 0 then body.bandwidth_estimate_kbps = o.estimateKbps
            if o.estimateSource <> "" then body.bandwidth_estimate_source = o.estimateSource
            if o.learnedLimit <> "" then body.learned_limit = o.learnedLimit
            sent = BQ_withKeptEstimate(body, ctx.kept, o)
            ctx.kept = sent.kept
            ctx.outputs.Push({ t: o.t, type: "replan", body: BQV_wireBody(sent.body) })
        else if o.type = "notice" then
            ctx.outputs.Push({ t: o.t, type: "notice", key: o.key })
        else if o.type = "summary" then
            ctx.summaries.Push(o.summary)
        else
            ctx.outputs.Push({ t: o.t, type: o.type })
        end if
    end for
    bq.out = []
end sub

sub BQV_sendClient(ctx as object, operation as string, t as integer, record as boolean)
    body = { playback_attempt_id: "attempt-" + ctx.attempt.ToStr(), operation: operation, quality_preference: ctx.adoptedQuality }
    sent = BQ_withKeptEstimate(body, ctx.kept, invalid)
    ctx.kept = sent.kept
    if record then ctx.outputs.Push({ t: t, type: "replan", body: BQV_wireBody(sent.body) })
end sub

function BQV_wireBody(body as object) as object
    out = {}
    for each k in ["operation", "quality_preference", "bandwidth_estimate_kbps", "bandwidth_estimate_source", "learned_limit"]
        if body.DoesExist(k) and body[k] <> invalid then out[k] = body[k]
    end for
    return out
end function

function BQV_arr(v as dynamic) as object
    if v = invalid or Type(v) <> "roArray" then return []
    return v
end function

' A canonical string for comparing JSON values: object keys sorted, numbers as integers.
function BQV_canon(v as dynamic) as string
    t = Type(v)
    if v = invalid then return "null"
    if t = "roArray" then
        parts = []
        for each x in v
            parts.Push(BQV_canon(x))
        end for
        return "[" + BQV_join(parts) + "]"
    end if
    if t = "roAssociativeArray" then
        keys = []
        for each k in v
            keys.Push(LCase(k))
        end for
        keys.Sort()
        parts = []
        for each k in keys
            parts.Push(k + ":" + BQV_canon(v[k]))
        end for
        return "{" + BQV_join(parts) + "}"
    end if
    if t = "roString" or t = "String" then return Chr(34) + v + Chr(34)
    if t = "roBoolean" or t = "Boolean" then
        if v then return "true"
        return "false"
    end if
    if t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return Int(v).ToStr()
    return v.ToStr()
end function

function BQV_join(parts as object) as string
    out = ""
    for i = 0 to parts.Count() - 1
        if i > 0 then out = out + ","
        out = out + parts[i]
    end for
    return out
end function
