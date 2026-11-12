' Phone sign-in: Silo's phone app signs this Roku in (companion pairing, the Roku's side of
' _silopair-roku._tcp; port of Android's PairingReceiver).
' Included by ServerConnectScreen (state "setup": the phone pushes servers, Siku checks each and
' runs its own device sign-in there) and LoginScreen (state "login": the phone approves the code
' the screen already shows). Several accounts in one phone session (Silo Android #810; adapted
' from Silo-Server/silo-roku, AGPL-3.0 (components/AppSceneCompanion.bs, #38)): on the server
' screen (TXT acct=1, lim) every push after a sign-in starts the next one, on any server, each
' saved as its own account (Api_saveSignIn); a failed one does not end the session; past lim, or
' when the registry could not keep one more beside them (PairSession_room), the push answers
' limit_reached and the session waits for the next push or done. Every device login of a phone
' session carries its binding at https servers whose device capability says session_binding.
' With several signed in, the session ends on the first one's profile picker with Change Account
' over it. The screen calls Pair_start / Pair_stop when shown / hidden and implements:
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
    m.pair = { mode: mode, srv: srv, conn: "", consented: false, push: invalid, attempt: invalid, signedIn: "", view: "idle", gen: 0, timerAction: "", busy: false, routed: false }
    Pair_newSession(invalid)
    t = RemoteControl_lanTask()
    if t = invalid then return
    t.unobserveField("pairEvent")
    t.observeField("pairEvent", "Pair_onEvent")
    lim = 0
    if mode = "setup" then lim = PairSession_limit()
    RemoteControl_setPairing(mode, srv, lim)
    if mode = "setup" then
        print "[siku-pair] accepting a phone (state setup); advertising acct=1 lim=" + lim.ToStr()
    else
        print "[siku-pair] accepting a phone (state " + mode + ")"
    end if
end sub

' A phone session's own state: the accounts it signed in (ids, in the order they first signed in),
' its last sign-in, the plain-HTTP origins the viewer allowed, its binding, and the push count.
sub Pair_newSession(binding as dynamic)
    m.pair.accounts = []
    m.pair.lastPush = invalid
    m.pair.lastUser = ""
    m.pair.allowedHttp = {}
    m.pair.pushes = 0
    m.pair.binding = invalid
    if binding <> invalid and Type(binding) = "roAssociativeArray" then m.pair.binding = binding
end sub

sub Pair_stop()
    if m.pair = invalid then return
    t = RemoteControl_lanTask()
    if t <> invalid then t.unobserveField("pairEvent")
    m.pairTimer.control = "stop"
    Pair_abandon()
    ' A Change Account still waiting for the end of the session is no longer due.
    if not m.pair.routed and m.pair.accounts.Count() > 1 then print "[siku-pair] receiver stopped; Change Account no longer due"
    m.pair.accounts = []
    RemoteControl_setPairing("")
    Pair_show(invalid)
    m.pair.conn = ""
end sub

' How long "Signed in" waits for the phone's next push or its done: the server screen takes more.
function Pair_finishSeconds() as float
    if Pair_isLogin() then return 4
    return 10
end function

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
        m.pair.busy = false
        ' A session that is ending keeps what it signed in; its pushes get auth_failed.
        if m.pair.view = "completed" then return
        m.pair.consented = false
        m.pair.signedIn = ""
        Pair_newSession(e.binding)
        print "[siku-pair] phone connected"
        Pair_view("connected")
    else if conn <> m.pair.conn then
        return
    else if kind = "closed" then
        print "[siku-pair] phone disconnected"
        m.pair.conn = ""
        Pair_abandon()
        if m.pair.accounts.Count() > 0 then
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
        if m.pair.accounts.Count() > 0 then
            Pair_complete()
        else if m.pair.view <> "failed" then
            Pair_show(invalid)
        end if
    else if kind = "cancel" then
        print "[siku-pair] phone cancelled (" + Str_orEmpty(msg.reason) + ")"
        Pair_abandon()
        if m.pair.accounts.Count() > 0 then Pair_complete() else Pair_show(invalid)
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

' The phone's word for the account it approves with (pushServer accountName): shown, never
' matched (the account that signs in is the poll's). At most 64 characters.
function Pair_accountLabel(push as dynamic) as string
    if push = invalid then return ""
    return Left(Str_orEmpty(push.accountName).Trim(), 64)
end function

sub Pair_onPush(push as object)
    ' A missing, empty or non-string serverURL (any device on the network can send one) is ignored.
    if Lan_trimUrl(push.serverURL) = "" then
        print "[siku-pair] push ignored: no usable server address"
        return
    end if
    m.pair.pushes = m.pair.pushes + 1
    n = m.pair.pushes.ToStr()
    signedIn = m.pair.accounts.Count()
    lim = PairSession_limit()
    refusal = PairSession_refusal(m.pair.mode, signedIn, lim, m.pair.view = "completed" or m.pair.routed)
    why = "lim=" + lim.ToStr() + " accounts=" + signedIn.ToStr()
    if refusal = "" and signedIn > 0 then
        ' One more sign-in must not cost an account this session signed in its stored sign-in.
        url = Url_normalize(Lan_trimUrl(push.serverURL))
        if not PairSession_room(Accounts_list(), Session_savedServers(), Registry_read("session"), m.pair.accounts, url, Pair_displayName(push), Str_orEmpty(push.serverIdentity).Trim(), Time_nowSeconds()) then
            refusal = "limit_reached"
            why = "registry room"
        end if
    end if
    if refusal <> "" then
        print "[siku-pair] push " + n + " " + refusal + " (" + why + ")"
        Pair_send({ "v": 1, "type": "serverResult", "serverURL": Str_orEmpty(push.serverURL), "status": "failed", "error": refusal })
        ' Still waiting for the phone's next push or its done, showing the last sign-in.
        if refusal = "limit_reached" and m.pair.view = "signedIn" then Pair_schedule("complete", Pair_finishSeconds())
        return
    end if
    print "[siku-pair] push " + n + " accepted (accounts so far " + signedIn.ToStr() + ")"
    ' A push after a sign-in starts the next one: the wait for it ends.
    if m.pair.timerAction = "complete" then
        m.pair.timerAction = ""
        m.pairTimer.control = "stop"
    end if
    ' One server at a time: a newer push replaces one in flight.
    Pair_abandon()
    m.pair.push = push
    unencrypted = LCase(Left(Lan_trimUrl(push.serverURL), 7)) = "http://"
    ' Consent once a session, and for every plain-HTTP origin not allowed yet in it.
    origin = Url_origin(Url_normalize(Lan_trimUrl(push.serverURL)))
    if not m.pair.consented or (unencrypted and not m.pair.allowedHttp.DoesExist(origin)) then
        m.pair.unencrypted = unencrypted
        Pair_view("consent")
        return
    end if
    Pair_begin()
end sub

' ---------- The panel ----------

sub Pair_show(view as dynamic)
    if m.pairPanel = invalid then return
    if view = invalid then
        m.pair.view = "idle"
        m.pairPanel.view = {}
        Pair_setBusy(false)
        applyFocus()
        return
    end if
    m.pairPanel.view = view
end sub

' The LanTask closes a phone that is silent for 180 s, except while an attempt is in flight
' (checking the pushed address, waiting on the viewer's choice of address, or showing the code).
sub Pair_setBusy(busy as boolean)
    if m.pair = invalid or m.pair.conn = "" then return
    if m.pair.busy = busy then return
    m.pair.busy = busy
    t = RemoteControl_lanTask()
    if t <> invalid then t.command = { kind: "pairBusy", conn: m.pair.conn, busy: busy }
end sub

' The panel, state by state, in the words of Silo's Android TV receiver panel (Silo Android #761,
' itself worded like Apple TV's, "this TV" for "this Apple TV"): a chip that says what is happening,
' the headline, the detail, and the card's title and note.
sub Pair_view(name as string, extra = {} as object)
    m.pair.view = name
    print "[siku-pair] panel " + name
    Pair_setBusy(name = "starting" or name = "unreachable" or name = "confirm")
    login = Pair_isLogin()
    push = m.pair.push
    server = ""
    if push <> invalid then server = Pair_displayName(push)
    v = invalid
    if name = "connected" then
        if login then
            v = { eyebrow: Tx("Phone or tablet connected"), title: Tx("Continue on your phone"), detail: Tx("Continue on your phone or tablet."), server: Tx("On your phone"), cardNote: Tx("Approve the sign-in there."), busy: true, buttons: [{ id: "cancel", text: Tx("Cancel") }] }
        else
            v = { eyebrow: Tx("Phone or tablet connected"), title: Tx("Choose accounts on your phone"), detail: Tx("On your phone or tablet, choose which accounts this TV should sign in to."), server: Tx("On your phone"), cardNote: Tx("Pick the accounts to bring over, then tap Continue."), busy: true, buttons: [{ id: "cancel", text: Tx("Cancel") }] }
        end if
    else if name = "consent" then
        chip = Tx("A nearby phone is setting up this TV")
        title = Tx("Allow this setup?")
        note = Tx("Only allow it if you started setup on your own phone or tablet.")
        if login then
            chip = Tx("A nearby phone is signing in this TV")
            title = Tx("Allow this sign-in?")
            note = Tx("Only allow it if you started this on your own phone or tablet.")
        end if
        detail = TxF("A nearby phone or tablet wants to sign this TV in to {0}.", [server])
        if Lan_isTrue(m.pair.unencrypted) then detail = detail + " " + TxF("Your password and what you watch will be sent unencrypted to {0}. Only do this on a network you trust.", [Url_host(Lan_trimUrl(push.serverURL))])
        v = { eyebrow: chip, title: title, detail: detail, server: server, cardNote: Tx("After you allow it, a code appears here to compare with your phone."), buttons: [{ id: "allow", text: Tx("Allow") }, { id: "deny", text: Tx("Don’t Allow") }], note: note }
    else if name = "starting" then
        title = TxF("Signing in to {0}", [server])
        account = Pair_accountLabel(push)
        if account <> "" then title = TxF("Signing in {0} on {1}", [account, server])
        v = { eyebrow: Tx("Getting a code"), title: title, detail: Tx("Getting this TV’s sign-in code."), server: server, busy: true, buttons: [{ id: "cancel", text: Tx("Cancel") }] }
    else if name = "unreachable" then
        detail = TxF("This TV can’t reach {0} at {1}. Check its network connection and try again.", [server, Url_host(Lan_trimUrl(push.serverURL))])
        buttons = []
        if not Str_isEmpty(extra.alternate) then buttons.Push({ id: "alternate", text: TxF("Use {0}", [Url_host(extra.alternate)]) })
        buttons.Push({ id: "retry", text: Tx("Try again") })
        buttons.Push({ id: "cancel", text: Tx("Cancel") })
        v = { title: TxF("Can’t reach {0}", [server]), detail: detail, server: Tx("No answer"), cardNote: Tx("This TV couldn’t reach the address your phone sent."), buttons: buttons }
    else if name = "confirm" then
        cardNote = ""
        words = UCase(Str_orEmpty(extra.matchCode).Trim())
        if words <> "" then cardNote = TxF("Older phones show {0} instead.", [words])
        detail = Tx("Check that your phone or tablet shows this code, then approve.")
        account = Pair_accountLabel(push)
        if account <> "" then detail = TxF("Signing in {0} on {1}.", [account, server]) + " " + detail
        v = { eyebrow: Tx("Waiting for your phone"), title: Tx("Confirm on your phone"), detail: detail, code: Pair_codeText(extra.userCode), server: server, cardNote: cardNote, busy: true, buttons: [{ id: "cancel", text: Tx("Cancel") }] }
    else if name = "signedIn" then
        detail = Tx("Finishing up on your phone or tablet…")
        if m.pair.lastUser <> "" then detail = TxF("{0} is signed in on {1}. Finishing up…", [m.pair.lastUser, server])
        v = { title: Tx("Signed in"), detail: detail, server: server, busy: true }
        ' The server screen waits for more accounts; Done ends the session with what signed in.
        if not login then v.buttons = [{ id: "finish", text: Tx("Done") }]
    else if name = "completed" then
        v = { title: Tx("You’re all set"), detail: PairSession_completedText(m.pair.accounts.Count(), m.pair.signedIn), server: Tx("Signed in"), buttons: [{ id: "continue", text: Tx("Continue") }] }
    else if name = "failed" then
        title = Tx("Setup didn’t finish")
        if login then title = Tx("Sign-in didn’t finish")
        v = { title: title, detail: Pair_failureText(Str_orEmpty(extra.code), server), server: Tx("Not finished"), cardNote: TxF("{0} wasn’t signed in.", [server]), buttons: [{ id: "close", text: Tx("OK") }] }
    end if
    Pair_show(v)
end sub

function Pair_codeText(code as dynamic) as string
    c = UCase(Str_orEmpty(code)).Replace("-", "").Replace(" ", "")
    if Len(c) = 8 then return Left(c, 4) + " " + Right(c, 4)
    return Str_orEmpty(code)
end function

function Pair_failureText(code as string, server as string) as string
    if code = "denied" then return TxF("The sign-in to {0} was declined. Try again from your phone or tablet.", [server])
    if code = "expired" then return TxF("The code for {0} expired before it was approved. Try again from your phone or tablet.", [server])
    if code = "unreachable" then return TxF("This TV can’t reach {0}. You can also add the server manually with its public address.", [server])
    if code = "identity_mismatch" then
        if Pair_isLogin() then return TxF("The phone or tablet offered {0}, which isn’t the server this TV uses. Choose this TV’s server on your phone or tablet, or sign in here with a password.", [server])
        return TxF("The phone or tablet sent an address for {0} that answered as a different server. Check the server on your phone or tablet, or add your server manually.", [server])
    end if
    if code = "update_required" then return TxF("{0} or this app needs an update before this TV can sign in.", [server])
    return TxF("Something went wrong signing in to {0}. Try again from your phone or tablet, or add your server manually.", [server])
end function

sub Pair_onChosen()
    id = m.pairPanel.chosen
    v = m.pair.view
    if id = "allow" and v = "consent" then
        m.pair.consented = true
        if Lan_isTrue(m.pair.unencrypted) and m.pair.push <> invalid then m.pair.allowedHttp[Url_origin(Url_normalize(Lan_trimUrl(m.pair.push.serverURL)))] = true
        Pair_begin()
    else if (id = "deny" or id = "back") and v = "consent" then
        print "[siku-pair] consent denied"
        Pair_send({ "v": 1, "type": "cancel", "reason": "consent_denied" })
        RemoteControl_pairClose(m.pair.conn, "")
        if m.pair.accounts.Count() > 0 then Pair_complete() else Pair_show(invalid)
    else if id = "alternate" and v = "unreachable" then
        Pair_useTarget(m.pair.alternate, Str_orEmpty(m.pair.push.serverIdentity).Trim())
    else if id = "retry" and v = "unreachable" then
        Pair_begin()
    else if id = "continue" and v = "completed" then
        Pair_onTimerRoute()
    else if (id = "finish" or id = "back") and v = "signedIn" then
        ' The session ends with what it signed in.
        if Pair_isLogin() then return
        Pair_endSession()
    else if id = "close" or (id = "back" and v = "failed") then
        ' After a sign-in, a later account's failure ends the session with the ones that did.
        if m.pair.accounts.Count() > 0 then Pair_endSession() else Pair_show(invalid)
    else if id = "cancel" or id = "back" then
        if v = "completed" or v = "signedIn" then return
        Pair_abandon()
        if m.pair.conn <> "" then RemoteControl_pairClose(m.pair.conn, "user-cancelled")
        if m.pair.accounts.Count() > 0 then Pair_complete() else Pair_show(invalid)
    end if
end sub

' The viewer ends a session that signed in: the phone hears it, "You're all set" shows.
sub Pair_endSession()
    Pair_abandon()
    if m.pair.conn <> "" then RemoteControl_pairClose(m.pair.conn, "user-cancelled")
    Pair_complete()
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
    m.pair.lastPush = push
    ' The saved account it signed in (or refreshed): the same account twice counts once.
    s = m.global.session
    id = Str_orEmpty(s.accountId)
    if Pair_isLogin() or id = "" then id = "push-" + m.pair.pushes.ToStr()
    m.pair.accounts = PairSession_note(m.pair.accounts, id)
    m.pair.lastUser = ""
    if not Pair_isLogin() then m.pair.lastUser = Left(Accounts_username(s), 64)
    print "[siku-pair] signed in (accounts this session " + m.pair.accounts.Count().ToStr() + ")"
    Pair_send({ "v": 1, "type": "serverResult", "serverURL": Str_orEmpty(push.serverURL), "status": "signedIn" })
    Pair_view("signedIn")
    ' The phone pushes the next account or answers with done; if it does neither, carry on.
    Pair_schedule("complete", Pair_finishSeconds())
end sub

' "You're all set", naming the last sign-in's server (not a later push that failed or was
' refused). An attempt still in flight is withdrawn.
sub Pair_complete()
    if m.pair.view = "completed" then return
    if m.pair.timerAction = "complete" then m.pair.timerAction = ""
    Pair_abandon()
    if m.pair.lastPush <> invalid then m.pair.push = m.pair.lastPush
    print "[siku-pair] session ended with " + m.pair.accounts.Count().ToStr() + " account(s)"
    Pair_view("completed")
    Pair_schedule("route", 2)
end sub

' Ends the attempt in flight; withdraws a setup code nobody will approve now.
sub Pair_abandon()
    a = m.pair.attempt
    m.pair.gen = m.pair.gen + 1
    if m.pairTimer <> invalid and m.pair.timerAction <> "route" and m.pair.timerAction <> "complete" then m.pairTimer.control = "stop"
    m.pair.attempt = invalid
    if a <> invalid and not Str_isEmpty(a.deviceCode) then
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
        Pair_onTimerRoute()
    end if
end sub

' "You're all set": Continue, or 2 s later, moves on to the profiles: the one account's, or with
' several, the first one's picker with Change Account over it, focused on its card (silo-roku
' companionOpenAccounts; Android TV ends on Change Account).
sub Pair_onTimerRoute()
    if m.pair = invalid or m.pair.routed = true then return
    m.pair.routed = true
    m.pairTimer.control = "stop"
    ids = m.pair.accounts
    several = not Pair_isLogin() and ids.Count() > 1
    Pair_stop()
    if several and Pair_openAccount(Str_orEmpty(ids[0])) then
        print "[siku-pair] " + ids.Count().ToStr() + " accounts signed in: the first one's profiles with Change Account over them"
        Nav_reset("@start", { switching: true, openAccounts: true })
        return
    end if
    Nav_reset("@start")
end sub

' Makes the session's first account the open one, its picker waiting for the viewer (a profile
' it had open closes). False when it is no longer saved.
function Pair_openAccount(id as string) as boolean
    s = m.global.session
    if id <> "" and Str_orEmpty(s.accountId) = id and not Accounts_isTemporary(s) then
        c = AA_copy(s)
        c.profileId = ""
        c.profileToken = ""
        c.profileName = ""
        c.profileAvatar = ""
        Session_save(c)
        return true
    end if
    e = Accounts_find(Accounts_list(), id)
    if e = invalid then return false
    srv = Session_savedServer(Str_orEmpty(e.url))
    if srv = invalid then return false
    Session_activateAccount(srv, e, true)
    return true
end function

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
    m.pair.attempt = { kind: "setup", gen: m.pair.gen, base: Url_normalize(base), identity: identity, deviceCode: "", interval: 3, deadline: 0, failingSince: 0, binding: invalid }
    Pair_view("starting")
    ' The session binding goes only to an https server whose capability says session_binding;
    ' over plain HTTP it is never sent, so the capability is not read there.
    if LCase(Left(m.pair.attempt.base, 8)) = "https://" and m.pair.binding <> invalid then
        Api_call({ method: "GET", path: "/api/v2/auth/device/capability", baseUrl: m.pair.attempt.base, auth: false, profile: false, timeout: 8, context: { gen: m.pair.gen } }, "Pair_onCapability")
        return
    end if
    Pair_startLogin(invalid)
end sub

sub Pair_onCapability(event as object)
    resp = Api_result(event)
    if not Pair_current(resp) then return
    cap = invalid
    if resp.ok and Type(resp.data) = "roAssociativeArray" then cap = resp.data
    Pair_startLogin(cap)
end sub

' POST device/start at the attempt's address, with the session's binding when that server takes it.
sub Pair_startLogin(capability as dynamic)
    a = m.pair.attempt
    a.binding = PairSession_bindingFor(a.base, capability, m.pair.binding)
    body = { device_name: Pair_deviceName(), device_platform: "roku" }
    if a.binding <> invalid then
        body["binding"] = a.binding.binding
        print "[siku-pair] binding sent=yes"
    else
        print "[siku-pair] binding sent=no reason=" + PairSession_noBindingReason(a.base, capability, m.pair.binding)
    end if
    Api_call({ method: "POST", path: "/api/v2/auth/device/start", baseUrl: a.base, body: body, auth: false, profile: false, timeout: 15, context: { gen: m.pair.gen } }, "Pair_onStart")
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
    Pair_view("confirm", { userCode: d.user_code, matchCode: d.match_code })
    Pair_schedule("poll", interval)
end sub

sub Pair_poll()
    a = m.pair.attempt
    if a = invalid or a.kind <> "setup" then return
    if Time_nowSeconds() >= a.deadline then
        Pair_failed("expired")
        return
    end if
    body = { device_code: a.deviceCode }
    if a.binding <> invalid then body["binding_secret"] = a.binding.secret
    Api_call({ method: "POST", path: "/api/v2/auth/device/poll", baseUrl: a.base, body: body, auth: false, profile: false, timeout: 15, context: { gen: m.pair.gen } }, "Pair_onPoll")
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
        ' A refused binding secret cannot change by polling again: the request is withdrawn.
        if resp.status = 403 and resp.error <> invalid and Str_orEmpty(resp.error.code) = "device_binding_mismatch" then
            print "[siku-pair] the server refused the session binding"
            Pair_failed("auth_failed")
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
    s = Session_ownCopy()
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
    Api_saveSignIn(s)
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
    Pair_view("confirm", { userCode: a.userCode, matchCode: code.match_code })
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
