' Siku — a Roku client for the Silo media server.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    ' The device input port lets us receive deep links while running.
    input = CreateObject("roInput")
    input.SetMessagePort(port)

    scene = screen.CreateScene("MainScene")
    screen.Show()
    scene.launchArgs = args
    scene.observeField("exitApp", port)
    ' AppLaunchComplete is signalled by MainScene once Home (or the first screen) has rendered or
    ' video is playing, as Roku certification measures it; not here at startup.

    ' Memory warnings (screens under the top one then drop their artwork and lists) and app focus
    ' (the screen reader repeats the focused control after a system overlay). Channels on older
    ' firmware without roAppMemoryMonitor fall back to the device-wide low-memory event.
    di = CreateObject("roDeviceInfo")
    if di <> invalid then
        di.SetMessagePort(port)
        di.EnableAppFocusEvent(true)
    end if
    monitor = CreateObject("roAppMemoryMonitor")
    warnings = false
    if monitor <> invalid then
        monitor.SetMessagePort(port)
        warnings = monitor.EnableMemoryWarningEvent(true)
    end if
    if not warnings and di <> invalid then di.EnableLowGeneralMemoryEvent(true)

    while true
        msg = Wait(0, port)
        msgType = Type(msg)
        if msgType = "roSGScreenEvent"
            if msg.IsScreenClosed() then return
        else if msgType = "roSGNodeEvent"
            if msg.GetField() = "exitApp" and msg.GetData() = true
                screen.Close()
                return
            end if
        else if msgType = "roInputEvent"
            if msg.IsInput() then scene.inputArgs = msg.GetInfo()
        else if msgType = "roAppMemoryNotificationEvent" or msgType = "roDeviceInfoEvent"
            info = msg.GetInfo()
            pressure = MainEvents_memoryPressure(msgType, info)
            if pressure >= 0 then scene.memoryPressure = pressure
            if msgType = "roDeviceInfoEvent" then
                focused = MainEvents_appFocus(info)
                if focused <> invalid then scene.appFocused = focused
            end if
        end if
    end while
end sub
