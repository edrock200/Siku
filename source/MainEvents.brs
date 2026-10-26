' Pure readers for the device events source/main.brs forwards to MainScene (host-tested in
' tests/test_main_events.py). Adapted from ManavA/silo-roku, AGPL-3.0 (source/main.brs).
' SPDX-License-Identifier: AGPL-3.0-or-later

' Memory pressure as a percentage of the channel's limit, or -1 to ignore the event.
' roAppMemoryNotificationEvent carries the channel's own usage (memoryUsagePercent); older
' firmware only has the device-wide roDeviceInfoEvent generalMemoryLevel, mapped to the same
' scale: normal 0, low 80, critical 95.
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
        if level = "low" then return 80
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
