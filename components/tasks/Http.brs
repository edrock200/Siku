' Low-level HTTP used by ApiTask and AuthTask (Task threads only).
' SPDX-License-Identifier: AGPL-3.0-or-later

' Response bodies larger than this are not parsed (a Silo answer is far smaller; an address that
' only advertised itself on the LAN must not make Siku parse megabytes).
function Http_maxBodyChars() as integer
    return 2097152
end function

' Performs a request and returns {status, text, data, error, headers}. status is 0 when no HTTP
' answer arrived (timeout or transport failure; a transport failure also sets transportCode).
function Http_send(method as string, url as string, headers as object, body as dynamic, timeoutSec as integer) as object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.EnableEncodings(true)
    xfer.RetainBodyOnError(true)
    if LCase(Left(url, 6)) = "https:" then
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        ' Both are Roku's defaults; set explicitly so no later change can weaken them.
        xfer.EnablePeerVerification(true)
        xfer.EnableHostVerification(true)
        xfer.InitClientCertificates()
    end if
    for each k in headers
        xfer.AddHeader(k, headers[k])
    end for
    xfer.SetRequest(method)

    payload = ""
    if body <> invalid then
        if Type(body) = "roString" or Type(body) = "String" then
            payload = body
        else
            payload = FormatJson(body)
        end if
        xfer.AddHeader("Content-Type", "application/json")
    end if

    started = false
    if method = "GET" then
        started = xfer.AsyncGetToString()
    else if method = "POST" and body <> invalid then
        started = xfer.AsyncPostFromString(payload)
    else if body <> invalid then
        started = xfer.AsyncPostFromString(payload) ' SetRequest overrides the verb
    else if method = "HEAD" then
        started = xfer.AsyncHead()
    else
        started = xfer.AsyncPostFromString("")
    end if
    if not started then return { status: 0, text: "", data: invalid, error: { code: "network", title: Tx("Could not start request") } }

    ' Only this transfer's completion counts; anything else on the port is skipped.
    clock = CreateObject("roTimespan")
    limitMs = timeoutSec * 1000
    msg = invalid
    while msg = invalid
        remainMs = limitMs - clock.TotalMilliseconds()
        if remainMs <= 0 then exit while
        ev = Wait(remainMs, port)
        if ev = invalid then exit while
        if Type(ev) = "roUrlEvent" then
            if ev.GetSourceIdentity() = xfer.GetIdentity() and ev.GetInt() = 1 then msg = ev
        end if
    end while
    if msg = invalid then
        xfer.AsyncCancel()
        return { status: 0, text: "", data: invalid, error: { code: "timeout", title: Tx("The server took too long to answer") } }
    end if

    status = msg.GetResponseCode()
    failure = Http_failureText(status, msg.GetFailureReason())
    transportCode = invalid
    if status < 0 then
        transportCode = status
        status = 0
    end if
    text = msg.GetString()
    if text = invalid then text = ""
    if Len(text) > Http_maxBodyChars() then
        print "[Http] response body over the limit ("; Len(text); " chars) refused"
        return { status: 0, text: "", data: invalid, error: { code: "too_large", title: Tx("The server's answer was too large") } }
    end if
    data = invalid
    if status > 0 and Len(text) > 0 then data = ParseJson(text)
    result = { status: status, text: text, data: data, error: invalid, headers: msg.GetResponseHeaders() }
    if transportCode <> invalid then result.transportCode = transportCode
    if status < 200 or status >= 300 then
        result.error = Http_problem(status, data, failure)
    end if
    return result
end function

' Roku reports DNS, connection, reset and TLS failures as a negative curl code, while every caller
' tests `status = 0` for "the server did not answer". Http_send/Http_download clamp the code to 0;
' this keeps the curl code in the failure text for the console (pure; tests/test_http_status.py).
function Http_failureText(status as dynamic, failure as dynamic) as string
    reason = Str_orEmpty(failure)
    s = Int(Num_or(status, 0))
    if s >= 0 then return reason
    if reason <> "" then reason = reason + " "
    return reason + "(curl " + s.ToStr() + ")"
end function

' A GET whose body is saved to path (tmp: only; ApiTask checks), not parsed. Returns
' {status, text, data: {path} or invalid, error}. A failed or refused download leaves no file.
function Http_download(url as string, headers as object, path as string, timeoutSec as integer) as object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    if LCase(Left(url, 6)) = "https:" then
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        xfer.EnablePeerVerification(true)
        xfer.EnableHostVerification(true)
        xfer.InitClientCertificates()
    end if
    for each k in headers
        xfer.AddHeader(k, headers[k])
    end for
    files = CreateObject("roFileSystem")
    if files.Exists(path) then files.Delete(path)
    if not xfer.AsyncGetToFile(path) then return { status: 0, text: "", data: invalid, error: { code: "network", title: Tx("Could not start request") } }
    clock = CreateObject("roTimespan")
    limitMs = timeoutSec * 1000
    msg = invalid
    while msg = invalid
        remainMs = limitMs - clock.TotalMilliseconds()
        if remainMs <= 0 then exit while
        ev = Wait(remainMs, port)
        if ev = invalid then exit while
        if Type(ev) = "roUrlEvent" then
            if ev.GetSourceIdentity() = xfer.GetIdentity() and ev.GetInt() = 1 then msg = ev
        end if
    end while
    if msg = invalid then
        xfer.AsyncCancel()
        if files.Exists(path) then files.Delete(path)
        return { status: 0, text: "", data: invalid, error: { code: "timeout", title: Tx("The server took too long to answer") } }
    end if
    status = msg.GetResponseCode()
    failure = Http_failureText(status, msg.GetFailureReason())
    if status < 0 then status = 0
    if status < 200 or status >= 300 or not files.Exists(path) then
        if files.Exists(path) then files.Delete(path)
        return { status: status, text: "", data: invalid, error: Http_problem(status, invalid, failure) }
    end if
    return { status: status, text: "", data: { path: path }, error: invalid, headers: msg.GetResponseHeaders() }
end function

' Turns an RFC 7807 problem body into {code, title, detail}.
function Http_problem(status as integer, data as dynamic, failure as dynamic) as object
    code = ""
    title = ""
    detail = ""
    if data <> invalid and Type(data) = "roAssociativeArray" then
        t = Str_orEmpty(data.type)
        if t <> "" then
            parts = t.Split("/")
            code = parts[parts.Count() - 1]
        end if
        title = Str_orEmpty(data.title)
        detail = Str_orEmpty(data.detail)
        if code = "" and data.code <> invalid then code = Str_orEmpty(data.code)
        if title = "" and data.error <> invalid and Type(data.error) <> "roAssociativeArray" then title = Str_orEmpty(data.error)
    end if
    if status <= 0 then
        code = "network"
        title = Tx("Can't reach the server")
        if failure <> invalid then detail = failure
    end if
    ' Stays English: Api_reasonText and ServerAddr_serverMessage recognise this stand-in by its prefix.
    if title = "" then title = "Something went wrong (" + status.ToStr() + ")"
    ' A temporary password (Silo Android #790): the server's detail is a protocol instruction, so
    ' every screen that shows the title or detail gets text a person can act on instead.
    if code = PasswordChange_code() then
        title = PasswordChange_message()
        detail = title
    end if
    ' shown: the catalog's text for this problem type in a non-English interface (error.<type>,
    ' Silo's docs/architecture/i18n.md), "" in English or when the catalog lacks it. title and
    ' detail stay the server's English: code matches on them; screens show `shown` first.
    shown = ""
    if code <> "" and code <> "network" and code <> PasswordChange_code() then shown = TxKey("error." + code, invalid, "")
    return { code: code, title: title, detail: detail, shown: shown }
end function

' Device identification headers sent on every request (docs/api-spec.md §2.3), except anonymous
' probes (`anonymous: true` on an ApiTask request), which send only Accept.
function Http_deviceHeaders(session as object) as object
    di = CreateObject("roDeviceInfo")
    ai = CreateObject("roAppInfo")
    return {
        "Accept": "application/json"
        "X-Silo-Device-Id": session.deviceId
        "X-Silo-Device-Name": "Roku " + di.GetModelDisplayName()
        "X-Silo-Device-Platform": "roku"
        "X-Silo-Client": "Siku"
        "X-Silo-Client-Version": ai.GetVersion()
        "X-Silo-Client-Channel": "sideload"
        "X-Silo-Client-Family": "tv"
    }
end function

' ---------- Token refresh (Task threads only: roMessagePort + Wait) ----------

' What a refresh answer means (pure; tests/test_auth_refresh.py; AuthTask and Api_revoke's ApiTask):
'   "ok"       a usable token response
'   "rejected" 400/401: the refresh token is invalid (api-spec §2.4 session_expired) -> sign in again
'   "retry"    anything else: unreachable, 5xx, 429, 403, a 200 without a token; the session stays
function AuthTask_outcome(status as dynamic, data as dynamic) as string
    s = Int(Num_or(status, 0))
    if s >= 200 and s < 300 then
        if Type(data) = "roAssociativeArray" then
            t = data.access_token
            if (Type(t) = "roString" or Type(t) = "String") and not Str_isEmpty(t) then return "ok"
        end if
        return "retry"
    end if
    if s = 400 or s = 401 then return "rejected"
    return "retry"
end function


' Asks the single AuthTask to refresh the access token a request sent (`tokenUsed`), then waits
' for AuthTask to answer this request. Returns true when a newer usable token exists.
function Auth_refresh(tokenUsed as string) as boolean
    auth = m.global.authTask
    if auth = invalid or Str_isEmpty(tokenUsed) then return false
    current = m.global.session.accessToken
    if current <> tokenUsed and not Str_isEmpty(current) then return true ' someone already refreshed
    port = CreateObject("roMessagePort")
    ' Scoped: unobserving must remove this task's observer only. A plain unobserveField removes
    ' every observer of the field, so the other requests waiting on parallel 401s would never wake
    ' and would sit out the whole wait.
    auth.observeFieldScoped("answered", port)
    id = CreateObject("roDeviceInfo").GetRandomUUID()
    auth.refreshRequest = { token: tokenUsed, id: id }
    ' Only the wake-up matters; the session itself tells us the outcome. Other requests' answers
    ' arrive on the same field and are skipped.
    clock = CreateObject("roTimespan")
    limitMs = Auth_waitSeconds() * 1000
    while true
        remainMs = limitMs - clock.TotalMilliseconds()
        if remainMs <= 0 then exit while
        ev = Wait(remainMs, port)
        if ev = invalid then exit while
        if Type(ev) = "roSGNodeEvent" and Str_orEmpty(ev.getData()) = id then exit while
    end while
    auth.unobserveFieldScoped("answered")
    return not Str_isEmpty(m.global.session.accessToken) and m.global.session.accessToken <> tokenUsed
end function

' How long a request waits for AuthTask: longer than one refresh's worst case
' (AuthTask_worstCaseSeconds, 41 s; tests/test_auth_refresh.py keeps the two in step), plus room
' for one refresh already running ahead of it.
function Auth_waitSeconds() as integer
    return 90
end function
