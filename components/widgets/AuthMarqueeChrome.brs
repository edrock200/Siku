' AuthMarqueeChrome: backdrop, wordmark and status chip for the first-run screens.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.backdrop = m.top.findNode("backdrop")
    m.logo = m.top.findNode("logo")
    m.chip = m.top.findNode("chip")
    m.chipBg = m.top.findNode("chipBg")
    m.chipRing = m.top.findNode("chipRing")
    m.chipIcon = m.top.findNode("chipIcon")
    m.chipLabel = m.top.findNode("chipLabel")
    render()
end sub

sub render()
    m.backdrop.uri = m.top.backdropUri
    m.logo.visible = m.top.showLogo
    t = m.top.chipText
    if t = "" then
        m.chip.visible = false
        return
    end if
    m.chip.visible = true
    x = 22
    if m.top.chipIconUri <> "" then
        m.chipIcon.uri = m.top.chipIconUri
        m.chipIcon.visible = true
        x = 22 + 24 + 14
    else
        m.chipIcon.visible = false
    end if
    m.chipLabel.text = t
    m.chipLabel.width = 0
    textW = Label_width(m.chipLabel)
    if textW > 600 then textW = 600
    m.chipLabel.width = textW + 2
    m.chipLabel.translation = [x, 0]
    w = x + textW + 22
    m.chipBg.width = w
    m.chipRing.width = w
    ' Right-aligned in the 64 px top row at the right safe edge (90 px).
    m.chip.translation = [1920 - 90 - w, 62]
end sub
