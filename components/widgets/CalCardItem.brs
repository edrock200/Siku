' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.inner = m.top.findNode("inner")
    m.badge = m.top.findNode("badge")
    m.badgeBg = m.top.findNode("badgeBg")
    m.badgeRing = m.top.findNode("badgeRing")
    m.badgeLabel = m.top.findNode("badgeLabel")
end sub

sub onContent()
    c = m.top.itemContent
    m.inner.itemContent = c
    text = ""
    if c <> invalid and c.badge <> invalid then text = c.badge
    if text = "" then
        m.badge.visible = false
    else
        m.badge.visible = true
        m.badgeLabel.text = text
        m.badgeLabel.width = 0
        w = Int(Label_width(m.badgeLabel)) + 24
        m.badgeLabel.width = w
        m.badgeBg.width = w
        m.badgeRing.width = w
    end if
end sub

sub forward()
    m.inner.width = m.top.width
    m.inner.height = m.top.height
    m.inner.focusPercent = m.top.focusPercent
    m.inner.itemHasFocus = m.top.itemHasFocus
    m.inner.rowHasFocus = m.top.rowHasFocus
    m.inner.gridHasFocus = m.top.gridHasFocus
    ' Keep the badge over the (scaled) poster corner; the poster itself sits cardInsetY px down.
    p = m.top.focusPercent
    if not (m.top.rowHasFocus or m.top.gridHasFocus) then p = 0
    off = 12 - Int(m.top.width * 0.05 * p)
    insetY = 0
    c = m.top.itemContent
    if c <> invalid and c.hasField("cardInsetY") and c.cardInsetY <> invalid then insetY = c.cardInsetY
    m.badge.translation = [off, off + insetY]
end sub
