' LanTask: sockets, framing, sealed handshake, heartbeats and mDNS for the phone features
' (see LanTask.xml for the fields). Console lines start with [siku-lan]; keys, nonces and tokens
' are never printed.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.top.functionName = "runLan"
end sub

' ---------- Constants ----------

function lanCastPort() as integer
    return 52817
end function

function lanPairPort() as integer
    return 52819
end function

function lanMaxControllers() as integer
    return 6
end function

' Receiver features this build implements (SiloCastFeature). replace_confirmation is not offered:
' Siku replaces what plays when a phone launches, as a Roku remote would.
function lanCastFeatures() as object
    return ["multi_controller", "close_reason", "resume_token", "presence", "volume_mute_only", "no_playback_speed"]
end function

function lanControlNames() as object
    return { play: true, pause: true, play_pause: true, seek: true, stop: true, select_audio_track: true, select_subtitle_track: true, set_playback_speed: true, set_quality: true, set_video_gravity: true, set_subtitle_sync_ms: true, set_subtitle_position: true, set_volume: true, set_muted: true, play_next: true }
end function

' ---------- Main loop ----------

sub runLan()
    m.port = CreateObject("roMessagePort")
    m.clock = CreateObject("roTimespan")
    m.rxBuf = CreateObject("roByteArray")
    m.rxBuf[16383] = 0
    ' Sockets are held one level down (m.io.*, m.conns[id].sock), never as a direct member of m:
    ' brs-node (the simulator) disposes a socket assigned straight to m.<name>, which closed the
    ' listener the moment it opened. Harmless on a Roku.
    m.io = { castListener: invalid, pairListener: invalid, mdns: invalid }
    m.conns = {}          ' conn id -> connection
    m.sockToConn = {}     ' socket id -> conn id
    m.connSeq = 0
    m.cfg = { castEnabled: false, sealed: true, pairing: { mode: "" } }
    m.castPort = 0
    m.pairPort = 0
    m.pairSid = ""
    m.stateJson = ""
    m.lastStateAt = 0
    m.lastHeartbeat = 0
    m.io.mdns = invalid
    m.mdnsStatus = "off"
    m.mdnsAnnounceAt = []
    m.mdnsAdvertised = []
    m.mdnsAnswered = 0
    m.ip = deviceIp()
    loadKey()

    m.top.observeField("config", m.port)
    m.top.observeField("command", m.port)
    m.top.observeField("castState", m.port)
    if m.top.config <> invalid then applyConfig(m.top.config)

    while true
        msg = Wait(250, m.port)
        t = Type(msg)
        if t = "roSocketEvent" then
            onSocketEvent(msg.GetSocketID())
        else if t = "roSGNodeEvent" then
            field = msg.GetField()
            if field = "config" then
                applyConfig(msg.GetData())
            else if field = "command" then
                onCommand(msg.GetData())
            else if field = "castState" then
                onCastState(msg.GetData())
            end if
        end if
        onTick()
    end while
end sub

function nowMs() as integer
    return m.clock.TotalMilliseconds()
end function

function deviceIp() as string
    di = CreateObject("roDeviceInfo")
    ips = di.GetIPAddrs()
    if ips <> invalid then
        for each k in ips
            v = Str_orEmpty(ips[k])
            if v <> "" and v <> "127.0.0.1" then return v
        end for
    end if
    info = di.GetConnectionInfo()
    if info <> invalid and not Str_isEmpty(info.ip) then return Str_orEmpty(info.ip)
    return "127.0.0.1"
end function

' ---------- Pairing key ----------

sub loadKey()
    hex = Str_orEmpty(Registry_read("lanPairingKey", ""))
    key = invalid
    if Len(hex) = 32 then key = Lan_hexBytes(hex)
    if key = invalid or key.Count() <> 16 then
        key = Lan_randomBytes(16)
        Registry_write("lanPairingKey", Lan_hex(key))
        print "[siku-lan] new pairing key generated (kid=" + Sealed_keyId(key) + ")"
    end if
    m.key = key
    m.keyId = Sealed_keyId(key)
end sub

sub publishPairingInfo()
    b32 = Lan_base32(m.key)
    link = "silo://cast?v=2&host=" + m.ip + "&port=" + m.castPort.ToStr() + "&id=" + Str_urlEncode(Str_orEmpty(m.cfg.deviceId))
    link = link + "&name=" + Str_urlEncode(Str_orEmpty(m.cfg.deviceName))
    if not Str_isEmpty(m.cfg.serverId) then link = link + "&server=" + Str_urlEncode(Str_orEmpty(m.cfg.serverId))
    if Lan_isTrue(m.cfg.sealed) then
        link = link + "&security=sealed&key=" + b32
    else
        link = link + "&security=plain"
    end if
    m.top.pairingInfo = { keyId: m.keyId, keyText: Lan_groupsOfFour(b32), ip: m.ip, port: m.castPort, sealed: Lan_isTrue(m.cfg.sealed), link: link, listening: m.io.castListener <> invalid }
end sub

' ---------- Config ----------

sub applyConfig(c as dynamic)
    if c = invalid or Type(c) <> "roAssociativeArray" then return
    old = m.cfg
    m.cfg = c
    if m.cfg.pairing = invalid then m.cfg.pairing = { mode: "" }
    m.ip = deviceIp()
    wasSealed = Lan_isTrue(old.sealed)
    nowSealed = Lan_isTrue(c.sealed)
    if Lan_isTrue(c.castEnabled) and m.io.castListener = invalid then
        startCastListener()
    else if not Lan_isTrue(c.castEnabled) and m.io.castListener <> invalid then
        stopCastListener("tv_disconnected")
    else if m.io.castListener <> invalid and wasSealed <> nowSealed then
        ' The transport changed: every controller has to dial again.
        closeAll("cast", "unauthorized")
    end if
    ' Who may control follows the server the TV plays from (its own, or a phone's borrowed one).
    if Str_orEmpty(old.serverId) <> Str_orEmpty(c.serverId) or Str_orEmpty(old.serverIdentity) <> Str_orEmpty(c.serverIdentity) then
        for each id in m.conns
            cn = m.conns[id]
            if cn.kind = "cast" and cn.didHello then cn.authorized = cn.granted or helloMatches(cn)
        end for
    end if
    mode = Str_orEmpty(c.pairing.mode)
    oldMode = Str_orEmpty(old.pairing.mode)
    if mode <> "" and (m.io.pairListener = invalid or mode <> oldMode or Str_orEmpty(c.pairing.srv) <> Str_orEmpty(old.pairing.srv)) then
        if m.io.pairListener = invalid then startPairListener()
        m.pairSid = Lan_hex(Lan_randomBytes(8))
    else if mode = "" and m.io.pairListener <> invalid then
        stopPairListener()
    end if
    ensureMdns()
    refreshAdvertisement()
    publishPairingInfo()
    publishStatus()
end sub

function helloMatches(cn as object) as boolean
    if not Lan_isTrue(m.cfg.signedIn) then return false
    return Lan_serversMatch(cn.serverId, cn.serverIdentity, m.cfg.serverId, m.cfg.serverIdentity)
end function

' ---------- Listeners ----------

function listenOn(port as integer) as dynamic
    for attempt = 0 to 4
        addr = CreateObject("roSocketAddress")
        addr.SetPort(port + attempt)
        s = CreateObject("roStreamSocket")
        if s = invalid then return invalid
        s.SetMessagePort(m.port)
        s.SetReuseAddr(true)
        if s.SetAddress(addr) then
            s.NotifyReadable(true)
            if s.Listen(4) then return { sock: s, port: port + attempt }
        end if
        print "[siku-lan] cannot listen on " + (port + attempt).ToStr() + " status=" + s.Status().ToStr()
        s.Close()
    end for
    return invalid
end function

sub startCastListener()
    l = listenOn(lanCastPort())
    if l = invalid then
        print "[siku-lan] remote control listener failed"
        return
    end if
    m.io.castListener = l.sock
    m.castPort = l.port
    print "[siku-lan] remote control listening on " + m.ip + ":" + m.castPort.ToStr() + " level=" + securityLevel()
end sub

sub stopCastListener(reason as string)
    closeAll("cast", reason)
    if m.io.castListener <> invalid then m.io.castListener.Close()
    m.io.castListener = invalid
    print "[siku-lan] remote control stopped"
end sub

sub startPairListener()
    l = listenOn(lanPairPort())
    if l = invalid then
        print "[siku-lan] phone sign-in listener failed"
        return
    end if
    m.io.pairListener = l.sock
    m.pairPort = l.port
    print "[siku-lan] phone sign-in listening on " + m.ip + ":" + m.pairPort.ToStr() + " state=" + Str_orEmpty(m.cfg.pairing.mode)
end sub

sub stopPairListener()
    closeAll("pair", "")
    if m.io.pairListener <> invalid then m.io.pairListener.Close()
    m.io.pairListener = invalid
    print "[siku-lan] phone sign-in stopped"
end sub

function securityLevel() as string
    if Lan_isTrue(m.cfg.sealed) then return "sealed"
    return "plain"
end function

' ---------- Socket events ----------

sub onSocketEvent(sockId as integer)
    if m.io.castListener <> invalid and sockId = m.io.castListener.GetID() then
        acceptOn(m.io.castListener, "cast")
    else if m.io.pairListener <> invalid and sockId = m.io.pairListener.GetID() then
        acceptOn(m.io.pairListener, "pair")
    else if m.io.mdns <> invalid and sockId = m.io.mdns.GetID() then
        onMdnsReadable()
    else
        id = m.sockToConn[sockId.ToStr()]
        if id <> invalid and m.conns.DoesExist(id) then onReadable(m.conns[id])
    end if
end sub

sub acceptOn(listener as object, kind as string)
    s = listener.Accept()
    if s = invalid then return
    s.SetMessagePort(m.port)
    s.NotifyReadable(true)
    peer = ""
    pa = s.GetReceivedFromAddress()
    if pa <> invalid then peer = pa.GetAddress()
    m.connSeq = m.connSeq + 1
    cn = { id: "c" + m.connSeq.ToStr(), kind: kind, sock: s, frames: LanFrames_new(), openedAt: nowMs(), peer: peer
        sealedState: "none", keys: invalid, sendSeq: 0, recvSeq: 0
        didHello: false, authorized: false, authorizedAtHello: false, granted: false, features: {}, deviceId: "", deviceName: "", serverId: "", serverIdentity: ""
        passive: false, missed: 0, lastState: "", lastStateAt: 0, budgetAt: 0, budget: 0, rateNoticeAt: -100000 }
    if kind = "pair" then
        if countConns("pair") > 0 then
            print "[siku-lan] phone sign-in busy; refused " + peer
            s.Close()
            return
        end if
        register(cn)
        print "[siku-lan] phone sign-in connection " + cn.id + " from " + peer
        hello = { "v": 1, "type": "hello", "tvName": Str_orEmpty(m.cfg.deviceName), "tvDeviceId": Str_orEmpty(m.cfg.deviceId), "state": Str_orEmpty(m.cfg.pairing.mode), "supportedVersions": [1] }
        sendJson(cn, hello)
        m.top.pairEvent = { type: "connected", conn: cn.id }
        return
    end if
    if countConns("cast") >= lanMaxControllers() then
        print "[siku-lan] remote control at its limit; refused " + peer
        if not Lan_isTrue(m.cfg.sealed) then
            sendJson(cn, tvHello())
            sendJson(cn, errorMessage("too_many_controllers", "Too many devices are controlling this TV. Disconnect one and try again."))
            sendJson(cn, { "type": "close", "v": 2, "close": { "reason": "too_many_controllers" } })
        end if
        s.Close()
        return
    end if
    register(cn)
    print "[siku-lan] remote control connection " + cn.id + " from " + peer + " level=" + securityLevel()
    if Lan_isTrue(m.cfg.sealed) then
        cn.sealedState = "await"
    else
        sendJson(cn, tvHello())
    end if
    publishStatus()
end sub

' A snapshot of the connection ids, for loops that may close connections.
function connIds() as object
    ids = []
    for each id in m.conns
        ids.Push(id)
    end for
    return ids
end function

sub register(cn as object)
    m.conns[cn.id] = cn
    m.sockToConn[cn.sock.GetID().ToStr()] = cn.id
end sub

function countConns(kind as string) as integer
    n = 0
    for each id in m.conns
        if m.conns[id].kind = kind then n = n + 1
    end for
    return n
end function

sub onReadable(cn as object)
    n = cn.sock.Receive(m.rxBuf, 0, 16384)
    if n <= 0 then
        if n < 0 and cn.sock.eWouldBlock() then return
        closeConn(cn, "peer closed")
        return
    end if
    for each payload in LanFrames_append(cn.frames, Lan_slice(m.rxBuf, 0, n))
        if not m.conns.DoesExist(cn.id) then return
        onFrame(cn, payload)
    end for
    if cn.frames.failed then closeConn(cn, "frame too large")
end sub

sub onFrame(cn as object, payload as object)
    if cn.kind = "cast" and cn.sealedState = "await" then
        onSealedHello(cn, payload)
        return
    end if
    if cn.sealedState = "open" then
        opened = Sealed_open(cn.keys, Sealed_fromPhone(), cn.recvSeq, payload)
        if opened = invalid then
            ' A frame that fails to open ends the connection without an answer.
            print "[siku-lan] sealed frame did not open; closing " + cn.id
            closeConn(cn, "sealed frame refused")
            return
        end if
        cn.recvSeq = cn.recvSeq + 1
        payload = opened
    end if
    msg = ParseJson(payload.ToAsciiString())
    if msg = invalid or Type(msg) <> "roAssociativeArray" then
        if cn.kind = "pair" then closeConn(cn, "undecodable pairing frame")
        return
    end if
    if cn.kind = "pair" then
        m.top.pairEvent = { type: "message", conn: cn.id, message: msg }
    else
        onCastMessage(cn, msg)
    end if
end sub

' Level sealed: the phone's plain sealed_hello comes first; a wrong key gets a plain close.
sub onSealedHello(cn as object, payload as object)
    hello = Sealed_readHello(payload.ToAsciiString())
    if hello = invalid or hello.keyId <> m.keyId then
        if hello = invalid then
            print "[siku-lan] sealed: " + cn.id + " sent no sealed_hello; refused"
        else
            print "[siku-lan] sealed: " + cn.id + " has another pairing key (kid " + hello.keyId + "); refused"
        end if
        sendJson(cn, { "type": "close", "v": 2, "close": { "reason": "unauthorized" } })
        closeConn(cn, "pairing key refused")
        return
    end if
    tvNonce = Lan_randomBytes(16)
    sendRaw(cn, Lan_bytes(Sealed_helloText(m.keyId, tvNonce)))
    cn.keys = Sealed_sessionKeys(m.key, hello.nonce, tvNonce)
    cn.sealedState = "open"
    print "[siku-lan] sealed: " + cn.id + " paired"
    sendJson(cn, tvHello())
end sub

' ---------- SiloCast messages ----------

function tvHello() as object
    h = { "role": "tv", "deviceName": Str_orEmpty(m.cfg.deviceName), "deviceId": Str_orEmpty(m.cfg.deviceId), "supportedVersions": [2], "features": lanCastFeatures() }
    if not Str_isEmpty(m.cfg.serverId) then h["serverId"] = Str_orEmpty(m.cfg.serverId)
    if not Str_isEmpty(m.cfg.serverName) then h["serverName"] = Str_orEmpty(m.cfg.serverName)
    if not Str_isEmpty(m.cfg.serverIdentity) then h["serverIdentity"] = Str_orEmpty(m.cfg.serverIdentity)
    return { "type": "hello", "v": 2, "hello": h }
end function

function errorMessage(code as string, text as string) as object
    return { "type": "error", "v": 2, "error": { "code": code, "message": text } }
end function

sub onCastMessage(cn as object, msg as object)
    kind = Str_orEmpty(msg["type"])
    if kind = "hello" then
        onHello(cn, msg.hello)
    else if kind = "ping" then
        sendJson(cn, { "type": "pong", "v": 2 })
    else if kind = "pong" then
        cn.missed = 0
    else if kind = "close" then
        closeConn(cn, "phone closed")
    else if not cn.didHello then
        ' Nothing but hello, ping and close before the hello.
        sendJson(cn, errorMessage("unauthorized", "Connect with a matching Silo account first."))
    else if kind = "presence" then
        p = msg.presence
        if Type(p) = "roAssociativeArray" then
            cn.passive = Lan_isTrue(p.passive)
            m.top.castEvent = { type: "presence", conn: cn.id, passive: cn.passive }
            publishStatus()
        end if
    else if kind = "handoff_offer" then
        if Type(msg.handoffOffer) = "roAssociativeArray" then m.top.castEvent = { type: "offer", conn: cn.id, offer: msg.handoffOffer, controller: controllerInfo(cn) }
    else if kind = "handoff_cancel" then
        if Type(msg.handoffCancel) = "roAssociativeArray" then m.top.castEvent = { type: "handoffCancel", conn: cn.id, cancel: msg.handoffCancel }
    else if kind = "launch" then
        if not requireAuthorized(cn) then return
        if Type(msg.launch) = "roAssociativeArray" then m.top.castEvent = { type: "launch", conn: cn.id, launch: msg.launch, controller: controllerInfo(cn) }
    else if kind = "control" then
        if not requireAuthorized(cn) then return
        c = msg.control
        if Type(c) <> "roAssociativeArray" then return
        if not allowCommand(cn) then return
        name = Str_orEmpty(c.name)
        ' A command from a newer remote is ignored without an error, as on Android TV.
        if not lanControlNames().DoesExist(name) then return
        m.top.castEvent = { type: "control", conn: cn.id, control: c }
    end if
end sub

function controllerInfo(cn as object) as object
    return { deviceId: cn.deviceId, deviceName: cn.deviceName, serverId: cn.serverId, serverIdentity: cn.serverIdentity, authorized: cn.authorized, authorizedAtHello: cn.authorizedAtHello, passive: cn.passive, features: cn.features }
end function

function requireAuthorized(cn as object) as boolean
    if cn.authorized then return true
    sendJson(cn, errorMessage("unauthorized", "Connect with a matching Silo account first."))
    return false
end function

' At most 20 commands a second per controller; the notice goes out once a second at most.
function allowCommand(cn as object) as boolean
    now = nowMs()
    if now - cn.budgetAt >= 1000 then
        cn.budgetAt = now
        cn.budget = 0
    end if
    cn.budget = cn.budget + 1
    if cn.budget <= 20 then return true
    if now - cn.rateNoticeAt >= 1000 then
        cn.rateNoticeAt = now
        sendJson(cn, errorMessage("rate_limited", "Too many commands. Slow down and try again."))
    end if
    return false
end function

sub onHello(cn as object, h as dynamic)
    if cn.didHello then return
    if h = invalid or Type(h) <> "roAssociativeArray" then return
    features = {}
    for each f in Arr_or(h.features)
        features[Str_orEmpty(f)] = true
    end for
    cn.features = features
    versionOk = false
    for each v in Arr_or(h.supportedVersions)
        if Num_or(v, 0) = 2 then versionOk = true
    end for
    if Str_orEmpty(h.role) <> "phone" or not versionOk then
        print "[siku-lan] hello from " + cn.id + " refused: role=" + Str_orEmpty(h.role) + " (version 2 required)"
        sendJson(cn, errorMessage("version_unsupported", "Update Silo on both devices to continue."))
        goodbye(cn, "unauthorized")
        return
    end if
    cn.didHello = true
    cn.deviceId = Str_orEmpty(h.deviceId)
    cn.deviceName = Str_orEmpty(h.deviceName)
    cn.serverId = Str_orEmpty(h.serverId)
    cn.serverIdentity = Str_orEmpty(h.serverIdentity).Trim()
    cn.passive = Lan_isTrue(h.passive)
    ' An older connection from the same device is one it abandoned.
    for each id in connIds()
        other = m.conns[id]
        if other <> invalid and other.kind = "cast" and other.id <> cn.id and other.deviceId <> "" and other.deviceId = cn.deviceId then goodbye(other, "replaced")
    end for
    cn.authorized = helloMatches(cn)
    cn.authorizedAtHello = cn.authorized
    print "[siku-lan] hello " + cn.id + " from " + Chr(34) + cn.deviceName + Chr(34) + " authorized=" + Lan_boolText(cn.authorized) + " passive=" + Lan_boolText(cn.passive)
    m.top.castEvent = { type: "hello", conn: cn.id, controller: controllerInfo(cn) }
    if cn.authorized then sendState(cn, true)
    publishStatus()
end sub

' ---------- Commands from the render thread ----------

sub onCommand(c as dynamic)
    if c = invalid or Type(c) <> "roAssociativeArray" then return
    kind = Str_orEmpty(c.kind)
    cn = invalid
    if not Str_isEmpty(c.conn) and m.conns.DoesExist(c.conn) then cn = m.conns[c.conn]
    if kind = "castSend" or kind = "pairSend" then
        if cn <> invalid and c.message <> invalid then sendJson(cn, c.message)
    else if kind = "castClose" or kind = "pairClose" then
        if cn <> invalid then goodbye(cn, Str_orEmpty(c.reason))
    else if kind = "castCloseAll" then
        closeAll("cast", Str_orEmpty(c.reason))
    else if kind = "castCloseActive" then
        ' The TV's own Disconnect: every controller that is not passive.
        for each id in connIds()
            other = m.conns[id]
            if other <> invalid and other.kind = "cast" and not other.passive then goodbye(other, "tv_disconnected")
        end for
    else if kind = "castAuthorize" then
        if cn <> invalid then
            cn.granted = Lan_isTrue(c.authorized)
            cn.authorized = cn.granted or helloMatches(cn)
            if cn.authorized then sendState(cn, true)
            publishStatus()
        end if
    else if kind = "resetKey" then
        m.key = Lan_randomBytes(16)
        m.keyId = Sealed_keyId(m.key)
        Registry_write("lanPairingKey", Lan_hex(m.key))
        print "[siku-lan] pairing key reset (kid=" + m.keyId + ")"
        if Lan_isTrue(m.cfg.sealed) then closeAll("cast", "unauthorized")
        refreshAdvertisement()
        publishPairingInfo()
    end if
end sub

' ---------- State fan-out ----------

sub onCastState(s as dynamic)
    if s = invalid then return
    m.stateJson = FormatJson({ "type": "state", "v": 2, "state": s })
    for each id in connIds()
        cn = m.conns[id]
        if cn <> invalid and cn.kind = "cast" and cn.authorized then sendState(cn, false)
    end for
end sub

sub sendState(cn as object, force as boolean)
    if m.stateJson = "" then return
    if not force and cn.lastState = m.stateJson then return
    cn.lastState = m.stateJson
    cn.lastStateAt = nowMs()
    sendText(cn, m.stateJson)
end sub

' ---------- Ticks: heartbeat, hello watchdog, state refresh, mDNS announcements ----------

sub onTick()
    now = nowMs()
    if now - m.lastHeartbeat >= 3000 then
        m.lastHeartbeat = now
        for each id in connIds()
            cn = m.conns[id]
            if cn <> invalid and cn.kind = "cast" then
                if cn.sealedState = "await" and now - cn.openedAt > 10000 then
                    closeConn(cn, "no sealed_hello")
                else if not cn.didHello and now - cn.openedAt > 5000 then
                    print "[siku-lan] " + cn.id + " sent no hello; closing"
                    goodbye(cn, "timeout")
                else if cn.didHello then
                    cn.missed = cn.missed + 1
                    if cn.missed > 3 then
                        print "[siku-lan] " + cn.id + " stopped answering pings; closing"
                        closeConn(cn, "heartbeat")
                    else
                        sendJson(cn, { "type": "ping", "v": 2 })
                    end if
                end if
            end if
        end for
    end if
    for each id in connIds()
        cn = m.conns[id]
        if cn <> invalid and cn.kind = "cast" and cn.authorized and now - cn.lastStateAt >= 2000 then sendState(cn, true)
    end for
    mdnsTick(now)
end sub

' ---------- Sending and closing ----------

sub sendJson(cn as object, obj as object)
    sendText(cn, FormatJson(obj))
end sub

sub sendText(cn as object, text as string)
    payload = Lan_bytes(text)
    if cn.sealedState = "open" then
        payload = Sealed_seal(cn.keys, Sealed_fromTv(), cn.sendSeq, payload)
        if payload = invalid then
            closeConn(cn, "seal failed")
            return
        end if
        cn.sendSeq = cn.sendSeq + 1
    else if cn.sealedState = "await" then
        ' Only a plain refusal goes out before the sealed handshake.
        if Instr(1, text, Chr(34) + "close" + Chr(34)) = 0 then return
    end if
    sendRaw(cn, payload)
end sub

sub sendRaw(cn as object, payload as object)
    data = Lan_frame(payload)
    total = data.Count()
    sent = 0
    waits = 0
    while sent < total
        k = cn.sock.Send(data, sent, total - sent)
        if k > 0 then
            sent = sent + k
        else if cn.sock.eWouldBlock() and waits < 200 then
            waits = waits + 1
            Sleep(10)
        else
            print "[siku-lan] send failed on " + cn.id + "; closing"
            closeConn(cn, "send failed")
            return
        end if
    end while
end sub

' A deliberate close: `close` first (with the reason for peers that read one), then the FIN.
sub goodbye(cn as object, reason as string)
    if not m.conns.DoesExist(cn.id) then return
    if cn.kind = "cast" and cn.sealedState <> "await" then
        if reason <> "" and (cn.features.DoesExist("close_reason") or reason = "too_many_controllers") then
            sendJson(cn, { "type": "close", "v": 2, "close": { "reason": reason } })
        else
            sendJson(cn, { "type": "close", "v": 2 })
        end if
    else if cn.kind = "pair" and reason <> "" then
        sendJson(cn, { "v": 1, "type": "cancel", "reason": reason })
    end if
    closeConn(cn, "goodbye " + reason)
end sub

sub closeAll(kind as string, reason as string)
    ids = []
    for each id in m.conns
        if m.conns[id].kind = kind then ids.Push(id)
    end for
    for each id in ids
        if m.conns.DoesExist(id) then goodbye(m.conns[id], reason)
    end for
end sub

sub closeConn(cn as object, why as string)
    if not m.conns.DoesExist(cn.id) then return
    m.conns.Delete(cn.id)
    m.sockToConn.Delete(cn.sock.GetID().ToStr())
    cn.sock.Close()
    print "[siku-lan] " + cn.kind + " connection " + cn.id + " closed (" + why + ")"
    if cn.kind = "pair" then
        m.top.pairEvent = { type: "closed", conn: cn.id }
    else
        m.top.castEvent = { type: "closed", conn: cn.id, controller: controllerInfo(cn) }
        publishStatus()
    end if
end sub

sub publishStatus()
    list = []
    for each id in m.conns
        cn = m.conns[id]
        if cn.kind = "cast" and cn.didHello then list.Push({ conn: cn.id, name: cn.deviceName, deviceId: cn.deviceId, passive: cn.passive, authorized: cn.authorized })
    end for
    m.top.status = { castPort: m.castPort, castListening: m.io.castListener <> invalid, pairPort: m.pairPort, pairListening: m.io.pairListener <> invalid, mdns: m.mdnsStatus, ip: m.ip, controllers: list }
end sub

' ---------- mDNS ----------

sub ensureMdns()
    if m.io.mdns <> invalid or m.mdnsStatus = "unavailable" then return
    wanted = m.io.castListener <> invalid or m.io.pairListener <> invalid
    if not wanted then return
    d = CreateObject("roDatagramSocket")
    if d = invalid then
        m.mdnsStatus = "unavailable"
        print "[siku-lan] mdns: roDatagramSocket unavailable"
        return
    end if
    d.SetMessagePort(m.port)
    reuse = d.SetReuseAddr(true)
    bindAddr = CreateObject("roSocketAddress")
    bindAddr.SetPort(5353)
    bound = d.SetAddress(bindAddr)
    m.mdnsGroup = CreateObject("roSocketAddress")
    m.mdnsGroup.SetAddress("224.0.0.251:5353")
    joined = false
    if bound then joined = d.JoinGroup(m.mdnsGroup)
    print "[siku-lan] mdns bind 5353 reuse=" + reuse.ToStr() + " bound=" + bound.ToStr() + " joined=" + joined.ToStr() + " status=" + d.Status().ToStr()
    if not bound or not joined then
        ' Another responder owns the port without sharing it, or multicast is refused. Phones
        ' then find Siku through the QR code's pairing link only.
        d.Close()
        m.mdnsStatus = "unavailable"
        return
    end if
    d.SetMulticastTTL(255)
    d.SetMulticastLoop(false)
    d.NotifyReadable(true)
    m.io.mdns = d
    m.mdnsStatus = "ok"
end sub

function shortId() as string
    id = LCase(Str_orEmpty(m.cfg.deviceId).Replace("-", ""))
    if Len(id) < 8 then id = Left(Lan_hex(Lan_sha256(Lan_bytes(id))), 8)
    return Left(id, 8)
end function

function mdnsHost() as string
    return "siku-" + shortId() + ".local"
end function

function mdnsServices() as object
    out = []
    inst = "Siku-" + shortId()
    if m.io.castListener <> invalid then
        txt = [["v", "2"], ["id", Str_orEmpty(m.cfg.deviceId)], ["deviceId", Str_orEmpty(m.cfg.deviceId)], ["name", Str_orEmpty(m.cfg.deviceName)]]
        if not Str_isEmpty(m.cfg.serverId) then txt.Push(["server", Str_orEmpty(m.cfg.serverId)])
        if not Str_isEmpty(m.cfg.serverName) then txt.Push(["serverName", Str_orEmpty(m.cfg.serverName)])
        if not Str_isEmpty(m.cfg.serverIdentity) then txt.Push(["serverIdentity", Str_orEmpty(m.cfg.serverIdentity)])
        playing = "0"
        if Lan_isTrue(m.cfg.playing) then playing = "1"
        txt.Push(["playing", playing])
        txt.Push(["sec", securityLevel()])
        if Lan_isTrue(m.cfg.sealed) then txt.Push(["kid", m.keyId])
        out.Push(Mdns_service("_silocast-roku._tcp", inst, m.castPort, txt))
    end if
    if m.io.pairListener <> invalid then
        mode = Str_orEmpty(m.cfg.pairing.mode)
        txt = [["v", "1"], ["name", Str_orEmpty(m.cfg.deviceName)], ["id", Str_orEmpty(m.cfg.deviceId)], ["sid", m.pairSid], ["st", mode]]
        if mode = "login" and not Str_isEmpty(m.cfg.pairing.srv) then txt.Push(["srv", Str_orEmpty(m.cfg.pairing.srv)])
        out.Push(Mdns_service("_silopair-roku._tcp", inst, m.pairPort, txt))
    end if
    return out
end function

' Announces what changed (three times, 1 s and 2 s apart) and says goodbye to what went away.
sub refreshAdvertisement()
    if m.io.mdns = invalid then return
    services = mdnsServices()
    gone = []
    for each old in m.mdnsAdvertised
        still = false
        for each s in services
            if s.serviceType = old.serviceType and s.port = old.port then still = true
        end for
        if not still then gone.Push(old)
    end for
    if gone.Count() > 0 then mdnsSend(Mdns_announcement(gone, mdnsHost(), m.ip, 0), invalid)
    if FormatJson(services) = FormatJson(m.mdnsAdvertised) then return
    m.mdnsAdvertised = services
    if services.Count() = 0 then return
    now = nowMs()
    m.mdnsAnnounceAt = [now, now + 1000, now + 3000]
end sub

sub mdnsTick(now as integer)
    if m.io.mdns = invalid then
        ensureMdns()
        if m.io.mdns <> invalid then refreshAdvertisement()
        return
    end if
    if m.mdnsAnnounceAt.Count() > 0 and now >= m.mdnsAnnounceAt[0] then
        m.mdnsAnnounceAt.Shift()
        if m.mdnsAdvertised.Count() > 0 then
            mdnsSend(Mdns_announcement(m.mdnsAdvertised, mdnsHost(), m.ip, 4500), invalid)
            print "[siku-lan] mdns announced " + m.mdnsAdvertised.Count().ToStr() + " service(s) as " + mdnsHost() + " " + m.ip
        end if
    end if
end sub

sub onMdnsReadable()
    buf = CreateObject("roByteArray")
    buf[8999] = 0
    n = m.io.mdns.Receive(buf, 0, 9000)
    if n <= 0 then return
    from = m.io.mdns.GetReceivedFromAddress()
    query = Mdns_parse(Lan_slice(buf, 0, n))
    resp = Mdns_respond(query, m.mdnsAdvertised, mdnsHost(), m.ip)
    if resp = invalid then return
    mdnsSend(resp.bytes, invalid)
    if resp.unicast and from <> invalid then mdnsSend(resp.bytes, from)
    m.mdnsAnswered = m.mdnsAnswered + 1
    if m.mdnsAnswered <= 5 or m.mdnsAnswered mod 50 = 0 then
        peer = ""
        if from <> invalid then peer = from.GetAddress()
        print "[siku-lan] mdns answered query #" + m.mdnsAnswered.ToStr() + " from " + peer
    end if
end sub

sub mdnsSend(bytes as object, target as dynamic)
    if m.io.mdns = invalid then return
    if target = invalid then target = m.mdnsGroup
    m.io.mdns.SetSendToAddress(target)
    m.io.mdns.Send(bytes, 0, bytes.Count())
end sub
