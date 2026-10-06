' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.arc = m.top.findNode("arc")
    m.anim = m.top.findNode("spin")
    m.top.observeField("visible", "onVisible")
    layout()
    onVisible()
end sub

sub layout()
    s = m.top.size
    m.arc.width = s
    m.arc.height = s
    m.arc.scaleRotateCenter = [s / 2, s / 2]
    m.arc.blendColor = m.top.color
end sub

sub onVisible()
    if m.top.visible then
        m.anim.control = "start"
    else
        m.anim.control = "stop"
    end if
end sub
