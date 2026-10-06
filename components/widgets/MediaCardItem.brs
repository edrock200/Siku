' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.inner = m.top.findNode("inner")
    m.card = m.top.findNode("card")
    m.glow = m.top.findNode("glow")
    m.placeholder = m.top.findNode("placeholder")
    m.placeholderText = m.top.findNode("placeholderText")
    m.initialsText = m.top.findNode("initialsText")
    m.mask = m.top.findNode("mask")
    m.image = m.top.findNode("image")
    m.shade = m.top.findNode("shade")
    m.track = m.top.findNode("progressTrack")
    m.fill = m.top.findNode("progressFill")
    m.badge = m.top.findNode("watchedBadge")
    m.badgeBg = m.top.findNode("watchedBg")
    m.badgeIcon = m.top.findNode("watchedIcon")
    m.border = m.top.findNode("border")
    m.title = m.top.findNode("title")
    m.subtitle = m.top.findNode("subtitle")
    m.style = "poster"
    m.insetX = 0
    m.insetY = 0
end sub

' Image box size for the current item width (minus the cell inset). Captions go below it.
function imageSize() as object
    w = m.top.width - 2 * m.insetX
    if w <= 0 then w = 176
    if m.style = "landscape" then return [w, Int(w * 9 / 16)]
    if m.style = "circle" or m.style = "square" then return [w, w]
    return [w, Int(w * 3 / 2)]
end function

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    if c.cardStyle <> invalid and c.cardStyle <> "" then m.style = c.cardStyle
    m.insetX = 0
    m.insetY = 0
    if c.cardInsetX <> invalid then m.insetX = c.cardInsetX
    if c.cardInsetY <> invalid then m.insetY = c.cardInsetY
    m.image.uri = c.HDPosterUrl
    initials = ""
    if c.initials <> invalid then initials = c.initials
    m.initialsText.text = initials
    m.initialsText.visible = initials <> ""
    m.placeholderText.visible = initials = ""
    m.placeholderText.text = c.title
    m.title.text = c.title
    m.subtitle.text = c.subtitle
    m.badge.visible = c.watched = true
    layout()
end sub

sub layout()
    size = imageSize()
    w = size[0]
    h = size[1]
    m.inner.translation = [m.insetX, m.insetY]
    m.card.scaleRotateCenter = [w / 2, h / 2]
    if m.style = "circle" then
        m.mask.maskUri = "pkg:/images/ui/mask_circle.png"
        m.placeholder.uri = "pkg:/images/ui/circle.png"
        m.border.uri = "pkg:/images/ui/circle_ring.png"
        m.glow.uri = "pkg:/images/ui/circle.png"
        m.title.horizAlign = "center"
        m.subtitle.horizAlign = "center"
    else if m.style = "landscape" then
        m.mask.maskUri = "pkg:/images/ui/mask_landscape.png"
    else if m.style = "square" then
        m.mask.maskUri = "pkg:/images/ui/mask_square.png"
    else
        m.mask.maskUri = "pkg:/images/ui/mask_poster.png"
    end if
    m.mask.maskSize = [w, h]
    m.placeholder.width = w
    m.placeholder.height = h
    m.placeholderText.width = w - 24
    m.placeholderText.height = h
    m.placeholderText.translation = [12, 0]
    m.initialsText.width = w
    m.initialsText.height = h
    m.image.width = w
    m.image.height = h
    m.border.width = w
    m.border.height = h
    m.glow.width = w + 24
    m.glow.height = h + 24
    m.glow.translation = [-12, -12]

    ' Progress bar (6 px) on landscape and poster cards that have progress.
    c = m.top.itemContent
    progress = 0
    if c <> invalid and c.progress <> invalid then progress = c.progress
    hasProgress = progress > 0.01 and progress < 0.995
    m.track.visible = hasProgress
    m.fill.visible = hasProgress
    m.shade.visible = hasProgress
    if hasProgress then
        m.shade.width = w
        m.shade.height = h / 2
        m.shade.translation = [0, h / 2]
        m.shade.opacity = 0.6
        barX = 12
        barW = w - 24
        barY = h - 18
        m.track.translation = [barX, barY]
        m.track.width = barW
        m.track.height = 6
        m.fill.translation = [barX, barY]
        m.fill.width = Int(barW * progress)
        m.fill.height = 6
    end if

    ' Watched badge: 24% of the width, clamped 40..64 px, inset 6%.
    bs = Int(w * 0.24)
    if bs < 40 then bs = 40
    if bs > 64 then bs = 64
    inset = Int(w * 0.06)
    m.badge.translation = [w - bs - inset, inset]
    m.badgeBg.width = bs
    m.badgeBg.height = bs
    m.badgeIcon.width = bs * 0.7
    m.badgeIcon.height = bs * 0.7
    m.badgeIcon.translation = [bs * 0.15, bs * 0.15]

    m.title.width = w
    m.subtitle.width = w
    m.title.translation = [0, h + 22]
    m.subtitle.translation = [0, h + 56]
    m.title.visible = m.title.text <> ""
    m.subtitle.visible = m.subtitle.text <> ""
end sub

sub onFocus()
    p = m.top.focusPercent
    ' RowList sets rowHasFocus on the focused row even when the RowList itself is not
    ' focused; rowListHasFocus (also set by RowList) tells us whether it is.
    listFocused = (m.top.rowHasFocus and m.top.rowListHasFocus) or m.top.gridHasFocus
    if not listFocused then p = 0
    s = 1.0 + 0.10 * p
    m.card.scale = [s, s]
    m.border.opacity = p
    m.glow.opacity = p * 0.9
    if p > 0.5 then
        m.title.color = "0xEDEDEDFF"
    else
        m.title.color = "0xEDEDEDC7"
    end if
    ' Keep the caption below the scaled image.
    size = imageSize()
    h = size[1]
    grow = h * 0.05 * p
    m.title.translation = [0, h + 22 + grow]
    m.subtitle.translation = [0, h + 56 + grow]
end sub
