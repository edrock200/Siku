' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.bg = m.top.findNode("bg")
    m.ring = m.top.findNode("ring")
    m.shadow = m.top.findNode("shadow")
    m.titleLabel = m.top.findNode("titleLabel")
    m.rowsGroup = m.top.findNode("rowsGroup")
    m.rowNodes = []
    m.ids = []
    m.focusIndex = 0
    m.width = 640
    m.rowH = 76
    m.fontRow = ThemeFont("medium", 27)
    m.fontRowFocused = ThemeFont("semibold", 27)
    m.top.focusable = true
    m.top.visible = false
    m.top.observeField("focusedChild", "applyFocus")
    m.top.observeField("visible", "onVisible")
end sub

sub onVisible()
    if m.top.visible then
        m.focusIndex = 0
        applyFocus()
    end if
end sub

function rowNode(i as integer) as object
    if i < m.rowNodes.Count() then return m.rowNodes[i]
    g = m.rowsGroup.createChild("Group")
    bg = g.createChild("Poster")
    bg.id = "bg"
    bg.uri = "pkg:/images/ui/r16.9.png"
    bg.blendColor = Theme().colors.ink
    bg.visible = false
    bg.width = m.width - 48
    bg.height = m.rowH
    icon = g.createChild("Poster")
    icon.id = "icon"
    icon.width = 36
    icon.height = 36
    icon.translation = [20, (m.rowH - 36) / 2]
    lbl = g.createChild("Label")
    lbl.id = "label"
    Label_setFont(lbl, "medium", 27)
    lbl.vertAlign = "center"
    lbl.height = m.rowH
    lbl.width = m.width - 48 - 40
    m.rowNodes.Push(g)
    return g
end function

sub rebuild()
    if m.rowsGroup = invalid then return
    actions = m.top.actions
    if actions = invalid then actions = []
    m.ids = []
    pad = 24
    y = pad
    hasTitle = not Str_isEmpty(m.top.title)
    if hasTitle then
        m.titleLabel.visible = true
        m.titleLabel.text = m.top.title
        m.titleLabel.translation = [pad + 20, y + 8]
        m.titleLabel.width = m.width - pad * 2 - 40
        y = y + 64
    else
        m.titleLabel.visible = false
    end if
    for i = 0 to actions.Count() - 1
        a = actions[i]
        g = rowNode(i)
        g.visible = true
        g.translation = [pad, y]
        icon = Node_find(g, "icon")
        lbl = Node_find(g, "label")
        iconName = Str_orEmpty(a.icon)
        if iconName <> "" then
            icon.visible = true
            icon.uri = "pkg:/images/icons/" + iconName + ".png"
            lbl.translation = [74, 0]
        else
            icon.visible = false
            lbl.translation = [20, 0]
        end if
        lbl.text = Str_orEmpty(a.label)
        m.ids.Push(Str_orEmpty(a.id))
        y = y + m.rowH + 4
    end for
    for i = actions.Count() to m.rowNodes.Count() - 1
        m.rowNodes[i].visible = false
    end for
    h = y + pad - 4
    x0 = (1920 - m.width) / 2
    y0 = (1080 - h) / 2
    m.bg.translation = [x0, y0]
    m.bg.width = m.width
    m.bg.height = h
    m.ring.translation = [x0, y0]
    m.ring.width = m.width
    m.ring.height = h
    m.shadow.translation = [x0 - 16, y0 - 8]
    m.shadow.width = m.width + 32
    m.shadow.height = h + 36
    m.rowsGroup.translation = [x0, y0]
    m.titleLabel.translation = [x0 + pad + 20, y0 + pad + 8]
    if m.focusIndex >= actions.Count() then m.focusIndex = 0
    applyFocus()
end sub

sub applyFocus()
    focused = m.top.hasFocus()
    for i = 0 to m.ids.Count() - 1
        g = m.rowNodes[i]
        isF = focused and i = m.focusIndex
        Node_find(g, "bg").visible = isF
        lbl = Node_find(g, "label")
        icon = Node_find(g, "icon")
        if isF then
            lbl.color = Theme().colors.onInk
            Label_setFont(lbl, "semibold", 27)
            icon.blendColor = Theme().colors.onInk
        else
            lbl.color = Theme().colors.ink
            Label_setFont(lbl, "medium", 27)
            icon.blendColor = Theme().colors.ink
        end if
    end for
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    n = m.ids.Count()
    if key = "up" then
        if m.focusIndex > 0 then m.focusIndex = m.focusIndex - 1
        applyFocus()
        return true
    else if key = "down" then
        if m.focusIndex < n - 1 then m.focusIndex = m.focusIndex + 1
        applyFocus()
        return true
    else if key = "OK" then
        if n > 0 then
            id = m.ids[m.focusIndex]
            m.top.visible = false
            m.top.chosen = id
        end if
        return true
    else if key = "back" then
        m.top.visible = false
        m.top.dismissed = true
        return true
    end if
    ' Swallow everything else while the menu is up.
    return true
end function
