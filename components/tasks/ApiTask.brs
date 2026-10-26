' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    req = m.top.request
    if req = invalid then req = {}
    resp = perform(req)
    ' A 401 means the access token was rejected: refresh once (single-flight via AuthTask) and retry.
    ' With no token at all (signed out meanwhile, e.g. the logout call itself) there is nothing to refresh.
    if resp.status = 401 and req.auth <> false and not Str_isEmpty(m.global.session.accessToken) then
        if Auth_refresh(m.global.session.accessToken) then
            resp = perform(req)
        else if Str_isEmpty(m.global.session.refreshToken) then
            ' Nothing to refresh with: the user has to sign in again. A refresh token the server
            ' rejected is flagged by AuthTask itself; a refresh that merely failed to reach the
            ' server keeps the session (the caller just sees the 401).
            m.global.authExpired = true
        end if
    end if
    resp.ok = resp.status >= 200 and resp.status < 300
    reportStaleProfile(req, resp)
    resp.context = req.context
    m.top.response = resp
end sub

' 403 profile_verification_required: the server stopped accepting the profile proof this request
' presented (an administrator changed the account's access). Report the identity that was sent;
' MainScene clears the profile selection only if it is still the active one (Android TV
' AccessChangeSignals.reportStaleProfileIfRefused, upstream #440). Household management (profile
' create/edit/delete and the household list) uses the same code for a missing permission, so it
' never reports.
sub reportStaleProfile(req as object, resp as object)
    if resp.status <> 403 or resp.error = invalid then return
    if Str_orEmpty(resp.error.code) <> "profile_verification_required" then return
    sent = m.sentProfile
    if sent = invalid or Str_isEmpty(sent.profileId) then return
    path = Str_orEmpty(req.path)
    method = UCase(Str_orEmpty(req.method))
    if method = "" then method = "GET"
    if Left(path, 16) = "/api/v2/profiles" and Right(path, 11) <> "/verify-pin" then
        if method <> "GET" or Instr(1, path, "/profiles/household") > 0 then return
    end if
    print "[ApiTask] stale profile proof: "; method; " "; path
    m.global.staleProfile = { profileId: sent.profileId, profileToken: sent.profileToken, serverUrl: sent.serverUrl, at: CreateObject("roDateTime").AsSeconds(), path: path }
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

    refusal = ApiTask_refusal(req)
    if refusal <> "" then
        ' Siku speaks only the Silo v2 API (docs/api-spec.md §0); v1 is a frozen alpha surface.
        print "[ApiTask] refused request: "; refusal
        return { status: 0, text: "", data: invalid, error: { code: "not_v2", title: "Unsupported API path" } }
    end if
    if not Str_isEmpty(req.url) then
        url = req.url
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
    m.sentProfile = invalid
    if req.profile <> false and not Str_isEmpty(session.profileId) then
        headers["X-Profile-Id"] = session.profileId
        if not Str_isEmpty(session.profileToken) then headers["X-Profile-Token"] = session.profileToken
        m.sentProfile = { profileId: session.profileId, profileToken: Str_orEmpty(session.profileToken), serverUrl: Str_orEmpty(session.serverUrl) }
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

' Why a request may not be sent ("" = it may): Siku calls the Silo v2 API only. A `path` must be
' under /api/v2/ with no dot segments (/api/v2/../v1 would reach v1); an absolute `url` must be
' http(s) and its path likewise under /api/v2/; a `baseUrl` (a server being probed, or one a phone
' pushed over the LAN) must be a bare http(s) origin or path prefix, with no query or fragment that
' would turn the v2 path into a parameter of some other route (pure; tests/test_api_guard.py).
function ApiTask_refusal(req as object) as string
    u = Str_orEmpty(req.url)
    if u <> "" then
        lower = LCase(u)
        if Left(lower, 7) = "http://" then
            rest = Mid(u, 8)
        else if Left(lower, 8) = "https://" then
            rest = Mid(u, 9)
        else
            return "url is not http(s)"
        end if
        slash = Instr(1, rest, "/")
        if slash = 0 then return "url has no /api/v2/ path"
        return ApiTask_pathRefusal(Mid(rest, slash))
    end if
    base = Str_orEmpty(req.baseUrl)
    if base <> "" then
        lb = LCase(base)
        if Left(lb, 7) <> "http://" and Left(lb, 8) <> "https://" then return "baseUrl is not http(s)"
        if Instr(1, base, "?") > 0 or Instr(1, base, "#") > 0 or Instr(1, base, "\") > 0 then return "baseUrl has a query or fragment"
        if Instr(1, base, "/..") > 0 or Instr(1, base, "/./") > 0 then return "baseUrl has dot segments"
    end if
    return ApiTask_pathRefusal(Str_orEmpty(req.path))
end function

function ApiTask_pathRefusal(path as string) as string
    if Left(path, 8) <> "/api/v2/" then return "not a /api/v2/ path: " + Left(path, 40)
    p = path
    q = Instr(1, p, "?")
    if q > 0 then p = Left(p, q - 1)
    h = Instr(1, p, "#")
    if h > 0 then p = Left(p, h - 1)
    if Instr(1, p, "\") > 0 then return "backslash in path"
    lp = LCase(p).Replace("%2e", ".").Replace("%2f", "/")
    for each seg in lp.Split("/")
        if seg = "." or seg = ".." then return "dot segment in path"
    end for
    return ""
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
    Wait(30000, port) ' only the wake-up matters; the session itself tells us the outcome
    auth.unobserveField("generation")
    return not Str_isEmpty(m.global.session.accessToken) and m.global.session.accessToken <> tokenUsed
end function
