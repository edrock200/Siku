' Numbered playback errors and the optional route-event report (docs/playback-errors.md).
' Every failure the player shows carries a stable four-digit number ("#3001 ... (Roku -5)") that
' a viewer can read out in a support request. The numbering follows ManavA/silo-roku's scheme
' (1001-1005 inventory, 2001-2016 server preparation, 3001-3004 the Roku itself), and the report
' is adapted from its SiloPlaybackErrorBody (ManavA/silo-roku, AGPL-3.0).
' When the server lists playback_route_diagnostics, one POST /api/v2/playback/route-events is sent
' per terminal failure of a recorded attempt: 3 s timeout, no retry, no token refresh, and only
' allowlisted diagnostics (the number, a fixed reason name, the Roku error code, the device
' model). Never URLs, titles, tokens or raw error text.
' SPDX-License-Identifier: AGPL-3.0-or-later

' Plain-language text for each number (the server's own message is shown instead when it has one).
function PlaybackError_text(number as string) as string
    t = {
        "1001": "This title has no playable file."
        "1004": "Couldn't open this title."
        "2001": "Playback couldn't be prepared. Check the connection to your server and try again."
        "2002": "The server has no playable source for this title."
        "2003": "No other version of this title can play here."
        "2004": "The server can't prepare this HDR or Dolby Vision format."
        "2005": "The server can't prepare this audio format."
        "2006": "The server can't prepare these subtitles."
        "2007": "This server's playback protocol isn't supported. The server may need an update."
        "2008": "The server sent a stream format Roku can't play."
        "2009": "The server has video conversion turned off for this playback."
        "2010": "A conversion tool the server needs is unavailable."
        "2011": "The server needs more information about this file's format."
        "2012": "The server couldn't read this file."
        "2013": "The server can't meet the bitrate limit for this playback."
        "2014": "The server has no other way left to play this title."
        "2015": "No playback route was found for this Roku."
        "2016": "The server couldn't start converting this title."
        "3001": "This Roku couldn't play the stream. Try another version or a lower quality."
        "3002": "Playback didn't start or stopped moving for too long. Check the connection and try a lower quality."
        "3003": "Siku tried every other way to play this title and none worked."
        "3004": "The playback session changed on the server. Start playback again."
    }
    if t.DoesExist(number) then return t[number]
    return "Something went wrong."
end function

' The number for a terminal decision or a failed start: the server's terminal reason first, then
' the problem code of the response (silo-roku SiloUIPlaybackFailureCode).
function PlaybackError_serverNumber(reason as string, code as string) as string
    if reason = "no_playable_source" then return "2002"
    if reason = "no_alternate_version" then return "2003"
    if reason = "hdr_transcode_unsupported" or reason = "dv_conversion_unsupported" then return "2004"
    if reason = "audio_conversion_unsupported" then return "2005"
    if reason = "transcode_start_failed" then return "2016"
    if reason = "subtitle_conversion_unsupported" or reason = "subtitle_codec_unsupported" or reason = "subtitle_burn_in_source_unsupported" then return "2006"
    if code = "unsupported_device" then return "2015"
    if code = "unsupported_protocol" or code = "unsupported_playback_protocol" then return "2007"
    if code = "unsupported_stream" or reason = "client_hls_unsupported" then return "2008"
    if reason = "transcoding_disabled" then return "2009"
    if reason = "conversion_tool_unavailable" then return "2010"
    if reason = "source_metadata_incomplete" then return "2011"
    if reason = "source_unreadable" then return "2012"
    if reason = "bitrate_policy_unavailable" then return "2013"
    if reason = "adaptation_exhausted" then return "2014"
    return "2001"
end function

' A plan the client must refuse (PlaybackCaps_planProblem): the contract (2007) or the stream (2008).
function PlaybackError_planProblemNumber(decision as dynamic) as string
    if decision = invalid then return "2007"
    if Int(Num_or(decision.protocol_version, 0)) <> 3 then return "2007"
    hasPlan = false
    hasNeutral = false
    for each f in Arr_or(decision.server_features)
        if f = "playback_plan_v3" then hasPlan = true
        if f = "neutral_playback_v3_contract_v1" then hasNeutral = true
    end for
    if not hasPlan or not hasNeutral then return "2007"
    return "2008"
end function

' Reason names that may leave the device: Siku's own failure classifications and the server's
' terminal reasons. Anything else is reported without a reason.
function PlaybackError_reasonName(reason as dynamic) as string
    value = LCase(Str_orEmpty(reason))
    allowed = ["decoder_failure", "network_error", "drm_failure", "buffering_timeout", "recovery_exhausted", "replan_failed",
               "no_playable_source", "no_alternate_version", "hdr_transcode_unsupported", "subtitle_conversion_unsupported",
               "client_hls_unsupported", "adaptation_unavailable", "adaptation_exhausted", "audio_conversion_unsupported",
               "dv_conversion_unsupported", "transcode_start_failed", "transcoding_disabled", "conversion_tool_unavailable",
               "source_metadata_incomplete", "source_unreadable", "bitrate_policy_unavailable", "subtitle_codec_unsupported",
               "subtitle_burn_in_source_unsupported", "unsupported_container", "subtitle_hls_rendition_failed"]
    for each a in allowed
        if a = value then return value
    end for
    return ""
end function

' The Roku Video node's error code as an integer, or invalid when there is none.
function PlaybackError_rokuCode(code as dynamic) as dynamic
    if code = invalid then return invalid
    t = Type(code)
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "LongInteger" or t = "roLongInteger" then
        if code = 0 then return invalid
        return code
    end if
    if t = "roString" or t = "String" then
        s = code.Trim()
        if s = "" or s = "0" then return invalid
        if not CreateObject("roRegex", "^-?[0-9]{1,6}$", "").IsMatch(s) then return invalid
        return Int(Val(s))
    end if
    return invalid
end function

' Shows a numbered error and, for a recorded attempt, reports it once.
' opts: { detail: text to show instead of the number's own, reason: classification or terminal
' reason, rokuCode: the Video node's errorCode, decision: the start decision (terminal),
' noReport: true to skip the report }.
sub PlaybackError_show(number as string, opts = invalid as dynamic)
    if opts = invalid then opts = {}
    detail = Str_orEmpty(opts.detail)
    if detail = "" then detail = PlaybackError_text(number)
    roku = PlaybackError_rokuCode(opts.rokuCode)
    text = "#" + number + "  " + detail
    if roku <> invalid then text = text + " (Roku " + roku.ToStr() + ")"
    reason = PlaybackError_reasonName(opts.reason)
    if m.errTicket = invalid then m.errTicket = 0
    m.errTicket = m.errTicket + 1
    m.errorReport.text = ""
    showError(text)
    ' The console line: number, reason, Roku code and where playback stood (no URLs, no titles).
    delivery = ""
    if m.plan <> invalid then delivery = Str_orEmpty(m.plan.delivery)
    rokuText = "-"
    if roku <> invalid then rokuText = roku.ToStr()
    keys = 0
    attempts = 0
    if m.rec <> invalid then
        keys = m.rec.keys.Count()
        attempts = m.rec.count
    end if
    sending = PlaybackError_reportable(number, opts)
    print "[siku-playback] error #" + number + " reason=" + reason + " roku=" + rokuText + " delivery=" + delivery + " recoveries=" + attempts.ToStr() + " plan_keys=" + keys.ToStr() + " report=" + PlaybackCaps_str(sending)
    if sending then PlaybackError_report(number, reason, roku, opts.decision)
end sub

' Inventory errors (1xxx) and failed requests have no recorded attempt on the server, so only a
' terminal decision or a failure inside a session is reported, and only to a server that takes it.
function PlaybackError_reportable(number as string, opts as object) as boolean
    if PlaybackCaps_truthy(opts.noReport) then return false
    if Left(number, 1) = "1" or number = "3004" then return false
    c = cachedCaps()
    if c = invalid then return false
    advertised = false
    for each f in Arr_or(c.features)
        if f = "playback_route_diagnostics" then advertised = true
    end for
    if not advertised then return false
    if m.sessionId <> "" then return true
    return opts.decision <> invalid
end function

' The route event: `plan_failed` inside a session, `terminal` for a start the server refused.
sub PlaybackError_report(number as string, reason as string, roku as dynamic, decision as dynamic)
    inst = installationId()
    if inst = "" or Len(Str_orEmpty(m.attemptId)) < 8 then return
    diagnostics = { "error_code": number }
    if reason <> "" then diagnostics["reason"] = reason
    if roku <> invalid then diagnostics["error_code_name"] = "roku_native_" + roku.ToStr()
    model = Str_orEmpty(m.di.GetModel())
    if CreateObject("roRegex", "^[A-Za-z0-9_-]{1,16}$", "").IsMatch(model) then diagnostics["device_model"] = model
    eventId = LCase(m.di.GetRandomUUID())
    body = { "installation_id": inst, "event_id": eventId, "protocol_version": 3, "playback_attempt_id": m.attemptId, "event": "terminal", "diagnostics": diagnostics }
    if m.sessionId <> "" then
        body["event"] = "plan_failed"
        body["session_id"] = m.sessionId
        if m.plan <> invalid then
            if not Str_isEmpty(m.plan.plan_id) then body["plan_id"] = Str_orEmpty(m.plan.plan_id)
            if not Str_isEmpty(m.plan.plan_attempt_key) then body["plan_attempt_key"] = Str_orEmpty(m.plan.plan_attempt_key)
        end if
    else if decision <> invalid and not Str_isEmpty(decision.session_id) then
        ' A terminal start that still names a session.
        body["session_id"] = Str_orEmpty(decision.session_id)
    end if
    if reason <> "" then body["failure_classification"] = reason
    m.errReport = { ticket: m.errTicket, eventId: eventId, number: number }
    Api_call({ method: "POST", path: "/api/v2/playback/route-events", body: body, timeout: 3, noRefresh: true }, "PlaybackError_onReported")
end sub

' Only a matching accepted receipt says the report arrived; anything else leaves the number alone.
sub PlaybackError_onReported(event as object)
    resp = Api_result(event)
    sent = m.errReport
    m.errReport = invalid
    if sent = invalid then return
    accepted = resp.status >= 200 and resp.status < 300 and Type(resp.data) = "roAssociativeArray"
    if accepted then accepted = Str_orEmpty(resp.data.outcome) = "accepted" and Str_orEmpty(resp.data.event_id) = sent.eventId
    print "[siku-playback] error report #" + sent.number + " status=" + Str_orEmpty(resp.status) + " accepted=" + PlaybackCaps_str(accepted)
    if not accepted or m.closing then return
    ' The dialog may have been dismissed or replaced by another error meanwhile.
    if sent.ticket <> m.errTicket or not m.errorGroup.visible then return
    m.errorReport.text = "Report sent to your server."
end sub
