' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.bg = m.top.findNode("bg")
    m.label = m.top.findNode("label")
    m.timer = m.top.findNode("timer")
    m.timer.observeField("fire", "onHide")
    m.top.visible = false
    m.top.translation = [960, 960]
end sub

sub onMessage()
    m.label.text = m.top.message
    m.label.wrap = false
    m.label.width = 0
    natural = Label_width(m.label)
    w = natural + 72
    h = 64
    if w > 1400 then
        ' A full sentence (an AI job's failure reason) wraps onto up to three lines instead of
        ' being cut off; the pill grows upwards from the usual bottom edge.
        w = 1400
        lines = 2
        if natural > (w - 72) * 2 then lines = 3
        h = 24 + lines * 36
        m.label.wrap = true
        m.label.maxLines = lines
    end if
    m.label.width = w - 72
    m.label.height = h
    m.bg.width = w
    m.bg.height = h
    m.bg.translation = [-w / 2, 64 - h]
    m.label.translation = [-w / 2 + 36, 64 - h]
    m.top.visible = true
    m.timer.duration = m.top.duration
    m.timer.control = "stop"
    m.timer.control = "start"
end sub

sub onHide()
    m.top.visible = false
end sub
