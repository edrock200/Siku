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
    if m.top.hasFocus() then
        label = m.top.a11yLabel
        if label = "" then label = Transport_iconName(m.top.iconUri)
        p = A11y_position(m.top, ["PlayerTransportButton"])
        A11y_say(A11y_id(), label, "button", p.idx, p.count)
    else
        A11y_blur(A11y_id())
    end if
end sub

' A spoken name for a transport glyph (the buttons have no text).
function Transport_iconName(uri as string) as string
    names = { "rewind": "Skip back", "forward": "Skip forward", "pause": "Pause", "play": "Play", "skip_next": "Next episode", "subtitles": "Subtitles", "tune": "Audio and video options", "close": "Close player" }
    slash = 0
    for i = 1 to Len(uri)
        if Mid(uri, i, 1) = "/" then slash = i
    end for
    base = Mid(uri, slash + 1)
    if LCase(Right(base, 4)) = ".png" then base = Left(base, Len(base) - 4)
    if names.DoesExist(base) then return names[base]
    return ""
end function

function onKeyEvent(key as string, press as boolean) as boolean
    if key = "OK" and press then
        m.top.buttonSelected = true
        return true
    end if
    return false
end function
