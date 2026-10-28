' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.bdA = m.top.findNode("bdA")
    m.bdB = m.top.findNode("bdB")
    m.imgA = m.top.findNode("imgA")
    m.imgB = m.top.findNode("imgB")
    m.fadeAnim = m.top.findNode("fadeAnim")
    m.fadeIn = m.top.findNode("fadeIn")
    m.fadeOut = m.top.findNode("fadeOut")
    m.marquee = m.top.findNode("marquee")
    m.logo = m.top.findNode("logo")
    m.titleLabel = m.top.findNode("titleLabel")
    m.badges = m.top.findNode("badges")
    m.metaLabel = m.top.findNode("metaLabel")
    m.synopsis = m.top.findNode("synopsis")
    m.rowList = m.top.findNode("rowList")
    m.rowTitles = m.top.findNode("rowTitles")
    ' Row title metrics: RowList reserves (label height + rowLabelOffset.y) above each row's items.
    probe = m.top.findNode("labelProbe")
    m.titleH = Int(Label_height(probe))
    if m.titleH <= 0 then m.titleH = 38
    ' Cards sit cellPad px down inside a taller cell so the focused card's scale, ring and glow
    ' stay inside it (a real Roku clips RowList items to their cell). rowLabelOffset.y in the XML
    ' is 44 - cellPad, so the title-to-card gap on screen is still 44.
    m.cellPad = 32
    m.labelBlock = m.titleH + 12
    m.rowTitleFont = ThemeFont("semibold", 31)
    m.titleNodes = []
    m.rowTops = []
    m.focusRow = 0
    m.spinner = m.top.findNode("spinner")
    m.status = m.top.findNode("status")
    m.statusTitle = m.top.findNode("statusTitle")
    m.statusBody = m.top.findNode("statusBody")
    m.actionBtn = m.top.findNode("actionBtn")
    m.restTimer = m.top.findNode("restTimer")
    m.pressTimer = m.top.findNode("pressTimer")
    m.pendingSelect = invalid
    LongPress_init()

    m.badgeNodes = []
    m.badgeFont = ThemeFont("semibold", 19)
    m.front = "A"           ' which backdrop layer is showing
    m.currentBackdrop = ""
    m.firstBackdrop = true
    m.marqueeCard = invalid
    m.pendingFocus = invalid

    m.top.focusable = true
    m.rowList.observeField("rowItemFocused", "onRowItemFocused")
    m.rowList.observeField("rowItemSelected", "onRowItemSelected")
    m.restTimer.observeField("fire", "onRest")
    m.pressTimer.observeField("fire", "onPressHeld")
    m.actionBtn.observeField("buttonSelected", "onAction")
    m.imgA.observeField("loadStatus", "onBackdropLoaded")
    m.imgB.observeField("loadStatus", "onBackdropLoaded")
    m.logo.observeField("loadStatus", "onLogoLoaded")
    layoutBand()
    applyState()
end sub

' ---------- Rows ----------

sub onRows()
    rows = m.top.rows
    if rows = invalid then rows = []
    specs = []
    for each r in rows
        style = Str_orEmpty(r.style)
        if style = "" then style = "poster"
        specs.Push({ id: r.id, title: r.title, style: style, items: Arr_or(r.items), exploreSectionId: Str_orEmpty(r.exploreSectionId), exploreTitle: Str_orEmpty(r.exploreTitle) })
    end for
    if specs.Count() = 0 then
        m.rowList.content = invalid
        m.top.hasRows = false
        m.rowList.visible = false
        m.rowTitles.visible = false
        return
    end if
    ' A refresh (the server answer replacing the cached Home, or a re-read) keeps the focused
    ' card when it is still there, else the same position in the same row, else the first card.
    keep = focusKey()
    content = Content_rows(specs, m.cellPad)
    addExploreCards(content, specs)
    m.rowList.content = content
    m.focusRow = 0
    target = findFocus(keep)
    m.focusRow = target[0]
    syncRowMetrics()
    if target[0] > 0 or target[1] > 0 then m.rowList.jumpToRowItem = target
    m.top.hasRows = true
    m.rowList.visible = m.top.state = "ready"
    m.rowTitles.visible = m.rowList.visible
    ' Marquee for the focused (or first) card without waiting for a focus event.
    if m.top.state = "ready" then
        card = cardAt(target[0], target[1])
        if isExploreNode(card) then card = cardAt(target[0], target[1] - 1)
        if card = invalid then card = firstCard()
        if card <> invalid then showCard(card)
    end if
end sub

' ---------- "Explore all" (Silo Android #688, TvExploreAllCard) ----------
' The last card of a Home or library row opens the row's full page. It is an ordinary item after
' the row's cards, shaped like them, so D-pad Right past the last card reaches it, the RowList cell
' headroom (cardInsetY) applies to it as to the cards, and Roku's screen reader reads its title and
' description ("Explore all", the row's title) like any list item.

function exploreContentId() as string
    return "siku:explore-all"
end function

sub addExploreCards(content as object, specs as object)
    for i = 0 to specs.Count() - 1
        spec = specs[i]
        if spec.exploreSectionId <> "" and spec.items.Count() > 0 then
            row = content.getChild(i)
            node = row.createChild("ContentNode")
            Content_ensureFields(node)
            node.addFields({ exploreAll: true, exploreSectionId: spec.exploreSectionId })
            node.contentId = exploreContentId()
            node.itemType = "explore_all"
            node.cardStyle = spec.style
            node.title = "Explore all"
            title = spec.exploreTitle
            if title = "" then title = Str_orEmpty(spec.title)
            node.description = title
            node.addFields({ exploreTitle: title })
            node.raw = {}
            node.cardInsetY = m.cellPad
        end if
    end for
end sub

function isExploreNode(node as dynamic) as boolean
    if node = invalid then return false
    if not node.hasField("exploreAll") then return false
    return node.exploreAll = true
end function

' The cards of a row, not counting its "Explore all" card.
function rowCardCount(row as object) as integer
    n = row.getChildCount()
    if n > 0 and isExploreNode(row.getChild(n - 1)) then n = n - 1
    return n
end function

' {rowId, contentId, row, item} of the focused card, or invalid when nothing is drawn.
function focusKey() as dynamic
    c = m.rowList.content
    if c = invalid or c.getChildCount() = 0 then return invalid
    rf = m.rowList.rowItemFocused
    if rf = invalid or rf.Count() < 2 then return invalid
    r = rf[0]
    i = rf[1]
    if r < 0 or r >= c.getChildCount() then return invalid
    row = c.getChild(r)
    key = { rowId: Str_orEmpty(row.rowId), contentId: "", row: r, item: i }
    if i >= 0 and i < row.getChildCount() then key.contentId = Str_orEmpty(row.getChild(i).contentId)
    return key
end function

' The [row, item] in the new content for a focusKey; [0, 0] when the row is gone.
function findFocus(key as dynamic) as object
    c = m.rowList.content
    if key = invalid or c = invalid then return [0, 0]
    for r = 0 to c.getChildCount() - 1
        row = c.getChild(r)
        if Str_orEmpty(row.rowId) = key.rowId then
            n = row.getChildCount()
            if n = 0 then return [r, 0]
            if key.contentId <> "" then
                for i = 0 to n - 1
                    if Str_orEmpty(row.getChild(i).contentId) = key.contentId then return [r, i]
                end for
            end if
            i = key.item
            if i >= n then i = n - 1
            if i < 0 then i = 0
            return [r, i]
        end if
    end for
    return [0, 0]
end function

' Card size per row style (poster 176×264, landscape 360×203, square 200×200; captions add 90).
function rowCardSize(style as string) as object
    scale = Theme_posterScale()
    if style = "landscape" then
        w = Int(360 * scale)
        return [w, Int(w * 9 / 16) + 90]
    else if style = "square" then
        w = Int(200 * scale)
        return [w, w + 90]
    end if
    w = Int(176 * scale)
    return [w, Int(w * 3 / 2) + 90]
end function

' Sets the per-row item sizes / heights from the content rows (also after a row was removed) and
' rebuilds the row titles. Row heights include the label block RowList reserves above the items.
sub syncRowMetrics()
    c = m.rowList.content
    sizes = []
    heights = []
    spacing = []
    tops = []
    y = 0
    if c <> invalid then
        for i = 0 to c.getChildCount() - 1
            row = c.getChild(i)
            style = Str_orEmpty(row.rowStyle)
            if style = "" then style = "poster"
            size = rowCardSize(style)
            sizes.Push([size[0], size[1] + m.cellPad])
            rowH = size[1] + m.cellPad + m.labelBlock
            heights.Push(rowH)
            spacing.Push([40, 0])
            tops.Push(y)
            y = y + rowH + 28
        end for
    end if
    if sizes.Count() = 0 then sizes.Push([176, 354 + m.cellPad])
    if heights.Count() = 0 then heights.Push(354 + m.cellPad + m.labelBlock)
    if spacing.Count() = 0 then spacing.Push([40, 0])
    m.rowList.rowItemSize = sizes
    m.rowList.rowHeights = heights
    m.rowList.rowItemSpacing = spacing
    m.rowTops = tops
    rebuildRowTitles()
end sub

' One full-width Label per row, stacked at the rows' tops inside rowTitles.
sub rebuildRowTitles()
    c = m.rowList.content
    n = 0
    if c <> invalid then n = c.getChildCount()
    for i = 0 to n - 1
        if i < m.titleNodes.Count() then
            lbl = m.titleNodes[i]
        else
            lbl = m.rowTitles.createChild("Label")
            Label_setFont(lbl, "semibold", 31)
            lbl.color = "0xEDEDEDFF"
            lbl.width = 1780
            lbl.maxLines = 1
            m.titleNodes.Push(lbl)
        end if
        lbl.text = Str_orEmpty(c.getChild(i).title)
        lbl.height = m.titleH
        lbl.translation = [0, m.rowTops[i]]
    end for
    for i = n to m.titleNodes.Count() - 1
        m.titleNodes[i].visible = false
        m.titleNodes[i].text = ""
    end for
    layoutRowTitles()
end sub

' Vertical fixedFocus keeps the focused row at bandTop; the titles group scrolls with it. Rows
' above the focused one have scrolled out of the band, so their titles hide.
sub layoutRowTitles()
    f = m.focusRow
    if f < 0 then f = 0
    if f >= m.rowTops.Count() then f = m.rowTops.Count() - 1
    offset = 0
    if f >= 0 then offset = m.rowTops[f]
    target = [88, m.top.bandTop - offset]
    for i = 0 to m.titleNodes.Count() - 1
        m.titleNodes[i].visible = i >= f and i < m.rowTops.Count()
    end for
    ' Set directly: RowList's own scroll is about instant on the focused row.
    m.rowTitles.translation = target
end sub

function firstCard() as dynamic
    c = m.rowList.content
    if c = invalid or c.getChildCount() = 0 then return invalid
    row = c.getChild(0)
    if row.getChildCount() = 0 then return invalid
    return row.getChild(0)
end function

sub layoutBand()
    bt = m.top.bandTop
    m.rowList.translation = [40, bt]
    layoutRowTitles()
    layoutMarquee()
end sub

sub applyState()
    s = m.top.state
    m.spinner.visible = s = "loading"
    m.status.visible = s = "error" or s = "empty"
    m.rowList.visible = s = "ready" and m.top.hasRows
    m.rowTitles.visible = m.rowList.visible
    m.marquee.visible = s = "ready"
    showBackdropLayers(s = "ready")
    if s = "error" then
        m.statusTitle.text = "Something went wrong"
        body = m.top.errorText
        if Str_isEmpty(body) then body = "Could not load this page."
        m.statusBody.text = body
        m.actionBtn.text = "Retry"
    else if s = "empty" then
        m.statusTitle.text = m.top.emptyTitle
        m.statusBody.text = m.top.emptyBody
        m.actionBtn.text = m.top.emptyAction
    end if
    if m.status.visible then
        m.actionBtn.translation = [(1920 - m.actionBtn.width) / 2, 560]
    end if
    if s = "ready" and m.top.hasRows then
        first = firstCard()
        if first <> invalid and m.marqueeCard = invalid then showCard(first)
        ' If focus is parked on the feed itself (content was not ready yet), move it to the rows.
        if m.top.hasFocus() then m.rowList.setFocus(true)
    end if
end sub

sub showBackdropLayers(show as boolean)
    if show then return
    m.bdA.opacity = 0
    m.bdB.opacity = 0
    m.currentBackdrop = ""
    m.firstBackdrop = true
    ' Forget the marquee card too, so a reload shows the new first card (and its backdrop)
    ' instead of keeping the old text with a blank backdrop until focus moves.
    m.marqueeCard = invalid
end sub

sub takeFocus()
    s = m.top.state
    if s = "ready" and m.top.hasRows then
        m.rowList.setFocus(true)
    else if s = "error" or s = "empty" then
        m.actionBtn.setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

sub onAction()
    m.top.actionSelected = true
end sub

' ---------- Focus / marquee ----------

sub onRowItemFocused()
    m.pendingFocus = m.rowList.rowItemFocused
    rf = m.pendingFocus
    if rf <> invalid and rf.Count() >= 1 and rf[0] <> m.focusRow then
        m.focusRow = rf[0]
        layoutRowTitles()
    end if
    m.restTimer.control = "stop"
    m.restTimer.control = "start"
end sub

sub onRest()
    rf = m.pendingFocus
    if rf = invalid or rf.Count() < 2 then return
    node = cardAt(rf[0], rf[1])
    if node = invalid then return
    ' "Explore all" leaves the marquee on the last card previewed (TvSkylineSectionFeed).
    if isExploreNode(node) then return
    showCard(node)
    m.top.focusedCard = { rowIndex: rf[0], itemIndex: rf[1] }
end sub

function cardAt(rowIndex as integer, itemIndex as integer) as dynamic
    c = m.rowList.content
    if c = invalid then return invalid
    if rowIndex < 0 or rowIndex >= c.getChildCount() then return invalid
    row = c.getChild(rowIndex)
    if itemIndex < 0 or itemIndex >= row.getChildCount() then return invalid
    return row.getChild(itemIndex)
end function

' OK on a card. RowList sets rowItemSelected on the OK *press* and consumes that key, so a long
' press is detected from the OK *release* (see LongPress_* in HomeCardActions.brs): the selection
' waits as `pendingSelect`; the release within 600 ms opens the detail, the timer opens the menu.
sub onRowItemSelected()
    sel = m.rowList.rowItemSelected
    if sel = invalid or sel.Count() < 2 then return
    node = cardAt(sel[0], sel[1])
    if node = invalid then return
    row = m.rowList.content.getChild(sel[0])
    if isExploreNode(node) then
        ' No card menu on "Explore all": it opens at once.
        m.pendingSelect = invalid
        m.top.exploreSelected = { rowIndex: sel[0], rowId: row.rowId, sectionId: node.exploreSectionId, title: node.exploreTitle }
        return
    end if
    payload = { rowIndex: sel[0], itemIndex: sel[1], rowId: row.rowId, card: node.raw }
    if LongPress_enabled() then
        m.pendingSelect = payload
        m.pressTimer.control = "stop"
        m.pressTimer.control = "start"
    else
        m.top.itemSelected = payload
    end if
end sub

' The OK key was held: open the card menu instead of the detail page.
sub onPressHeld()
    payload = m.pendingSelect
    m.pendingSelect = invalid
    if payload <> invalid then m.top.itemOptions = payload
end sub

' A short press ended (or another key arrived): perform the normal selection now.
sub flushPendingSelect()
    m.pressTimer.control = "stop"
    payload = m.pendingSelect
    m.pendingSelect = invalid
    if payload <> invalid then m.top.itemSelected = payload
end sub

sub showCard(node as object)
    card = node.raw
    if card = invalid then return
    m.marqueeCard = card
    ' Backdrop: backdrop_url, else poster.
    url = Str_orEmpty(node.backdropUrl)
    if url = "" then url = Str_orEmpty(node.HDPosterUrl)
    setBackdrop(url)

    ' Title: logo or text. Episodes show the series title.
    t = LCase(Str_orEmpty(card.type))
    title = Str_orEmpty(card.title)
    if t = "episode" and not Str_isEmpty(card.series_title) then title = card.series_title
    logoUrl = Str_orEmpty(node.logoUrl)
    if not Theme_showTitleArt() then logoUrl = "" ' Settings → General → Show title art
    m.titleLabel.text = title
    if logoUrl <> "" then
        ' Hidden until loaded and sized (onLogoLoaded), so it never flashes centered.
        m.logo.visible = false
        m.titleLabel.visible = false
        if m.logo.uri <> logoUrl then
            m.logo.width = 880
            m.logo.height = 168
            m.logo.uri = logoUrl
        end if
        ' A cached bitmap may already be "ready" without a loadStatus change.
        onLogoLoaded()
    else
        m.logo.visible = false
        m.logo.uri = ""
        m.titleLabel.visible = true
        m.titleLabel.text = title
    end if

    ' Badges: spec badges from overlay_summary + content rating.
    labels = []
    os = card.overlay_summary
    if os <> invalid then
        res = Str_orEmpty(os.resolution)
        if res <> "" then labels.Push(prettyResolution(res))
        hdr = Str_orEmpty(os.hdr)
        if hdr <> "" then
            lh = LCase(hdr)
            if Instr(1, lh, "dv") > 0 or Instr(1, lh, "dolby") > 0 then
                labels.Push("DOLBY VISION")
            else
                labels.Push(UCase(hdr))
            end if
        end if
        audio = Str_orEmpty(os.audio)
        if audio <> "" then labels.Push(UCase(audio))
    end if
    if not Str_isEmpty(card.content_rating) then labels.Push(UCase(card.content_rating))
    setBadges(labels)

    ' Meta: for episodes the marquee title is the series, so the meta carries "S2 E8 · Episode title".
    meta = AA_copy(card)
    meta.content_rating = invalid  ' already shown as a badge
    if t = "episode" and Str_isEmpty(card.episode_title) then meta.episode_title = card.title
    m.metaLabel.text = Content_metaLine(meta)
    m.synopsis.text = Spoilers_overview(card) ' empty for an unwatched episode under spoiler protection
    layoutMarquee()
end sub

function prettyResolution(res as string) as string
    r = LCase(res)
    if r = "2160p" or r = "4k" or r = "uhd" then return "4K"
    if r = "1080p" then return "HD"
    if r = "720p" then return "720P"
    return UCase(res)
end function

sub setBadges(labels as object)
    x = 0
    for i = 0 to labels.Count() - 1
        g = badgeNode(i)
        g.visible = true
        lbl = Node_find(g, "label")
        lbl.text = labels[i]
        lbl.width = 0
        w = Int(Label_width(lbl)) + 24
        lbl.width = w
        Node_find(g, "bg").width = w
        Node_find(g, "ring").width = w
        g.translation = [x, 0]
        x = x + w + 10
    end for
    for i = labels.Count() to m.badgeNodes.Count() - 1
        m.badgeNodes[i].visible = false
    end for
    m.badgesWidth = x
end sub

function badgeNode(i as integer) as object
    if i < m.badgeNodes.Count() then return m.badgeNodes[i]
    g = m.badges.createChild("Group")
    bg = g.createChild("Poster")
    bg.id = "bg"
    bg.uri = "pkg:/images/ui/r6.9.png"
    bg.blendColor = "0xFFFFFF14"
    bg.height = 36
    ring = g.createChild("Poster")
    ring.id = "ring"
    ring.uri = "pkg:/images/ui/r6_ring2.9.png"
    ring.blendColor = "0xFFFFFF3D"
    ring.height = 36
    lbl = g.createChild("Label")
    lbl.id = "label"
    Label_setFont(lbl, "semibold", 19)
    lbl.color = "0xEDEDEDE6"
    lbl.height = 36
    lbl.vertAlign = "center"
    lbl.horizAlign = "center"
    m.badgeNodes.Push(g)
    return g
end function

' Stacks the marquee bottom-up so it ends 30 px above the row band.
sub layoutMarquee()
    if m.marquee = invalid then return
    bottom = m.top.bandTop - 30
    gap = 12
    y = bottom
    hasSyn = m.synopsis.text <> ""
    if hasSyn then
        h = Label_height(m.synopsis)
        if h < 36 then h = 36
        y = y - h
        m.synopsis.translation = [0, y]
        y = y - gap
    end if
    m.synopsis.visible = hasSyn
    ' Badges + meta share one line.
    hasMeta = m.metaLabel.text <> ""
    bw = 0
    if m.badgesWidth <> invalid then bw = m.badgesWidth
    if hasMeta or bw > 0 then
        y = y - 36
        m.badges.translation = [0, y]
        m.metaLabel.translation = [bw + 4, y + 2]
        m.metaLabel.height = 36
        m.metaLabel.width = 880 - bw
        y = y - gap
    end if
    m.metaLabel.visible = hasMeta
    if m.logo.visible then
        y = y - m.logo.height
        m.logo.translation = [0, y]
    else if m.titleLabel.visible then
        th = Label_height(m.titleLabel)
        if th < 80 then th = 80
        y = y - th
        m.titleLabel.translation = [0, y]
    end if
end sub

' Resize the logo to its aspect ratio (max 880x168) so it sits left-aligned.
sub onLogoLoaded()
    if m.logo.uri = "" then return
    if m.logo.loadStatus = "failed" then
        ' Fall back to the text title.
        m.logo.visible = false
        m.titleLabel.visible = true
        layoutMarquee()
        return
    end if
    if m.logo.loadStatus <> "ready" then return
    bw = m.logo.bitmapWidth
    bh = m.logo.bitmapHeight
    if bw <= 0 or bh <= 0 then return
    m.logo.visible = true
    m.titleLabel.visible = false
    scale = 880 / bw
    if 168 / bh < scale then scale = 168 / bh
    if scale > 1.5 then scale = 1.5
    m.logo.width = Int(bw * scale)
    m.logo.height = Int(bh * scale)
    layoutMarquee()
end sub

' ---------- Backdrop crossfade ----------

sub setBackdrop(url as string)
    if url = m.currentBackdrop then return
    m.currentBackdrop = url
    if url = "" then
        m.fadeAnim.control = "stop"
        m.bdA.opacity = 0
        m.bdB.opacity = 0
        m.firstBackdrop = true
        return
    end if
    ' Load into the back layer; the crossfade starts when it is ready.
    if m.front = "A" then
        m.imgB.uri = url
    else
        m.imgA.uri = url
    end if
end sub

sub onBackdropLoaded(event as object)
    poster = event.getRoSGNode()
    if poster.loadStatus <> "ready" then return
    if poster.uri <> m.currentBackdrop then return
    if m.top.state <> "ready" then return
    ' The front layer reloading its own image (artwork given back after a memory warning,
    ' Memory.brs) must not flip the layers.
    if m.front = "A" and poster.isSameNode(m.imgA) then return
    if m.front = "B" and poster.isSameNode(m.imgB) then return
    if m.front = "A" then
        incoming = "bdB"
        outgoing = "bdA"
        m.front = "B"
    else
        incoming = "bdA"
        outgoing = "bdB"
        m.front = "A"
    end if
    inNode = m.top.findNode(incoming)
    outNode = m.top.findNode(outgoing)
    m.fadeAnim.control = "stop"
    if m.firstBackdrop then
        ' The first frame snaps in without fading.
        m.firstBackdrop = false
        inNode.opacity = 1
        outNode.opacity = 0
        return
    end if
    m.fadeIn.fieldToInterp = incoming + ".opacity"
    m.fadeIn.keyValue = [inNode.opacity, 1.0]
    m.fadeOut.fieldToInterp = outgoing + ".opacity"
    m.fadeOut.keyValue = [outNode.opacity, 0.0]
    m.fadeAnim.control = "start"
end sub

' ---------- Patches from the host after mutations ----------

function isProgressRowId(rowId as dynamic) as boolean
    rid = LCase(Str_orEmpty(rowId))
    return rid = "continue_watching" or rid = "next_up" or rid = "in_progress" or rid = "up_next"
end function

sub removeShowFromProgressRows(seriesId as string)
    c = m.rowList.content
    for r = 0 to c.getChildCount() - 1
        row = c.getChild(r)
        if isProgressRowId(row.rowId) then
            for i = rowCardCount(row) - 1 to 0 step -1
                card = row.getChild(i).raw
                if card <> invalid and (Str_orEmpty(card.series_id) = seriesId or Str_orEmpty(card.content_id) = seriesId) then row.removeChild(row.getChild(i))
            end for
        end if
    end for
end sub

sub removeEmptyRows()
    c = m.rowList.content
    removed = false
    for r = c.getChildCount() - 1 to 0 step -1
        ' A row left with only its "Explore all" card goes too.
        if rowCardCount(c.getChild(r)) = 0 then
            c.removeChild(c.getChild(r))
            removed = true
        end if
    end for
    if c.getChildCount() = 0 then
        m.top.hasRows = false
        m.top.state = "empty"
        return
    end if
    if m.focusRow >= c.getChildCount() then m.focusRow = c.getChildCount() - 1
    if removed then syncRowMetrics()
end sub

sub onItemPatch()
    p = m.top.itemPatch
    if p = invalid then return
    node = cardAt(p.rowIndex, p.itemIndex)
    if node = invalid or isExploreNode(node) then return
    if p.remove = true then
        row = m.rowList.content.getChild(p.rowIndex)
        row.removeChild(node)
        ' A dismissed episode or series drops the whole show (#632): every card of that series
        ' leaves the Continue Watching, In Progress and Next Up rows too.
        dropped = ""
        if p.removeSeries <> invalid then dropped = p.removeSeries
        if dropped <> "" then removeShowFromProgressRows(dropped)
        removeEmptyRows()
        return
    end if
    raw = AA_copy(node.raw)
    us = AA_copy(raw.user_state)
    if p.watched <> invalid then
        node.watched = p.watched
        us.played = p.watched
    end if
    if p.favorite <> invalid then us.is_favorite = p.favorite
    if p.inWatchlist <> invalid then us.in_watchlist = p.inWatchlist
    raw.user_state = us
    if p.progress <> invalid then node.progress = p.progress
    node.raw = raw
    if m.marqueeCard <> invalid and m.marqueeCard.content_id = raw.content_id then m.marqueeCard = raw
end sub

' ---------- Keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then
        if m.rowList.hasFocus() then LongPress_sawRelease()
        if key = "OK" then flushPendingSelect()
        return false
    end if
    ' Any other key while a selection is pending ends the press as a short one.
    if m.pendingSelect <> invalid and key <> "OK" then flushPendingSelect()
    if key = "options" and m.rowList.hasFocus() then
        rf = m.rowList.rowItemFocused
        if rf <> invalid and rf.Count() >= 2 then
            node = cardAt(rf[0], rf[1])
            if isExploreNode(node) then return true
            if node <> invalid then
                row = m.rowList.content.getChild(rf[0])
                m.top.itemOptions = { rowIndex: rf[0], itemIndex: rf[1], rowId: row.rowId, card: node.raw }
                return true
            end if
        end if
    end if
    return false
end function
