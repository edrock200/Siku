' Helpers for calling the Silo API from a component (render thread).
' Usage:
'   Api_get("/api/v2/home/sections", {image_size: "medium"}, "onHome")
'   sub onHome(event as object)
'       resp = Api_result(event)
'       if resp.ok then ... resp.data ...
'   end sub
' SPDX-License-Identifier: AGPL-3.0-or-later

function Api_call(request as object, callback as string) as object
    if m.apiTasks = invalid then m.apiTasks = {}
    if m.apiSeq = invalid then m.apiSeq = 0
    m.apiSeq = m.apiSeq + 1
    task = CreateObject("roSGNode", "ApiTask")
    task.id = "api" + m.apiSeq.ToStr()
    ' Keep the caller's context here instead of round-tripping it through the Task
    ' (nested values in a Task field did not always come back in the simulator).
    if m.apiContexts = invalid then m.apiContexts = {}
    if request.context <> invalid then
        m.apiContexts[task.id] = request.context
        request = AA_copy(request)
        request.Delete("context")
    end if
    task.request = request
    task.observeField("response", callback)
    m.apiTasks[task.id] = task
    task.control = "RUN"
    ' Leaving the app (MainScene.beginExit): this request (a sign-in code withdrawn as the screen
    ' hides) holds the exit until it answers, at most 2 s.
    if m.global <> invalid and m.global.hasField("exiting") then
        if m.global.exiting = true then
            holds = m.global.exitHolds
            holds.Push(task)
            m.global.exitHolds = holds
        end if
    end if
    return task
end function

function Api_get(path as string, query = invalid as dynamic, callback = "" as string, context = invalid as dynamic) as object
    return Api_call({ method: "GET", path: path, query: query, context: context }, callback)
end function

function Api_send(method as string, path as string, body as dynamic, callback = "" as string, context = invalid as dynamic) as object
    return Api_call({ method: method, path: path, body: body, context: context }, callback)
end function

' Call from the observer: returns the response and releases the task.
function Api_result(event as object) as object
    resp = event.getData()
    task = event.getRoSGNode()
    context = invalid
    if task <> invalid and m.apiTasks <> invalid then
        task.unobserveField("response")
        m.apiTasks.Delete(task.id)
        if m.apiContexts <> invalid then
            context = m.apiContexts[task.id]
            m.apiContexts.Delete(task.id)
        end if
    end if
    if resp = invalid then resp = { ok: false, status: 0, error: { title: "No response" } }
    if context <> invalid then resp.context = context
    return resp
end function

' Fire-and-forget (mutations whose result we don't need, e.g. favorites).
sub Api_fire(method as string, path as string, body = invalid as dynamic)
    Api_call({ method: method, path: path, body: body }, "Api_onFired")
end sub

sub Api_onFired(event as object)
    resp = Api_result(event)
    if not resp.ok and resp.error <> invalid then
        print "[Api] "; resp.status; " "; resp.error.title
    end if
end sub

' Ends a sign-in on its server: POST /api/v2/auth/logout with its access token. ApiTask refreshes
' first when that token has expired, or when the logout answers 401, and uses the refreshed tokens
' for the logout only (never stored), then logs "[siku-auth] logout outcome=" (no tokens).
' signIn: {accessToken, refreshToken, expiresAt} (a session or a stored sign-in). Returns the task,
' or invalid when there is nothing to end. Background revokes go through Session_queueRevoke.
function Api_revoke(baseUrl as string, signIn as dynamic, callback = "Api_onFired" as string, context = invalid as dynamic) as dynamic
    if baseUrl = "" or signIn = invalid or Type(signIn) <> "roAssociativeArray" then return invalid
    access = Str_orEmpty(signIn.accessToken)
    refreshTok = Str_orEmpty(signIn.refreshToken)
    if access = "" and refreshTok = "" then return invalid
    return Api_call({ method: "POST", path: "/api/v2/auth/logout", baseUrl: baseUrl, auth: false, profile: false, timeout: 5, revoke: { access: access, refresh: refreshTok, expiresAt: Accounts_int(signIn.expiresAt) }, context: context }, callback)
end function

' Saves a new sign-in (password, code or a phone's approval). When the same server user had a
' saved sign-in on this Roku, that account is refreshed rather than added again (Accounts.brs), and
' the session it replaces is ended on the server, best effort, as Silo Android #795 does.
sub Api_saveSignIn(s as object)
    c = AA_copy(s)
    c.accountId = ""
    ' A sign-in is stored, never published only as a phone's borrowed profile is.
    c.Delete("temporary")
    old = Accounts_replacedSignIn(Accounts_list(), m.global.session, c)
    Session_save(c)
    if old <> invalid then
        Diag_log("[siku-accounts] signed in again as a saved account; ending the session it replaces")
        Session_queueRevoke(Str_orEmpty(c.serverUrl), old)
    end if
end sub

' Cancels all in-flight tasks this component started (call when leaving a screen).
sub Api_cancelAll()
    if m.apiTasks = invalid then return
    for each id in m.apiTasks
        t = m.apiTasks[id]
        t.unobserveField("response")
        t.control = "STOP"
    end for
    m.apiTasks = {}
end sub

' Error message to show for a failed response.
function Api_errorText(resp as object) as string
    if resp = invalid or resp.error = invalid then return Tx("Something went wrong")
    if Int(Num_or(resp.status, 0)) <= 0 then
        ' No HTTP answer: say why when the request knows (Http.brs / ApiTask error codes).
        code = Api_errorCode(resp)
        if code = "timeout" then return Tx("The server took too long to answer. Try again.")
        if code = "too_large" then return Tx("The server's answer was too large for this Roku.")
        if code = "not_v2" or code = "bad_download" then return Tx("Something went wrong")
        return Tx("Can't reach the server. Check your connection and try again.")
    end if
    if Type(resp.error) = "roAssociativeArray" and not Str_isEmpty(resp.error.shown) then return resp.error.shown
    return Api_titleText(resp.error.title)
end function

' The error code of a failed response ("timeout", "too_large", "not_v2", "bad_download", "network",
' or a problem type's last segment), "" when it has none.
function Api_errorCode(resp as dynamic) as string
    if Type(resp) <> "roAssociativeArray" then return ""
    err = resp.error
    if Type(err) <> "roAssociativeArray" then return ""
    return Str_orEmpty(err.code)
end function

' A problem title for the screen: Http.brs's English stand-ins ("Can't reach the server",
' "The server took too long to answer", "Something went wrong (500)") in the interface
' language; a title the server wrote is shown as it came.
function Api_titleText(title as dynamic) as string
    t = Str_orEmpty(title)
    if t = "Can't reach the server" or t = "The server took too long to answer" then return Tx(t)
    pre = "Something went wrong ("
    if Left(t, Len(pre)) = pre and Right(t, 1) = ")" then
        code = Mid(t, Len(pre) + 1, Len(t) - Len(pre) - 1)
        if code <> "" and Str(Val(code)).Trim() = code then return TxF("Something went wrong ({0})", [code])
    end if
    return t
end function

' The server's reason for a failed write, for a toast after "Couldn't …": the problem's detail,
' else its title, the connection advice when the server was not reached, else `fallback`.
' Http_problem's stand-in title ("Something went wrong (500)") is not a reason.
function Api_reasonText(resp as dynamic, fallback as string) as string
    if resp = invalid or Type(resp) <> "roAssociativeArray" then return fallback
    if Int(Num_or(resp.status, 0)) <= 0 then
        code = Api_errorCode(resp)
        if code = "timeout" then return Tx("The server took too long to answer.")
        if code = "too_large" then return Tx("The server's answer was too large.")
        if code = "not_v2" or code = "bad_download" then return fallback
        return Tx("Can't reach the server. Check your connection.")
    end if
    err = resp.error
    if err = invalid or Type(err) <> "roAssociativeArray" then return fallback
    if not Str_isEmpty(err.shown) then return err.shown
    reason = Str_orEmpty(err.detail).Trim()
    if reason <> "" then return reason
    title = Str_orEmpty(err.title).Trim()
    if title <> "" and Left(title, 20) <> "Something went wrong" then return title
    return fallback
end function
