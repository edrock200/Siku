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
    m.label.width = 0
    rect = m.label.boundingRect()
    w = rect.width + 72
    if w > 1400 then
        w = 1400
    end if
    m.label.width = w - 72
    m.bg.width = w
    m.bg.translation = [-w / 2, 0]
    m.label.translation = [-w / 2 + 36, 0]
    m.top.visible = true
    m.timer.control = "stop"
    m.timer.control = "start"
end sub

sub onHide()
    m.top.visible = false
end sub
