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

' Outbound queue limits per connection: more than this waiting means the peer stopped reading.
function lanMaxQueuedFrames() as integer
    return 128
end function

function lanMaxQueuedBytes() as integer
    return 524288
end function

' Frames before a cast connection's hello (sealed_hello, hello) are small; a larger declared
' length closes it, so an unauthenticated peer cannot make Siku buffer a megabyte. Phone sign-in
' frames (pushServer, done, cancel) stay small too.
function lanPreHelloFrameBytes() as integer
    return 4096
end function

function lanPairFrameBytes() as integer
    return 65536
end function

' A phone sign-in connection that sends no frame this long after connecting is closed (it holds
' the only slot). Once the phone has spoken, the sign-in flow's own steps govern it.
function lanPairIdleMs() as integer
    return 30000
end function

' A queue that makes no progress for this long closes the connection.
function lanSendStallMs() as integer
    return 10000
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
    m.mdnsSentAt = {}     ' record hex -> when it was last multicast (one per second, RFC 6762 s6)
    m.mdnsSendFailures = 0
    m.mdnsIgnored = 0
    m.disc = invalid      ' the running "Find servers" scan, if any
    m.ip = deviceIp()
    loadKey()

    m.top.observeField("config", m.port)
    m.top.observeField("command", m.port)
    m.top.observeField("castState", m.port)
    m.top.observeField("discover", m.port)
    if m.top.config <> invalid then applyConfig(m.top.config)
    ' A screen can ask for a scan before this thread observes anything (ServerConnectScreen shows
    ' as the app starts), so the last request is read once here too.
    if m.top.discover <> invalid then onDiscover(m.top.discover)
    ' RemoteControl publishes the idle state before this thread observes castState: without this
    ' read, controllers got no state until a player opened.
    st = m.top.castState
    if st <> invalid and st.Count() > 0 then onCastState(st)

    while true
        msg = Wait(loopWaitMs(), m.port)
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
            else if field = "discover" then
                onDiscover(msg.GetData())
            end if
        end if
        flushAll()
        onTick()
    end while
end sub

' 250 ms when idle; at most 25 ms while a scan runs or a send queue waits (no busy loop: the
' sockets only notify on readable).
function loopWaitMs() as integer
    if m.disc <> invalid then return 25
    for each id in m.conns
        if m.conns[id].outQ.Count() > 0 then return 25
    end for
    return 250
end function

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
    ' Who may control follows the server the TV plays from (its own, or a phone's borrowed one),
    ' and needs the TV signed in with a profile; a sign-out (the login gone, not just a profile
    ' being picked) drops every controller.
    if m.io.castListener <> invalid and Lan_isTrue(old.hasLogin) and not Lan_isTrue(c.hasLogin) then
        print "[siku-lan] signed out; closing remote control connections"
        closeAll("cast", "unauthorized")
    end if
    if Str_orEmpty(old.serverId) <> Str_orEmpty(c.serverId) or Str_orEmpty(old.serverIdentity) <> Str_orEmpty(c.serverIdentity) or Lan_isTrue(old.signedIn) <> Lan_isTrue(c.signedIn) then
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

' Accepts what is pending (a few at most per event); a listener that is not readable has nothing.
sub acceptOn(listener as object, kind as string)
    for i = 1 to 4
        if not listener.IsReadable() then
            if not listener.eOK() then print "[siku-lan] " + kind + " listener error status=" + listener.Status().ToStr()
            return
        end if
        s = listener.Accept()
        if s = invalid then
            if not listener.eOK() then print "[siku-lan] " + kind + " accept failed status=" + listener.Status().ToStr()
            return
        end if
        acceptOne(s, kind)
    end for
end sub

sub acceptOne(s as object, kind as string)
    s.SetMessagePort(m.port)
    s.NotifyReadable(true)
    peer = ""
    pa = s.GetReceivedFromAddress()
    if pa <> invalid then peer = pa.GetAddress()
    m.connSeq = m.connSeq + 1
    cn = { id: "c" + m.connSeq.ToStr(), kind: kind, sock: s, frames: LanFrames_new(), openedAt: nowMs(), peer: peer
        sealedState: "none", keys: invalid, sendSeq: 0, recvSeq: 0
        didHello: false, authorized: false, authorizedAtHello: false, granted: false, features: {}, deviceId: "", deviceName: "", serverId: "", serverIdentity: ""
        passive: false, missed: 0, lastState: "", lastStateAt: 0, budgetAt: 0, budget: 0, rateNoticeAt: -100000, gotFrame: false
        outQ: [], outOff: 0, outBytes: 0, outSince: 0 }
    if kind = "pair" then
        cn.frames.max = lanPairFrameBytes()
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
        ' The refusal goes straight to the socket: this connection is never registered, so the
        ' queued senders would drop it (TvSiloCastReceiver: hello, error, close with the reason).
        ' At the sealed level nothing is sent: a plain answer to a sealed_hello reads on the phone
        ' as a refused pairing key, which would send its user to pair again.
        if not Lan_isTrue(m.cfg.sealed) then
            refusal = [tvHello(), errorMessage("too_many_controllers", "Too many devices are controlling this TV. Disconnect one and try again."), { "type": "close", "v": 2, "close": { "reason": "too_many_controllers" } }]
            for each frame in refusal
                data = Lan_frame(Lan_bytes(FormatJson(frame)))
                if s.Send(data, 0, data.Count()) <> data.Count() then exit for
            end for
        end if
        s.Close()
        return
    end if
    cn.frames.max = lanPreHelloFrameBytes()
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

' Reads what is waiting (a few reads per event). Receive runs only on a readable socket; a socket
' that is not readable and not eOK has failed. 0 bytes from a readable socket is the peer's FIN.
sub onReadable(cn as object)
    for i = 1 to 8
        if not m.conns.DoesExist(cn.id) then return
        if not cn.sock.IsReadable() then
            if not cn.sock.eOK() then closeConn(cn, "socket error " + cn.sock.Status().ToStr())
            return
        end if
        n = cn.sock.Receive(m.rxBuf, 0, 16384)
        if n <= 0 then
            if n < 0 and (cn.sock.eWouldBlock() or cn.sock.eOK()) then return
            closeConn(cn, "peer closed")
            return
        end if
        for each payload in LanFrames_append(cn.frames, Lan_slice(m.rxBuf, 0, n))
            if not m.conns.DoesExist(cn.id) then return
            onFrame(cn, payload)
        end for
        if cn.frames.failed then
            closeConn(cn, "frame too large")
            return
        end if
    end for
end sub

sub onFrame(cn as object, payload as object)
    cn.gotFrame = true
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
    cn.frames.max = Lan_maxFrameBytes()
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
        checkIp()
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
        if cn <> invalid and cn.kind = "pair" and not cn.gotFrame and now - cn.openedAt > lanPairIdleMs() then
            print "[siku-lan] phone sign-in " + cn.id + " sent nothing in " + Int(lanPairIdleMs() / 1000).ToStr() + " s; closing"
            closeConn(cn, "idle")
        end if
    end for
    mdnsTick(now)
end sub

' A DHCP renewal or a network switch can give the Roku another address: the pairing link, the
' status and the mDNS A record must follow. The 5353 socket is reopened (its group membership
' belonged to the old interface) and everything is announced again.
sub checkIp()
    ip = deviceIp()
    if ip = m.ip then return
    print "[siku-lan] address changed to " + ip
    m.ip = ip
    if m.io.mdns <> invalid then
        m.io.mdns.Close()
        m.io.mdns = invalid
        m.mdnsStatus = "off"
        m.mdnsAdvertised = []
        m.mdnsAnnounceAt = []
        m.mdnsSentAt = {}
        ensureMdns()
        refreshAdvertisement()
    end if
    publishPairingInfo()
    publishStatus()
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

' Frames go into the connection's queue and out as fast as the socket takes them: now, and on
' every loop pass after (the loop waits at most 25 ms while anything is queued). Nothing blocks
' the Task. A peer that stops reading fills the queue and is closed.
sub sendRaw(cn as object, payload as object)
    if not m.conns.DoesExist(cn.id) then return
    data = Lan_frame(payload)
    if cn.outQ.Count() >= lanMaxQueuedFrames() or cn.outBytes + data.Count() > lanMaxQueuedBytes() then
        print "[siku-lan] send queue full on " + cn.id + " (" + cn.outQ.Count().ToStr() + " frames, " + cn.outBytes.ToStr() + " bytes); closing"
        cn.outQ = []
        cn.outBytes = 0
        closeConn(cn, "send queue full")
        return
    end if
    if cn.outQ.Count() = 0 then cn.outSince = nowMs()
    cn.outQ.Push(data)
    cn.outBytes = cn.outBytes + data.Count()
    flushConn(cn, true)
end sub

' Sends what the socket accepts without waiting. With mayClose false (the last try before a
' close) a failure only stops it. Returns false when the connection was closed.
function flushConn(cn as object, mayClose as boolean) as boolean
    while cn.outQ.Count() > 0
        data = cn.outQ[0]
        k = cn.sock.Send(data, cn.outOff, data.Count() - cn.outOff)
        if k > 0 then
            cn.outOff = cn.outOff + k
            cn.outSince = nowMs()
            if cn.outOff >= data.Count() then
                cn.outQ.Shift()
                cn.outBytes = cn.outBytes - data.Count()
                cn.outOff = 0
            end if
        else if cn.sock.eWouldBlock() or cn.sock.eOK() then
            ' Not writable yet.
            if mayClose and nowMs() - cn.outSince > lanSendStallMs() then
                print "[siku-lan] send stalled on " + cn.id + "; closing"
                closeConn(cn, "send stalled")
                return false
            end if
            return true
        else
            if not mayClose then return true
            print "[siku-lan] send failed on " + cn.id + " status=" + cn.sock.Status().ToStr() + "; closing"
            cn.outQ = []
            cn.outBytes = 0
            closeConn(cn, "send failed")
            return false
        end if
    end while
    return true
end function

sub flushAll()
    for each id in connIds()
        cn = m.conns[id]
        if cn <> invalid and cn.outQ.Count() > 0 then flushConn(cn, true)
    end for
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
    ' One last try for what is queued (the `close` frame of a goodbye), then the FIN.
    if cn.outQ.Count() > 0 then flushConn(cn, false)
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

' Opens the 5353 socket the way a Roku is known to accept (ManavA/silo-roku, device evidence on a
' C208X, Roku OS 16.0.4): SO_REUSEADDR set and read back, bound to 0.0.0.0:5353 and the bound port
' read back, the group joined, multicast TTL 255 set and read back. Each step prints one
' [siku-lan] mdns step line; any failure closes the socket and marks mDNS unavailable.
sub ensureMdns()
    if m.io.mdns <> invalid or m.mdnsStatus = "unavailable" then return
    wanted = m.io.castListener <> invalid or m.io.pairListener <> invalid or m.disc <> invalid
    if not wanted then return
    d = CreateObject("roDatagramSocket")
    if d = invalid then
        m.mdnsStatus = "unavailable"
        print "[siku-lan] mdns: roDatagramSocket unavailable"
        return
    end if
    d.SetMessagePort(m.port)
    reuse = d.SetReuseAddr(true)
    try
        reuse = d.GetReuseAddr()
    catch e
        ' brs-engine registers GetReuseAddr under another name; the setter's answer stands there.
        print "[siku-lan] mdns step reuse: GetReuseAddr unavailable (" + Str_orEmpty(e.message) + ")"
    end try
    print "[siku-lan] mdns step reuse=" + Lan_boolText(reuse)
    bindAddr = CreateObject("roSocketAddress")
    bound = false
    boundPort = 0
    if reuse and bindAddr.SetAddress("0.0.0.0:5353") then bound = d.SetAddress(bindAddr)
    if bound then
        actual = d.GetAddress()
        if actual <> invalid then boundPort = actual.GetPort()
        bound = boundPort = 5353
    end if
    print "[siku-lan] mdns step bind 0.0.0.0:5353 ok=" + Lan_boolText(bound) + " port=" + boundPort.ToStr() + " status=" + d.Status().ToStr()
    m.mdnsGroup = CreateObject("roSocketAddress")
    joined = false
    if bound and m.mdnsGroup.SetAddress("224.0.0.251:5353") then joined = d.JoinGroup(m.mdnsGroup)
    if bound then print "[siku-lan] mdns step join 224.0.0.251 ok=" + Lan_boolText(joined)
    ttlOk = false
    if joined and d.SetMulticastTTL(255) then ttlOk = d.GetMulticastTTL() = 255
    if joined then print "[siku-lan] mdns step ttl 255 ok=" + Lan_boolText(ttlOk)
    print "[siku-lan] mdns bind 5353 reuse=" + Lan_boolText(reuse) + " bound=" + Lan_boolText(bound) + " joined=" + Lan_boolText(joined) + " ttl=" + Lan_boolText(ttlOk) + " status=" + d.Status().ToStr()
    if not ttlOk then
        ' Another responder owns the port without sharing it, or multicast is refused. Phones
        ' then find Siku through the QR code's pairing link only, and Find servers says so.
        d.Close()
        m.mdnsStatus = "unavailable"
        return
    end if
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
        if m.disc <> invalid then discoverTick(now)
        return
    end if
    ' Receive notifications can coalesce (the simulator reports several datagrams as one event).
    if m.io.mdns.IsReadable() then onMdnsReadable()
    if m.mdnsAnnounceAt.Count() > 0 and now >= m.mdnsAnnounceAt[0] then
        m.mdnsAnnounceAt.Shift()
        if m.mdnsAdvertised.Count() > 0 then
            ann = Mdns_announcement(m.mdnsAdvertised, mdnsHost(), m.ip, 4500)
            if mdnsSend(ann, invalid) then print "[siku-lan] mdns announced " + m.mdnsAdvertised.Count().ToStr() + " service(s) as " + mdnsHost() + " " + m.ip
        end if
    end if
    if m.disc <> invalid then discoverTick(now)
    ' Forget multicast times older than the one-second window.
    if m.mdnsSentAt.Count() > 64 then
        keep = {}
        for each k in m.mdnsSentAt
            if now - m.mdnsSentAt[k] < 1000 then keep[k] = m.mdnsSentAt[k]
        end for
        m.mdnsSentAt = keep
    end if
end sub

' Reads every waiting datagram (at most 16 per call). Only a readable socket is read.
sub onMdnsReadable()
    for i = 1 to 16
        if m.io.mdns = invalid then return
        if not m.io.mdns.IsReadable() then
            if not m.io.mdns.eOK() then print "[siku-lan] mdns socket status=" + m.io.mdns.Status().ToStr()
            return
        end if
        buf = CreateObject("roByteArray")
        buf[9000] = 0
        n = m.io.mdns.Receive(buf, 0, 9001)
        if n <= 0 then return
        from = m.io.mdns.GetReceivedFromAddress()
        host = ""
        port = 0
        if from <> invalid then
            parts = Str_orEmpty(from.GetAddress()).Split(":")
            if parts.Count() = 2 then host = parts[0]
            port = from.GetPort()
        end if
        if n > 9000 then
            if m.disc <> invalid then m.disc.oversized = m.disc.oversized + 1
        else
            onMdnsPacket(Lan_slice(buf, 0, n), host, port, from)
        end if
    end for
end sub

sub onMdnsPacket(packet as object, host as string, port as integer, from as dynamic)
    if packet.Count() < 12 then return
    isResponse = (packet[2] and &h80) <> 0
    if isResponse then
        if m.disc <> invalid then
            m.disc.received = m.disc.received + 1
            selfIp = ""
            if m.disc.allowSelf then selfIp = m.ip
            m.disc.state = LanDisc_reduce(m.disc.state, packet, host, port, nowMs() - m.disc.startedAt, selfIp)
            discoverPublish("scanning", false)
        end if
        return
    end if
    query = Mdns_parse(packet)
    if query = invalid then return
    asksUnicast = false
    for each q in query.questions
        if q.unicast then asksUnicast = true
    end for
    ' A query from another port is a one-shot (legacy) resolver; it is answered only when it asks
    ' for a unicast reply, and then only to it.
    if port <> 5353 and not asksUnicast then
        m.mdnsIgnored = m.mdnsIgnored + 1
        if m.mdnsIgnored <= 3 then print "[siku-lan] mdns ignored a query from port " + port.ToStr()
        return
    end if
    resp = Mdns_respond(query, m.mdnsAdvertised, mdnsHost(), m.ip)
    if resp = invalid then return
    if asksUnicast then
        if from <> invalid then mdnsSend(resp.bytes, from)
    else
        ' Each record goes out by multicast at most once a second (RFC 6762 section 6).
        now = nowMs()
        answers = []
        for each r in resp.answers
            if not m.mdnsSentAt.DoesExist(r) or now - m.mdnsSentAt[r] >= 1000 then answers.Push(r)
        end for
        if answers.Count() = 0 then return
        additionals = []
        for each r in resp.additionals
            if not m.mdnsSentAt.DoesExist(r) or now - m.mdnsSentAt[r] >= 1000 then additionals.Push(r)
        end for
        mdnsSend(Mdns_message(answers, additionals), invalid)
        for each r in answers
            m.mdnsSentAt[r] = now
        end for
        for each r in additionals
            m.mdnsSentAt[r] = now
        end for
    end if
    m.mdnsAnswered = m.mdnsAnswered + 1
    if m.mdnsAnswered <= 5 or m.mdnsAnswered mod 50 = 0 then
        print "[siku-lan] mdns answered query #" + m.mdnsAnswered.ToStr() + " from " + host + ":" + port.ToStr() + " unicast=" + Lan_boolText(asksUnicast)
    end if
end sub

' Sends one datagram; true when the socket took every byte. target invalid = the mDNS group.
function mdnsSend(bytes as object, target as dynamic) as boolean
    if m.io.mdns = invalid then return false
    if target = invalid then target = m.mdnsGroup
    m.io.mdns.SetSendToAddress(target)
    sent = m.io.mdns.Send(bytes, 0, bytes.Count())
    if sent = bytes.Count() then return true
    m.mdnsSendFailures = m.mdnsSendFailures + 1
    if m.mdnsSendFailures <= 5 or m.mdnsSendFailures mod 50 = 0 then
        print "[siku-lan] mdns send #" + m.mdnsSendFailures.ToStr() + " incomplete: " + sent.ToStr() + "/" + bytes.Count().ToStr() + " status=" + m.io.mdns.Status().ToStr()
    end if
    return false
end function

' ---------- Find servers on this network (_silo._tcp) ----------

' The `discover` field: {kind: "start", token, allowSelf} or {kind: "stop"}.
sub onDiscover(c as dynamic)
    if Type(c) <> "roAssociativeArray" then return
    k = Str_orEmpty(c.kind)
    if k = "start" then
        discoverStart(c)
    else if k = "stop" then
        discoverStop()
    end if
end sub

' {token, allowSelf}: a five-second scan from the 5353 socket; the query goes out at 0, 1 and 3 s,
' answers are read strictly (LanDiscovery.brs) and published on `discovery` as they arrive.
sub discoverStart(c as object)
    if m.disc <> invalid then discoverPublish("cancelled", true)
    ' A scan is a reason to try the socket again even if an earlier bind failed.
    if m.mdnsStatus = "unavailable" and m.io.mdns = invalid then m.mdnsStatus = "off"
    m.disc = { token: Str_orEmpty(c.token), startedAt: nowMs(), sent: 0, received: 0, oversized: 0, state: LanDisc_new(0), allowSelf: Lan_isTrue(c.allowSelf), lastJson: "", query: Lan_hexBytes(LanDisc_queryHex()) }
    ensureMdns()
    print "[siku-lan] discovery started (mdns " + m.mdnsStatus + ")"
    if m.io.mdns = invalid then
        discoverPublish("unavailable", true)
        return
    end if
    if m.mdnsAdvertised.Count() = 0 then refreshAdvertisement()
    discoverPublish("scanning", true)
    discoverTick(nowMs())
end sub

sub discoverStop()
    if m.disc = invalid then return
    print "[siku-lan] discovery stopped"
    m.disc = invalid
end sub

sub discoverTick(now as integer)
    d = m.disc
    if d = invalid then return
    if m.io.mdns = invalid then
        discoverPublish("unavailable", true)
        return
    end if
    elapsed = now - d.startedAt
    schedule = LanDisc_schedule()
    if d.sent < schedule.Count() and elapsed >= schedule[d.sent] then
        if not mdnsSend(d.query, invalid) then
            discoverPublish("unavailable", true)
            return
        end if
        d.sent = d.sent + 1
    end if
    if elapsed >= LanDisc_scanMs() or d.state.closed then
        d.state = LanDisc_advance(d.state, elapsed)
        discoverPublish("complete", true)
    end if
end sub

' Publishes the scan to the screen when its list changed (or with force). Any status but
' "scanning" is the scan's last word and ends it.
sub discoverPublish(status as string, force as boolean)
    d = m.disc
    if d = invalid then return
    final = status <> "scanning"
    servers = []
    if status <> "unavailable" then servers = LanDisc_servers(d.state.candidates)
    out = { token: d.token, status: status, servers: servers, sent: d.sent, received: d.received }
    j = FormatJson(servers)
    if not force and not final and j = d.lastJson then return
    d.lastJson = j
    if final then
        print "[siku-lan] discovery " + status + ": " + servers.Count().ToStr() + " server(s), queries=" + d.sent.ToStr() + " packets=" + d.received.ToStr() + " oversized=" + d.oversized.ToStr() + " conflicts=" + d.state.conflicts.Count().ToStr()
        m.disc = invalid
    end if
    m.top.discovery = out
end sub
