' Pure readers for the device events source/main.brs forwards to MainScene (host-tested in
' tests/test_main_events.py). Adapted from ManavA/silo-roku, AGPL-3.0 (source/main.brs).
' SPDX-License-Identifier: AGPL-3.0-or-later

' Memory pressure as a percentage of the channel's limit, or -1 to ignore the event.
' roAppMemoryNotificationEvent carries the channel's own usage (memoryUsagePercent); older
' firmware only has the device-wide roDeviceInfoEvent generalMemoryLevel, mapped to the same
' scale: normal 0, low 85 (the "pressure" level), critical 95.
function MainEvents_memoryPressure(eventType as string, info as dynamic) as integer
    if Type(info) <> "roAssociativeArray" then return -1
    if eventType = "roAppMemoryNotificationEvent" then
        usage = info.Lookup("memoryUsagePercent")
        if usage = invalid then usage = info.Lookup("MemoryUsagePercent")
        t = Type(usage)
        if t <> "Integer" and t <> "roInt" and t <> "roInteger" and t <> "LongInteger" and t <> "roLongInteger" and t <> "Float" and t <> "roFloat" and t <> "Double" and t <> "roDouble" then return -1
        if usage < 0 then return -1
        if usage > 100 then return 100
        return Int(usage)
    else if eventType = "roDeviceInfoEvent" then
        level = info.Lookup("generalMemoryLevel")
        if Type(level) <> "String" and Type(level) <> "roString" then return -1
        level = LCase(level)
        if level = "normal" then return 0
        if level = "low" then return 85
        if level = "critical" then return 95
    end if
    return -1
end function

' true / false when a roDeviceInfoEvent says the channel gained or lost focus (a system overlay, the
' screensaver), invalid for any other device event.
function MainEvents_appFocus(info as dynamic) as dynamic
    if Type(info) <> "roAssociativeArray" then return invalid
    focused = info.Lookup("appFocused")
    if Type(focused) = "Boolean" or Type(focused) = "roBoolean" then return focused
    exited = info.Lookup("exitedScreensaver")
    if Type(exited) = "Boolean" or Type(exited) = "roBoolean" then
        if exited then return true
    end if
    return invalid
end function

' True for a Roku transport event (voice "pause", "fast forward", "seek forward 30 seconds" ...;
' roInput after EnableTransportEvents). Such events are answered and never treated as deep links.
function MainEvents_isTransport(info as dynamic) as boolean
    if Type(info) <> "roAssociativeArray" then return false
    t = info.Lookup("type")
    if Type(t) <> "String" and Type(t) <> "roString" then return false
    return LCase(t) = "transport"
end function

' The roInput.EventResponse answer for a transport event: the event's own id and the status the
' scene returned when it is one Roku defines, else "error.generic" (the player could not act).
function MainEvents_transportResponse(info as dynamic, result as dynamic) as object
    response = { "status": "error.generic" }
    if Type(info) = "roAssociativeArray" then
        id = info.Lookup("id")
        if id <> invalid then response["id"] = id
    end if
    if Type(result) = "roAssociativeArray" then
        st = result.Lookup("status")
        if Type(st) = "String" or Type(st) = "roString" then
            for each known in ["success", "success.seek-start", "success.seek-end", "error.generic"]
                if st = known then response["status"] = known
            end for
        end if
    end if
    return response
end function

' What the device says about its memory and graphics, read on the main thread (each call guarded:
' older firmware lacks some): { ui, graphics, warnings, foregroundKb }.
function MainEvents_deviceFacts(di as dynamic, monitor as dynamic, warnings as boolean) as object
    facts = { ui: "", graphics: "", warnings: warnings, foregroundKb: -1 }
    if di <> invalid then
        try
            res = di.GetUIResolution()
            if Type(res) = "roAssociativeArray" and res.name <> invalid then facts.ui = res.name
        catch e1
            facts.ui = "" ' e1: firmware without the call
            if e1 = invalid then facts.ui = ""
        end try
        try
            g = di.GetGraphicsPlatform()
            if Type(g) = "String" or Type(g) = "roString" then facts.graphics = g
        catch e2
            facts.graphics = "" ' e2: firmware without the call
            if e2 = invalid then facts.graphics = ""
        end try
    end if
    if monitor <> invalid then
        try
            limits = monitor.GetChannelMemoryLimit()
            if Type(limits) = "roAssociativeArray" then
                kb = limits.Lookup("maxForegroundMemory")
                t = Type(kb)
                if t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then facts.foregroundKb = Int(kb)
            end if
        catch e3
            facts.foregroundKb = -1 ' e3: firmware without the call
            if e3 = invalid then facts.foregroundKb = -1
        end try
    end if
    return facts
end function

' The device tier for MainScene.deviceTier: low on an HD UI, without OpenGL, without the memory
' monitor's warnings, or with a foreground limit under 400 MB (a 512 MB player). An unknown value
' counts against the device, as in Silo-Server/silo-roku, AGPL-3.0 (source/memory/policy.bs).
function MainEvents_deviceTier(facts as object) as object
    reasons = []
    if UCase(Str_orEmptyMain(facts.ui)) <> "FHD" then reasons.Push("ui")
    if LCase(Str_orEmptyMain(facts.graphics)) <> "opengl" then reasons.Push("graphics")
    warned = false
    if Type(facts.warnings) = "Boolean" or Type(facts.warnings) = "roBoolean" then warned = facts.warnings
    if not warned then reasons.Push("monitor")
    kb = facts.foregroundKb
    if Type(kb) <> "Integer" and Type(kb) <> "roInt" and Type(kb) <> "roInteger" then kb = -1
    if kb < 409600 then reasons.Push("foregroundLimit")
    mb = -1
    if kb >= 0 then mb = kb \ 1024
    return { low: reasons.Count() > 0, reasons: reasons.Join(","), foregroundMb: mb }
end function

' GetMemoryLimitPercent() as an integer, or -1 when it cannot be read.
function MainEvents_memorySample(monitor as dynamic) as integer
    if monitor = invalid then return -1
    try
        v = monitor.GetMemoryLimitPercent()
        t = Type(v)
        if t = "Integer" or t = "roInt" or t = "roInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
            if v < 0 then return -1
            if v > 100 then return 100
            return Int(v)
        end if
    catch e
        if e = invalid then return -1 ' e: firmware without the call
    end try
    return -1
end function

function Str_orEmptyMain(v as dynamic) as string
    if Type(v) = "String" or Type(v) = "roString" then return v
    return ""
end function
