' Default handlers. A screen that extends BaseScreen overrides any of
' onScreenShown / onScreenHidden / onChildResult by defining a sub with the same name.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub onActiveChanged()
    if m.top.active then
        onScreenShown()
    else
        onScreenHidden()
    end if
end sub

sub onScreenResult()
    onChildResult(m.top.screenResult)
end sub

sub onScreenShown()
end sub

sub onScreenHidden()
end sub

sub onChildResult(result as object)
end sub
