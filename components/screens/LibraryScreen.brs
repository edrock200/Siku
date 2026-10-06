' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.page = m.top.findNode("page")
    m.page.observeField("navigateTo", "onPageNavigate")
    m.top.observeField("params", "onParams")
end sub

sub onParams()
    p = AA_copy(m.top.params)
    p.hostedInShell = false
    m.page.params = p
end sub

sub onPageNavigate()
    req = m.page.navigateTo
    if req <> invalid then m.top.navigateTo = req
end sub

sub onScreenShown()
    m.page.active = true
    m.page.focusRequested = true
end sub

sub onScreenHidden()
    m.page.active = false
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    ' The page handles its own panels and collection drill-down; anything else (Back) pops this screen.
    return false
end function
