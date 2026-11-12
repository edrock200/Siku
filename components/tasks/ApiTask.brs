' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    req = m.top.request
    if req = invalid then req = {}
    if Type(req.revoke) = "roAssociativeArray" then
        ' Api_revoke: its own refresh rules, never the active session's.
        resp = ApiTask_revoke(req)
        resp.ok = resp.status >= 200 and resp.status < 300
        resp.context = req.context
        m.top.response = resp
        return
    end if
    resp = perform(req)
    ' A 401 means the access token was rejected: refresh once (single-flight via AuthTask) and retry.
    ' With no token at all (signed out meanwhile, e.g. the logout call itself) there is nothing to refresh.
    ' noRefresh (a playback route event): one attempt with the token at hand, nothing more.
    if resp.status = 401 and req.auth <> false and not noRefresh(req) and not Str_isEmpty(m.global.session.accessToken) then
        ' Refresh the token this request actually sent: one already replaced meanwhile counts as done.
        if Auth_refresh(m.sentToken) then
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

' True when the caller asked for no token refresh (read loosely: a missing flag is false).
function noRefresh(req as object) as boolean
    v = req.noRefresh
    if Type(v) = "roBoolean" or Type(v) = "Boolean" then return v
    return false
end function

function perform(req as object) as object
    session = m.global.session
    m.sentToken = ""
    method = UCase(Str_orEmpty(req.method))
    if method = "" then method = "GET"

    ' Proactive refresh when the token is about to expire.
    if req.auth <> false and not noRefresh(req) and not Str_isEmpty(session.refreshToken) and session.expiresAt > 0 then
        if Time_nowSeconds() > session.expiresAt - 60 then
            Auth_refresh(session.accessToken)
            session = m.global.session
        end if
    end if

    refusal = ApiTask_refusal(req)
    if refusal <> "" then
        ' Siku speaks only the Silo v2 API (docs/api-spec.md §0); v1 is a frozen alpha surface.
        print "[ApiTask] refused request: "; refusal
        return { status: 0, text: "", data: invalid, error: { code: "not_v2", title: Tx("Unsupported API path") } }
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

    ' A file download (card overlay images): only a GET, only into tmp:, and its body is not parsed.
    saveTo = Str_orEmpty(req.saveTo)
    if saveTo <> "" and (method <> "GET" or Left(saveTo, 5) <> "tmp:/" or Instr(1, saveTo, "..") > 0) then
        return { status: 0, text: "", data: invalid, error: { code: "bad_download", title: Tx("Unsupported download") } }
    end if

    if isAnonymous(req) then
        ' An address that only advertised itself (Find servers) gets no credentials and no device
        ' metadata, as on Silo Android (LanServerProbe): Accept is the only header.
        m.sentProfile = invalid
        timeout = 8
        if req.timeout <> invalid then timeout = req.timeout
        return Http_send(method, url, { "Accept": "application/json" }, req.body, timeout)
    end if
    headers = Http_deviceHeaders(session)
    if req.auth <> false and not Str_isEmpty(session.accessToken) then
        headers["Authorization"] = "Bearer " + session.accessToken
        m.sentToken = session.accessToken
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
    if saveTo <> "" then return Http_download(url, headers, saveTo, timeout)
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

' True only for a request that sets anonymous: true (a missing flag is never compared with a boolean).
function isAnonymous(req as object) as boolean
    v = req.anonymous
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function

' ---------- Ending a sign-in on its server (Api_revoke) ----------

' POST /auth/logout with the sign-in's access token. A token that has expired (or is about to) is
' refreshed first with its refresh token, and so is one the logout refuses with 401: the stored
' access token of a stashed account, or of the open one after an hour idle, has usually expired,
' and a refused logout would leave that session and its refresh token alive on the server. The
' refreshed tokens serve this logout only and are never stored. A refresh the server rejects
' (400/401) means the session has already ended there. Logs the outcome, never a token.
function ApiTask_revoke(req as object) as object
    refusal = ApiTask_refusal(req)
    if refusal <> "" then
        print "[ApiTask] refused request: "; refusal
        return { status: 0, text: "", data: invalid, error: { code: "not_v2", title: Tx("Unsupported API path") } }
    end if
    rv = req.revoke
    base = Str_orEmpty(req.baseUrl)
    access = Str_orEmpty(rv.access)
    refreshTok = Str_orEmpty(rv["refresh"])
    timeout = 5
    if req.timeout <> invalid then timeout = Int(Num_or(req.timeout, 5))
    headers = Http_deviceHeaders(m.global.session)
    refreshed = "no"
    resp = invalid
    if ApiTask_revokeRefreshFirst(access, refreshTok, Accounts_int(rv.expiresAt), Time_nowSeconds()) then
        r = ApiTask_revokeRefresh(base, headers, refreshTok, timeout)
        refreshed = r.outcome
        if r.outcome = "rejected" then return ApiTask_revokeDone("ended", refreshed, r.resp)
        if r.outcome = "ok" then access = r.access
    end if
    if access <> "" then
        resp = ApiTask_logout(base, headers, access, timeout)
        if resp.status = 401 and refreshed = "no" and refreshTok <> "" then
            r = ApiTask_revokeRefresh(base, headers, refreshTok, timeout)
            refreshed = r.outcome
            if r.outcome = "rejected" then return ApiTask_revokeDone("ended", refreshed, r.resp)
            if r.outcome = "ok" then resp = ApiTask_logout(base, headers, r.access, timeout)
        end if
    end if
    if resp = invalid then resp = { status: 0, text: "", data: invalid, error: { code: "network", title: Tx("Can't reach the server") } }
    outcome = "failed"
    if resp.status >= 200 and resp.status < 300 then outcome = "revoked"
    return ApiTask_revokeDone(outcome, refreshed, resp)
end function

' Whether Api_revoke refreshes before its logout (pure; tests/test_auth_refresh.py): no access token,
' or one that expires within a minute, with a refresh token to use.
function ApiTask_revokeRefreshFirst(access as string, refreshTok as string, expiresAt as integer, now as integer) as boolean
    if refreshTok = "" then return false
    if access = "" then return true
    return expiresAt > 0 and now > expiresAt - 60
end function

function ApiTask_revokeRefresh(base as string, headers as object, refreshTok as string, timeout as integer) as object
    r = Http_send("POST", base + "/api/v2/auth/refresh", headers, { refresh_token: refreshTok }, timeout)
    outcome = AuthTask_outcome(r.status, r.data)
    access = ""
    if outcome = "ok" then access = Str_orEmpty(r.data.access_token)
    return { outcome: outcome, access: access, resp: r }
end function

function ApiTask_logout(base as string, headers as object, access as string, timeout as integer) as object
    h = AA_copy(headers)
    h["Authorization"] = "Bearer " + access
    return Http_send("POST", base + "/api/v2/auth/logout", h, invalid, timeout)
end function

' The answer for Api_revoke's caller: the logout's (or, when the session had already ended, the
' refresh's with ok true), plus revokeOutcome "revoked" | "ended" | "failed".
function ApiTask_revokeDone(outcome as string, refreshed as string, resp as object) as object
    Diag_log("[siku-auth] logout outcome=" + outcome + " refreshed=" + refreshed + " status=" + Str_orEmpty(resp.status))
    out = AA_copy(resp)
    if outcome = "ended" then
        out.status = 204
        out.error = invalid
    end if
    out.revokeOutcome = outcome
    return out
end function
