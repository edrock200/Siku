' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.bg = m.top.findNode("bg")
    m.ring = m.top.findNode("ring")
    m.label = m.top.findNode("label")
    m.font = CreateObject("roSGNode", "Font")
    m.font.uri = "pkg:/fonts/Inter-semibold.otf"
    m.label.font = m.font
    m.top.focusable = true
    m.top.observeField("focusedChild", "applyState")
    layout()
end sub

function chipUri(h as integer, ring as boolean) as string
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
    w = textW + m.top.padX * 2
    m.bg.uri = chipUri(h, false)
    m.ring.uri = chipUri(h, true)
    m.bg.width = w
    m.bg.height = h
    m.ring.width = w
    m.ring.height = h
    m.label.width = w
    m.label.height = h
    m.top.width = w
    applyState()
end sub

sub applyState()
    focused = m.top.hasFocus()
    if m.top.selected then
        m.bg.visible = true
        m.bg.blendColor = "0xEDEDEDFF"
        m.ring.visible = focused
        m.ring.blendColor = "0xFFFFFF80"
        m.label.color = "0x000000FF"
    else if focused then
        m.bg.visible = true
        m.bg.blendColor = "0xFFFFFF3D"
        m.ring.visible = true
        m.ring.blendColor = "0xFFFFFF99"
        m.label.color = "0xEDEDEDFF"
    else
        m.bg.visible = true
        m.bg.blendColor = "0xFFFFFF14"
        m.ring.visible = true
        m.ring.blendColor = "0xFFFFFF24"
        m.label.color = "0xEDEDEDBF"
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if key = "OK" and press then
        m.top.buttonSelected = true
        return true
    end if
    return false
end function
