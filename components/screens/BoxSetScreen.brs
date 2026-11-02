' One movie box set (Silo Android #646: TvBoxSetScreen + the shared BoxSetViewModel). Model helpers
' are in components/common/BoxSets.brs.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.page = m.top.findNode("page")
    m.backdrop = m.top.findNode("backdrop")
    m.boxSetTitle = m.top.findNode("boxSetTitle")
    m.facts = m.top.findNode("facts")
    m.overview = m.top.findNode("overview")
    m.playBtn = m.top.findNode("playBtn")
    m.moviesSection = m.top.findNode("moviesSection")
    m.movieRow = m.top.findNode("movieRow")
    m.spinner = m.top.findNode("spinner")
    m.messageGroup = m.top.findNode("messageGroup")
    m.messageIcon = m.top.findNode("messageIcon")
    m.messageLabel = m.top.findNode("messageLabel")
    m.retryBtn = m.top.findNode("retryBtn")
    m.menu = m.top.findNode("menu")
    m.pressTimer = m.top.findNode("pressTimer")
    m.scrollAnim = m.top.findNode("scrollAnim")
    m.scrollInterp = m.top.findNode("scrollInterp")
    m.top.focusable = true

    m.detail = invalid
    m.items = []
    m.loading = false
    m.shownBefore = false
    m.readSeq = 0
    ' Watched changes from the card menu, numbered in order: {contentId: {n, watched, pending}}
    ' (BoxSet_withChangesSince), and each movie as it was before its latest change (rollback).
    m.changes = {}
    m.changeSeq = 0
    m.beforeChange = {}
    m.zone = "play"
    m.nextIndex = -1
    m.optionsTarget = invalid
    m.pendingSelect = invalid
    m.heroBottom = 700
    LongPress_init()

    m.playBtn.observeField("buttonSelected", "onPlay")
    m.retryBtn.observeField("buttonSelected", "load")
    m.movieRow.observeField("rowItemSelected", "onMovieSelected")
    m.menu.observeField("chosen", "onMenuChosen")
    m.menu.observeField("dismissed", "onMenuDismissed")
    m.pressTimer.observeField("fire", "onPressHeld")
end sub

function boxSetId() as string
    p = m.top.params
    if p = invalid then return ""
    id = Str_orEmpty(p.boxSetId)
    if id = "" then id = Str_orEmpty(p.itemId)
    return id
end function

function libraryId() as string
    p = m.top.params
    if p = invalid then return ""
    return Str_orEmpty(p.libraryId)
end function

sub onScreenShown()
    if m.detail = invalid then
        if not m.loading then load()
        if m.retryBtn.visible then
            m.retryBtn.setFocus(true)
        else
            m.top.setFocus(true)
        end if
        return
    end if
    ' Back from a movie's page or the player: watched state and the play target follow
    ' (BoxSetViewModel.onScreenResumed). Focus returns to where it was (the movie's card).
    if m.shownBefore then read(true)
    m.shownBefore = true
    focusZone(m.zone)
end sub

' ---------- Loading ----------

sub load()
    m.loading = true
    m.messageGroup.visible = false
    m.spinner.visible = true
    m.top.setFocus(true)
    read(false)
end sub

' A read replaces any read in flight: one that started before a watched change made on a movie's
' own page would answer with the state from before it. quiet: the page stays as it is while it loads
' and when the read fails.
sub read(quiet as boolean)
    m.readSeq = m.readSeq + 1
    q = Artwork_query(Artwork_query({ library_id: libraryId(), image_size: "medium" }, "detail"), "similar", Theme_posterScale())
    ctx = { seq: m.readSeq, quiet: quiet, readStart: m.changeSeq }
    Api_get("/api/v2/catalog/box-sets/" + Str_urlEncode(boxSetId()), q, "onBoxSet", ctx)
end sub

sub onBoxSet(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid or ctx.seq <> m.readSeq then return
    m.loading = false
    m.spinner.visible = false
    status = Int(Num_or(resp.status, 0))
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then
        Diag_log(Diag_join(["[siku-boxsets] box set read failed status=", status, " quiet=", ctx.quiet = true]))
        ' Box sets turned off for the library, or the viewer sees too few of its movies (404); a
        ' 410 is the same for a box set that is gone.
        if status = 404 or status = 410 then
            showUnavailable()
        else if ctx.quiet <> true or m.detail = invalid then
            showError(Api_errorText(resp))
        end if
        return
    end if
    detail = BoxSet_withChangesSince(resp.data, m.changes, Int(Num_or(ctx.readStart, 0)))
    Diag_log(Diag_join(["[siku-boxsets] box set read movies=", Arr_or(detail.items).Count(), " played=", BoxSet_playedCount(detail.items), " quiet=", ctx.quiet = true]))
    first = m.detail = invalid
    render(detail)
    if first then
        m.shownBefore = true
        if m.nextIndex >= 0 then focusZone("play") else focusZone("row")
    end if
end sub

sub showUnavailable()
    m.detail = invalid
    m.items = []
    m.page.visible = false
    m.messageGroup.visible = true
    m.messageIcon.visible = false
    m.retryBtn.visible = false
    m.messageLabel.text = "This box set isn't available. Box sets may be turned off for this library, or too few of its movies are here."
    m.top.setFocus(true)
end sub

sub showError(msg as string)
    m.detail = invalid
    m.page.visible = false
    m.messageGroup.visible = true
    m.messageIcon.visible = true
    m.retryBtn.visible = true
    m.messageLabel.text = msg
    m.retryBtn.setFocus(true)
end sub

' ---------- Rendering ----------

sub render(detail as object)
    m.detail = detail
    items = []
    for each it in Arr_or(detail.items)
        if Type(it) = "roAssociativeArray" then items.Push(it)
    end for
    m.items = items
    m.messageGroup.visible = false
    m.page.visible = true
    m.boxSetTitle.text = Str_orEmpty(detail.title)
    m.boxSetTitle.visible = m.boxSetTitle.text <> ""
    m.overview.text = Str_orEmpty(detail.overview)
    m.overview.visible = m.overview.text <> ""
    bd = Url_resolve(detail.backdrop_url)
    if m.backdrop.uri <> bd then m.backdrop.uri = bd
    renderHeroState()
    layoutHero()
    renderRow()
end sub

' The facts line and the Play button follow the watched state (a card menu change, a re-read).
sub renderHeroState()
    m.facts.text = Str_joinDots(BoxSet_heroFacts(m.detail))
    m.nextIndex = BoxSet_nextIndex(m.items)
    m.playBtn.visible = m.nextIndex >= 0
    if m.nextIndex >= 0 then
        nextMovie = m.items[m.nextIndex]
        m.playBtn.text = BoxSet_playLabel(m.detail, nextMovie)
    end if
    if m.nextIndex < 0 and m.zone = "play" and m.items.Count() > 0 then m.zone = "row"
end sub

sub layoutHero()
    x = 100
    y = 116
    gap = 18
    m.boxSetTitle.translation = [x, y]
    y = y + Label_height(m.boxSetTitle) + gap
    m.facts.translation = [x, y]
    y = y + 34 + gap
    if m.overview.visible then
        m.overview.translation = [x, y]
        y = y + Label_height(m.overview) + gap
    end if
    actionsY = y + 14
    if actionsY < 560 then actionsY = 560
    m.playBtn.translation = [x, actionsY]
    m.heroBottom = actionsY + 76 + 64
    m.moviesSection.translation = [x, m.heroBottom]
end sub

sub renderRow()
    w = Int(176 * Theme_posterScale())
    cellH = Int(w * 3 / 2) + 90 + 32
    m.movieRow.rowItemSize = [[w, cellH]]
    m.movieRow.itemSize = [1820, cellH]
    focused = -1
    if m.movieRow.content <> invalid then
        rf = m.movieRow.rowItemFocused
        if rf <> invalid and rf.Count() > 1 then focused = rf[1]
    end if
    m.movieRow.content = Content_rows([{ id: "movies", title: "", style: "poster", items: m.items }], 32)
    m.moviesSection.visible = m.items.Count() > 0
    if focused >= m.items.Count() then focused = m.items.Count() - 1
    if focused > 0 then m.movieRow.jumpToRowItem = [0, focused]
end sub

' ---------- Focus ----------

sub focusZone(zone as string)
    if zone = "play" and not m.playBtn.visible then zone = "row"
    if zone = "row" and m.items.Count() = 0 then zone = "play"
    m.zone = zone
    if m.detail = invalid then return
    if zone = "play" then
        m.playBtn.setFocus(true)
        scrollTo(0)
    else
        m.movieRow.setFocus(true)
        ' Keep the whole row on screen: the page moves up just enough to show it.
        bottom = m.heroBottom + 28 + m.movieRow.itemSize[1] + 40
        target = 0
        if bottom > 1040 then target = -(bottom - 1040)
        scrollTo(target)
    end if
end sub

sub scrollTo(targetY as float)
    cur = m.page.translation
    if Abs(cur[1] - targetY) < 1 then return
    m.scrollInterp.keyValue = [[0, cur[1]], [0, targetY]]
    m.scrollAnim.control = "start"
end sub

' ---------- Play and movies ----------

sub onPlay()
    if m.nextIndex < 0 or m.nextIndex >= m.items.Count() then return
    movie = m.items[m.nextIndex]
    id = Str_orEmpty(movie.content_id)
    if id = "" then return
    params = { itemId: id, title: Str_orEmpty(movie.title), itemType: "movie" }
    r = BoxSet_resumePosition(movie)
    if r > 0 then params.startPosition = r
    Diag_log(Diag_join(["[siku-boxsets] play movie index=", m.nextIndex, " of ", m.items.Count(), " resume=", r > 0]))
    Nav_play(params)
end sub

' OK on a movie. RowList consumes the OK press, so a long press is told from the release
' (LongPress_* in Utils.brs): a release within 600 ms opens the movie, the timer firing first opens
' its card menu.
sub onMovieSelected()
    sel = m.movieRow.rowItemSelected
    if sel = invalid or sel.Count() < 2 then return
    idx = sel[1]
    if idx < 0 or idx >= m.items.Count() then return
    if LongPress_enabled() then
        m.pendingSelect = idx
        m.pressTimer.control = "stop"
        m.pressTimer.control = "start"
    else
        openMovie(idx)
    end if
end sub

sub openMovie(idx as integer)
    if idx < 0 or idx >= m.items.Count() then return
    movie = m.items[idx]
    ' The movie's page reads its own box set row in this library.
    Nav_push("DetailScreen", { itemId: Str_orEmpty(movie.content_id), itemType: Str_orEmpty(movie["type"]), libraryId: libraryId() })
end sub

sub onPressHeld()
    idx = m.pendingSelect
    m.pendingSelect = invalid
    if idx <> invalid then openOptionsFor(idx)
end sub

sub flushPendingSelect()
    m.pressTimer.control = "stop"
    idx = m.pendingSelect
    m.pendingSelect = invalid
    if idx <> invalid then openMovie(idx)
end sub

sub openOptionsFor(idx as integer)
    if idx < 0 or idx >= m.items.Count() then return
    movie = m.items[idx]
    m.optionsTarget = { index: idx, contentId: Str_orEmpty(movie.content_id) }
    m.menu.title = Str_orEmpty(movie.title)
    m.menu.actions = CardActions_build(movie, "")
    m.menu.visible = true
    m.menu.setFocus(true)
end sub

function indexOfMovie(contentId as string) as integer
    for i = 0 to m.items.Count() - 1
        if Str_orEmpty(m.items[i].content_id) = contentId then return i
    end for
    return -1
end function

sub onMenuChosen()
    target = m.optionsTarget
    m.movieRow.setFocus(true)
    if target = invalid then return
    idx = indexOfMovie(target.contentId)
    if idx < 0 then return
    movie = m.items[idx]
    action = m.menu.chosen
    patch = CardActions_perform(action, movie, "", target)
    if patch = invalid then return
    if action = "watched" or action = "unwatched" then
        ' The count and the play target follow at once; a re-read settles them from the server.
        watched = action = "watched"
        m.beforeChange[target.contentId] = movie
        m.changeSeq = m.changeSeq + 1
        m.changes[target.contentId] = { n: m.changeSeq, watched: watched, pending: true }
        replaceMovie(idx, BoxSet_withWatched(movie, watched))
    else
        us = {}
        if Type(movie.user_state) = "roAssociativeArray" then us = AA_copy(movie.user_state)
        if patch.favorite <> invalid then us["is_favorite"] = patch.favorite
        if patch.inWatchlist <> invalid then us["in_watchlist"] = patch.inWatchlist
        updated = AA_copy(movie)
        updated["user_state"] = us
        replaceMovie(idx, updated)
    end if
end sub

sub onMenuDismissed()
    m.movieRow.setFocus(true)
end sub

' A refused Mark as Watched / Unwatched (HomeCardActions.brs): the movie goes back to how it was
' before that change, and the box set is read again (BoxSetViewModel.onMovieWatchedWriteFailed).
sub CardActions_rollback(target as dynamic, patch as object)
    if target = invalid or patch = invalid then return
    id = Str_orEmpty(target.contentId)
    m.changes.Delete(id)
    before = m.beforeChange[id]
    m.beforeChange.Delete(id)
    idx = indexOfMovie(id)
    if before <> invalid and idx >= 0 then replaceMovie(idx, before)
    if m.detail <> invalid then read(true)
end sub

sub replaceMovie(idx as integer, movie as object)
    if m.detail = invalid or idx < 0 or idx >= m.items.Count() then return
    m.items[idx] = movie
    detail = AA_copy(m.detail)
    detail["items"] = m.items
    detail["played_count"] = BoxSet_playedCount(m.items)
    m.detail = detail
    row = invalid
    if m.movieRow.content <> invalid then row = m.movieRow.content.getChild(0)
    if row <> invalid then
        node = row.getChild(idx)
        if node <> invalid then Content_fillCard(node, movie, "poster")
    end if
    renderHeroState()
end sub

' ---------- Keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then
        if m.movieRow.hasFocus() then LongPress_sawRelease()
        if key = "OK" then flushPendingSelect()
        return false
    end if
    if m.pendingSelect <> invalid and key <> "OK" then flushPendingSelect()
    if m.menu.visible then return false
    if m.detail = invalid then
        if key = "back" then return false
        if key = "OK" and m.retryBtn.visible then return false
        return true
    end if
    if key = "down" and m.zone = "play" then
        if m.items.Count() > 0 then
            ' Down starts the row at its first movie, not whichever card sits under the button.
            m.movieRow.jumpToRowItem = [0, 0]
            focusZone("row")
        end if
        return true
    else if key = "up" and m.zone = "row" then
        if m.playBtn.visible then focusZone("play")
        return true
    else if key = "options" and m.zone = "row" then
        rf = m.movieRow.rowItemFocused
        if rf <> invalid and rf.Count() > 1 then openOptionsFor(rf[1])
        return true
    end if
    return false
end function
