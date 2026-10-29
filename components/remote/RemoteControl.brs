' RemoteControl: the SiloCast receiver's decisions (see RemoteControl.xml).
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.prefs = RemotePrefs_load()
    m.ready = {}           ' conn -> "own" | borrowed generation: may launch next
    m.controllers = {}     ' conn -> controller info from the hello
    m.greeted = {}         ' device ids already announced on screen this run
    m.handoff = invalid    ' the one in-flight full handoff
    m.borrowed = invalid   ' the phone identity Siku plays on, if any
    m.ownSession = invalid ' the Roku's own session while one is borrowed
    m.activation = invalid ' an approved handoff waiting for the old player to close
    m.lastOwnServer = ""
    m.pollTimer = m.top.findNode("pollTimer")
    m.pollTimer.observeField("fire", "onPollTimer")
    m.endTimer = m.top.findNode("endTimer")
    m.endTimer.observeField("fire", "onEndTimer")
    m.activateTimer = m.top.findNode("activateTimer")
    m.activateTimer.observeField("fire", "onActivateTimer")
    m.addrTimer = m.top.findNode("addrTimer")
    m.addrTimer.observeField("fire", "onAddrTimer")
    m.identityAsked = ""   ' the own server whose identity this listener start already asked for

    m.task = CreateObject("roSGNode", "LanTask")
    if not m.global.hasField("castPlayer") then m.global.addField("castPlayer", "node", false)
    m.global.addFields({ lanTask: m.task, remoteControl: m.top })
    m.task.observeField("castEvent", "onCastEvent")
    m.global.observeField("sessionChanged", "onSessionChanged")
    m.global.observeField("castPlayer", "onCastPlayer")
    m.lastOwnServer = Str_orEmpty(m.global.session.serverUrl)
    pushConfig()
    m.task.castState = RemoteState_idle()
    m.task.control = "RUN"
    recordOwnIdentity()
end sub

' ---------- Config for the LanTask ----------

function deviceName() as string
    di = CreateObject("roDeviceInfo")
    name = di.GetFriendlyName()
    if name = invalid or name = "" then name = "Roku " + di.GetModelDisplayName()
    return name
end function

sub pushConfig()
    s = m.global.session
    pairing = m.top.pairing
    if pairing = invalid then pairing = { mode: "" }
    serverUrl = Str_orEmpty(s.serverUrl)
    serverId = ""
    if serverUrl <> "" then serverId = Lan_serverIdFor(serverUrl)
    serverName = Str_orEmpty(s.serverName)
    if m.borrowed <> invalid then
        ' The phone's own registry key: the URL it sent, exactly.
        serverId = m.borrowed.serverId
        if not Str_isEmpty(m.borrowed.serverName) then serverName = m.borrowed.serverName
    end if
    m.task.config = {
        castEnabled: m.prefs.enabled
        sealed: m.prefs.sealed
        deviceId: Str_orEmpty(s.deviceId)
        deviceName: deviceName()
        serverId: serverId
        serverName: serverName
        serverIdentity: Str_orEmpty(s.serverId)
        signedIn: not Str_isEmpty(s.accessToken) and not Str_isEmpty(s.profileId)
        hasLogin: not Str_isEmpty(s.accessToken)
        playing: m.global.castPlayer <> invalid
        pairing: pairing
    }
end sub

sub onReloadPrefs()
    wasEnabled = m.prefs.enabled
    m.prefs = RemotePrefs_load()
    pushConfig()
    ' A listener start: an identity that could not be read last time is tried again.
    if m.prefs.enabled and not wasEnabled then
        m.identityAsked = ""
        recordOwnIdentity()
    end if
end sub

' ---------- The own server's identity (Silo Android #717) ----------

' Phones on another address of this server find the Roku by the deployment identity it
' advertises (mDNS TXT `serverIdentity`, the hello). Sessions saved by older Siku builds (and a
' server whose identity read failed at connect) have none: read it once per listener start, save
' it on the session (and the remembered server), and the next config re-advertises. An
' unreachable server is tried again on the next listener start.
function ownSession() as dynamic
    if m.borrowed <> invalid then return m.ownSession
    s = m.global.session
    if s = invalid or Lan_isTrue(s.temporary) then return invalid
    return s
end function

sub recordOwnIdentity()
    if not m.prefs.enabled then return
    s = ownSession()
    if s = invalid then return
    url = Str_orEmpty(s.serverUrl)
    if url = "" or Lan_isServerId(s.serverId) or url = m.identityAsked then return
    m.identityAsked = url
    print "[siku-cast] reading the server identity (none recorded)"
    Api_call({ method: "GET", path: "/api/v2/system/identity", baseUrl: url, auth: false, profile: false, timeout: 8, context: { url: url } }, "onOwnIdentity")
end sub

sub onOwnIdentity(event as object)
    resp = Api_result(event)
    url = ""
    if resp.context <> invalid then url = Str_orEmpty(resp.context.url)
    answer = HandoffAddr_classify(resp)
    if answer.state <> "identity" then
        print "[siku-cast] server identity not recorded (" + answer.state + " status=" + Str_orEmpty(resp.status) + "); trying again at the next start"
        return
    end if
    s = ownSession()
    if s = invalid or Str_orEmpty(s.serverUrl) <> url or Lan_isServerId(s.serverId) then return
    if m.borrowed <> invalid then
        ' The phone's profile is in use: record it on the Roku's own session for the hand-back
        ' (a Session_save now would end the borrowed profile).
        m.ownSession.serverId = answer.id
        Registry_write("session", m.ownSession)
        Session_rememberServer(m.ownSession)
        print "[siku-cast] recorded server identity"
        return
    end if
    c = AA_copy(s)
    c.serverId = answer.id
    print "[siku-cast] recorded server identity"
    Session_save(c) ' onSessionChanged pushes the config: LanTask re-advertises with it
end sub

sub onSessionChanged()
    s = m.global.session
    if m.borrowed <> invalid then
        if Lan_isTrue(s.temporary) then
            if Str_isEmpty(s.accessToken) then
                ' Sign Out on the phone's profile: the Roku signs out, its own account does not
                ' come back when the identity ends.
                endBorrowedBySignOut()
                pushConfig()
                return
            end if
            ' A token refresh of the borrowed session: logout must use the current token.
            if Str_orEmpty(s.serverUrl) = m.borrowed.serverUrl then
                m.borrowed.accessToken = Str_orEmpty(s.accessToken)
                m.borrowed.session = s
            end if
        else if isOwnRefresh(s) then
            ' A refresh of the Roku's own tokens that finished after the phone's profile went in:
            ' keep it for the hand-back and put the borrowed session back.
            m.ownSession = s
            Session_save(m.borrowed.session)
            pushConfig()
            return
        else
            ' Change server or another sign-in replaced the Roku's own session (Android ends the
            ' borrowed identity when the active server changes). Nothing old is restored.
            print "[siku-cast] the TV's own session changed; ending the borrowed profile"
            endBorrowedIdentity(true)
        end if
    end if
    if not Lan_isTrue(s.temporary) then
        own = Str_orEmpty(s.serverUrl)
        if own <> m.lastOwnServer then
            ' Hellos were judged against the previous server.
            m.lastOwnServer = own
            m.task.command = { kind: "castCloseAll", reason: "unauthorized" }
            m.ready = {}
        end if
    end if
    pushConfig()
    recordOwnIdentity()
end sub

function isOwnRefresh(s as object) as boolean
    own = m.ownSession
    if own = invalid or Str_isEmpty(s.accessToken) then return false
    if Str_orEmpty(s.serverUrl) <> Str_orEmpty(own.serverUrl) or Str_orEmpty(s.profileId) <> Str_orEmpty(own.profileId) then return false
    return sessionUserId(s) = sessionUserId(own)
end function

function sessionUserId(s as object) as string
    if s.user = invalid or Type(s.user) <> "roAssociativeArray" then return ""
    return Str_orEmpty(s.user.id)
end function

' Sign Out while the phone's profile plays: end it, then sign the Roku's own account out too
' (best-effort logout with its own token), keeping its server, as a Sign Out on it would.
sub endBorrowedBySignOut()
    print "[siku-cast] signed out on the phone's profile; ending it and signing the TV out"
    own = endBorrowedIdentity(true)
    if own = invalid then return
    if not Str_isEmpty(own.accessToken) and not Str_isEmpty(own.serverUrl) then
        Api_call({ method: "POST", path: "/api/v2/auth/logout", baseUrl: Str_orEmpty(own.serverUrl), auth: false, profile: false, headers: { Authorization: "Bearer " + Str_orEmpty(own.accessToken) }, timeout: 5 }, "Api_onFired")
    end if
    own.temporary = false
    Session_signOutLocal(own)
end sub

sub onDisconnectAll()
    print "[siku-cast] disconnect on the TV"
    m.task.command = { kind: "castCloseActive" }
end sub

' ---------- Sending ----------

sub castSend(conn as string, message as object)
    m.task.command = { kind: "castSend", conn: conn, message: message }
end sub

sub castError(conn as string, code as string, text as string)
    castSend(conn, { "type": "error", "v": 2, "error": { "code": code, "message": text } })
end sub

sub handoffCancel(conn as string, requestId as string, reason as string, text as string)
    print "[siku-cast] handoff refused: " + reason
    castSend(conn, { "type": "handoff_cancel", "v": 2, "handoffCancel": { "requestId": requestId, "reason": reason, "message": text } })
end sub

function isoIn(seconds as integer) as string
    d = CreateObject("roDateTime")
    d.FromSeconds(d.AsSeconds() + seconds)
    return d.ToISOString()
end function

' ---------- Events from the LanTask ----------

sub onCastEvent(event as object)
    e = event.getData()
    if e = invalid then return
    kind = Str_orEmpty(e["type"])
    conn = Str_orEmpty(e.conn)
    if kind = "hello" then
        onHello(conn, e.controller)
    else if kind = "offer" then
        onOffer(conn, e.offer, e.controller)
    else if kind = "handoffCancel" then
        onHandoffCancel(conn, e.cancel)
    else if kind = "launch" then
        onLaunch(conn, e.launch, e.controller)
    else if kind = "control" then
        onControl(conn, e.control)
    else if kind = "closed" then
        onClosed(conn)
    end if
end sub

sub onHello(conn as string, c as object)
    m.controllers[conn] = c
    if not Lan_isTrue(c.authorized) or Lan_isTrue(c.passive) then return
    id = Str_orEmpty(c.deviceId)
    if m.greeted.DoesExist(id) or m.global.castPlayer <> invalid then return
    m.greeted[id] = true
    name = Str_orEmpty(c.deviceName)
    if name = "" then name = "A phone"
    m.global.toast = name + " can now control Siku"
end sub

sub onClosed(conn as string)
    m.ready.Delete(conn)
    m.controllers.Delete(conn)
    if m.handoff <> invalid and m.handoff.conn = conn then abandonHandoff("controller left")
    b = m.borrowed
    if b <> invalid and b.connId = conn then
        b.connId = ""
        ' Playback outlives a lost socket; with nothing playing the profile goes back shortly.
        if m.global.castPlayer = invalid then scheduleEnd(5)
    end if
end sub

' ---------- Handoff (TvSiloCastReceiver.handleOffer) ----------

sub onOffer(conn as string, offer as object, c as object)
    requestId = Str_orEmpty(offer.requestId)
    s = m.global.session
    serverUrl = Lan_trimUrl(offer.serverURL)
    profileId = Str_orEmpty(offer.profileId)
    if serverUrl = "" or profileId = "" or Lan_serverIdFor(serverUrl) <> Str_orEmpty(offer.serverId) then
        handoffCancel(conn, requestId, "handoff_failed", "The phone sent an invalid server or profile.")
        return
    end if
    if m.activation <> invalid then
        handoffCancel(conn, requestId, "launch_pending", "The TV is still starting the last title. Try again in a moment.")
        return
    end if
    m.ready.Delete(conn)
    ' A newer offer replaces one in flight from another controller.
    if m.handoff <> invalid then
        old = m.handoff
        abandonHandoff("superseded")
        if old.conn <> conn then
            who = Str_orEmpty(c.deviceName)
            if who = "" then who = "Another device"
            handoffCancel(old.conn, old.requestId, "superseded", who + " started playing on this TV.")
        end if
    end if
    ' Own identity: the phone's hello matched this Roku's server and it offers the profile Siku
    ' plays as (RemotePlaybackOwnIdentityPolicy).
    signedIn = not Str_isEmpty(s.accessToken) and not Str_isEmpty(s.profileId)
    if m.borrowed = invalid and signedIn and Lan_isTrue(c.authorizedAtHello) and Str_orEmpty(s.profileId) = profileId and Lan_serversMatch(offer.serverId, offer.serverIdentity, Lan_serverIdFor(s.serverUrl), s.serverId) then
        m.ready[conn] = "own"
        print "[siku-cast] handoff skipped: phone offers this Roku's own profile"
        castSend(conn, { "type": "handoff_ready", "v": 2, "handoffReady": { "requestId": requestId, "serverId": Str_orEmpty(offer.serverId), "profileId": profileId, "sessionExpiresAt": isoIn(86400), "reused": true } })
        return
    end if
    ' Reuse of the borrowed identity: the connection that installed it, or its resume token.
    b = m.borrowed
    if b <> invalid and b.serverId = Str_orEmpty(offer.serverId) and b.profileId = profileId and b.controllerDeviceId = Str_orEmpty(c.deviceId) then
        tokenOk = b.resumeToken <> "" and Lan_bytesEqual(Lan_bytes(Str_orEmpty(offer.resumeToken)), Lan_bytes(b.resumeToken))
        if b.connId = conn or tokenOk then
            m.endTimer.control = "stop"
            b.connId = conn
            m.ready[conn] = b.generation
            m.task.command = { kind: "castAuthorize", conn: conn, authorized: true }
            print "[siku-cast] handoff reused the borrowed profile"
            castSend(conn, readyMessage(requestId, b, true, c))
            return
        end if
    end if
    startFullHandoff(conn, offer, c)
end sub

function readyMessage(requestId as string, b as object, reused as boolean, c as object) as object
    r = { "requestId": requestId, "serverId": b.serverId, "profileId": b.profileId, "sessionExpiresAt": b.expiresAt, "reused": reused }
    if c <> invalid and c.features <> invalid and c.features.DoesExist("resume_token") and b.resumeToken <> "" then r["resumeToken"] = b.resumeToken
    return { "type": "handoff_ready", "v": 2, "handoffReady": r }
end function

sub startFullHandoff(conn as string, offer as object, c as object)
    m.handoffGen = Int(Num_or(m.handoffGen, 0)) + 1
    ' base: where the handoff runs, chosen by resolveHandoffAddress before the first request.
    m.handoff = { conn: conn, requestId: Str_orEmpty(offer.requestId), offer: offer, controller: c, base: "", gen: m.handoffGen, deviceCode: "", interval: 3, deadline: 0, probes: invalid, answers: invalid }
    who = Str_orEmpty(c.deviceName)
    if who = "" then who = "your phone"
    title = Str_orEmpty(offer.title)
    if title <> "" then
        m.global.toast = "Starting " + title + " from " + who
    else
        m.global.toast = "Getting ready for " + who
    end if
    resolveHandoffAddress()
end sub

' ---------- The handoff's server address (Silo Android #716; HandoffAddress.brs) ----------

' With the phone's deployment identity, every candidate address is probed at once and the first,
' in order, that reports that identity from here is used, so a Roku signed in over the LAN stays
' on the LAN while the phone uses a public address. Without one, the phone's address as before.
' The handoff still names the phone's server id (offer.serverId).
sub resolveHandoffAddress()
    h = m.handoff
    plan = HandoffAddr_plan(h.offer, ownSession(), Session_savedServers())
    if plan.expected = "" then
        print "[siku-cast] handoff address phone (tried 0)"
        runHandoffAt(plan.offered)
        return
    end if
    probes = plan.candidates
    h.probes = probes
    h.answers = []
    for i = 0 to probes.Count() - 1
        h.answers.Push(invalid)
    end for
    print "[siku-cast] full handoff: checking " + probes.Count().ToStr() + " address(es) for the phone's server"
    for i = 0 to probes.Count() - 1
        Api_call({ method: "GET", path: "/api/v2/system/identity", baseUrl: probes[i].url, auth: false, profile: false, timeout: HandoffAddr_probeTimeout(), context: { gen: h.gen, probe: i } }, "onHandoffProbe")
    end for
    m.addrTimer.control = "stop"
    m.addrTimer.duration = HandoffAddr_budgetSeconds()
    m.addrTimer.control = "start"
    judgeHandoffAddress(false)
end sub

sub onHandoffProbe(event as object)
    resp = Api_result(event)
    if not handoffCurrent(resp) then return
    h = m.handoff
    if h.probes = invalid then return ' already decided
    i = Int(Num_or(resp.context.probe, -1))
    if i < 0 or i >= h.answers.Count() then return
    h.answers[i] = HandoffAddr_classify(resp)
    judgeHandoffAddress(false)
end sub

sub onAddrTimer()
    h = m.handoff
    if h = invalid or h.probes = invalid then return
    judgeHandoffAddress(true)
end sub

sub judgeHandoffAddress(final as boolean)
    h = m.handoff
    offered = Lan_trimUrl(h.offer.serverURL)
    r = HandoffAddr_judge(h.probes, h.answers, offered, Str_orEmpty(h.offer.serverIdentity).Trim(), final)
    if not r.done then return
    tried = h.probes.Count().ToStr()
    h.probes = invalid
    h.answers = invalid
    m.addrTimer.control = "stop"
    if r.url <> "" then
        print "[siku-cast] handoff address " + r.kind + " (tried " + tried + ")"
        runHandoffAt(r.url)
    else if r.failure = "mismatch" then
        print "[siku-cast] handoff address refused: another server answered at the phone's address (tried " + tried + ")"
        failHandoff("The phone's server address reached a different Silo server.")
    else
        print "[siku-cast] handoff address none (tried " + tried + ")"
        name = Str_orEmpty(h.offer.serverName).Trim()
        if name = "" then name = "the phone's server"
        failHandoff("This TV can't reach " + name + ".")
    end if
end sub

sub runHandoffAt(base as string)
    m.handoff.base = base
    print "[siku-cast] full handoff: checking the phone's server"
    Api_call({ method: "GET", path: "/api/v2/auth/device/capability", baseUrl: base, auth: false, profile: false, timeout: 8, context: { gen: m.handoff.gen } }, "onHandoffCapability")
end sub

function handoffCurrent(resp as object) as boolean
    return m.handoff <> invalid and resp.context <> invalid and resp.context.gen = m.handoff.gen
end function

sub failHandoff(text as string)
    h = m.handoff
    if h = invalid then return
    m.handoff = invalid
    m.pollTimer.control = "stop"
    m.addrTimer.control = "stop"
    handoffCancel(h.conn, h.requestId, "handoff_failed", text)
end sub

sub onHandoffCapability(event as object)
    resp = Api_result(event)
    if not handoffCurrent(resp) then return
    d = resp.data
    supported = false
    if resp.ok and Type(d) = "roAssociativeArray" and Lan_isTrue(d.remote_playback_handoff) then
        for each v in Arr_or(d.protocol_versions)
            if Num_or(v, 0) = 2 then supported = true
        end for
    end if
    if not supported then
        failHandoff("The phone's Silo server does not support remote playback handoff.")
        return
    end if
    body = { device_name: deviceName(), device_platform: "roku", client_purpose: "remote_playback", temporary: true }
    Api_call({ method: "POST", path: "/api/v2/auth/device/start", baseUrl: m.handoff.base, body: body, auth: false, profile: false, timeout: 15, context: { gen: m.handoff.gen } }, "onHandoffStart")
end sub

sub onHandoffStart(event as object)
    resp = Api_result(event)
    if not handoffCurrent(resp) then return
    d = resp.data
    if not resp.ok or Type(d) <> "roAssociativeArray" or Str_isEmpty(d.device_code) then
        failHandoff("The TV could not start the remote playback handoff.")
        return
    end if
    if Str_orEmpty(d.client_purpose) <> "remote_playback" or not Lan_isTrue(d.temporary) then
        failHandoff("The server did not create a temporary remote playback session.")
        return
    end if
    h = m.handoff
    h.deviceCode = Str_orEmpty(d.device_code)
    interval = Int(Num_or(d.interval, 3))
    if interval < 1 then interval = 3
    h.interval = interval
    expiresIn = Int(Num_or(d.expires_in, 600))
    if expiresIn < 1 then expiresIn = 600
    h.deadline = Time_nowSeconds() + expiresIn
    print "[siku-cast] full handoff: challenge sent; waiting for the phone to approve"
    castSend(h.conn, { "type": "handoff_challenge", "v": 2, "handoffChallenge": { "requestId": h.requestId, "userCode": Str_orEmpty(d.user_code), "matchCode": Str_orEmpty(d.match_code), "expiresAt": Str_orEmpty(d.expires_at) } })
    pollHandoff()
end sub

sub pollHandoff()
    h = m.handoff
    if h = invalid then return
    if Time_nowSeconds() >= h.deadline then
        failHandoff("Remote playback handoff expired.")
        return
    end if
    Api_call({ method: "POST", path: "/api/v2/auth/device/poll", baseUrl: h.base, body: { device_code: h.deviceCode }, auth: false, profile: false, timeout: 15, context: { gen: h.gen } }, "onHandoffPoll")
end sub

sub onPollTimer()
    pollHandoff()
end sub

sub onHandoffPoll(event as object)
    resp = Api_result(event)
    if not handoffCurrent(resp) then return
    h = m.handoff
    d = resp.data
    if not resp.ok or Type(d) <> "roAssociativeArray" then
        if resp.status = 404 then
            failHandoff("Remote playback handoff expired.")
        else
            failHandoff("Pairing status could not be confirmed. Start pairing again.")
        end if
        return
    end if
    st = LCase(Str_orEmpty(d.status))
    if st = "pending" then
        wait = Int(Num_or(d.poll_after, h.interval))
        if wait < 1 then wait = 1
        m.pollTimer.duration = wait
        m.pollTimer.control = "start"
    else if st = "approved" then
        tokens = d.tokens
        if Type(tokens) <> "roAssociativeArray" then tokens = d
        access = Str_orEmpty(tokens.access_token)
        refresh = Str_orEmpty(tokens.refresh_token)
        profileId = Str_orEmpty(d.profile_id)
        profileToken = Str_orEmpty(d.profile_token)
        if access = "" or refresh = "" or profileId = "" then
            failHandoff("The approved remote session omitted its credentials.")
            return
        end if
        if not Lan_isTrue(d.temporary) or profileId <> Str_orEmpty(h.offer.profileId) then
            failHandoff("The server approved a different or non-temporary profile.")
            return
        end if
        expiresAt = Str_orEmpty(d.session_expires_at)
        if expiresAt = "" then expiresAt = isoIn(86400)
        m.handoff = invalid
        approved = { handoff: h, access: access, refresh: refresh, expiresIn: Int(Num_or(tokens.expires_in, 3600)), profileId: profileId, profileToken: profileToken, expiresAt: expiresAt }
        print "[siku-cast] full handoff approved"
        beginActivation(approved)
    else if st = "denied" then
        failHandoff("Remote playback handoff was denied.")
    else if st = "expired" or st = "consumed" then
        failHandoff("Remote playback handoff expired.")
    else
        failHandoff("The server returned an unknown remote playback status.")
    end if
end sub

sub onHandoffCancel(conn as string, cancel as object)
    h = m.handoff
    if h <> invalid and h.conn = conn and h.requestId = Str_orEmpty(cancel.requestId) then abandonHandoff("controller cancelled")
    m.ready.Delete(conn)
end sub

' Stops polling and withdraws the code on the server (best effort).
sub abandonHandoff(why as string)
    h = m.handoff
    if h = invalid then return
    m.handoff = invalid
    m.pollTimer.control = "stop"
    m.addrTimer.control = "stop"
    print "[siku-cast] handoff abandoned (" + why + ")"
    if h.deviceCode <> "" then Api_call({ method: "POST", path: "/api/v2/auth/device/cancel", baseUrl: h.base, body: { device_code: h.deviceCode }, auth: false, profile: false, timeout: 5 }, "Api_onFired")
end sub

' An approved handoff stops what plays first, so that player's session closes under the identity
' it started with; the new identity goes in once the player is gone (or after 8 s).
sub beginActivation(approved as object)
    m.activation = approved
    player = m.global.castPlayer
    if player <> invalid then
        player.remoteCommand = { name: "stop" }
        ' 8 s for the player to close (onCastPlayer shortens it to 1.5 s once it has).
        m.activateTimer.control = "stop"
        m.activateTimer.duration = 8
        m.activateTimer.control = "start"
    else
        activateBorrowed()
    end if
end sub

sub onActivateTimer()
    if m.activation <> invalid then activateBorrowed()
end sub

sub activateBorrowed()
    a = m.activation
    if a = invalid then return
    m.activation = invalid
    m.activateTimer.control = "stop"
    h = a.handoff
    if m.borrowed <> invalid then restoreOwn(true)
    own = AA_copy(m.global.session)
    m.ownSession = own
    offer = h.offer
    t = AA_copy(own)
    t.serverUrl = Url_normalize(h.base)
    t.serverOrigin = Url_origin(t.serverUrl)
    t.serverId = Str_orEmpty(offer.serverIdentity).Trim()
    if not Lan_isServerId(t.serverId) then t.serverId = ""
    t.serverName = Str_orEmpty(offer.serverName)
    if t.serverName = "" then t.serverName = Url_host(t.serverUrl)
    t.accessToken = a.access
    t.refreshToken = a.refresh
    if a.expiresIn < 60 then a.expiresIn = 3600
    t.expiresAt = Time_nowSeconds() + a.expiresIn
    t.user = {}
    t.profileId = a.profileId
    t.profileToken = a.profileToken
    t.profileName = Str_orEmpty(offer.profileName)
    t.profileAvatar = ""
    t.temporary = true
    c = h.controller
    resume = ""
    if c <> invalid and c.features <> invalid and c.features.DoesExist("resume_token") then resume = Lan_base64url(Lan_bytes(CreateObject("roDeviceInfo").GetRandomUUID() + CreateObject("roDeviceInfo").GetRandomUUID()))
    ' serverUrl/accessToken: the borrowed session's own, so its logout never uses the Roku's.
    m.borrowed = { generation: CreateObject("roDeviceInfo").GetRandomUUID(), serverId: Str_orEmpty(offer.serverId), serverName: Str_orEmpty(offer.serverName), profileId: a.profileId, connId: h.conn, controllerDeviceId: Str_orEmpty(c.deviceId), resumeToken: resume, expiresAt: a.expiresAt, serverUrl: t.serverUrl, accessToken: a.access, session: t }
    Session_forgetPlaybackCaps()
    Session_save(t) ' temporary: published, never written to the registry
    m.ready[h.conn] = m.borrowed.generation
    m.task.command = { kind: "castAuthorize", conn: h.conn, authorized: true }
    print "[siku-cast] playing as the phone's profile (borrowed, not saved)"
    castSend(h.conn, readyMessage(h.requestId, m.borrowed, false, c))
    if m.global.castPlayer = invalid then scheduleEnd(600)
end sub

' Hands the borrowed identity back: best-effort logout of the temporary session, then the
' Roku's own session again.
sub restoreOwn(logout as boolean)
    if m.borrowed = invalid then return
    own = endBorrowedIdentity(logout)
    if own <> invalid then Session_save(own)
    print "[siku-cast] borrowed profile handed back"
end sub

' Ends the borrowed identity (best-effort logout with the borrowed session's own token, never
' the Roku's) and its readiness and grant, and returns the Roku's own session snapshot (or
' invalid) for the caller to restore or not.
function endBorrowedIdentity(logout as boolean) as dynamic
    b = m.borrowed
    if b = invalid then return invalid
    m.borrowed = invalid
    m.endTimer.control = "stop"
    if logout and b.accessToken <> "" and b.serverUrl <> "" then
        Api_call({ method: "POST", path: "/api/v2/auth/logout", baseUrl: b.serverUrl, auth: false, profile: false, headers: { Authorization: "Bearer " + b.accessToken }, timeout: 5 }, "Api_onFired")
    end if
    for each conn in m.ready.Keys()
        if Str_orEmpty(m.ready[conn]) = b.generation then m.ready.Delete(conn)
    end for
    if b.connId <> "" then m.task.command = { kind: "castAuthorize", conn: b.connId, authorized: false }
    Session_forgetPlaybackCaps()
    own = m.ownSession
    m.ownSession = invalid
    m.global.homeDirty = true
    return own
end function

sub scheduleEnd(seconds as integer)
    if m.borrowed = invalid then return
    m.endTimer.control = "stop"
    m.endTimer.duration = seconds
    m.endTimer.control = "start"
end sub

sub onEndTimer()
    if m.borrowed = invalid or m.global.castPlayer <> invalid then return
    restoreOwn(true)
end sub

sub onEndBorrowed()
    if m.borrowed = invalid then return
    print "[siku-cast] borrowed session ended: " + m.top.endBorrowed
    ' Only the controllers made ready for the borrowed identity; an "own" one is unaffected.
    for each conn in m.ready.Keys()
        if Str_orEmpty(m.ready[conn]) = m.borrowed.generation then castError(conn, "temporary_session_expired", "The phone profile session expired.")
    end for
    player = m.global.castPlayer
    if player <> invalid then player.remoteCommand = { name: "stop" }
    restoreOwn(false)
end sub

sub onCastPlayer()
    player = m.global.castPlayer
    if player = invalid then
        m.task.castState = RemoteState_idle()
        if m.activation <> invalid then
            ' Give the closed player's DELETE a moment under the identity it started with.
            m.activateTimer.control = "stop"
            m.activateTimer.duration = 1.5
            m.activateTimer.control = "start"
        else if m.borrowed <> invalid then
            if m.borrowed.connId = "" then scheduleEnd(5) else scheduleEnd(600)
        end if
    else
        m.endTimer.control = "stop"
    end if
    pushConfig()
end sub

' ---------- Launch and control ----------

sub onLaunch(conn as string, launch as object, c as object)
    readyFor = Str_orEmpty(m.ready[conn])
    ok = false
    if readyFor = "own" then
        ok = m.borrowed = invalid
    else if readyFor <> "" then
        ok = m.borrowed <> invalid and m.borrowed.generation = readyFor
    end if
    if not ok then
        m.ready.Delete(conn)
        castError(conn, "handoff_required", "Prepare the phone profile before playing.")
        return
    end if
    s = m.global.session
    effId = Lan_serverIdFor(s.serverUrl)
    if m.borrowed <> invalid then effId = m.borrowed.serverId
    launchId = Str_orEmpty(launch.serverId)
    identity = ""
    if launchId = Str_orEmpty(c.serverId) then identity = Str_orEmpty(c.serverIdentity)
    if not Lan_serversMatch(launchId, identity, effId, s.serverId) then
        castError(conn, "server_mismatch", "This TV is connected to a different Silo server.")
        return
    end if
    pb = launch.playback
    if Type(pb) <> "roAssociativeArray" or Str_isEmpty(pb.contentId) then
        castError(conn, "launch_failed", "The TV could not open remote playback.")
        return
    end if
    params = { itemId: Str_orEmpty(pb.contentId), remote: true }
    if pb.fileId <> invalid then params.fileId = Int(Num_or(pb.fileId, 0)).ToStr()
    if pb.audioTrackIndex <> invalid and Num_or(pb.audioTrackIndex, -1) >= 0 then params.audioTrackIndex = Int(Num_or(pb.audioTrackIndex, 0))
    ' A Roku launch carries the server's combined subtitle ordinal (externals first), which is
    ' what Siku's subtitle index means; -1 is Off.
    if pb.subtitleTrackIndex <> invalid then params.subtitleTrackIndex = Int(Num_or(pb.subtitleTrackIndex, -1))
    if Lan_isTrue(pb.startFromBeginning) then
        params.startPosition = 0
    else if pb.resumePosition <> invalid and Num_or(pb.resumePosition, -1) >= 0 then
        params.startPosition = Num_or(pb.resumePosition, 0)
    end if
    m.ready.Delete(conn)
    m.endTimer.control = "stop"
    print "[siku-cast] launch from " + Str_orEmpty(c.deviceName) + " file=" + Str_orEmpty(params.fileId) + " audio=" + Str_orEmpty(params.audioTrackIndex) + " sub=" + Str_orEmpty(params.subtitleTrackIndex)
    m.top.launchRequest = params
end sub

function unsupportedControls() as object
    return { set_playback_speed: "Siku can't change the playback speed on a Roku.", set_video_gravity: "Siku can't change the picture size on a Roku.", set_subtitle_position: "Siku can't move subtitles on a Roku.", set_subtitle_sync_ms: "Adjust subtitle timing on the Roku." }
end function

sub onControl(conn as string, control as object)
    name = Str_orEmpty(control.name)
    unsupported = unsupportedControls()
    reason = unsupported[name]
    if reason <> invalid then
        castError(conn, "command_failed", reason)
        return
    end if
    player = m.global.castPlayer
    if player = invalid then
        if name <> "stop" then castError(conn, "player_not_ready", "The TV player is not ready yet.")
        return
    end if
    player.remoteCommand = control
end sub
