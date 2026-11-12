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

' Starts a request whose answer nobody waits for and that must finish even when the caller
' leaves its screen right away (sign-out, change server). Api_call keeps the task only in the
' calling screen's m.apiTasks, which Nav_reset frees together with the screen, so the task is
' parented to the scene instead. Finished ones from earlier calls are removed here.
sub Api_detached(request as object)
    task = CreateObject("roSGNode", "ApiTask")
    task.request = request
    scene = m.top.getScene()
    if scene <> invalid then
        for i = scene.getChildCount() - 1 to 0 step -1
            c = scene.getChild(i)
            if c <> invalid and c.subtype() = "ApiTask" then
                if c.state = "stop" or c.state = "done" then scene.removeChildIndex(i)
            end if
        end for
        scene.appendChild(task)
    end if
    task.control = "RUN"
end sub

' Revokes the login session on the server (best effort) with the token and server we hold now.
' Both are passed explicitly because the caller clears the session right after this returns,
' before the task thread reads m.global.session.
sub Api_revokeSession()
    s = m.global.session
    token = Str_orEmpty(s.accessToken)
    if token = "" or Str_isEmpty(s.serverUrl) then return
    Api_detached({ method: "POST", path: "/api/v2/auth/logout", baseUrl: s.serverUrl, auth: false, profile: false, headers: { Authorization: "Bearer " + token }, timeout: 8 })
end sub

' Signs out: revokes the login session on the server and clears the local tokens and profile.
' Callers then route with Nav_reset("@start").
sub Api_signOut()
    Api_revokeSession()
    Session_signOutLocal(m.global.session)
end sub

' Change server: revokes the login session, then forgets the server. Callers then route with
' Nav_reset("ServerConnectScreen").
sub Api_leaveServer()
    Api_revokeSession()
    Session_clearServer()
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
    if resp = invalid or resp.error = invalid then return "Something went wrong"
    if resp.status = 0 then return "Can't reach the server. Check your connection and try again."
    return resp.error.title
end function
