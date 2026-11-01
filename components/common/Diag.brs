' Diagnostics log and last-exit report, pure parts (host-tested in tests/test_diag.py). DiagTask
' keeps the log on cachefs: and reads Roku's record of how the last launch ended; MainScene shows a
' notice after an unexpected close; Settings › Diagnostics shows and clears the log. The log never
' leaves the Roku. Exit codes and the redaction approach are adapted from Silo-Server/silo-roku,
' AGPL-3.0 (source/diagnostics/report.bs, source/diagnostics/scrub.bs).
' SPDX-License-Identifier: AGPL-3.0-or-later

' The longest line kept, in characters.
function Diag_maxLine() as integer
    return 400
end function

' A log line with what could identify the viewer, their server or their media taken out: URLs,
' e-mail addresses, IP addresses, UUIDs and long hex ids, token-like strings, and the values of
' id-like keys (file=, item=, video=, session=, user= ...). Capped at Diag_maxLine().
function Diag_scrub(line as dynamic) as string
    if Type(line) <> "String" and Type(line) <> "roString" then return ""
    s = line
    s = CreateObject("roRegex", "[a-z][a-z0-9+.\-]*://[^\s]*", "i").ReplaceAll(s, "<url>")
    s = CreateObject("roRegex", "[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", "").ReplaceAll(s, "<email>")
    s = CreateObject("roRegex", "\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?\b", "").ReplaceAll(s, "<ip>")
    s = CreateObject("roRegex", "\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", "i").ReplaceAll(s, "<id>")
    s = Diag_scrubKeys(s)
    s = CreateObject("roRegex", "\b[0-9a-f]{20,}\b", "i").ReplaceAll(s, "<id>")
    s = CreateObject("roRegex", "(?=[A-Za-z0-9_\-]*[A-Z])(?=[A-Za-z0-9_\-]*[0-9])" + "[A-Za-z0-9_\-]{20,}", "").ReplaceAll(s, "<token>")
    s = CreateObject("roRegex", "[\x00-\x1F]", "").ReplaceAll(s, " ")
    if Len(s) > Diag_maxLine() then s = Left(s, Diag_maxLine()) + "…"
    return s
end function

' The value of every id-like key=value word becomes <id>. Word by word, because brs-engine's
' roRegex.ReplaceAll does not support \1 back-references (Roku's does).
function Diag_scrubKeys(s as string) as string
    if Instr(1, s, "=") = 0 then return s
    keyRe = CreateObject("roRegex", "^(id|[a-z]+_id|[a-z]+id|file|item|video|key|session|sid|token|user|username|profile|name|server|host|path|cursor|address|ssid|serial)$", "i")
    words = s.Split(" ")
    for i = 0 to words.Count() - 1
        w = words[i]
        eq = Instr(1, w, "=")
        if eq > 1 and eq < Len(w) then
            if keyRe.IsMatch(Left(w, eq - 1)) then words[i] = Left(w, eq) + "<id>"
        end if
    end for
    return words.Join(" ")
end function

' What kind of ending a Roku exit code is: "crash", "hang", "memory", "killed", or "" for an
' ordinary one (the viewer left, the Roku slept or updated, or nothing is recorded).
function Diag_exitKind(code as dynamic) as string
    if Type(code) <> "String" and Type(code) <> "roString" then return ""
    name = "|" + UCase(code) + "|"
    if Instr(1, "|EXIT_BRIGHTSCRIPT_CRASH|EXIT_BRIGHTSCRIPT_STOP|", name) > 0 then return "crash"
    if Instr(1, "|EXIT_BRIGHTSCRIPT_TIMEOUT|EXIT_SIGNAL_TIMEOUT|", name) > 0 then return "hang"
    if Instr(1, "|EXIT_CHANNEL_MEM_LIMIT_FG|EXIT_CHANNEL_MEM_LIMIT_BG|EXIT_OUT_OF_MEMORY|EXIT_AM_LOWRESOURCE|", name) > 0 then return "memory"
    if Instr(1, "|EXIT_SYSTEM_KILL|EXIT_APP_ERROR|EXIT_NOT_RESUMED|EXIT_RUNNING_AFTER_SUSPEND|", name) > 0 then return "killed"
    return ""
end function

' Plain words for an exit kind, completing "Siku closed unexpectedly last time: ...".
function Diag_exitWords(kind as string) as string
    if kind = "crash" then return "an error stopped it"
    if kind = "hang" then return "it stopped responding"
    if kind = "memory" then return "it ran out of memory"
    if kind = "killed" then return "the Roku closed it"
    return ""
end function

' The last exit from roAppManager.GetLastExitInfo() (info, Roku OS 13+) or Main's
' lastExitOrTerminationReason (reason, used when info has no code):
' { code, kind, when, appState, mediaState, memLimitMb, key } with key = code@timestamp, the
' value remembered so one exit is announced once. console_log is ignored: it holds no BrightScript
' error text (found by silo-roku on a device) and could hold addresses.
function Diag_exitOf(info as dynamic, reason as dynamic) as object
    out = { code: "", kind: "", when: "", appState: "", mediaState: "", memLimitMb: -1, key: "" }
    if Type(info) = "roAssociativeArray" then
        out.code = Diag_text(info.exit_code)
        out.when = Diag_text(info.timestamp)
        out.appState = LCase(Diag_text(info.app_state))
        out.mediaState = LCase(Diag_text(info.media_player_state))
        ml = info.mem_limit
        t = Type(ml)
        if t = "Integer" or t = "roInt" or t = "roInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then out.memLimitMb = Int(ml)
    end if
    if out.code = "" or UCase(out.code) = "EXIT_UNKNOWN" then out.code = Diag_text(reason)
    out.code = UCase(out.code)
    out.kind = Diag_exitKind(out.code)
    if out.code <> "" then out.key = out.code + "@" + out.when
    return out
end function

function Diag_text(v as dynamic) as string
    if Type(v) = "String" or Type(v) = "roString" then return v
    return ""
end function

' The Settings row value for an exit: "Normal", "Not reported", or the plain words and time.
function Diag_exitLabel(e as dynamic) as string
    if Type(e) <> "roAssociativeArray" then return "Not reported"
    code = Diag_text(e.code)
    if code = "" then return "Not reported"
    kind = Diag_text(e.kind)
    if kind = "" then return "Normal"
    words = Diag_exitWords(kind)
    words = UCase(Left(words, 1)) + Mid(words, 2)
    when = Diag_text(e.when)
    if when <> "" then words = words + " (" + Diag_shortTime(when) + ")"
    return words
end function

' "2026-11-01T02:11:03Z" -> "2026-11-01 02:11 UTC"; anything else as it is, cut short.
function Diag_shortTime(stamp as string) as string
    if Len(stamp) >= 16 and Mid(stamp, 11, 1) = "T" then return Left(stamp, 10) + " " + Mid(stamp, 12, 5) + " UTC"
    return Left(stamp, 24)
end function

' Lines of text for the viewer: the newest maxLines, each cut into pieces of at most width
' characters so nothing is hidden past the screen's edge.
function Diag_viewLines(text as dynamic, width as integer, maxLines as integer) as object
    out = []
    if Type(text) <> "String" and Type(text) <> "roString" then return out
    raw = []
    for each ln in text.Split(Chr(10))
        if ln <> "" then raw.Push(ln)
    end for
    first = raw.Count() - maxLines
    if first < 0 then first = 0
    for i = first to raw.Count() - 1
        ln = raw[i]
        if ln <> "" then
            ' Continuation pieces are indented when the width leaves room for it.
            indent = ""
            if width > 20 then indent = "    "
            if width < 1 then width = 1
            while Len(ln) > width
                out.Push(Left(ln, width))
                ln = indent + Mid(ln, width + 1)
            end while
            out.Push(ln)
        end if
    end for
    return out
end function
