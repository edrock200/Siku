' Default handlers for pages hosted in the shell. A page overrides
' onPageShown / onPageHidden / focusContent by defining a sub with the same name.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub onPageActiveChanged()
    if m.top.active then
        onPageShown()
    else
        onPageHidden()
    end if
end sub

sub onFocusRequested()
    focusContent()
end sub

sub onPageShown()
end sub

sub onPageHidden()
end sub

' Default: focus the page itself so keys still reach the shell.
sub focusContent()
    m.top.setFocus(true)
end sub
