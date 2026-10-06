' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.bg = m.top.findNode("bg")
    m.currentIcon = m.top.findNode("currentIcon")
    m.number = m.top.findNode("number")
    m.titleLabel = m.top.findNode("title")
    m.subtitle = m.top.findNode("subtitle")
    m.trailing = m.top.findNode("trailing")
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.titleLabel.text = c.title
    m.number.text = fieldStr(c, "number")
    m.subtitle.text = fieldStr(c, "subtitle")
    m.trailing.text = fieldStr(c, "trailing")
    layout()
end sub

function fieldStr(c as object, name as string) as string
    if not c.hasField(name) then return ""
    v = c.getField(name)
    if v = invalid then return ""
    return v
end function

function isCurrent() as boolean
    c = m.top.itemContent
    if c = invalid or not c.hasField("isCurrent") then return false
    return c.isCurrent = true
end function

sub layout()
    w = m.top.width
    h = m.top.height
    if w <= 0 or h <= 0 then return
    m.bg.width = w
    m.bg.height = h
    hasNumber = m.number.text <> "" or isCurrent()
    numW = 0
    if hasNumber then numW = 72
    m.number.translation = [12, 0]
    m.number.width = numW - 12
    m.number.height = h
    m.currentIcon.translation = [12 + Int((numW - 12 - 34) / 2), Int((h - 34) / 2)]
    trailW = 0
    if m.trailing.text <> "" then trailW = 180
    m.trailing.width = trailW
    m.trailing.height = h
    m.trailing.translation = [w - trailW - 28, 0]
    textX = 28 + numW
    if hasNumber then textX = numW + 20
    textW = w - textX - trailW - 56
    m.titleLabel.width = textW
    m.subtitle.width = textW
    if m.subtitle.text <> "" then
        m.titleLabel.translation = [textX, Int(h / 2) - 36]
        m.subtitle.translation = [textX, Int(h / 2) + 4]
        m.subtitle.visible = true
    else
        m.titleLabel.translation = [textX, Int((h - 36) / 2)]
        m.subtitle.visible = false
    end if
    applyFocus()
end sub

sub applyFocus()
    focused = m.top.focusPercent > 0.5 and m.top.listHasFocus
    cur = isCurrent()
    m.currentIcon.visible = cur
    m.number.visible = not cur
    if focused then
        m.bg.visible = true
        m.bg.blendColor = "0xEDEDEDFF"
        m.titleLabel.color = "0x000000FF"
        m.subtitle.color = "0x000000B3"
        m.number.color = "0x000000B3"
        m.trailing.color = "0x000000B3"
        m.currentIcon.blendColor = "0x000000FF"
    else
        m.bg.visible = cur
        m.bg.blendColor = "0xFFFFFF1F"
        m.titleLabel.color = "0xEDEDEDFF"
        m.subtitle.color = "0xEDEDED9E"
        m.number.color = "0xEDEDED9E"
        m.trailing.color = "0xEDEDED9E"
        m.currentIcon.blendColor = "0xEDEDEDFF"
    end if
end sub
