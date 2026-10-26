' Phone sign-in: Silo's phone app signs this Roku in (companion pairing, the Roku's side of
' _silopair-roku._tcp; port of Android's PairingReceiver for a Roku, which keeps one server).
' Included by ServerConnectScreen (state "setup": the phone pushes a server, Siku checks it and
' runs its own device sign-in there) and LoginScreen (state "login": the phone approves the code
' the screen already shows). The screen calls Pair_start / Pair_stop when shown / hidden and
' implements:
'   Pair_screenCode()   login only: the code on screen {device_code, user_code, match_code} or invalid
'   applyFocus()        to take focus back when the panel closes
' LoginScreen reports its sign-in outcome with Pair_codeStatus(status).
' Wire (4-byte big-endian length + JSON, v 1): hello (Roku), pushServer / done / cancel (phone),
' deviceStarted / serverResult / cancel (Roku). Tokens never cross it: the server hands them to
' the Roku over HTTPS after the person approves the code. Console lines: [siku-pair].
' SPDX-License-Identifier: AGPL-3.0-or-later

sub Pair_start(mode as string, srv = "" as string)
    if m.pair = invalid then
        m.pairPanel = m.top.createChild("PairingPanel")
        m.pairPanel.observeField("chosen", "Pair_onChosen")
        m.pairTimer = m.top.createChild("Timer")
        m.pairTimer.repeat = false
        m.pairTimer.observeField("fire", "Pair_onTimer")
    end if
    m.pair = { mode: mode, srv: srv, conn: "", consented: false, push: invalid, attempt: invalid, signedIn: "", view: "idle", gen: 0, timerAction: "" }
    t = RemoteControl_lanTask()
    if t = invalid then return
    t.unobserveField("pairEvent")
    t.observeField("pairEvent", "Pair_onEvent")
    RemoteControl_setPairing(mode, srv)
    print "[siku-pair] accepting a phone (state " + mode + ")"
end sub

sub Pair_stop()
    if m.pair = invalid then return
    t = RemoteControl_lanTask()
    if t <> invalid then t.unobserveField("pairEvent")
    m.pairTimer.control = "stop"
    Pair_abandon()
    RemoteControl_setPairing("")
    Pair_show(invalid)
    m.pair.conn = ""
end sub

function Pair_isLogin() as boolean
    return m.pair <> invalid and m.pair.mode = "login"
end function

' LoginScreen waits a little longer before routing on while a phone still has to hear the result.
function Pair_holdsRoute() as boolean
    return m.pair <> invalid and m.pair.conn <> "" and m.pair.signedIn <> ""
end function

' ---------- Events from the LanTask ----------

sub Pair_onEvent(event as object)
    e = event.getData()
    if e = invalid or m.pair = invalid then return
    kind = Str_orEmpty(e["type"])
    conn = Str_orEmpty(e.conn)
    if kind = "connected" then
        m.pair.conn = conn
        m.pair.consented = false
        m.pair.signedIn = ""
        print "[siku-pair] phone connected"
        Pair_view("connected")
    else if conn <> m.pair.conn then
        return
    else if kind = "closed" then
        print "[siku-pair] phone disconnected"
        m.pair.conn = ""
        Pair_abandon()
        if m.pair.signedIn <> "" then
            Pair_complete()
        else if m.pair.view <> "failed" then
            Pair_show(invalid)
        end if
    else if kind = "message" then
        Pair_onMessage(e.message)
    end if
end sub

sub Pair_onMessage(msg as dynamic)
    if Type(msg) <> "roAssociativeArray" then return
    kind = Str_orEmpty(msg["type"])
    if kind = "pushServer" then
        Pair_onPush(msg)
    else if kind = "done" then
        print "[siku-pair] phone finished"
        Pair_abandon()
        if m.pair.signedIn <> "" then
            Pair_complete()
        else if m.pair.view <> "failed" then
            Pair_show(invalid)
        end if
    else if kind = "cancel" then
        print "[siku-pair] phone cancelled (" + Str_orEmpty(msg.reason) + ")"
        Pair_abandon()
        if m.pair.signedIn <> "" then Pair_complete() else Pair_show(invalid)
    end if
end sub

sub Pair_send(message as object)
    if m.pair.conn <> "" then RemoteControl_pairSend(m.pair.conn, message)
end sub

function Pair_displayName(push as object) as string
    n = Str_orEmpty(push.serverName).Trim()
    if n <> "" then return n
    return Lan_trimUrl(push.serverURL)
end function

sub Pair_onPush(push as object)
    if Str_isEmpty(push.serverURL) then return
    print "[siku-pair] server pushed"
    ' A Roku keeps one server: a second push after a sign-in is refused.
    if m.pair.signedIn <> "" then
        Pair_send({ "v": 1, "type": "serverResult", "serverURL": Str_orEmpty(push.serverURL), "status": "failed", "error": "auth_failed" })
        return
    end if
    ' One server at a time: a newer push replaces one in flight.
    Pair_abandon()
    m.pair.push = push
    unencrypted = LCase(Left(Lan_trimUrl(push.serverURL), 7)) = "http://"
    if not m.pair.consented or unencrypted then
        m.pair.unencrypted = unencrypted
        Pair_view("consent")
        return
    end if
    Pair_begin()
end sub

' ---------- The panel ----------

function Pair_noun() as string
    return "this Roku"
end function

sub Pair_show(view as dynamic)
    if m.pairPanel = invalid then return
    if view = invalid then
        m.pair.view = "idle"
        m.pairPanel.view = {}
        applyFocus()
        return
    end if
    m.pairPanel.view = view
end sub

sub Pair_view(name as string, extra = {} as object)
    m.pair.view = name
    login = Pair_isLogin()
    push = m.pair.push
    server = ""
    if push <> invalid then server = Pair_displayName(push)
    v = invalid
    if name = "connected" then
        detail = "On your phone or tablet, choose which server " + Pair_noun() + " should sign in to."
        if login then detail = "Continue on your phone or tablet."
        v = { eyebrow: "Step 01 — Connect", title: "Phone or tablet connected", detail: detail, buttons: [{ id: "cancel", text: "Cancel" }] }
    else if name = "consent" then
        title = "Allow this setup?"
        if login then title = "Allow this sign-in?"
        detail = "A nearby phone or tablet wants to sign " + Pair_noun() + " in to " + server + "."
        if Lan_isTrue(m.pair.unencrypted) then detail = detail + " Your password and what you watch will be sent unencrypted to " + Url_host(Lan_trimUrl(push.serverURL)) + ". Only do this on a network you trust."
        v = { eyebrow: "Step 01 — Connect", title: title, detail: detail, buttons: [{ id: "allow", text: "Allow" }, { id: "deny", text: "Don't allow" }] }
    else if name = "starting" then
        title = "Setting up " + Pair_noun()
        label = "SETTING UP "
        if login then
            title = "Signing in " + Pair_noun()
            label = "SIGNING IN TO "
        end if
        v = { eyebrow: "Step 02 — Account", title: title, detail: "Starting secure sign-in…", server: label + server, busy: true, buttons: [{ id: "cancel", text: "Cancel" }] }
    else if name = "unreachable" then
        detail = "This Roku can't reach " + server + " at " + Url_host(Lan_trimUrl(push.serverURL)) + ". Check its network connection and try again."
        buttons = []
        if not Str_isEmpty(extra.alternate) then buttons.Push({ id: "alternate", text: "Use " + Url_host(extra.alternate) })
        buttons.Push({ id: "retry", text: "Try again" })
        buttons.Push({ id: "cancel", text: "Cancel" })
        v = { eyebrow: "Step 02 — Account", title: "Can't reach " + server, detail: detail, buttons: buttons }
    else if name = "confirm" then
        v = { eyebrow: "Almost there", title: "Confirm on your phone or tablet", detail: "Check that your phone or tablet shows this code, then approve.", code: Pair_codeText(extra.userCode), server: server, buttons: [{ id: "cancel", text: "Cancel" }] }
    else if name = "signedIn" then
        v = { eyebrow: "All set", title: "Signed in", detail: "Finishing up on your phone or tablet…", server: server, busy: true }
    else if name = "completed" then
        v = { eyebrow: "All set", title: "You're all set", detail: "Signed in to " + m.pair.signedIn + ". Taking you to your profiles…", busy: true }
    else if name = "failed" then
        title = "Setup didn't finish"
        if login then title = "Sign-in didn't finish"
        v = { eyebrow: "Step 02 — Account", title: title, detail: Pair_failureText(Str_orEmpty(extra.code), server), buttons: [{ id: "close", text: "OK" }] }
    end if
    Pair_show(v)
end sub

function Pair_codeText(code as dynamic) as string
    c = UCase(Str_orEmpty(code)).Replace("-", "").Replace(" ", "")
    if Len(c) = 8 then return Left(c, 4) + " " + Right(c, 4)
    return Str_orEmpty(code)
end function

function Pair_failureText(code as string, server as string) as string
    if code = "denied" then return "The sign-in to " + server + " was declined on the phone."
    if code = "expired" then return "The code for " + server + " expired before it was approved. Try again from your phone."
    if code = "unreachable" then return "This Roku can't reach " + server + ". Check its network connection and try again."
    if code = "identity_mismatch" then return "The address for " + server + " answered as a different server, so nothing was signed in."
    if code = "update_required" then return server + " or Siku needs an update before this Roku can sign in."
    return "Something went wrong signing in to " + server + ". Try again from your phone, or sign in on this Roku."
end function

sub Pair_onChosen()
    id = m.pairPanel.chosen
    v = m.pair.view
    if id = "allow" and v = "consent" then
        m.pair.consented = true
        Pair_begin()
    else if (id = "deny" or id = "back") and v = "consent" then
        print "[siku-pair] consent denied"
        Pair_send({ "v": 1, "type": "cancel", "reason": "consent_denied" })
        RemoteControl_pairClose(m.pair.conn, "")
        Pair_show(invalid)
    else if id = "alternate" and v = "unreachable" then
        Pair_useTarget(m.pair.alternate, Str_orEmpty(m.pair.push.serverIdentity).Trim())
    else if id = "retry" and v = "unreachable" then
        Pair_begin()
    else if id = "close" or (id = "back" and v = "failed") then
        Pair_show(invalid)
    else if id = "cancel" or id = "back" then
        if v = "completed" or v = "signedIn" then return
        Pair_abandon()
        if m.pair.conn <> "" then RemoteControl_pairClose(m.pair.conn, "user-cancelled")
        Pair_show(invalid)
    end if
end sub

' ---------- One attempt ----------

sub Pair_failed(code as string)
    push = m.pair.push
    print "[siku-pair] sign-in failed: " + code
    Pair_abandon()
    if push <> invalid then Pair_send({ "v": 1, "type": "serverResult", "serverURL": Str_orEmpty(push.serverURL), "status": "failed", "error": code })
    Pair_view("failed", { code: code })
end sub

sub Pair_signedInNow()
    push = m.pair.push
    m.pair.attempt = invalid
    m.pair.signedIn = Pair_displayName(push)
    print "[siku-pair] signed in"
    Pair_send({ "v": 1, "type": "serverResult", "serverURL": Str_orEmpty(push.serverURL), "status": "signedIn" })
    Pair_view("signedIn")
    ' The phone answers with done; if it never does, carry on anyway.
    Pair_schedule("complete", 4)
end sub

sub Pair_complete()
    if m.pair.view = "completed" then return
    Pair_view("completed")
    Pair_schedule("route", 1.5)
end sub

' Ends the attempt in flight; withdraws a setup code nobody will approve now.
sub Pair_abandon()
    a = m.pair.attempt
    m.pair.gen = m.pair.gen + 1
    if m.pairTimer <> invalid and m.pair.timerAction <> "route" and m.pair.timerAction <> "complete" then m.pairTimer.control = "stop"
    m.pair.attempt = invalid
    if a <> invalid and not Str_isEmpty(a.deviceCode) and m.pair.signedIn = "" then
        Api_call({ method: "POST", path: "/api/v2/auth/device/cancel", baseUrl: a.base, body: { device_code: a.deviceCode }, auth: false, profile: false, timeout: 5 }, "Api_onFired")
    end if
end sub

sub Pair_schedule(action as string, seconds as float)
    m.pair.timerAction = action
    m.pairTimer.control = "stop"
    m.pairTimer.duration = seconds
    m.pairTimer.control = "start"
end sub

sub Pair_onTimer()
    a = m.pair.timerAction
    m.pair.timerAction = ""
    if a = "poll" then
        Pair_poll()
    else if a = "code" then
        Pair_loginCode()
    else if a = "complete" then
        Pair_complete()
    else if a = "route" then
        Pair_stop()
        Nav_reset("@start")
    end if
end sub

sub Pair_begin()
    push = m.pair.push
    if push = invalid then return
    m.pair.gen = m.pair.gen + 1
    Pair_view("starting")
    identity = Str_orEmpty(push.serverIdentity).Trim()
    ' An identity Siku would not store (too long, odd characters) matches nothing.
    if identity <> "" and not Lan_isServerId(identity) then
        Pair_failed("identity_mismatch")
        return
    end if
    if Pair_isLogin() then
        ' Only the advertised server, by the identity the phone verified.
        if m.pair.srv = "" or identity <> m.pair.srv then
            Pair_failed("identity_mismatch")
            return
        end if
        m.pair.attempt = { kind: "login", gen: m.pair.gen, waited: 0, base: "", deviceCode: "" }
        Pair_loginCode()
        return
    end if
    pushed = Lan_trimUrl(push.serverURL)
    if identity = "" then
        ' A legacy push without an identity uses the pushed address exactly.
        Pair_useTarget(pushed, "")
        return
    end if
    m.pair.attempt = { kind: "probe", gen: m.pair.gen, base: pushed, deviceCode: "", candidates: [], alternate: "" }
    Api_call({ method: "GET", path: "/api/v2/system/identity", baseUrl: pushed, auth: false, profile: false, timeout: 8, context: { gen: m.pair.gen, url: pushed, pushed: true } }, "Pair_onIdentity")
end sub

function Pair_current(resp as object) as boolean
    return m.pair <> invalid and m.pair.attempt <> invalid and resp.context <> invalid and resp.context.gen = m.pair.gen
end function

' setup: the pushed address must answer with the pushed identity. If it does not answer, the
' server's other addresses are checked and a match is OFFERED, never taken.
sub Pair_onIdentity(event as object)
    resp = Api_result(event)
    if not Pair_current(resp) then return
    want = Str_orEmpty(m.pair.push.serverIdentity).Trim()
    got = ""
    if resp.ok and Type(resp.data) = "roAssociativeArray" then got = Str_orEmpty(resp.data.server_id)
    a = m.pair.attempt
    if Lan_isTrue(resp.context.pushed) then
        if got = want then
            Pair_useTarget(resp.context.url, want)
            return
        end if
        if resp.ok or (resp.status >= 400 and resp.status < 500) then
            ' It answered, as another server (or not as a Silo server at all).
            Pair_failed("identity_mismatch")
            return
        end if
        ' Unreachable: try the other addresses the phone listed.
        pushedCanon = Lan_canonicalUrl(a.base)
        for each ep in Arr_or(m.pair.push.endpoints)
            u = Lan_trimUrl(AA_get(ep, "url", ""))
            if u <> "" and Lan_canonicalUrl(u) <> pushedCanon then a.candidates.Push(u)
        end for
    else if got = want and a.alternate = "" then
        a.alternate = resp.context.url
    end if
    if a.candidates.Count() > 0 and a.alternate = "" then
        nextUrl = a.candidates.Shift()
        Api_call({ method: "GET", path: "/api/v2/system/identity", baseUrl: nextUrl, auth: false, profile: false, timeout: 6, context: { gen: m.pair.gen, url: nextUrl, pushed: false } }, "Pair_onIdentity")
        return
    end if
    m.pair.alternate = a.alternate
    print "[siku-pair] pushed address unreachable; alternate offered=" + Lan_boolText(a.alternate <> "")
    Pair_view("unreachable", { alternate: a.alternate })
end sub

sub Pair_useTarget(base as string, identity as string)
    m.pair.gen = m.pair.gen + 1
    m.pair.attempt = { kind: "setup", gen: m.pair.gen, base: Url_normalize(base), identity: identity, deviceCode: "", interval: 3, deadline: 0, failingSince: 0 }
    Pair_view("starting")
    body = { device_name: Pair_deviceName(), device_platform: "roku" }
    Api_call({ method: "POST", path: "/api/v2/auth/device/start", baseUrl: m.pair.attempt.base, body: body, auth: false, profile: false, timeout: 15, context: { gen: m.pair.gen } }, "Pair_onStart")
end sub

function Pair_deviceName() as string
    di = CreateObject("roDeviceInfo")
    name = di.GetFriendlyName()
    if name = invalid or name = "" then name = "Roku " + di.GetModelDisplayName()
    return name
end function

sub Pair_onStart(event as object)
    resp = Api_result(event)
    if not Pair_current(resp) then return
    d = resp.data
    if not resp.ok or Type(d) <> "roAssociativeArray" or Str_isEmpty(d.device_code) then
        if resp.status = 0 or resp.status >= 500 then
            Pair_failed("unreachable")
        else if resp.status = 410 or resp.status = 426 then
            Pair_failed("update_required")
        else
            Pair_failed("auth_failed")
        end if
        return
    end if
    a = m.pair.attempt
    a.deviceCode = Str_orEmpty(d.device_code)
    interval = Int(Num_or(d.interval, 3))
    if interval < 1 then interval = 3
    a.interval = interval
    expiresIn = Int(Num_or(d.expires_in, 900))
    if expiresIn < 1 then expiresIn = 900
    a.deadline = Time_nowSeconds() + expiresIn
    Pair_send({ "v": 1, "type": "deviceStarted", "serverURL": Str_orEmpty(m.pair.push.serverURL), "userCode": Str_orEmpty(d.user_code), "matchCode": Str_orEmpty(d.match_code) })
    Pair_view("confirm", { userCode: d.user_code })
    Pair_schedule("poll", interval)
end sub

sub Pair_poll()
    a = m.pair.attempt
    if a = invalid or a.kind <> "setup" then return
    if Time_nowSeconds() >= a.deadline then
        Pair_failed("expired")
        return
    end if
    Api_call({ method: "POST", path: "/api/v2/auth/device/poll", baseUrl: a.base, body: { device_code: a.deviceCode }, auth: false, profile: false, timeout: 15, context: { gen: m.pair.gen } }, "Pair_onPoll")
end sub

sub Pair_onPoll(event as object)
    resp = Api_result(event)
    if not Pair_current(resp) then return
    a = m.pair.attempt
    d = resp.data
    if not resp.ok or Type(d) <> "roAssociativeArray" then
        if resp.status = 404 then
            Pair_failed("expired")
            return
        end if
        if a.failingSince = 0 then a.failingSince = Time_nowSeconds()
        if Time_nowSeconds() - a.failingSince >= 30 then
            Pair_failed("unreachable")
        else
            Pair_schedule("poll", a.interval)
        end if
        return
    end if
    a.failingSince = 0
    st = LCase(Str_orEmpty(d.status))
    if st = "pending" then
        wait = Int(Num_or(d.poll_after, a.interval))
        if wait < 1 then wait = 1
        Pair_schedule("poll", wait)
    else if st = "approved" then
        tokens = d.tokens
        if Type(tokens) <> "roAssociativeArray" or Str_isEmpty(tokens.access_token) or Str_isEmpty(tokens.refresh_token) then
            Pair_failed("auth_failed")
            return
        end if
        Pair_persist(a, tokens, d)
    else if st = "denied" then
        Pair_failed("denied")
    else if st = "expired" or st = "consumed" or st = "canceled" or st = "cancelled" then
        Pair_failed("expired")
    else
        Pair_failed("auth_failed")
    end if
end sub

' Saves the server and the approved sign-in, as the address screen and the sign-in screen would.
sub Pair_persist(a as object, tokens as object, d as object)
    push = m.pair.push
    s = AA_copy(m.global.session)
    s.serverUrl = a.base
    s.serverOrigin = Url_origin(a.base)
    s.serverId = a.identity
    name = Str_orEmpty(push.serverName).Trim()
    if name = "" then name = Url_host(a.base)
    s.serverName = name
    s = Session_withTokens(s, tokens)
    s.profileId = ""
    s.profileToken = ""
    s.profileName = ""
    s.profileAvatar = ""
    if not Str_isEmpty(d.profile_id) then
        s.profileId = Str_orEmpty(d.profile_id)
        s.profileToken = Str_orEmpty(d.profile_token)
    end if
    Session_forgetPlaybackCaps()
    Session_save(s)
    Pair_signedInNow()
end sub

' ---------- login: the sign-in screen's own code ----------

sub Pair_loginCode()
    a = m.pair.attempt
    if a = invalid or a.kind <> "login" then return
    code = Pair_screenCode()
    if code = invalid or Str_isEmpty(code.user_code) then
        ' The screen is fetching a code: wait briefly.
        a.waited = a.waited + 1
        if a.waited > 20 then
            Pair_failed("expired")
        else
            Pair_schedule("code", 0.5)
        end if
        return
    end if
    a.userCode = Str_orEmpty(code.user_code)
    Pair_send({ "v": 1, "type": "deviceStarted", "serverURL": Str_orEmpty(m.pair.push.serverURL), "userCode": a.userCode, "matchCode": Str_orEmpty(code.match_code) })
    Pair_view("confirm", { userCode: a.userCode })
    print "[siku-pair] sent the sign-in screen's code"
end sub

' LoginScreen's device status (signedin, denied, newcode, failed, update, paused, ...).
sub Pair_codeStatus(st as string)
    if m.pair = invalid then return
    a = m.pair.attempt
    if a = invalid or a.kind <> "login" or Str_isEmpty(a.userCode) then return
    if st = "signedin" then
        Pair_signedInNow()
    else if st = "denied" then
        Pair_failed("denied")
    else if st = "newcode" or st = "paused" or st = "getting" then
        Pair_failed("expired")
    else if st = "update" then
        Pair_failed("update_required")
    else if st = "failed" or st = "couldntfinish" then
        Pair_failed("auth_failed")
    end if
end sub
