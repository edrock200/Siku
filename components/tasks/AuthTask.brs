' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.top.functionName = "loop"
end sub

sub loop()
    port = CreateObject("roMessagePort")
    m.top.observeField("refreshRequest", port)
    while true
        msg = Wait(0, port)
        if Type(msg) = "roSGNodeEvent" then
            req = msg.getData()
            session = m.global.session
            if req <> invalid and req.token = session.accessToken and not Str_isEmpty(session.refreshToken) then
                doRefresh(session)
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
        r = Http_send("POST", session.serverUrl + "/api/v2/auth/refresh", headers, { refresh_token: session.refreshToken }, 20)
        if not Auth_isSameLogin(session) then return ' signed out or switched server meanwhile: drop the answer
        if r.status = 200 and Type(r.data) = "roAssociativeArray" and not Str_isEmpty(r.data.access_token) then
            ' Apply the tokens to the session as it is now, not to the snapshot taken before the call.
            Session_save(Session_withTokens(m.global.session, r.data))
            return
        end if
        if r.status = 400 or r.status = 401 or r.status = 403 then
            print "[siku-auth] refresh rejected ("; r.status; "); signing out"
            m.global.authExpired = true
            return
        end if
        print "[siku-auth] refresh attempt "; attempt; " failed (status "; r.status; "); session kept"
    end while
end sub

' True while m.global.session still holds the login `session` was taken from.
function Auth_isSameLogin(session as object) as boolean
    cur = m.global.session
    if cur = invalid then return false
    return Str_orEmpty(cur.serverUrl) = Str_orEmpty(session.serverUrl) and Str_orEmpty(cur.accessToken) = Str_orEmpty(session.accessToken) and Str_orEmpty(cur.refreshToken) = Str_orEmpty(session.refreshToken)
end function
