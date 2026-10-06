' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.bar = m.top.findNode("bar")
    m.wordmark = m.top.findNode("wordmark")
    m.searchBtn = m.top.findNode("searchBtn")
    m.searchBg = m.top.findNode("searchBg")
    m.searchIcon = m.top.findNode("searchIcon")
    m.tabsGroup = m.top.findNode("tabsGroup")
    m.avatar = m.top.findNode("avatar")
    m.avatarBg = m.top.findNode("avatarBg")
    m.avatarMask = m.top.findNode("avatarMask")
    m.avatarImg = m.top.findNode("avatarImg")
    m.avatarInitials = m.top.findNode("avatarInitials")
    m.avatarRing = m.top.findNode("avatarRing")
    m.dimAnim = m.top.findNode("dimAnim")
    m.dimInterp = m.top.findNode("dimInterp")
    m.tabNodes = []
    m.fontMedium = ThemeFont("medium", 26)
    m.fontSemibold = ThemeFont("semibold", 26)
    t = Theme()
    m.barTop = t.barTop
    m.barH = t.barHeight
    m.tabH = 60
    m.tabPadX = 29
    m.gap = 8
    m.top.focusable = true
    m.top.observeField("focusedChild", "applyState")

    ' Wordmark: 52 px tall, aspect from the 520x140 asset.
    m.wordmark.height = 52
    m.wordmark.width = Int(52 * 520 / 140)
    m.wordmark.translation = [88, m.barTop + (m.barH - 52) / 2]

    m.avatar.translation = [1920 - 88 - 56, m.barTop + (m.barH - 56) / 2]
    m.top.avatarFrame = [1920 - 88 - 56, 56]
    updateAvatar()
    rebuild()
end sub

function tabNode(i as integer) as object
    if i < m.tabNodes.Count() then return m.tabNodes[i]
    g = m.tabsGroup.createChild("Group")
    bg = g.createChild("Poster")
    bg.id = "bg"
    bg.uri = "pkg:/images/ui/r30.9.png"
    bg.height = m.tabH
    ring = g.createChild("Poster")
    ring.id = "ring"
    ring.uri = "pkg:/images/ui/r30_ring2.9.png"
    ring.height = m.tabH
    lbl = g.createChild("Label")
    lbl.id = "label"
    lbl.height = m.tabH
    lbl.vertAlign = "center"
    lbl.horizAlign = "center"
    lbl.font = m.fontSemibold
    m.tabNodes.Push(g)
    return g
end function

' Lays out the centered cluster: [search] gap tabs... gap [56 px spacer].
' When every media type plus Requests is present the cluster can be wider than the
' space between the wordmark and the avatar: tab padding then shrinks, and as a last
' resort the cluster is left-aligned after the wordmark instead of centered.
sub rebuild()
    if m.tabsGroup = invalid then return
    tabs = m.top.tabs
    if tabs = invalid then tabs = []
    minX = 88 + m.wordmark.width + 32
    maxX = 1920 - 88 - 56 - 32
    textWidths = []
    for i = 0 to tabs.Count() - 1
        g = tabNode(i)
        lbl = g.findNode("label")
        lbl.font = m.fontSemibold
        lbl.text = Str_orEmpty(tabs[i].label)
        lbl.width = 0
        textWidths.Push(Int(Label_width(lbl)))
    end for
    padX = m.tabPadX
    while true
        widths = []
        total = 56 + m.gap
        for each tw in textWidths
            w = tw + padX * 2
            widths.Push(w)
            total = total + w + m.gap
        end for
        total = total + 56
        x = Int((1920 - total) / 2)
        if x >= minX or padX <= 14 then exit while
        padX = padX - 3
    end while
    if x < minX then x = minX
    if x + total - 56 > maxX then x = minX
    y = m.barTop + (m.barH - m.tabH) / 2
    m.searchBtn.translation = [x, m.barTop + (m.barH - 56) / 2]
    x = x + 56 + m.gap
    frames = []
    for i = 0 to tabs.Count() - 1
        g = m.tabNodes[i]
        g.visible = true
        g.translation = [x, y]
        w = widths[i]
        g.findNode("bg").width = w
        g.findNode("ring").width = w
        lbl = g.findNode("label")
        lbl.width = w
        lbl.translation = [0, 0]
        frames.Push([x, w])
        x = x + w + m.gap
    end for
    for i = tabs.Count() to m.tabNodes.Count() - 1
        m.tabNodes[i].visible = false
    end for
    m.top.tabFrames = frames
    applyState()
end sub

sub applyState()
    if m.tabNodes = invalid then return
    tabs = m.top.tabs
    if tabs = invalid then tabs = []
    focused = m.top.hasFocus()
    fi = m.top.focusIndex
    si = m.top.selectedIndex
    c = Theme().colors
    ' Search button.
    searchFocused = focused and fi = -1
    m.searchBg.visible = searchFocused
    if searchFocused then
        m.searchIcon.blendColor = c.onInk
    else
        m.searchIcon.blendColor = c.inkMuted
    end if
    ' Tabs.
    for i = 0 to tabs.Count() - 1
        g = m.tabNodes[i]
        bg = g.findNode("bg")
        ring = g.findNode("ring")
        lbl = g.findNode("label")
        isF = (focused and fi = i) or m.top.activeTab = i
        isS = si = i
        if isF then
            bg.visible = true
            bg.blendColor = c.ink
            ring.visible = false
            lbl.color = c.onInk
            lbl.font = m.fontSemibold
        else if isS then
            bg.visible = true
            bg.blendColor = c.selectedFill
            ring.visible = true
            ring.blendColor = c.selectedBorder
            lbl.color = c.ink
            lbl.font = m.fontSemibold
        else
            bg.visible = false
            ring.visible = false
            lbl.color = c.inkMuted
            lbl.font = m.fontMedium
        end if
    end for
    ' Avatar ring.
    if (focused and fi = tabs.Count()) or m.top.activeTab = tabs.Count() then
        m.avatarRing.blendColor = c.ink
        m.avatarRing.width = 64
        m.avatarRing.height = 64
        m.avatarRing.translation = [-4, -4]
    else
        m.avatarRing.blendColor = "0xFFFFFF2E"
        m.avatarRing.width = 60
        m.avatarRing.height = 60
        m.avatarRing.translation = [-2, -2]
    end if
end sub

sub updateAvatar()
    if m.avatarImg = invalid then return
    url = Str_orEmpty(m.top.avatarUrl)
    if url <> "" then
        m.avatarImg.uri = Url_resolve(url)
        m.avatarMask.visible = true
        m.avatarInitials.visible = false
    else
        m.avatarMask.visible = false
        m.avatarInitials.visible = true
        m.avatarInitials.text = Bar_initials(Str_orEmpty(m.top.profileName))
    end if
end sub

function Bar_initials(name as string) as string
    out = ""
    for each part in name.Trim().Split(" ")
        if Len(part) > 0 and Len(out) < 2 then out = out + UCase(Left(part, 1))
    end for
    return out
end function

sub onDimmed()
    if m.dimAnim = invalid then return
    applyState()
    m.dimAnim.control = "stop"
    if m.top.dimmed then
        m.dimInterp.keyValue = [m.bar.opacity, 0.7]
    else
        m.dimInterp.keyValue = [m.bar.opacity, 1.0]
    end if
    m.dimAnim.control = "start"
end sub

function tabCount() as integer
    if m.top.tabs = invalid then return 0
    return m.top.tabs.Count()
end function

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    n = tabCount()
    fi = m.top.focusIndex
    if key = "left" then
        if fi > -1 then m.top.focusIndex = fi - 1
        return true
    else if key = "right" then
        if fi < n then m.top.focusIndex = fi + 1
        return true
    else if key = "OK" then
        if fi = -1 then
            m.top.searchSelected = true
        else if fi = n then
            m.top.panelRequested = 1000
        else if m.top.tabs[fi].hasPanel = true then
            m.top.panelRequested = fi
        else
            m.top.tabCommitted = fi
        end if
        return true
    else if key = "down" then
        if fi = n then
            m.top.panelRequested = 1000
        else if fi >= 0 and m.top.tabs[fi].hasPanel = true then
            m.top.panelRequested = fi
        else
            m.top.enterContent = true
        end if
        return true
    else if key = "up" then
        return true
    end if
    return false
end function
