' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.bg = m.top.findNode("bg")
    m.ring = m.top.findNode("ring")
    m.icon = m.top.findNode("icon")
    m.label = m.top.findNode("label")
    m.top.focusable = true
    m.top.observeField("focusedChild", "applyState")
    applyState()
end sub

' Capsule 9-patch for a given height (largest available radius that fits).
function circleCapsuleUri(h as integer) as string
    radii = [42, 40, 38, 32, 30, 28, 26, 22, 20, 16, 14, 12, 8, 6]
    r = 6
    for each candidate in radii
        if candidate * 2 <= h then
            r = candidate
            exit for
        end if
    end for
    return "pkg:/images/ui/r" + r.ToStr() + ".9.png"
end function

sub applyState()
    s = m.top.size
    focused = m.top.hasFocus()
    iconSize = Int(s * 0.5)
    uri = m.top.iconUri
    if m.top.active and not Str_isEmpty(m.top.activeIconUri) then uri = m.top.activeIconUri
    m.icon.uri = uri
    m.icon.width = iconSize
    m.icon.height = iconSize

    if focused and not Str_isEmpty(m.top.label) then
        m.label.text = m.top.label
        m.label.width = 0
        textW = m.label.boundingRect().width
        padX = Int(s * 0.3)
        w = padX + iconSize + 14 + textW + padX
        m.bg.uri = circleCapsuleUri(s)
        m.bg.width = w
        m.bg.height = s
        m.bg.blendColor = "0xEDEDEDFF"
        m.ring.visible = false
        m.icon.translation = [padX, (s - iconSize) / 2]
        m.icon.blendColor = "0x000000FF"
        m.label.visible = true
        m.label.translation = [padX + iconSize + 14, 0]
        m.label.width = textW + 4
        m.label.height = s
        m.top.width = w
    else
        w = s
        m.bg.uri = "pkg:/images/ui/circle.png"
        m.bg.width = s
        m.bg.height = s
        if focused then
            m.bg.blendColor = "0xEDEDEDFF"
            m.icon.blendColor = "0x000000FF"
            m.ring.visible = false
        else
            m.bg.blendColor = "0xFFFFFF1A"
            m.icon.blendColor = "0xEDEDEDFF"
            m.ring.visible = true
            m.ring.width = s
            m.ring.height = s
        end if
        m.icon.translation = [(s - iconSize) / 2, (s - iconSize) / 2]
        m.label.visible = false
        m.top.width = w
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if key = "OK" and press then
        m.top.buttonSelected = true
        return true
    end if
    return false
end function
