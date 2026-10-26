' PairingPanel: the phone sign-in overlay (see PairingPanel.xml).
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.card = m.top.findNode("card")
    m.cardBg = m.top.findNode("cardBg")
    m.cardRing = m.top.findNode("cardRing")
    m.eyebrow = m.top.findNode("eyebrow")
    m.title = m.top.findNode("title")
    m.detail = m.top.findNode("detail")
    m.code = m.top.findNode("code")
    m.server = m.top.findNode("server")
    m.spinner = m.top.findNode("spinner")
    m.buttonsGroup = m.top.findNode("buttons")
    m.buttons = []
    m.focusIndex = 0
    m.top.visible = false
end sub

sub render()
    v = m.top.view
    if v = invalid or v.Count() = 0 then
        m.top.visible = false
        m.spinner.visible = false
        return
    end if
    m.eyebrow.text = Str_orEmpty(v.eyebrow)
    m.title.text = Str_orEmpty(v.title)
    m.detail.text = Str_orEmpty(v.detail)
    m.code.text = Str_orEmpty(v.code)
    m.server.text = Str_orEmpty(v.server)

    ' Rebuild the buttons; keep the focused one when the same ids come back.
    oldIds = ""
    for each b in m.buttons
        oldIds = oldIds + b.id + "|"
    end for
    newIds = ""
    for each b in Arr_or(v.buttons)
        newIds = newIds + Str_orEmpty(b.id) + "|"
    end for
    if newIds <> oldIds then
        m.buttonsGroup.removeChildrenIndex(m.buttonsGroup.getChildCount(), 0)
        m.buttons = []
        for each b in Arr_or(v.buttons)
            btn = m.buttonsGroup.createChild("PillButton")
            btn.variant = "glass"
            btn.text = Str_orEmpty(b.text)
            btn.observeField("buttonSelected", "onButton")
            btn.observeField("width", "layout")
            m.buttons.Push({ id: Str_orEmpty(b.id), node: btn })
        end for
        m.focusIndex = 0
    end if
    m.top.visible = true
    m.spinner.visible = panelTrue(v.busy)
    layout()
    applyFocus()
end sub

function panelTrue(v as dynamic) as boolean
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function

sub layout()
    y = 104
    m.title.translation = [60, y]
    y = y + Int(Label_height(m.title)) + 20
    if m.detail.text <> "" then
        m.detail.translation = [60, y]
        y = y + Int(Label_height(m.detail)) + 24
    end if
    m.code.visible = m.code.text <> ""
    if m.code.visible then
        m.code.translation = [60, y]
        y = y + Int(Label_height(m.code)) + 20
    end if
    m.server.visible = m.server.text <> ""
    if m.server.visible then
        m.server.translation = [60, y]
        y = y + Int(Label_height(m.server)) + 20
    end if
    if m.spinner.visible then
        m.spinner.translation = [60, y + 6]
        y = y + 64
    end if
    if m.buttons.Count() > 0 then
        x = 0
        for each b in m.buttons
            b.node.translation = [x, 0]
            x = x + b.node.width + 18
        end for
        m.buttonsGroup.translation = [60, y + 10]
        y = y + 10 + 76
    end if
    h = y + 56
    m.cardBg.height = h
    m.cardRing.height = h
    m.card.translation = [460, (1080 - h) \ 2]
end sub

sub applyFocus()
    if not m.top.visible then return
    if m.buttons.Count() > 0 then
        if m.focusIndex >= m.buttons.Count() then m.focusIndex = 0
        m.buttons[m.focusIndex].node.setFocus(true)
    else
        m.buttonsGroup.setFocus(true)
    end if
end sub

sub onButton(event as object)
    node = event.getRoSGNode()
    for each b in m.buttons
        if b.node.isSameNode(node) then m.top.chosen = b.id
    end for
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press or not m.top.visible then return false
    if key = "left" and m.focusIndex > 0 then
        m.focusIndex = m.focusIndex - 1
        applyFocus()
        return true
    else if key = "right" and m.focusIndex < m.buttons.Count() - 1 then
        m.focusIndex = m.focusIndex + 1
        applyFocus()
        return true
    else if key = "back" then
        m.top.chosen = "back"
        return true
    end if
    ' The panel is modal: nothing behind it takes keys.
    return true
end function
