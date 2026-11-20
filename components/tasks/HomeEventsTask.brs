' SPDX-License-Identifier: AGPL-3.0-or-later
' HomeEventsTask: one events socket for Home (see HomeEventsTask.xml). The roWebSocket recipe is the
' one AiLiveTask uses (Silo's Roku app, measured on a Roku Ultra with Roku OS 16.0.4):
'   - SetProtocols sends Sec-WebSocket-Protocol; Open(0) is asynchronous and returns false; the
'     socket is open when event 1 arrives, and only when GetSelectedProtocol() is silo.events.v2.
'   - Events: 1 opened, 2 closed { Code }, 3 error, 4 sent, 5 text, 7 ping, 8 pong.
'   - Automatic pongs answer the server's pings; wss:// verifies against the system CA bundle.
' The subscription is declared in the URL (channels=user_state); the server confirms it with a
' subscribed frame, and a socket without one 15 s after opening is closed.

sub init()
    m.top.functionName = "work"
end sub

sub work()
    req = m.top.request
    if Type(req) <> "roAssociativeArray" then req = {}
    m.seq = 0
    port = CreateObject("roMessagePort")
    m.top.observeField("shutdown", port)
    ' brighterscript 0.73 predates Roku OS 16's roWebSocket.
    ' bs:disable-next-line: 1129
    ws = CreateObject("roWebSocket")
    if Type(ws) <> "roWebSocket" then
        report("closed", "unsupported", "", 0, 0)
        return
    end if
    ws.SetMessagePort(port)
    ws.SetProtocols(Str_orEmpty(req.protocols))
    if not ws.SetUrl(Str_orEmpty(req.url)) then
        report("closed", "url", "", 0, 0)
        return
    end if
    ws.Open(0)
    profileId = Str_orEmpty(req.profileId)
    lifetimeMs = Int(Num_or(req.lifetime, 300)) * 1000
    clock = CreateObject("roTimespan")
    opened = false
    openedAt = 0
    subscribed = false
    changes = 0
    others = 0
    lastHeard = -1    ' the server's last ping, pong or text; until the first, never judged quiet
    lastOwnerCheck = 0
    while true
        msg = wait(1000, port)
        now = clock.TotalMilliseconds()
        if Type(msg) = "roSGNodeEvent" then
            if m.top.shutdown = true then
                finish(ws, "shutdown")
                return
            end if
        else if Type(msg) = "roWebSocketEvent" then
            kind = msg.GetType()
            if kind = 1 then
                if ws.GetSelectedProtocol() <> HomeWatch_protocol() then
                    finish(ws, "protocol")
                    return
                end if
                opened = true
                openedAt = now
            else if kind = 2 then
                reason = "closed_by_server"
                info = msg.GetInfo()
                code = 0
                if Type(info) = "roAssociativeArray" then code = Int(Num_or(info.Code, Num_or(info.code, 0)))
                if not opened then
                    reason = "error"
                else if code = 4001 then
                    reason = "access_changed"
                else if now >= lifetimeMs - 15000 then
                    ' The server ends every connection after max_connection_seconds: a planned end.
                    reason = "max_age"
                end if
                report("closed", reason, "", changes, others)
                return
            else if kind = 3 then
                finish(ws, "error")
                return
            else if kind = 5 then
                lastHeard = now
                info = msg.GetInfo()
                text = invalid
                if Type(info) = "roAssociativeArray" then text = info.Text
                if text = invalid and Type(info) = "roAssociativeArray" then text = info.text
                f = HomeWatch_frame(text, profileId)
                if f.kind = "subscribed" and not subscribed then
                    subscribed = true
                    report("subscribed", "", "", changes, others)
                else if f.kind = "rejected" and not subscribed then
                    finish(ws, "rejected")
                    return
                else if f.kind = "changed" and subscribed then
                    changes = changes + 1
                    if f.change <> "progress" then others = others + 1
                    report("changed", "", f.change, changes, others)
                else if f.kind = "access_changed" then
                    report("access_changed", "", "", changes, others)
                end if
            else if kind = 7 or kind = 8 then
                lastHeard = now
            end if
        end if
        if not opened and now > 10000 then
            finish(ws, "timeout")
            return
        end if
        if opened and not subscribed and now - openedAt > 15000 then
            finish(ws, "no_subscribe")
            return
        end if
        ' The server pings about every 20 s; two missed pings and a margin is a dead socket. A Roku OS
        ' that reports no ping events never arms this (as Silo's Roku app does it).
        if opened and lastHeard >= 0 and now - lastHeard > 50000 then
            finish(ws, "quiet")
            return
        end if
        ' Close just before the server would, then Home mints a new ticket at once.
        if now >= lifetimeMs - 2000 then
            finish(ws, "max_age")
            return
        end if
        ' A safety net: Home stops this socket when it hides (sign-out and profile changes hide it),
        ' but a session change must never keep another profile's socket open.
        if now - lastOwnerCheck >= 5000 then
            lastOwnerCheck = now
            s = m.global.session
            pid = ""
            if Type(s) = "roAssociativeArray" then pid = Str_orEmpty(s.profileId)
            if pid <> profileId then
                finish(ws, "owner")
                return
            end if
        end if
    end while
end sub

sub finish(ws as object, reason as string)
    ws.Close(1000, "")
    report("closed", reason, "", 0, 0)
end sub

sub report(kind as string, reason as string, change as string, changes as integer, others as integer)
    m.seq = m.seq + 1
    m.top.signal = { seq: m.seq, kind: kind, reason: reason, change: change, changes: changes, others: others }
end sub
