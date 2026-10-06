' Low-level HTTP used by ApiTask and AuthTask (Task threads only).
' SPDX-License-Identifier: AGPL-3.0-or-later

' Performs a request and returns {status, text, data, error, headers}.
function Http_send(method as string, url as string, headers as object, body as dynamic, timeoutSec as integer) as object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.EnableEncodings(true)
    xfer.RetainBodyOnError(true)
    if LCase(Left(url, 5)) = "https" then
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
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
    if not started then return { status: 0, text: "", data: invalid, error: { code: "network", title: "Could not start request" } }

    msg = Wait(timeoutSec * 1000, port)
    if msg = invalid then
        xfer.AsyncCancel()
        return { status: 0, text: "", data: invalid, error: { code: "timeout", title: "The server took too long to answer" } }
    end if
    if Type(msg) <> "roUrlEvent" then
        return { status: 0, text: "", data: invalid, error: { code: "network", title: "Network error" } }
    end if

    status = msg.GetResponseCode()
    text = msg.GetString()
    if text = invalid then text = ""
    data = invalid
    if Len(text) > 0 then data = ParseJson(text)
    result = { status: status, text: text, data: data, error: invalid, headers: msg.GetResponseHeaders() }
    if status < 200 or status >= 300 then
        result.error = Http_problem(status, data, msg.GetFailureReason())
    end if
    return result
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
        title = "Can't reach the server"
        if failure <> invalid then detail = failure
    end if
    if title = "" then title = "Something went wrong (" + status.ToStr() + ")"
    return { code: code, title: title, detail: detail }
end function

' Device identification headers sent on every request (docs/api-spec.md §2.3).
function Http_deviceHeaders(session as object) as object
    di = CreateObject("roDeviceInfo")
    ai = CreateObject("roAppInfo")
    return {
        "Accept": "application/json"
        "X-Silo-Device-Id": session.deviceId
        "X-Silo-Device-Name": "Roku " + di.GetModelDisplayName()
        "X-Silo-Device-Platform": "roku"
        "X-Silo-Client": "Soku"
        "X-Silo-Client-Version": ai.GetVersion()
        "X-Silo-Client-Channel": "sideload"
        "X-Silo-Client-Family": "tv"
    }
end function
