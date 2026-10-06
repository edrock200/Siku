' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.card = m.top.findNode("card")
    m.glow = m.top.findNode("glow")
    m.placeholder = m.top.findNode("placeholder")
    m.placeholderIcon = m.top.findNode("placeholderIcon")
    m.mask = m.top.findNode("mask")
    m.image = m.top.findNode("image")
    m.border = m.top.findNode("border")
    m.title = m.top.findNode("title")
    m.subtitle = m.top.findNode("subtitle")
    m.padY = 0
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    ' cardInsetY: headroom in the cell so the focused 1.10 card is not clipped (see Content_rows).
    m.padY = 0
    if c.hasField("cardInsetY") and c.cardInsetY <> invalid then m.padY = c.cardInsetY
    m.image.uri = c.HDPosterUrl
    m.title.text = c.title
    sub2 = ""
    if c.hasField("subtitle") then sub2 = c.subtitle
    m.subtitle.text = sub2
    if c.hasField("itemType") and c.itemType = "audiobook" then
        m.placeholderIcon.uri = "pkg:/images/icons/audiobook.png"
    else
        m.placeholderIcon.uri = "pkg:/images/icons/album.png"
    end if
    layout()
end sub

sub layout()
    w = m.top.width
    if w <= 0 then w = 264
    m.card.scaleRotateCenter = [w / 2, w / 2]
    m.card.translation = [0, m.padY]
    m.mask.maskSize = [w, w]
    m.placeholder.width = w
    m.placeholder.height = w
    iconS = Int(w * 0.36)
    m.placeholderIcon.width = iconS
    m.placeholderIcon.height = iconS
    m.placeholderIcon.translation = [Int((w - iconS) / 2), Int((w - iconS) / 2)]
    m.image.width = w
    m.image.height = w
    m.border.width = w
    m.border.height = w
    m.glow.width = w + 24
    m.glow.height = w + 24
    m.glow.translation = [-12, -12]
    m.title.width = w
    m.subtitle.width = w
    onFocus()
end sub

sub onFocus()
    p = m.top.focusPercent
    if not ((m.top.rowHasFocus and m.top.rowListHasFocus) or m.top.gridHasFocus) then p = 0
    s = 1.0 + 0.10 * p
    m.card.scale = [s, s]
    m.border.opacity = p
    m.glow.opacity = p * 0.9
    if p > 0.5 then m.title.color = "0xEDEDEDFF" else m.title.color = "0xEDEDEDC7"
    w = m.top.width
    if w <= 0 then w = 264
    grow = w * 0.05 * p
    m.title.translation = [0, m.padY + w + 22 + grow]
    m.subtitle.translation = [0, m.padY + w + 56 + grow]
    m.subtitle.visible = m.subtitle.text <> ""
end sub
