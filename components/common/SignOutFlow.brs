' SPDX-License-Identifier: AGPL-3.0-or-later
' Sign Out's question and the one sign-out behind Who's watching, the profile menu and Settings
' (Silo Android TV #764 and #795, Apple TV's AppRouter.requestSignOut). It signs out of the open
' account only: "Sign out of alex on Home?" with Cancel and Sign Out (the server and its other
' accounts stay; then Change Account when another account has a session, else this server's
' sign-in), plus Sign Out & Remove Server while the server has no other account (forget it, then
' open the next saved server with its own account, or first-run setup). Wording adapted from
' Silo-Server/silo-roku, AGPL-3.0 (components/screens/home/SignOutDialog.xml,
' locale/en_US/strings.json) and Android TV's TvSignOutDialog.
' Include with Session.brs, Accounts.brs, Api.brs, Nav.brs and ProfileLaunch.brs. A screen that
' asks calls SignOut_ask(); SettingsScreen draws its own picker and calls SignOut_run(remove).
' One sign-out at a time: a second request while one runs is ignored.
' A phone's borrowed profile (RemoteControl) is ended first, as today: the temporary session is
' signed out, RemoteControl hands it back and signs the TV's own account out (keeping its server);
' with "& Remove Server" the TV's own server is then removed once that has happened (at most 5 s).

' The Roku's own session: a phone's borrowed profile signs the TV's own account out too.
function SignOut_ownSession() as object
    s = m.global.session
    if Session_isTemporary(s) then
        own = Registry_read("session")
        if own <> invalid and Type(own) = "roAssociativeArray" then return own
    end if
    return s
end function

' Sign Out & Remove Server is offered only while the server has no other saved account.
function SignOut_offersRemove() as boolean
    return Accounts_countOn(Str_orEmpty(SignOut_ownSession().serverUrl)) <= 1
end function

' "Sign out of alex on Home?", dropping whichever part is unknown (Android TV's tvSignOutTitle).
function SignOut_title() as string
    s = SignOut_ownSession()
    account = Accounts_username(s)
    server = Str_orEmpty(s.serverName).Trim()
    if server = "" then server = Url_host(Str_orEmpty(s.serverUrl))
    return SignOut_titleFor(account, server)
end function

function SignOut_titleFor(account as string, server as string) as string
    if account <> "" and server <> "" then return TxF("Sign out of {0} on {1}?", [account, server])
    if account <> "" then return TxF("Sign out of {0}?", [account])
    if server <> "" then return TxF("Sign out of {0}?", [server])
    return Tx("Sign Out?")
end function

function SignOut_message() as string
    if SignOut_offersRemove() then return Tx("This account's profiles and settings leave this Roku. Sign Out keeps the server saved, so you can sign in again; Sign Out & Remove Server removes it too.")
    return Tx("This account's profiles and settings leave this Roku. The server and its other accounts stay saved, so you can sign in again.")
end function

function SignOut_buttons() as object
    if SignOut_offersRemove() then return [Tx("Cancel"), Tx("Sign Out"), Tx("Sign Out & Remove Server")]
    return [Tx("Cancel"), Tx("Sign Out")]
end function

sub SignOut_ask()
    if SignOut_isRunning() or m.signOutDialog <> invalid then return
    title = SignOut_title()
    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    if dlg <> invalid then
        dlg.title = title
        dlg.message = [SignOut_message()]
    else
        dlg = CreateObject("roSGNode", "Dialog")
        dlg.title = title
        dlg.message = SignOut_message()
    end if
    ' Cancel first, so it takes focus.
    dlg.buttons = SignOut_buttons()
    dlg.observeField("buttonSelected", "SignOut_onButton")
    dlg.observeField("wasClosed", "SignOut_onClosed")
    m.signOutDialog = dlg
    m.top.getScene().dialog = dlg
    print "[siku-servers] sign out asked"
end sub

sub SignOut_onButton()
    dlg = m.signOutDialog
    if dlg = invalid then return
    choice = dlg.buttonSelected
    SignOut_closeDialog()
    if choice = 1 then
        SignOut_run(false)
    else if choice = 2 then
        SignOut_run(true)
    else
        SignOut_cancelled()
    end if
end sub

' Back on the dialog answers Cancel.
sub SignOut_onClosed()
    if m.signOutDialog = invalid then return
    SignOut_closeDialog()
    SignOut_cancelled()
end sub

sub SignOut_closeDialog()
    dlg = m.signOutDialog
    m.signOutDialog = invalid
    if dlg = invalid then return
    dlg.unobserveField("buttonSelected")
    dlg.unobserveField("wasClosed")
    dlg.close = true
    scene = m.top.getScene()
    if scene.dialog <> invalid and scene.dialog.isSameNode(dlg) then scene.dialog = invalid
end sub

sub SignOut_cancelled()
    print "[siku-servers] sign out cancelled"
    SignOut_afterCancel()
end sub

' The one sign-out. remove: also forget the server and move on to the next saved one.
sub SignOut_run(remove as boolean)
    if SignOut_isRunning() then
        print "[siku-servers] sign out ignored: one is already running"
        return
    end if
    m.signOutRunning = true
    m.signOutRemove = remove
    s = m.global.session
    borrowed = Session_isTemporary(s)
    print "[siku-servers] sign out remove=" + Session_boolWord(remove) + " borrowed=" + Session_boolWord(borrowed)
    ' Revoke the login on the server first and wait for the answer (at most 5 s): a request left
    ' running when this screen goes away never reached the server in the simulator.
    ' Api_revoke refreshes an expired token first, so an hour idle still ends the session there.
    token = Str_orEmpty(s.accessToken)
    if token <> "" and Api_revoke(Str_orEmpty(s.serverUrl), s, "SignOut_onLoggedOut", { token: token }) <> invalid then return
    SignOut_afterLogout(token)
end sub

sub SignOut_onLoggedOut(event as object)
    resp = Api_result(event)
    token = ""
    if resp.context <> invalid then token = Str_orEmpty(resp.context.token)
    if not resp.ok then print "[siku-servers] logout answered status=" + Str_orEmpty(resp.status) + "; signing out on this Roku anyway"
    SignOut_afterLogout(token)
end sub

' Signs out locally (keeping the server); for a phone's borrowed profile RemoteControl then ends
' it and signs the TV's own account out. With remove, the server goes too.
sub SignOut_afterLogout(token as string)
    remove = SignOut_flag(m.signOutRemove)
    s = m.global.session
    borrowed = Session_isTemporary(s)
    if token = "" or Str_orEmpty(s.accessToken) = token then
        Session_signOutLocal(s)
    else
        print "[siku-servers] the session changed while signing out; leaving it"
    end if
    if borrowed and remove then
        m.signOutWaits = 0
        m.signOutTimer = CreateObject("roSGNode", "Timer")
        m.signOutTimer.duration = 0.25
        m.signOutTimer.repeat = true
        m.signOutTimer.observeField("fire", "SignOut_onBorrowedWait")
        m.signOutTimer.control = "start"
        return
    end if
    if remove then SignOut_removeActive()
    SignOut_finish()
end sub

' Waiting for RemoteControl to hand the borrowed profile back (it saves the TV's own session).
sub SignOut_onBorrowedWait()
    m.signOutWaits = m.signOutWaits + 1
    if Session_isTemporary(m.global.session) and m.signOutWaits < 20 then return
    m.signOutTimer.control = "stop"
    m.signOutTimer.unobserveField("fire")
    if Session_isTemporary(m.global.session) then
        print "[siku-servers] the phone's profile did not end in time; the server is kept"
        m.global.toast = Tx("Couldn't end remote playback. Try signing out again.")
    else
        SignOut_removeActive()
    end if
    SignOut_finish()
end sub

' Forgets the active server (signed out already) and makes the next saved one active, with its
' own sign-in; with none left, first-run setup.
sub SignOut_removeActive()
    s = m.global.session
    url = Str_orEmpty(s.serverUrl)
    if url = "" then return
    ' Its stored copy, if any, must not come back: drop the entry before anything saves again.
    ' Its other accounts (none when Remove Server was offered) are signed out too.
    SignOut_revokeServerAccounts(url, Str_orEmpty(s.accountId))
    Session_forgetServer(url)
    nxt = invalid
    list = Session_savedServers()
    if list.Count() > 0 then nxt = list[0]
    if nxt <> invalid then
        print "[siku-servers] removed current=true next=" + SignOut_entryState(nxt)
        Session_activateServer(nxt, ProfileLaunch_requiresSelectionAtLaunch())
    else
        print "[siku-servers] removed current=true next=setup"
        Session_clearServer()
    end if
end sub

function SignOut_entryState(e as object) as string
    if Session_serverSignedIn(Str_orEmpty(e.url)) then return "signed_in"
    return "signed_out"
end function

' Ends the stored sessions of the saved accounts on `url` (except `exceptId`) on the server, best
' effort, before the server is forgotten (MainScene sends them: they outlive this screen; an
' expired stored token is refreshed first, Api_revoke).
sub SignOut_revokeServerAccounts(url as string, exceptId as string)
    list = Accounts_onServer(Accounts_list(), url)
    for i = 0 to list.Count() - 1
        e = list[i]
        if Str_orEmpty(e.id) <> exceptId and Accounts_hasSignIn(e) then Session_queueRevoke(url, e.session)
    end for
end sub

sub SignOut_finish()
    m.signOutRunning = false
    if m.global.hasField("homeDirty") then m.global.homeDirty = true
    Nav_reset("@start")
end sub

function Session_isTemporary(s as dynamic) as boolean
    if s = invalid or Type(s) <> "roAssociativeArray" then return false
    t = s.temporary
    if Type(t) = "Boolean" or Type(t) = "roBoolean" then return t
    return false
end function

' m.signOutRunning is unset until a sign-out starts; comparing invalid with a boolean throws on a
' Roku (pitfall 16).
function SignOut_isRunning() as boolean
    return SignOut_flag(m.signOutRunning)
end function

function SignOut_flag(v as dynamic) as boolean
    if Type(v) = "Boolean" or Type(v) = "roBoolean" then return v
    return false
end function
