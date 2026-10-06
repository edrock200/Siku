' Soku — a Roku client for the Silo media server.
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
    scene.signalBeacon("AppLaunchComplete")

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
        end if
    end while
end sub
