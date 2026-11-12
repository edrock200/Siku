' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.top.functionName = "loop"
end sub

sub loop()
    port = CreateObject("roMessagePort")
    m.top.observeField("refreshRequest", port)
    m.failed = { token: "", at: 0 }
    while true
        msg = Wait(0, port)
        if Type(msg) = "roSGNodeEvent" then
            req = msg.getData()
            session = m.global.session
            if req <> invalid and req.token = session.accessToken and not Str_isEmpty(session.refreshToken) then
                ' A refresh for this token just failed after its retries: the requests queued behind
                ' it (N parallel 401s) get the same answer at once instead of another round each.
                if m.failed.token = req.token and Time_nowSeconds() - m.failed.at < AuthTask_failureHoldSeconds() then
                    Diag_log("[siku-auth] refresh skipped: the last attempt for this token failed moments ago")
                else
                    doRefresh(session)
                end if
            end if
            if req <> invalid and req.id <> invalid then m.top.answered = Str_orEmpty(req.id)
            m.top.generation = m.top.generation + 1
        end if
    end while
end sub

' One refresh with retries. Worst case: AuthTask_attempts() transfers of AuthTask_timeoutSeconds()
' plus the back-off sleeps (AuthTask_worstCaseSeconds); Auth_refresh waits longer than that.
sub doRefresh(session as object)
    headers = Http_deviceHeaders(session)
    attempt = 0
    while true
        r = Http_send("POST", session.serverUrl + "/api/v2/auth/refresh", headers, { refresh_token: session.refreshToken }, AuthTask_timeoutSeconds())
        outcome = AuthTask_outcome(r.status, r.data)
        if outcome = "ok" then
            saveTokens(session.refreshToken, r.data)
            m.failed = { token: "", at: 0 }
            Diag_log("[siku-auth] refresh ok")
            return
        end if
        code = ""
        if r.error <> invalid then code = Str_orEmpty(r.error.code)
        if outcome = "rejected" then
            ' 400/401 (session_expired, invalid_grant): the refresh token is no longer valid, so
            ' the user must sign in again — unless the session moved on meanwhile (a new sign-in).
            Diag_log(Diag_join(["[siku-auth] refresh rejected status=", r.status, " code=", code]))
            if m.global.session.refreshToken = session.refreshToken then m.global.authExpired = true
            return
        end if
        ' Anything else (no answer, 5xx, 429, 403, a 200 that is not a token): keep the session.
        attempt = attempt + 1
        Diag_log(Diag_join(["[siku-auth] refresh failed status=", r.status, " code=", code, " attempt=", attempt]))
        if attempt >= AuthTask_attempts() then exit while
        Sleep(AuthTask_backoffMs(attempt))
    end while
    ' Give up quietly: the caller sees its error; the next request tries again.
    Diag_log("[siku-auth] refresh gave up, keeping the session")
    m.failed = { token: session.accessToken, at: Time_nowSeconds() }
end sub

' Merges only the new tokens into the session as it is now, so a profile switch or a profile
' clear made while the refresh was in flight is kept. When the refresh token changed meanwhile
' (sign-out, a new sign-in, another server) the answer belongs to a session that is gone.
sub saveTokens(usedRefreshToken as string, data as object)
    current = m.global.session
    ' Only the token fields: a response carrying `user` would read as a new sign-in and drop the profile.
    tokens = { access_token: data.access_token, refresh_token: data.refresh_token, expires_in: data.expires_in }
    if current.refreshToken = usedRefreshToken then
        Session_save(Session_withTokens(current, tokens))
        return
    end if
    ' The session changed meanwhile, but the refresh token rotated on the server, so the old one is
    ' spent: the pair belongs wherever the used token lives now, or that sign-in breaks later.
    where = AuthTask_rotatedHome(current, Registry_read("session"), usedRefreshToken)
    if where = "own" then
        ' The TV's own sign-in while a phone's profile is borrowed: saved through Session_save, so
        ' RemoteControl keeps it for the hand-back (isOwnRefresh) and puts the borrowed one back.
        own = Session_withTokens(Registry_read("session"), tokens)
        own.Delete("temporary")
        Diag_log("[siku-auth] refresh answer kept for the TV's own sign-in")
        Session_save(own)
        return
    end if
    fresh = Session_withTokens({}, tokens)
    r = Accounts_withRotatedTokens(Accounts_list(), usedRefreshToken, fresh.accessToken, Str_orEmpty(data.refresh_token), fresh.expiresAt)
    if r.found then
        Registry_write("accounts", r.list)
        Diag_log("[siku-auth] refresh answer kept for a saved account")
        return
    end if
    Diag_log("[siku-auth] refresh answer dropped: the session changed meanwhile")
end sub

' Where a refresh answer goes when the published session no longer holds the used refresh token
' (pure; tests/test_auth_refresh.py): "own" when the registry session still does under a phone's
' borrowed (temporary) profile, else "accounts" (a saved account's stored sign-in, if any holds it).
function AuthTask_rotatedHome(current as dynamic, stored as dynamic, usedRefreshToken as string) as string
    if usedRefreshToken = "" then return "accounts"
    if stored = invalid or Type(stored) <> "roAssociativeArray" then return "accounts"
    if Accounts_isTemporary(current) and Str_orEmpty(stored.refreshToken) = usedRefreshToken then return "own"
    return "accounts"
end function

function AuthTask_attempts() as integer
    return 3
end function

function AuthTask_timeoutSeconds() as integer
    return 12
end function

function AuthTask_backoffMs(attempt as integer) as integer
    return 1500 * attempt
end function

function AuthTask_failureHoldSeconds() as integer
    return 15
end function

' The longest one refresh can take (3 x 12 s transfers + 1.5 s + 3 s back-off = 40.5 s).
function AuthTask_worstCaseSeconds() as integer
    total = AuthTask_attempts() * AuthTask_timeoutSeconds()
    for i = 1 to AuthTask_attempts() - 1
        total = total + AuthTask_backoffMs(i) / 1000
    end for
    return Int(total + 0.999)
end function
