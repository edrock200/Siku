' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.top.functionName = "loop"
end sub

sub loop()
    port = CreateObject("roMessagePort")
    m.top.observeField("refreshRequest", port)
    ' The token whose last refresh failed for a temporary reason, and when. Requests that queued
    ' behind that attempt are answered at once for a short while instead of each running another
    ' full retry cycle against a server that is down.
    m.failedToken = ""
    m.failedAt = 0
    while true
        msg = Wait(0, port)
        if Type(msg) = "roSGNodeEvent" then
            req = msg.getData()
            session = m.global.session
            if req <> invalid and req.token = session.accessToken and not Str_isEmpty(session.refreshToken) then
                coolingDown = (m.failedToken = session.accessToken) and (Time_nowSeconds() - m.failedAt < 10)
                if not coolingDown then doRefresh(session)
            end if
            m.top.generation = m.top.generation + 1
        end if
    end while
end sub

' Refreshes the tokens of `session`. Only a refresh token the server rejects (400/401/403) signs
' the user out, as on Android TV; a network failure, timeout, 5xx, redirect or non-JSON answer is
' temporary: retry with backoff, then keep the session so the next request tries again.
sub doRefresh(session as object)
    headers = Http_deviceHeaders(session)
    attempt = 0
    while attempt < 3
        if attempt > 0 then Sleep(1500 * attempt)
        attempt = attempt + 1
        ' 8 s per attempt keeps the whole cycle (about 28 s) inside ApiTask's 30 s wait.
        r = Http_send("POST", session.serverUrl + "/api/v2/auth/refresh", headers, { refresh_token: session.refreshToken }, 8)
        if not Auth_isSameLogin(session) then return ' signed out or switched server meanwhile: drop the answer
        if r.status = 200 and Type(r.data) = "roAssociativeArray" and not Str_isEmpty(r.data.access_token) then
            ' Apply the tokens to the session as it is now, not to the snapshot taken before the call.
            Session_save(Session_withTokens(m.global.session, r.data))
            m.failedToken = ""
            return
        end if
        if r.status = 400 or r.status = 401 or r.status = 403 then
            print "[siku-auth] refresh rejected ("; r.status; "); signing out"
            m.global.authExpired = true
            return
        end if
        print "[siku-auth] refresh attempt "; attempt; " failed (status "; r.status; "); session kept"
    end while
    m.failedToken = session.accessToken
    m.failedAt = Time_nowSeconds()
end sub

' True while m.global.session still holds the login `session` was taken from.
function Auth_isSameLogin(session as object) as boolean
    cur = m.global.session
    if cur = invalid then return false
    return Str_orEmpty(cur.serverUrl) = Str_orEmpty(session.serverUrl) and Str_orEmpty(cur.accessToken) = Str_orEmpty(session.accessToken) and Str_orEmpty(cur.refreshToken) = Str_orEmpty(session.refreshToken)
end function
