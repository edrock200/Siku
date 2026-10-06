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

sub doRefresh(session as object)
    headers = Http_deviceHeaders(session)
    attempt = 0
    while attempt < 3
        r = Http_send("POST", session.serverUrl + "/api/v2/auth/refresh", headers, { refresh_token: session.refreshToken }, 20)
        if r.status = 200 and r.data <> invalid and not Str_isEmpty(r.data.access_token) then
            Session_save(Session_withTokens(session, r.data))
            return
        end if
        ' 503 provider_unavailable or a network error: keep the session, try again shortly.
        if r.status = 0 or r.status = 503 or r.status = 429 then
            attempt = attempt + 1
            Sleep(1500 * attempt)
        else
            ' 400/401: the refresh token is no longer valid — the user must sign in again.
            m.global.authExpired = true
            return
        end if
    end while
end sub
