' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.inner = m.top.findNode("inner")
    m.card = m.top.findNode("card")
    m.glow = m.top.findNode("glow")
    m.placeholder = m.top.findNode("placeholder")
    m.placeholderText = m.top.findNode("placeholderText")
    m.defaultArt = m.top.findNode("defaultArt")
    m.defaultMark = m.top.findNode("defaultMark")
    m.initialsText = m.top.findNode("initialsText")
    m.mask = m.top.findNode("mask")
    m.image = m.top.findNode("image")
    m.shade = m.top.findNode("shade")
    m.track = m.top.findNode("progressTrack")
    m.fill = m.top.findNode("progressFill")
    m.badge = m.top.findNode("watchedBadge")
    m.playGlyph = m.top.findNode("playGlyph")
    m.badgeBg = m.top.findNode("watchedBg")
    m.badgeIcon = m.top.findNode("watchedIcon")
    m.badgeRing = m.top.findNode("watchedRing")
    m.border = m.top.findNode("border")
    m.explore = m.top.findNode("explore")
    m.exploreCircle = m.top.findNode("exploreCircle")
    m.exploreIcon = m.top.findNode("exploreIcon")
    m.exploreLabel = m.top.findNode("exploreLabel")
    m.exploreLabel.text = Tx("Explore all")
    m.isExplore = false
    m.sleeves = m.top.findNode("sleeves")
    m.sleeveBack = m.top.findNode("sleeveBack")
    m.sleeveFrontEdge = m.top.findNode("sleeveFrontEdge")
    m.sleeveFront = m.top.findNode("sleeveFront")
    m.boxPill = m.top.findNode("boxPill")
    m.boxPillBg = m.top.findNode("boxPillBg")
    m.boxPillRing = m.top.findNode("boxPillRing")
    m.boxPillLabel = m.top.findNode("boxPillLabel")
    m.cornerTag = m.top.findNode("cornerTag")
    m.cornerTagBg = m.top.findNode("cornerTagBg")
    m.cornerTagLabel = m.top.findNode("cornerTagLabel")
    m.isBoxSet = false
    m.isMarked = false
    m.reportedUri = ""
    m.title = m.top.findNode("title")
    m.subtitle = m.top.findNode("subtitle")
    m.style = "poster"
    m.insetX = 0
    m.insetY = 0
    ' Labels drawn over the art: their resting boxes (FocusText_rest), the Fonts made for the lifted
    ' card, and whether they are placed for it now.
    m.artLabels = [m.placeholderText, m.initialsText, m.exploreLabel]
    m.artRest = []
    m.fonts = {}
    m.textLifted = false
    m.image.observeField("loadStatus", "onImageStatus")
    ' Card overlays (CardOverlayCard.brs): their Posters go under the watched check.
    CardOverlay_init(m.card, m.badge)
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
    ' RowList reuses item components, so every state is set for every content.
    m.isExplore = c.hasField("exploreAll") and c.exploreAll = true
    m.explore.visible = m.isExplore
    ' A box set card (Content.brs boxSet / cornerLabel); every other card resets it (reuse).
    m.isBoxSet = (not m.isExplore) and c.hasField("boxSet") and c.boxSet = true
    m.sleeves.visible = m.isBoxSet
    ' markedBadge: the movie on screen in a movie page's box set row, outlined at rest and tagged
    ' ("THIS FILM", TvMediaRow markedContentId / markedBadge).
    marked = ""
    if not m.isExplore and c.hasField("markedBadge") then marked = c.markedBadge
    m.isMarked = marked <> ""
    m.boxPill.visible = m.isBoxSet or m.isMarked
    if m.isMarked then m.boxPillLabel.text = marked else m.boxPillLabel.text = Tx("BOX SET")
    m.cornerTag.visible = false
    if m.isBoxSet and c.hasField("cornerLabel") then
        m.cornerTagLabel.text = c.cornerLabel
        m.cornerTag.visible = c.cornerLabel <> ""
    end if
    if m.isExplore then
        m.image.uri = ""
        m.initialsText.visible = false
        m.placeholderText.visible = false
        m.title.text = ""
        m.subtitle.text = ""
        m.badge.visible = false
        m.playGlyph.visible = false
        m.defaultArt.visible = false
        m.defaultMark.visible = false
        layout()
        onFocus()
        return
    end if
    m.placeholder.blendColor = "0x15171CFF"
    ' Decode the artwork at the card's drawn size (with room for the 1.05 focus lift) instead of the
    ' server's full image; the load size must be set before the uri.
    sz = imageSize()
    m.image.loadWidth = Int(sz[0] * CardFocus_scale() + 0.5)
    m.image.loadHeight = Int(sz[1] * CardFocus_scale() + 0.5)
    m.image.uri = c.HDPosterUrl
    initials = ""
    if c.initials <> invalid then initials = c.initials
    m.initialsText.text = initials
    m.initialsText.visible = initials <> ""
    m.placeholderText.visible = initials = ""
    m.placeholderText.text = c.title
    m.title.text = c.title
    ' Every card shows its title and details (the caption choice is retired, Silo Android #700).
    m.subtitle.text = c.subtitle
    m.playGlyph.visible = c.hasField("playGlyph") and c.playGlyph = true
    ' A trailer card without an image keeps a plain tile behind its play button (the title is below).
    if m.playGlyph.visible then m.placeholderText.visible = false
    layout()
    updateDefaultArt()
end sub

' The mark for the kind of title (DefaultArtworkKind.forItemType): series, seasons and episodes
' the TV, audiobooks and podcasts the headphones, anything else the film.
function markIcon(itemType as string) as string
    t = LCase(itemType)
    if t = "series" or t = "season" or t = "episode" then return "tv"
    if t = "audiobook" or t = "audiobook_part" or t = "podcast" or t = "podcast_episode" or t = "book" then return "audiobook"
    return "movie"
end function

sub onImageStatus()
    updateDefaultArt()
    if m.image.loadStatus = "failed" then reportArtFailure()
end sub

' A server image that fails may be a signed URL that expired: tell the page (the nearest ancestor
' content node with an `artFailed` counter, see components/common/Freshness.brs) once per URI, so it
' can read its data again.
sub reportArtFailure()
    uri = LCase(m.image.uri)
    if Left(uri, 7) <> "http://" and Left(uri, 8) <> "https://" then return
    if m.reportedUri = m.image.uri then return
    m.reportedUri = m.image.uri
    n = m.top.itemContent
    hops = 0
    while n <> invalid and hops < 4
        n = n.getParent()
        hops = hops + 1
        if n <> invalid and n.hasField("artFailed") then
            n.artFailed = n.artFailed + 1
            return
        end if
    end while
end sub

' Shows the default artwork while the card has no image to draw: no URL, or a failed load.
' People (circle) keep the plain circle and initials cards their letters.
sub updateDefaultArt()
    c = m.top.itemContent
    if c = invalid or m.isExplore then return
    noImage = c.HDPosterUrl = invalid or c.HDPosterUrl = "" or m.image.loadStatus = "failed"
    hasInitials = c.initials <> invalid and c.initials <> ""
    show = noImage and m.style <> "circle" and not hasInitials
    m.defaultArt.visible = show
    m.defaultMark.visible = show
    if show then
        m.defaultArt.uri = "pkg:/images/ui/art_default_" + artAspect() + ".png"
        itemType = ""
        if c.itemType <> invalid then itemType = c.itemType
        m.defaultMark.uri = "pkg:/images/icons/" + markIcon(itemType) + ".png"
    end if
    ' The title placeholder is for circles only now; cards with the glow carry their caption below.
    m.placeholderText.visible = noImage and not hasInitials and not show
end sub

function artAspect() as string
    if m.style = "landscape" then return "landscape"
    if m.style = "square" then return "square"
    return "poster"
end function

sub layout()
    ' Back to the resting boxes before they are measured again below.
    placeArtLabels(false)
    size = imageSize()
    w = size[0]
    h = size[1]
    m.inner.translation = [m.insetX, m.insetY]
    if m.style = "circle" then
        m.mask.maskUri = "pkg:/images/ui/mask_circle.png"
        m.placeholder.uri = "pkg:/images/ui/circle.png"
        m.border.uri = "pkg:/images/ui/card_ring_circle.png"
        m.glow.uri = "pkg:/images/ui/card_shadow_circle.png"
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
    m.defaultArt.width = w
    m.defaultArt.height = h
    ' Mark: 24% of the width, at least 28 px and at most 128 px (64 dp on the TV app).
    ms = Int(w * 0.24)
    if ms < 28 then ms = 28
    if ms > 128 then ms = 128
    m.defaultMark.width = ms
    m.defaultMark.height = ms
    m.defaultMark.translation = [(w - ms) \ 2, (h - ms) \ 2]
    m.border.width = w
    m.border.height = h
    CardFocus_layoutShadow(m.glow, w, h)
    m.playGlyph.translation = [(w - 60) / 2, (h - 60) / 2]
    if m.isExplore then
        ' Arrow circle over the label, centred as one block (88 + 16 + label height).
        lh = 34
        m.exploreLabel.width = w - 16
        m.exploreLabel.height = lh
        top = Int((h - (88 + 16 + lh)) / 2)
        m.exploreCircle.translation = [Int((w - 88) / 2), top]
        m.exploreIcon.translation = [Int((w - 88) / 2) + 16, top + 16]
        m.exploreLabel.translation = [8, top + 88 + 16]
    end if

    ' Progress bar (6 px) on landscape and poster cards that have progress.
    c = m.top.itemContent
    progress = 0
    if c <> invalid and c.progress <> invalid then progress = c.progress
    ' A box set's bar is the share of its films watched, which may be all of them.
    hasProgress = progress > 0.01 and (progress < 0.995 or m.isBoxSet)
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

    ' Watch status (Silo Android #882, the web's CardWatchStatus): the check on a watched title,
    ' 22 at the 185 px reference poster width and 8 in, on poster-shaped art only; a started
    ' series' episodes left take its place in the overlay image (CardOverlayCard.brs).
    watched = false
    if c <> invalid then watched = c.watched = true
    corner = CardOverlay_check(artAspect(), Int(w))
    m.badge.visible = corner.size > 0 and CardOverlay_status(watched, 0, h >= w) = "check"
    if m.badge.visible then
        bs = corner.size
        m.badge.translation = [w - bs - corner.inset, corner.inset]
        m.badgeRing.width = bs
        m.badgeRing.height = bs
        m.badgeBg.width = bs - 2
        m.badgeBg.height = bs - 2
        m.badgeBg.translation = [1, 1]
        icon = Int(bs * 0.62 + 0.5)
        m.badgeIcon.width = icon
        m.badgeIcon.height = icon
        m.badgeIcon.translation = [Int((bs - icon) / 2), Int((bs - icon) / 2)]
    end if

    if m.isBoxSet then layoutBoxSet(w, h)
    if m.isBoxSet or m.isMarked then layoutPill()

    ' The card overlays for this content at this size (none on Explore all, people, audio).
    if c <> invalid then CardOverlay_show(c, CardOverlay_shapeOf(m.style), Int(w), Int(h), hasProgress and not m.isBoxSet)

    m.title.width = w
    m.subtitle.width = w
    m.title.translation = [0, h + 22]
    m.subtitle.translation = [0, h + 56]
    m.title.visible = m.title.text <> ""
    m.subtitle.visible = m.subtitle.text <> ""

    ' The art labels' resting boxes, for drawing them unscaled on the lifted card.
    m.artRest = []
    for each lbl in m.artLabels
        lbl.setFields({ scale: [1.0, 1.0], scaleRotateCenter: [0.0, 0.0] })
        m.artRest.Push(FocusText_rest(lbl))
    end for
    onFocus()
end sub

' The sleeves rise 6 and 3 dp above the poster at Android's 140 dp reference width (web BoxSetCard:
' 6 px and 3 px over a 12 px radius), scaled with the card; the back one is inset 10% a side, the
' front one 5% with a 1 px edge. Each runs 44 px down under the poster, which hides that part.
' The cell's 30 px cardInsetY leaves room for them (pitfall 12).
sub layoutBoxSet(w as float, h as float)
    scale = w / 280.0
    backRise = Int(12 * scale + 0.5)
    frontRise = Int(6 * scale + 0.5)
    bx = Int(w * 0.10)
    m.sleeveBack.translation = [bx, -backRise]
    m.sleeveBack.width = w - 2 * bx
    m.sleeveBack.height = backRise + 44
    fx = Int(w * 0.05)
    m.sleeveFrontEdge.translation = [fx, -frontRise - 1]
    m.sleeveFrontEdge.width = w - 2 * fx
    m.sleeveFrontEdge.height = frontRise + 45
    m.sleeveFront.translation = [fx + 1, -frontRise]
    m.sleeveFront.width = w - 2 * fx - 2
    m.sleeveFront.height = frontRise + 43
    ' Estimated width: this item has no text measuring helper (Utils.brs is not in its scope), and
    ' the label centres in it; the count at ~12 px a character.
    tw = Len(m.cornerTagLabel.text) * 12 + 18
    m.cornerTagBg.width = tw
    m.cornerTagLabel.width = tw
    m.cornerTag.translation = [w - tw - 12, h - 32 - 30]
end sub

' The "BOX SET" / "THIS FILM" pill in the top-left corner, ~12 px a character at 19 px semibold.
sub layoutPill()
    pw = Len(m.boxPillLabel.text) * 12 + 28
    m.boxPillBg.width = pw
    m.boxPillRing.width = pw
    m.boxPillLabel.width = pw
    m.boxPill.translation = [12, 12]
end sub

sub onFocus()
    p = m.top.focusPercent
    ' RowList sets rowHasFocus on the focused row even when the RowList itself is not
    ' focused; rowListHasFocus (also set by RowList) tells us whether it is.
    listFocused = (m.top.rowHasFocus and m.top.rowListHasFocus) or m.top.gridHasFocus
    if not listFocused then p = 0
    size = imageSize()
    w = size[0]
    h = size[1]
    CardFocus_apply(m.card, m.border, m.glow, w, h, p, [0, 0], m.isMarked = true)
    placeArtLabels(p >= 1)
    CardOverlay_focus(p)
    if m.isExplore then
        ' White 8% at rest, 16% focused (over black; opaque, so the shadow behind the tile does not
        ' show through it); the circle and label brighten with it.
        if p > 0.5 then
            m.placeholder.blendColor = "0x2E2F33FF"
            m.exploreCircle.blendColor = "0xFFFFFF3D"
            m.exploreLabel.color = "0xFFFFFFFF"
        else
            m.placeholder.blendColor = "0x1A1B1EFF"
            m.exploreCircle.blendColor = "0xFFFFFF24"
            m.exploreLabel.color = "0xEDEDEDD9"
        end if
    end if
    ' Only the caption's colour changes, so a cut-off title does not reflow; the lift reaches
    ' less than the caption's gap below the card, so the caption stays put.
    if p > 0.5 then
        m.title.color = "0xEDEDEDFF"
    else
        m.title.color = "0xEDEDEDC7"
    end if
end sub

' The labels on the art (Explore all, initials, a person's name) are set at the lifted size once
' the lift settles, instead of being resampled with the card (FocusText.brs); at rest and while
' the lift animates they sit in their resting boxes.
sub placeArtLabels(lifted as boolean)
    if lifted = m.textLifted then return
    if m.artRest.Count() <> m.artLabels.Count() then return
    m.textLifted = lifted
    sx = 1.0
    sy = 1.0
    if lifted then
        sx = m.card.scale[0]
        sy = m.card.scale[1]
    end if
    for i = 0 to m.artLabels.Count() - 1
        FocusText_place(m.artLabels[i], m.artRest[i], [0, 0], sx, sy, m.fonts)
    end for
end sub
