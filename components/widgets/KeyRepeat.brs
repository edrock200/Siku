' SPDX-License-Identifier: AGPL-3.0-or-later
'
' Hold-to-repeat for widgets that move their own focus in onKeyEvent. SceneGraph sends a custom
' onKeyEvent one press and one release per key and never repeats while it is held (only the
' built-in list nodes do), so holding Up/Down walked one row. A component that includes this
' file calls KeyRepeat_init() in init(), KeyRepeat_start(key) after handling an Up/Down press,
' KeyRepeat_stop() on every release, and defines
'     function onKeyRepeat(key as string) as boolean
' which repeats the move and returns false when nothing moved (the end of the list).

sub KeyRepeat_init()
    m.keyRepeatKey = ""
    m.keyRepeatTimer = m.top.createChild("Timer")
    m.keyRepeatTimer.repeat = false
    m.keyRepeatTimer.observeField("fire", "KeyRepeat_onFire")
end sub

' Starts repeating `key` after a 400 ms hold, then every 90 ms.
sub KeyRepeat_start(key as string)
    if m.keyRepeatTimer = invalid then return
    m.keyRepeatKey = key
    m.keyRepeatTimer.control = "stop"
    m.keyRepeatTimer.repeat = false
    m.keyRepeatTimer.duration = 0.4
    m.keyRepeatTimer.control = "start"
end sub

sub KeyRepeat_stop()
    if m.keyRepeatTimer = invalid then return
    m.keyRepeatKey = ""
    m.keyRepeatTimer.control = "stop"
end sub

sub KeyRepeat_onFire()
    key = m.keyRepeatKey
    ' The release may go elsewhere once focus leaves (or the widget closes): stop then too.
    if key = "" or not m.top.visible or not m.top.isInFocusChain() then
        KeyRepeat_stop()
        return
    end if
    if not onKeyRepeat(key) then
        KeyRepeat_stop()
        return
    end if
    if not m.keyRepeatTimer.repeat then
        m.keyRepeatTimer.control = "stop"
        m.keyRepeatTimer.repeat = true
        m.keyRepeatTimer.duration = 0.09
        m.keyRepeatTimer.control = "start"
    end if
end sub
