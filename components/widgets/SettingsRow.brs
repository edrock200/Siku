' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.bg = m.top.findNode("bg")
    m.ring = m.top.findNode("ring")
    m.icon = m.top.findNode("icon")
    m.labelText = m.top.findNode("labelText")
    m.descText = m.top.findNode("descText")
    m.valueText = m.top.findNode("valueText")
    m.chevron = m.top.findNode("chevron")
    layout()
end sub

sub layout()
    w = m.top.rowWidth
    h = m.top.rowHeight
    m.bg.width = w
    m.bg.height = h
    m.ring.width = w
    m.ring.height = h
    x = 28
    if not Str_isEmpty(m.top.iconUri) then
        m.icon.uri = m.top.iconUri
        m.icon.visible = true
        m.icon.translation = [28, (h - 40) / 2]
        x = 88
    else
        m.icon.visible = false
    end if
    m.labelText.text = m.top.label
    m.labelText.translation = [x, 0]
    hasDesc = not Str_isEmpty(m.top.description)
    m.descText.visible = hasDesc
    if hasDesc then
        m.labelText.height = h * 0.58
        m.descText.text = m.top.description
        m.descText.translation = [x, h * 0.48]
        m.descText.height = h * 0.42
        m.descText.vertAlign = "top"
    else
        m.labelText.height = h
    end if
    chevronSpace = 0
    if m.top.showChevron then chevronSpace = 44
    m.chevron.visible = m.top.showChevron
    m.chevron.translation = [w - 20 - 36, (h - 36) / 2]
    m.valueText.text = m.top.value
    m.valueText.width = w / 2
    m.valueText.height = h
    m.valueText.translation = [w / 2 - 24 - chevronSpace, 0]
    m.labelText.width = w / 2
    m.descText.width = w - x - 24
    applyState()
end sub

sub applyState()
    if m.top.focusedState then
        m.bg.visible = true
        m.bg.blendColor = "0xEDEDEDFF"
        m.ring.visible = false
        ink = "0x000000FF"
        sub2 = "0x000000B3"
    else if m.top.highlighted then
        m.bg.visible = true
        m.bg.blendColor = "0xFFFFFF24"
        m.ring.visible = true
        ink = "0xEDEDEDFF"
        sub2 = "0xEDEDEDA6"
    else
        m.bg.visible = false
        m.ring.visible = false
        ink = "0xEDEDEDFF"
        sub2 = "0xEDEDEDA6"
    end if
    if m.top.destructive and not m.top.focusedState then ink = "0xFF6961FF"
    m.labelText.color = ink
    m.descText.color = sub2
    m.valueText.color = sub2
    m.chevron.blendColor = sub2
    m.icon.blendColor = ink
end sub
