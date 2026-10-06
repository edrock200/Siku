' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.segments = m.top.findNode("segments")
    m.labels = m.top.findNode("labels")
    m.labelFont = ThemeFont("semibold", 24)
    for i = 0 to 3
        m.segments.createChild("Rectangle")
        lbl = m.labels.createChild("Label")
        Label_setFont(lbl, "semibold", 24)
        lbl.maxLines = 1
    end for
    layout()
end sub

sub layout()
    if m.segments = invalid then return
    p = m.top.progress
    completed = 0
    current = -1
    tint = "0xFFFFFF24"
    if p <> invalid then
        if p.completed <> invalid then completed = p.completed
        if p.current <> invalid then current = p.current
        if p.tint <> invalid then tint = p.tint
    end if
    w = m.top.trackWidth
    h = m.top.trackHeight
    gap = h
    segW = Int((w - gap * 3) / 4)
    doneColor = "0xEDEDEDD1"
    restColor = "0xFFFFFF24"
    steps = Req_steps()
    for i = 0 to 3
        seg = m.segments.getChild(i)
        seg.width = segW
        seg.height = h
        seg.translation = [i * (segW + gap), 0]
        if i = current then
            seg.color = tint
        else if i < completed then
            seg.color = doneColor
        else
            seg.color = restColor
        end if
        lbl = m.labels.getChild(i)
        lbl.text = steps[i]
        lbl.width = segW + gap
        lbl.translation = [i * (segW + gap), h + 10]
        if i = current then
            lbl.color = tint
        else if i < completed then
            lbl.color = "0xEDEDEDFF"
        else
            lbl.color = "0xEDEDED73"
        end if
    end for
    m.labels.visible = m.top.showLabels
end sub
