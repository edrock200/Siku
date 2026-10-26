' Default handlers. A screen that extends BaseScreen overrides any of
' onScreenShown / onScreenHidden / onChildResult by defining a sub with the same name.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub onActiveChanged()
    if m.top.active then
        ' Artwork and lists dropped on a memory warning come back before the screen takes focus.
        Memory_restore()
        onScreenShown()
    else
        onScreenHidden()
    end if
end sub

sub onScreenResult()
    onChildResult(m.top.screenResult)
end sub

sub onMemoryRelease()
    if m.top.memoryRelease <> true or m.top.active then return
    Memory_release(m.top)
end sub

sub onMemoryPressureChanged()
    onMemoryPressure(m.top.memoryPressure)
end sub

' Overridden by screens that keep their own caches (PlayerScreen drops seek-preview sheets).
sub onMemoryPressure(level as integer)
    if level < 0 then return
end sub

sub onScreenShown()
end sub

sub onScreenHidden()
end sub

sub onChildResult(result as object)
    ' Overridden by screens that expect a result; the base ignores it.
    if result = invalid then return
end sub
