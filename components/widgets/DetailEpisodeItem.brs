' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.card = m.top.findNode("card")
    m.shadow = m.top.findNode("shadow")
    m.insetY = 0
    m.placeholder = m.top.findNode("placeholder")
    m.placeholderIcon = m.top.findNode("placeholderIcon")
    m.mask = m.top.findNode("mask")
    m.image = m.top.findNode("image")
    m.track = m.top.findNode("progressTrack")
    m.fill = m.top.findNode("progressFill")
    m.badge = m.top.findNode("watchedBadge")
    m.watchedBg = m.top.findNode("watchedBg")
    m.watchedIcon = m.top.findNode("watchedIcon")
    m.focusRing = m.top.findNode("focusRing")
    m.eyebrow = m.top.findNode("eyebrow")
    m.title = m.top.findNode("title")
    m.meta = m.top.findNode("meta")
    m.synopsis = m.top.findNode("synopsis")
    m.aiIcon = m.top.findNode("aiIcon")
    m.translating = m.top.findNode("translating")
    m.translating.text = Tx("Translating description…")
    ' Card overlays (CardOverlayCard.brs): their Posters go under the watched check.
    CardOverlay_init(m.card, m.badge)
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
    m.insetY = fieldOr(c, "cardInsetY", 0)
    m.image.uri = c.HDPosterUrl
    m.eyebrow.text = fieldOr(c, "eyebrow", "")
    m.title.text = c.title
    m.meta.text = fieldOr(c, "meta", "")
    m.synopsis.text = fieldOr(c, "synopsis", "")
    m.badge.visible = fieldOr(c, "watched", false) = true
    m.aiIcon.visible = fieldOr(c, "aiTranslated", false) = true
    ' The progress replaces the mark while the season's job fills this description (#822).
    m.translating.visible = fieldOr(c, "aiTranslating", false) = true
    if m.translating.visible then m.aiIcon.visible = false
    layout()
end sub

sub layout()
    w = m.top.width
    if w <= 0 then w = 360
    h = Int(w * 9 / 16)
    m.placeholder.width = w
    m.placeholder.height = h
    m.defaultArt = m.top.findNode("defaultArt")
    m.defaultArt.width = w
    m.defaultArt.height = h
    ms = Int(w * 0.24)
    if ms > 128 then ms = 128
    m.placeholderIcon.width = ms
    m.placeholderIcon.height = ms
    m.placeholderIcon.translation = [(w - ms) \ 2, (h - ms) \ 2]
    m.mask.maskSize = [w, h]
    m.image.width = w
    m.image.height = h
    m.focusRing.width = w
    m.focusRing.height = h
    CardFocus_layoutShadow(m.shadow, w, h)
    ' The watched check at the wide cards' overlay scale, so it matches their badges (Silo Android
    ' #912): 44 px 12 in on a Standard card, with Poster Size from there.
    corner = CardOverlay_check("episode", Int(w), CardOverlay_scaleFor("episode", w))
    bs = corner.size
    m.badge.translation = [w - bs - corner.inset, corner.inset]
    m.watchedBg.width = bs
    m.watchedBg.height = bs
    icon = Int(bs * 30 / 44 + 0.5)
    m.watchedIcon.width = icon
    m.watchedIcon.height = icon
    m.watchedIcon.translation = [Int((bs - icon) / 2), Int((bs - icon) / 2)]

    c = m.top.itemContent
    progress = fieldOr(c, "progress", 0)
    hasProgress = progress > 0.01 and progress < 0.995
    WatchProgress_place(m.track, m.fill, w, h, progress, hasProgress, false)

    ' Caption: "S01E02 · Title" over "Feb 18, 2026  ·  52m", then the description (#644). The
    ' meta line keeps its place when empty so every card in the rail lines up.
    top = m.insetY + h + 14
    if m.eyebrow.text <> "" then
        m.eyebrow.translation = [0, top]
        top = top + 24
    end if
    m.eyebrow.width = w
    m.title.translation = [0, top]
    m.title.width = w
    m.meta.translation = [0, top + 40]
    m.meta.width = w
    m.synopsis.translation = [0, top + 74]
    m.synopsis.width = w
    m.synopsis.maxLines = 3
    m.translating.width = w
    if m.translating.visible then
        m.translating.translation = [0, top + 74]
        m.synopsis.translation = [0, top + 108]
        m.synopsis.maxLines = 2
    end if
    m.eyebrow.visible = m.eyebrow.text <> ""
    m.meta.visible = m.meta.text <> ""
    ' Compact AI marker at the right end of the meta line; the meta text stops short of it.
    m.aiIcon.translation = [w - 24, m.insetY + h + 80]
    if m.aiIcon.visible then m.meta.width = w - 36
    if c <> invalid then CardOverlay_show(c, "episode", Int(w), Int(h), hasProgress)
    onFocus()
end sub

sub onFocus()
    p = m.top.focusPercent
    if not (m.top.rowHasFocus and m.top.rowListHasFocus) then p = 0
    w = m.top.width
    if w <= 0 then w = 360
    h = Int(w * 9 / 16)
    current = fieldOr(m.top.itemContent, "isCurrent", false) = true
    CardFocus_apply(m.card, m.focusRing, m.shadow, w, h, p, [0, m.insetY], current)
    CardOverlay_focus(p)
    if p > 0.5 or current then
        m.title.color = "0xEDEDEDFF"
    else
        m.title.color = "0xEDEDEDC7"
    end if
end sub
