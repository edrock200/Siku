' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.entries = m.top.findNode("entries")
    m.panelBg = m.top.findNode("panelBg")
    m.panelShadow = m.top.findNode("panelShadow")
    m.letters = ["All", "#"]
    for i = 0 to 25
        m.letters.Push(Chr(Asc("A") + i))
    end for
    m.nodes = []
    m.chipFont = ThemeFont("semibold", 22)
    m.allFont = ThemeFont("semibold", 20)
    for i = 0 to m.letters.Count() - 1
        g = m.entries.createChild("Group")
        dot = g.createChild("Poster")
        dot.id = "dot"
        dot.uri = "pkg:/images/ui/circle.png"
        bg = g.createChild("Poster")
        bg.id = "bg"
        lbl = g.createChild("Label")
        lbl.id = "label"
        lbl.text = m.letters[i]
        lbl.horizAlign = "center"
        lbl.vertAlign = "center"
        lbl.maxLines = 1
        if i = 0 then Label_setFont(lbl, "semibold", 20) else Label_setFont(lbl, "semibold", 22)
        m.nodes.Push(g)
    end for
    m.focusIndex = 0
    m.expanded = false
    m.top.focusable = true
    m.top.observeField("focusedChild", "onFocusChange")
    relayout()
end sub

function selectedIndex() as integer
    s = m.top.selected
    if s = "" then return 0
    for i = 1 to m.letters.Count() - 1
        if m.letters[i] = s then return i
    end for
    return 0
end function

' Expand while the rail (or a child) holds focus; collapse to the dot column otherwise.
sub onFocusChange()
    expanded = m.top.hasFocus() or m.top.isInFocusChain()
    if expanded and not m.expanded then m.focusIndex = 0   ' entering always lands on "All"
    if expanded <> m.expanded then
        m.expanded = expanded
        relayout()
    end if
end sub

sub relayout()
    n = m.letters.Count()
    span = m.top.railBottom - m.top.railTop
    if span < n * 12 + 24 then span = n * 12 + 24
    ' 12 px of panel padding above "All" and below "Z".
    pad = 12
    pitch = Int((span - 2 * pad) / n)
    if m.expanded then
        width = 192
    else
        width = 36
    end if
    m.top.translation = [1920 - width, m.top.railTop]
    m.panelBg.visible = m.expanded
    m.panelShadow.visible = m.expanded
    m.panelBg.width = width
    m.panelBg.height = span
    m.panelShadow.width = width + 16
    m.panelShadow.height = span + 16
    m.panelShadow.translation = [-8, -8]
    chip = pitch - 4
    if chip > 40 then chip = 40
    if chip < 12 then chip = 12
    ' Letter glyphs follow the chip height; chips are a little wider than tall so "W" fits.
    fontPx = chip - 4
    if fontPx > 22 then fontPx = 22
    if fontPx < 12 then fontPx = 12
    m.chipFont.size = fontPx
    m.allFont.size = fontPx
    for i = 0 to n - 1
        g = m.nodes[i]
        y = pad + Int(i * pitch + (pitch - chip) / 2)
        dot = Node_find(g, "dot")
        bg = Node_find(g, "bg")
        lbl = Node_find(g, "label")
        if m.expanded then
            dot.visible = false
            if i = 0 then
                bw = 72
                bg.uri = "pkg:/images/ui/r14.9.png"
            else
                bw = chip + 10
                bg.uri = "pkg:/images/ui/r8.9.png"
            end if
            bg.width = bw
            bg.height = chip
            bg.translation = [Int((width - bw) / 2), y]
            lbl.width = bw + 20
            lbl.height = chip
            lbl.translation = [Int((width - bw) / 2) - 10, y]
            lbl.visible = true
        else
            lbl.visible = false
            bg.visible = false
            ' Every other entry draws a dot (plus the selected one, so the position always shows).
            showDot = (i mod 2 = 0) or i = selectedIndex()
            dot.visible = showDot
            ds = 4
            if i = selectedIndex() then ds = 8
            dot.width = ds
            dot.height = ds
            dot.translation = [Int((width - ds) / 2), pad + Int(i * pitch + (pitch - ds) / 2)]
        end if
    end for
    restyle()
end sub

' Colors per entry (TvAlphabetRail.LetterButton): focused → white chip, black text; selected → white
' chip (All: 22% white); All at rest 8% white; letters at rest transparent, 55% white text.
sub restyle()
    sel = selectedIndex()
    for i = 0 to m.nodes.Count() - 1
        g = m.nodes[i]
        dot = Node_find(g, "dot")
        bg = Node_find(g, "bg")
        lbl = Node_find(g, "label")
        focused = m.expanded and i = m.focusIndex
        isSel = i = sel
        if not m.expanded then
            if isSel then dot.blendColor = "0xFFFFFFE6" else dot.blendColor = "0xFFFFFF59"
        else
            bg.visible = true
            if i = 0 then
                if focused then
                    bg.blendColor = "0xFFFFFFF0"
                    lbl.color = "0x000000FF"
                else if isSel then
                    bg.blendColor = "0xFFFFFF38"
                    lbl.color = "0xFFFFFFFF"
                else
                    bg.blendColor = "0xFFFFFF14"
                    lbl.color = "0xFFFFFFD9"
                end if
            else if focused or isSel then
                bg.blendColor = "0xFFFFFFFF"
                lbl.color = "0x000000FF"
            else
                bg.visible = false
                lbl.color = "0xFFFFFF8C"
            end if
        end if
    end for
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "up" then
        if m.focusIndex > 0 then
            m.focusIndex = m.focusIndex - 1
            restyle()
        end if
        return true
    else if key = "down" then
        if m.focusIndex < m.letters.Count() - 1 then
            m.focusIndex = m.focusIndex + 1
            restyle()
        end if
        return true
    else if key = "OK" then
        if m.focusIndex = 0 then
            m.top.prefixSelected = ""
        else
            m.top.prefixSelected = m.letters[m.focusIndex]
        end if
        return true
    else if key = "left" then
        m.top.exitLeft = true
        return true
    else if key = "right" then
        return true
    end if
    return false
end function
