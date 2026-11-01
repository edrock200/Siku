' SPDX-License-Identifier: AGPL-3.0-or-later
' The diagnostics log on cachefs: and the last-exit read (see DiagTask.xml). Every storage failure
' is ignored: diagnostics must never make Siku fail.

sub init()
    m.top.functionName = "runDiag"
end sub

function diagPath(n as integer) as string
    if n = 0 then return "cachefs:/siku-diag.txt"
    return "cachefs:/siku-diag.1.txt"
end function

' Bytes kept in the current file before it becomes the previous one.
function diagFileBudget() as integer
    return 48000
end function

sub runDiag()
    port = CreateObject("roMessagePort")
    m.global.observeField("diagLine", port)
    m.top.observeField("command", port)
    m.top.observeField("launchReason", port)
    m.text = ""
    m.dirty = false
    m.text = readFile(diagPath(0))
    appendLine("---- Siku " + App_version() + " started; Roku " + deviceLine() + " ----")
    ' Lines logged before this Task listened (a line logged meanwhile may also arrive as an event).
    m.global.diagReady = true
    early = m.global.diagBacklog
    m.global.diagBacklog = []
    m.early = {}
    if Type(early) = "roArray" then
        for each ln in early
            appendLine(Diag_scrub(ln))
            m.early[ln] = true
        end for
    end if

    ' Main hands over lastExitOrTerminationReason just after the scene starts: wait for it briefly.
    exitRead = false
    started = CreateObject("roTimespan")
    while true
        timeout = 2000
        if not exitRead then timeout = 300
        msg = Wait(timeout, port)
        if Type(msg) = "roSGNodeEvent" then
            f = msg.getField()
            if f = "diagLine" then
                ln = Diag_text(msg.getData())
                ' Skip the copy of a backlog line that also arrived as an event.
                if ln <> "" and m.early.Count() > 0 then
                    if m.early.DoesExist(ln) then
                        m.early.Delete(ln)
                        ln = ""
                    end if
                end if
                if ln <> "" then appendLine(Diag_scrub(ln))
            else if f = "command" then
                doCommand(msg.getData())
            else if f = "launchReason" and not exitRead then
                exitRead = true
                readExit(m.top.launchReason)
            end if
        else if m.dirty then
            flush()
        end if
        if not exitRead and started.TotalMilliseconds() > 1500 then
            exitRead = true
            readExit(m.top.launchReason)
        end if
    end while
end sub

function deviceLine() as string
    di = CreateObject("roDeviceInfo")
    model = ""
    os = ""
    try
        model = di.GetModel()
        v = di.GetOSVersion()
        if Type(v) = "roAssociativeArray" then os = Str_orEmpty(v.major) + "." + Str_orEmpty(v.minor) + "." + Str_orEmpty(v.revision)
    catch e
        if e = invalid then os = "" ' e: older firmware
    end try
    return Str_orEmpty(model) + ", OS " + os
end function

sub appendLine(line as string)
    if line = "" then return
    dt = CreateObject("roDateTime")
    stamp = dt.ToISOString()
    stamp = Left(stamp, 10) + " " + Mid(stamp, 12, 8)
    m.text = m.text + stamp + " " + line + Chr(10)
    m.dirty = true
    if Len(m.text) > diagFileBudget() then rotate()
end sub

' The current file becomes the previous one (replacing it); a new current file starts.
sub rotate()
    try
        DeleteFile(diagPath(1))
        WriteAsciiFile(diagPath(1), m.text)
        DeleteFile(diagPath(0))
    catch e
        if e = invalid then return ' e: storage refused; the next flush tries again
    end try
    m.text = ""
    m.dirty = false
end sub

sub flush()
    m.dirty = false
    try
        WriteAsciiFile(diagPath(0), m.text)
    catch e
        if e = invalid then m.dirty = false ' e: storage refused or evicted; nothing to do
    end try
end sub

function readFile(path as string) as string
    t = ""
    try
        fs = CreateObject("roFileSystem")
        if fs = invalid then return ""
        if not fs.Exists(path) then return ""
        t = ReadAsciiFile(path)
    catch e
        if e = invalid then t = "" ' e: no file
    end try
    if Type(t) <> "String" and Type(t) <> "roString" then t = ""
    return t
end function

sub doCommand(c as dynamic)
    if Type(c) <> "roAssociativeArray" then return
    action = Str_orEmpty(c.action)
    if action = "read" then
        if m.dirty then flush()
        m.top.logText = readFile(diagPath(1)) + m.text
    else if action = "clear" then
        try
            DeleteFile(diagPath(0))
            DeleteFile(diagPath(1))
        catch e
            if e = invalid then action = "clear" ' e: nothing to delete
        end try
        m.text = ""
        m.dirty = false
        Registry_delete("diagLastProblem")
        Diag_log("[siku-diag] log cleared")
        m.top.logText = ""
    end if
end sub

' Roku's record of how the last launch ended (roAppManager.GetLastExitInfo, Roku OS 13+), else
' Main's launch reason. An unexpected close is announced once (registry diagHandledExit) and
' remembered for Settings (diagLastProblem).
sub readExit(reason as dynamic)
    info = invalid
    try
        am = CreateObject("roAppManager")
        if am <> invalid then info = am.GetLastExitInfo()
    catch e
        info = invalid ' e: firmware before GetLastExitInfo
        if e = invalid then info = invalid
    end try
    ex = Diag_exitOf(info, reason)
    line = "[siku-diag] last exit code=" + ex.code + " kind=" + ex.kind + " app_state=" + ex.appState + " media=" + ex.mediaState
    if ex.memLimitMb >= 0 then line = line + " mem_limit_mb=" + ex.memLimitMb.ToStr()
    print line
    appendLine(line)
    fresh = false
    if ex.kind <> "" then
        handled = Str_orEmpty(Registry_read("diagHandledExit", ""))
        fresh = ex.when = "" or ex.key <> handled
        if fresh then
            Registry_write("diagHandledExit", ex.key)
            Registry_write("diagLastProblem", { code: ex.code, kind: ex.kind, when: ex.when })
        end if
    end if
    last = Registry_read("diagLastProblem", {})
    if Type(last) <> "roAssociativeArray" then last = {}
    m.global.diagExit = { code: ex.code, kind: ex.kind, when: ex.when, fresh: fresh, last: last }
    flush()
end sub
