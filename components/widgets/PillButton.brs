' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.body = m.top.findNode("body")
    m.bg = m.top.findNode("bg")
    m.ring = m.top.findNode("ring")
    m.icon = m.top.findNode("icon")
    m.label = m.top.findNode("label")
    m.font = CreateObject("roSGNode", "Font")
    m.font.uri = "pkg:/fonts/Inter-semibold.otf"
    m.label.font = m.font
    m.top.focusable = true
    m.top.observeField("focusedChild", "applyState")
    layout()
end sub

function capsuleUri(h as integer, ring as boolean) as string
    ' 9-patch radii available: 6..42 (images/ui). Pick the largest that fits a capsule.
    radii = [42, 40, 38, 32, 30, 28, 26, 22, 20, 16, 14, 12, 8, 6]
    r = 6
    for each candidate in radii
        if candidate * 2 <= h then
            r = candidate
            exit for
        end if
    end for
    if ring then return "pkg:/images/ui/r" + r.ToStr() + "_ring2.9.png"
    return "pkg:/images/ui/r" + r.ToStr() + ".9.png"
end function

sub layout()
    h = m.top.height
    m.font.size = m.top.fontSize
    m.label.text = m.top.text
    m.label.width = 0
    textW = Label_width(m.label)
    iconSize = Int(h * 0.42)
    hasIcon = not Str_isEmpty(m.top.iconUri)
    contentW = textW
    if hasIcon then
        if textW > 0 then contentW = textW + iconSize + 14 else contentW = iconSize
    end if
    w = contentW + m.top.padX * 2
    if w < m.top.minWidth then w = m.top.minWidth
    if m.top.fixedWidth > 0 then w = m.top.fixedWidth
    if not hasIcon and m.top.text = "" then w = h

    m.bg.uri = capsuleUri(h, false)
    m.ring.uri = capsuleUri(h, true)
    m.bg.width = w
    m.bg.height = h
    m.ring.width = w
    m.ring.height = h

    startX = (w - contentW) / 2
    if hasIcon then
        m.icon.visible = true
        m.icon.uri = m.top.iconUri
        m.icon.width = iconSize
        m.icon.height = iconSize
        m.icon.translation = [startX, (h - iconSize) / 2]
        m.label.translation = [startX + iconSize + 14, 0]
        m.label.width = textW + 2
    else
        m.icon.visible = false
        m.label.translation = [startX, 0]
        m.label.width = textW + 2
    end if
    m.label.height = h
    m.body.scaleRotateCenter = [w / 2, h / 2]
    m.top.width = w
    applyState()
end sub

sub applyState()
    focused = m.top.hasFocus()
    v = m.top.variant
    if focused then
        m.bg.visible = true
        m.bg.blendColor = "0xEDEDEDFF"
        m.ring.visible = false
        m.label.color = "0x000000FF"
        m.icon.blendColor = "0x000000FF"
        s = m.top.scaleOnFocus
        m.body.scale = [s, s]
    else
        m.body.scale = [1, 1]
        m.label.color = "0xEDEDEDFF"
        m.icon.blendColor = "0xEDEDEDFF"
        if v = "plain" then
            m.bg.visible = false
            m.ring.visible = false
            m.label.color = "0xEDEDED9E"
            m.icon.blendColor = "0xEDEDED9E"
        else if v = "solid" then
            m.bg.visible = true
            m.bg.blendColor = "0xFFFFFFC2"
            m.ring.visible = false
            m.label.color = "0x000000FF"
            m.icon.blendColor = "0x000000FF"
        else
            m.bg.visible = true
            if m.top.selectedState then
                m.bg.blendColor = "0xFFFFFF38"
            else
                m.bg.blendColor = "0xFFFFFF14"
            end if
            m.ring.visible = true
            m.ring.blendColor = "0xFFFFFF24"
        end if
    end if
    if m.top.disabled then m.body.opacity = 0.4 else m.body.opacity = 1.0
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if key = "OK" and press then
        if not m.top.disabled then m.top.buttonSelected = true
        return true
    end if
    return false
end function
