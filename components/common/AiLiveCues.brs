' SPDX-License-Identifier: AGPL-3.0-or-later
' Live AI subtitle cues: the lines a Silo server streams to the requesting playback session while
' an AI translation (or transcription) runs, before the finished track is stored. Silo's web player
' shows them as they arrive; Silo's Android TV app ignores them and waits for the whole file, so
' this is a deliberate step past the app Siku ports (the user's request, 2026-11-07).
'
' The server (internal/subtitles/ai/service.go, internal/playback/realtime.go) sends them over the
' session's playback control socket (silo.playback-control.v2) as events:
'   subtitle_translation_started   { session_id, file_id, job_id, track_key, language, label, total_cues }
'   subtitle_translation_cues      { ..., track_key, cues: [{ start, end, text }], done, total }
'   subtitle_translation_completed { ..., track_key, subtitle_id, language, label, track }
'   subtitle_translation_failed    { ..., track_key, message }
' Cue times are source (file) seconds. Batches come playhead-first, then wrap to the start, so a
' batch can land anywhere in the file. Delivery is best effort and a reconnect replays nothing:
' the job poll stays the authority.
'
' Pure helpers here (host-tested in tests/test_ai_live.py); the socket is AiLiveTask, the overlay
' and the flow are components/player/AiLive.brs.

function AiLive_protocol() as string
    return "silo.playback-control.v2"
end function

' At most this many cues are kept (a feature film has 1,500 to 2,000) and this many characters a cue.
function AiLive_maxCues() as integer
    return 4000
end function

function AiLive_maxCueChars() as integer
    return 300
end function

' Whether the server serves the control socket this client speaks: GET
' /api/v2/playback/sessions/control/capabilities → { available, protocol }.
function AiLive_capsUsable(caps as dynamic) as boolean
    if Type(caps) <> "roAssociativeArray" then return false
    a = caps.available
    if Type(a) <> "roBoolean" and Type(a) <> "Boolean" then return false
    if not a then return false
    return Str_orEmpty(caps.protocol) = AiLive_protocol()
end function

' The control socket's URL for a server URL (session.serverUrl, which may carry a path prefix).
' https → wss, http → ws; "" for anything else.
function AiLive_socketUrl(serverUrl as dynamic, sessionId as string) as string
    base = Str_orEmpty(serverUrl)
    while Right(base, 1) = "/"
        base = Left(base, Len(base) - 1)
    end while
    if LCase(Left(base, 8)) = "https://" then
        base = "wss://" + Mid(base, 9)
    else if LCase(Left(base, 7)) = "http://" then
        base = "ws://" + Mid(base, 8)
    else
        return ""
    end if
    if sessionId = "" then return ""
    return base + "/api/v2/playback/sessions/" + Str_urlEncode(sessionId) + "/control/ws"
end function

' The subprotocol list roWebSocket.SetProtocols takes: the protocol, then the ticket.
function AiLive_protocols(ticket as string) as string
    return AiLive_protocol() + ", silo.ticket." + ticket
end function

' The hello frame: no commands are advertised, so the server's deadline fallbacks for remote
' commands (stop, pause, …) behave as they do without a socket. Quoted keys (pitfall 15).
function AiLive_hello(sessionId as string, version as string) as string
    if version = "" then version = "0"
    return FormatJson({ "type": "hello", "session_id": sessionId, "client": { "name": "Siku", "version": version }, "capabilities": { "commands": [] } })
end function

' A text frame as { name, payload } when it is a live AI subtitle event for this session and file,
' else invalid (commands, other events, other sessions, malformed JSON).
function AiLive_frameEvent(text as dynamic, sessionId as string, fileId as string) as dynamic
    if Type(text) <> "roString" and Type(text) <> "String" then return invalid
    if Instr(1, text, "subtitle_translation_") = 0 then return invalid
    ' job_id, file_id and subtitle_id are JSON numbers (Go int64) while the job projection's id is a
    ' decimal string that may pass 2^53: quote them before parsing so no digit is lost.
    text = AiLive_quoteIds(text)
    msg = ParseJson(text)
    if Type(msg) <> "roAssociativeArray" then return invalid
    if Str_orEmpty(msg["type"]) <> "event" then return invalid
    name = Str_orEmpty(msg["name"])
    if name <> "subtitle_translation_started" and name <> "subtitle_translation_cues" and name <> "subtitle_translation_completed" and name <> "subtitle_translation_failed" then return invalid
    payload = msg["payload"]
    if Type(payload) <> "roAssociativeArray" then return invalid
    sid = Str_orEmpty(payload.session_id)
    if sid = "" then sid = Str_orEmpty(msg["session_id"])
    if sid <> sessionId then return invalid
    if fileId <> "" and Str_orEmpty(payload.file_id) <> fileId then return invalid
    return { name: name, payload: payload }
end function

' text with the numbers after "job_id", "file_id" and "subtitle_id" quoted ("job_id":7 → "job_id":"7").
' A plain scan: brs-engine's roRegex has no backreferences. Escaped quotes inside cue text never
' match (the key's closing quote would be preceded by a backslash).
function AiLive_quoteIds(text as string) as string
    q = Chr(34)
    for each key in ["job_id", "file_id", "subtitle_id"]
        needle = q + key + q
        at = Instr(1, text, needle)
        while at > 0
            i = at + Len(needle)
            n = Len(text)
            while i <= n and (Mid(text, i, 1) = " " or Mid(text, i, 1) = ":")
                i = i + 1
            end while
            j = i
            while j <= n and Instr(1, "-0123456789", Mid(text, j, 1)) > 0
                j = j + 1
            end while
            if j > i then
                text = Left(text, i - 1) + q + Mid(text, i, j - i) + q + Mid(text, j)
                j = j + 2
            end if
            at = Instr(j, text, needle)
        end while
    end for
    return text
end function

' Whether an event belongs to the job (and live track) the player follows. jobId "" matches
' nothing; trackKey "" accepts any track of that job (the started event names it).
function AiLive_matches(payload as dynamic, jobId as string, trackKey as string) as boolean
    if Type(payload) <> "roAssociativeArray" or jobId = "" then return false
    if Str_orEmpty(payload.job_id) <> jobId then return false
    if trackKey <> "" and Str_orEmpty(payload.track_key) <> "" and Str_orEmpty(payload.track_key) <> trackKey then return false
    return true
end function

' Adds a batch of server cues to cues (sorted by start; changed in place and returned). seen
' ({ key: true }) drops a cue sent twice. Cues with no text, bad times or past the cap are skipped.
function AiLive_mergeCues(cues as object, seen as object, batch as dynamic, maxCues as integer) as object
    if Type(batch) <> "roArray" then return cues
    added = 0
    for each c in batch
        if cues.Count() >= maxCues then exit for
        if Type(c) = "roAssociativeArray" then
            text = Str_orEmpty(c.text)
            st = Num_or(c.start, -1)
            en = Num_or(c["end"], -1)
            if text <> "" and st >= 0 and en > st then
                if Len(text) > AiLive_maxCueChars() then text = Left(text, AiLive_maxCueChars())
                key = Str(st).Trim() + "|" + Str(en).Trim() + "|" + text
                if seen[key] = invalid then
                    seen[key] = true
                    cues.Push({ "start": st, "end": en, "text": text })
                    added = added + 1
                end if
            end if
        end if
    end for
    if added > 0 then cues.SortBy("start")
    return cues
end function

' The text on screen at source time t: every cue with start <= t < end, in start order, one per
' line. Binary search for the last cue starting at or before t, then a short look back for cues
' that started earlier and still run (overlapping dialogue).
function AiLive_textAt(cues as object, t as float) as string
    n = cues.Count()
    if n = 0 then return ""
    lo = 0
    hi = n - 1
    found = -1
    while lo <= hi
        half = Int((lo + hi) / 2)
        c = cues[half]
        if c.start <= t then
            found = half
            lo = half + 1
        else
            hi = half - 1
        end if
    end while
    if found < 0 then return ""
    lines = []
    first = found - 8
    if first < 0 then first = 0
    for i = first to found
        c = cues[i]
        if c.start <= t and t < c["end"] then lines.Push(c.text)
    end for
    return lines.Join(Chr(10))
end function

' Source time for a player position: the player runs timelineOffset behind the file, and a
' subtitle delay of d ms shows a cue d ms later (as Subs_buildTrack's timestamp_offset does).
function AiLive_sourceTime(playerSeconds as float, timelineOffset as float, delayMs as integer) as float
    return playerSeconds + timelineOffset - delayMs / 1000.0
end function
