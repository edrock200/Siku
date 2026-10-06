' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.bg = m.top.findNode("bg")
    m.icon = m.top.findNode("icon")
    m.top.focusable = true
    m.top.observeField("focusedChild", "applyState")
    applyState()
end sub

sub applyState()
    s = m.top.size
    g = Int(s * 0.5)
    m.bg.width = s
    m.bg.height = s
    m.icon.uri = m.top.iconUri
    m.icon.width = g
    m.icon.height = g
    m.icon.translation = [(s - g) / 2, (s - g) / 2]
    if m.top.hasFocus() then
        m.bg.blendColor = "0xFFFFFFFF"
        m.icon.blendColor = "0x000000FF"
    else
        m.bg.blendColor = "0x00000059"
        m.icon.blendColor = "0xEDEDEDFF"
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if key = "OK" and press then
        m.top.buttonSelected = true
        return true
    end if
    return false
end function
