' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.inner = m.top.findNode("inner")
    m.badges = m.top.findNode("badges")
    m.pills = []
    for i = 0 to 2
        m.pills.Push({
            group: m.top.findNode("badge" + i.ToStr())
            bg: m.top.findNode("badgeBg" + i.ToStr())
            ring: m.top.findNode("badgeRing" + i.ToStr())
            label: m.top.findNode("badgeLabel" + i.ToStr())
        })
    end for
    m.timeTag = m.top.findNode("timeTag")
    m.timeBg = m.top.findNode("timeBg")
    m.timeLabel = m.top.findNode("timeLabel")
    m.timeW = 0
end sub

sub onContent()
    c = m.top.itemContent
    m.inner.itemContent = c
    text = ""
    if c <> invalid and c.badge <> invalid then text = c.badge
    labels = []
    if text <> "" then labels = text.Split("|")
    for i = 0 to m.pills.Count() - 1
        p = m.pills[i]
        if i < labels.Count() and labels[i] <> "" then
            p.group.visible = true
            p.group.translation = [0, i * 40]
            p.label.text = labels[i]
            p.label.width = 0
            w = Int(Label_width(p.label)) + 24
            p.label.width = w
            p.bg.width = w
            p.ring.width = w
        else
            p.group.visible = false
        end if
    end for
    t = ""
    if c <> invalid and c.hasField("timeTag") and c.timeTag <> invalid then t = c.timeTag
    m.timeTag.visible = t <> ""
    m.timeW = 0
    if t <> "" then
        m.timeLabel.text = t
        m.timeLabel.width = 0
        m.timeW = Int(Label_width(m.timeLabel)) + 22
        m.timeLabel.width = m.timeW
        m.timeBg.width = m.timeW
    end if
    forward()
end sub

sub forward()
    m.inner.width = m.top.width
    m.inner.height = m.top.height
    m.inner.focusPercent = m.top.focusPercent
    m.inner.itemHasFocus = m.top.itemHasFocus
    m.inner.rowHasFocus = m.top.rowHasFocus
    m.inner.gridHasFocus = m.top.gridHasFocus
    m.inner.rowListHasFocus = m.top.rowListHasFocus
    ' Keep the badges and the time over the lifted poster's corners (CardFocus.brs: the poster
    ' grows by whole px about its top-left, moved back by the lift); it sits cardInsetY px down.
    p = m.top.focusPercent
    if not ((m.top.rowHasFocus and m.top.rowListHasFocus) or m.top.gridHasFocus) then p = 0
    w = m.top.width
    h = Int(w * 3 / 2)
    insetY = 0
    c = m.top.itemContent
    if c <> invalid and c.hasField("cardInsetY") and c.cardInsetY <> invalid then insetY = c.cardInsetY
    tl = CardFocus_point(12, 12, w, h, p)
    m.badges.translation = [Int(tl[0] + 0.5), Int(tl[1] + 0.5) + insetY]
    br = CardFocus_point(w - 12, h - 12, w, h, p)
    m.timeTag.translation = [Int(br[0] + 0.5) - m.timeW, Int(br[1] + 0.5) - 32 + insetY]
end sub
