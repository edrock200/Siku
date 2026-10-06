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
    if task <> invalid and m.apiTasks <> invalid then
        task.unobserveField("response")
        m.apiTasks.Delete(task.id)
    end if
    if resp = invalid then resp = { ok: false, status: 0, error: { title: "No response" } }
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
