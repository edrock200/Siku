' SPDX-License-Identifier: AGPL-3.0-or-later
' AiLiveTask: one control socket for one playback session (see AiLiveTask.xml). The recipe is
' Silo's official Roku app's, measured on a Roku Ultra with Roku OS 16.0.4 (silo-roku
' docs/watch-party.md §2.1, source/watchparty/socket.bs):
'   - SetProtocols sends Sec-WebSocket-Protocol (AddHeader of it never reaches the server).
'   - Open(0) is asynchronous and returns false; the socket is open when event 1 arrives and only
'     when GetSelectedProtocol() is then the protocol asked for.
'   - Events: 1 opened, 2 closed, 3 error, 4 sent (also automatic pongs), 5 text, 7 ping, 8 pong.
'   - Automatic pongs answer the server's pings with SetAutoPingReply left at its default.
'   - wss:// verifies against the system CA bundle with no setup.
'   - A text message over 524,288 bytes closes the socket with 1009 (a cue batch is far smaller).

sub init()
    m.top.functionName = "work"
end sub

sub work()
    req = m.top.request
    if Type(req) <> "roAssociativeArray" then req = {}
    port = CreateObject("roMessagePort")
    m.top.observeField("shutdown", port)
    m.top.observeField("ack", port)
    pending = []
    nextId = 1
    ' brighterscript 0.73 predates Roku OS 16's roWebSocket.
    ' bs:disable-next-line: 1129
    ws = CreateObject("roWebSocket")
    if Type(ws) <> "roWebSocket" then
        report("failed", "unsupported")
        return
    end if
    ws.SetMessagePort(port)
    ws.SetProtocols(Str_orEmpty(req.protocols))
    if not ws.SetUrl(Str_orEmpty(req.url)) then
        report("failed", "url")
        return
    end if
    ws.Open(0)
    sessionId = Str_orEmpty(req.sessionId)
    fileId = Str_orEmpty(req.fileId)
    clock = CreateObject("roTimespan")
    opened = false
    lastHeard = -1   ' set by the server's first ping, pong or text; until then never judged quiet
    while true
        msg = wait(1000, port)
        now = clock.TotalMilliseconds()
        if Type(msg) = "roSGNodeEvent" then
            if m.top.shutdown = true then
                finish(ws, opened, "shutdown")
                return
            end if
            ' The player handled everything up to ack.
            acked = m.top.ack
            while pending.Count() > 0 and pending[0].id <= acked
                pending.Shift()
            end while
        else if Type(msg) = "roWebSocketEvent" then
            kind = msg.GetType()
            if kind = 1 then
                if ws.GetSelectedProtocol() <> AiLive_protocol() then
                    finish(ws, true, "protocol")
                    return
                end if
                opened = true
                ws.Send(Str_orEmpty(req.hello))
                report("open", "")
            else if kind = 2 then
                reason = "closed_by_server"
                if not opened then reason = "error"
                report(stateFor(opened), reason)
                return
            else if kind = 3 then
                finish(ws, opened, "error")
                return
            else if kind = 5 then
                lastHeard = now
                info = msg.GetInfo()
                text = invalid
                if Type(info) = "roAssociativeArray" then text = info.Text
                ev = AiLive_frameEvent(text, sessionId, fileId)
                if ev <> invalid then
                    ev.id = nextId
                    nextId = nextId + 1
                    pending.Push(ev)
                    ' A player that stopped acknowledging must not grow this without bound.
                    if pending.Count() > 200 then pending.Shift()
                    m.top.event = { items: pending }
                end if
            else if kind = 7 or kind = 8 then
                lastHeard = now
            end if
        end if
        if not opened and now > 10000 then
            finish(ws, false, "timeout")
            return
        end if
        ' The server pings about every 20 s; two missed pings and a margin is a dead socket. A Roku OS
        ' that reports no ping events never arms this (as Silo's Roku app does it).
        if opened and lastHeard >= 0 and now - lastHeard > 50000 then
            finish(ws, true, "quiet")
            return
        end if
        ' The server ends the lane after four hours anyway.
        if now > 4 * 3600 * 1000 then
            finish(ws, opened, "max_age")
            return
        end if
    end while
end sub

function stateFor(opened as boolean) as string
    if opened then return "closed"
    return "failed"
end function

sub finish(ws as object, opened as boolean, reason as string)
    ws.Close(1000, "")
    report(stateFor(opened), reason)
end sub

sub report(kind as string, reason as string)
    m.top.socketState = { kind: kind, reason: reason }
end sub
