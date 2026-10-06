' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.placeholder = m.top.findNode("placeholder")
    m.placeholderIcon = m.top.findNode("placeholderIcon")
    m.mask = m.top.findNode("mask")
    m.image = m.top.findNode("image")
    m.track = m.top.findNode("progressTrack")
    m.fill = m.top.findNode("progressFill")
    m.badge = m.top.findNode("watchedBadge")
    m.currentRing = m.top.findNode("currentRing")
    m.focusRing = m.top.findNode("focusRing")
    m.eyebrow = m.top.findNode("eyebrow")
    m.title = m.top.findNode("title")
    m.meta = m.top.findNode("meta")
    m.synopsis = m.top.findNode("synopsis")
end sub

function fieldOr(c as object, name as string, default as dynamic) as dynamic
    if c = invalid then return default
    if not c.hasField(name) then return default
    v = c[name]
    if v = invalid then return default
    return v
end function

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.image.uri = c.HDPosterUrl
    m.eyebrow.text = fieldOr(c, "eyebrow", "")
    m.title.text = c.title
    m.meta.text = fieldOr(c, "meta", "")
    m.synopsis.text = fieldOr(c, "synopsis", "")
    m.badge.visible = fieldOr(c, "watched", false) = true
    m.currentRing.visible = fieldOr(c, "isCurrent", false) = true
    layout()
end sub

sub layout()
    w = m.top.width
    if w <= 0 then w = 360
    h = Int(w * 9 / 16)
    m.placeholder.width = w
    m.placeholder.height = h
    m.placeholderIcon.width = 64
    m.placeholderIcon.height = 64
    m.placeholderIcon.translation = [(w - 64) / 2, (h - 64) / 2]
    m.mask.maskSize = [w, h]
    m.image.width = w
    m.image.height = h
    m.currentRing.width = w
    m.currentRing.height = h
    m.focusRing.width = w
    m.focusRing.height = h
    m.badge.translation = [w - 44 - 12, 12]

    c = m.top.itemContent
    progress = fieldOr(c, "progress", 0)
    hasProgress = progress > 0.01 and progress < 0.995
    m.track.visible = hasProgress
    m.fill.visible = hasProgress
    if hasProgress then
        m.track.translation = [0, h - 10]
        m.track.width = w
        m.track.height = 10
        m.fill.translation = [0, h - 10]
        m.fill.width = Int(w * progress)
        m.fill.height = 10
    end if

    m.eyebrow.translation = [0, h + 14]
    m.eyebrow.width = w
    m.title.translation = [0, h + 38]
    m.title.width = w
    m.meta.translation = [0, h + 76]
    m.meta.width = w
    m.synopsis.translation = [0, h + 108]
    m.synopsis.width = w
    m.eyebrow.visible = m.eyebrow.text <> ""
    m.meta.visible = m.meta.text <> ""
end sub

sub onFocus()
    p = m.top.focusPercent
    if not m.top.rowHasFocus then p = 0
    m.focusRing.opacity = p
    if p > 0.5 then
        m.title.color = "0xEDEDEDFF"
        m.currentRing.visible = false
    else
        m.title.color = "0xEDEDEDC7"
        m.currentRing.visible = fieldOr(m.top.itemContent, "isCurrent", false) = true
    end if
end sub
