' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    req = m.top.request
    if req = invalid then req = {}
    resp = perform(req)
    ' A 401 means the access token was rejected: refresh once (single-flight via AuthTask) and retry.
    if resp.status = 401 and req.auth <> false then
        if Auth_refresh(m.global.session.accessToken) then
            resp = perform(req)
        else
            m.global.authExpired = true
        end if
    end if
    resp.ok = resp.status >= 200 and resp.status < 300
    resp.context = req.context
    m.top.response = resp
end sub

function perform(req as object) as object
    session = m.global.session
    method = UCase(Str_orEmpty(req.method))
    if method = "" then method = "GET"

    ' Proactive refresh when the token is about to expire.
    if req.auth <> false and not Str_isEmpty(session.refreshToken) and session.expiresAt > 0 then
        if Time_nowSeconds() > session.expiresAt - 60 then
            Auth_refresh(session.accessToken)
            session = m.global.session
        end if
    end if

    if not Str_isEmpty(req.url) then
        url = req.url
    else if Left(Str_orEmpty(req.path), 8) <> "/api/v2/" then
        ' Soku speaks only the Silo v2 API (docs/api-spec.md §0); v1 is a frozen alpha surface.
        print "[ApiTask] refused non-v2 path: "; req.path
        return { status: 0, text: "", data: invalid, error: { code: "not_v2", title: "Unsupported API path" } }
    else
        base = req.baseUrl
        if Str_isEmpty(base) then base = session.serverUrl
        url = base + req.path
    end if
    qs = Str_queryString(req.query)
    if qs <> "" then
        if Instr(1, url, "?") > 0 then url = url + "&" + qs else url = url + "?" + qs
    end if

    headers = Http_deviceHeaders(session)
    if req.auth <> false and not Str_isEmpty(session.accessToken) then
        headers["Authorization"] = "Bearer " + session.accessToken
    end if
    if req.profile <> false and not Str_isEmpty(session.profileId) then
        headers["X-Profile-Id"] = session.profileId
        if not Str_isEmpty(session.profileToken) then headers["X-Profile-Token"] = session.profileToken
    end if
    if req.headers <> invalid then
        for each k in req.headers
            headers[k] = req.headers[k]
        end for
    end if

    timeout = 20
    if req.timeout <> invalid then timeout = req.timeout
    return Http_send(method, url, headers, req.body, timeout)
end function

' Asks the single AuthTask to refresh, then waits for it. Returns true when a usable token exists.
function Auth_refresh(tokenUsed as string) as boolean
    auth = m.global.authTask
    if auth = invalid then return false
    port = CreateObject("roMessagePort")
    auth.observeField("generation", port)
    current = m.global.session.accessToken
    if current <> tokenUsed and not Str_isEmpty(current) then
        auth.unobserveField("generation")
        return true ' someone already refreshed
    end if
    auth.refreshRequest = { token: tokenUsed }
    msg = Wait(30000, port)
    auth.unobserveField("generation")
    return not Str_isEmpty(m.global.session.accessToken) and m.global.session.accessToken <> tokenUsed
end function
