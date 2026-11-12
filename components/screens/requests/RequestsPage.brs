' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.feed = m.top.findNode("feed")
    ' The layout's empty-state copy in the interface language (these fields are not translated with the tree).
    m.feed.emptyTitle = Tx("Nothing here yet")
    m.feed.emptyBody = Tx("Use Search to find a movie or series to request")
    m.feed.emptyAction = Tx("Refresh")
    m.marquee = m.top.findNode("reqMarquee")
    m.mqTitle = m.top.findNode("mqTitle")
    m.mqMeta = m.top.findNode("mqMeta")
    m.mqSynopsis = m.top.findNode("mqSynopsis")
    m.mqStatus = m.top.findNode("mqStatus")
    m.mqDot = m.top.findNode("mqDot")
    m.mqStatusText = m.top.findNode("mqStatusText")
    m.mqTrack = m.top.findNode("mqTrack")
    m.menu = m.top.findNode("menu")
    m.menu.visible = false

    ' The feed draws the backdrop and rows; this page draws the request marquee in place of the
    ' feed's own (which has no slot for a status line and stage track).
    feedMarquee = Node_find(m.feed, "marquee") ' not findNode: it would search this page, not the feed (pitfall 11)
    if feedMarquee <> invalid then feedMarquee.opacity = 0

    m.feed.observeField("itemSelected", "onItemSelected")
    m.feed.observeField("itemOptions", "onItemOptions")
    m.feed.observeField("actionSelected", "onRetry")
    m.feed.observeField("focusedCard", "onFocusedCard")
    m.feed.observeField("state", "onFeedState")
    m.menu.observeField("chosen", "onMenuChosen")
    m.menu.observeField("dismissed", "onMenuDismissed")

    m.loaded = false
    m.loading = false
    m.loadSeq = 0
    m.discover = []        ' merged discover carousels
    m.mine = []            ' the user's requests, bucketed
    m.rowsSpec = []
    m.lastSig = ""
    m.busy = {}            ' request ids with an action in flight
    m.menuMode = ""
    m.menuTarget = invalid
    m.removedIds = {}      ' requests this page removed: a list read already in flight must not bring them back
    m.removeCheck = invalid ' an uncertain removal: the next re-read says whether it landed
    m.removeDialog = invalid
    m.top.focusable = true
end sub

' Re-read on every return, as the TV page does; unchanged rows are not re-applied, so focus stays put.
sub onPageHidden()
    m.feed.overlaysWatched = false
end sub

sub onPageShown()
    m.feed.overlaysWatched = true
    if not m.loading then load()
end sub

sub focusContent()
    if m.removeDialog <> invalid then return
    if m.menu.visible then
        m.menu.setFocus(true)
    else
        m.feed.focusRequested = true
    end if
end sub

' ---------- Loading ----------

sub load()
    m.loading = true
    m.loadSeq = m.loadSeq + 1
    if not m.loaded then m.feed.state = "loading"
    m.pending = { discover: true, mine: true }
    m.hubError = invalid
    m.discoverError = invalid
    m.mineError = invalid
    m.newDiscover = invalid
    m.newMine = invalid
    Api_get("/api/v2/requests/discover", invalid, "onDiscover", { seq: m.loadSeq })
    ReqApi_loadList("mine", "/api/v2/requests/mine", invalid, 100)
end sub

sub onRetry()
    load()
end sub

sub onDiscover(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.loadSeq then return
    if resp.ok and resp.data <> invalid then
        ' The admin's Discover layout (row_order) in its order, else the two merged carousels.
        m.newDiscover = Req_discoverCarousels(resp.data)
    else
        m.discoverError = resp
    end if
    readDone("discover")
end sub

sub onRequestsListLoaded(tag as string, ok as boolean, items as object, resp as object)
    if tag = "mine" then
        if ok then
            for each id in m.removedIds
                items = Req_recordsWithout(items, id)
            end for
            m.newMine = Req_bucketMine(items)
        else
            m.mineError = resp
        end if
    end if
    readDone(tag)
end sub

' Rows appear together once every read for the page has answered.
sub readDone(tag as string)
    if m.pending = invalid then return
    m.pending.Delete(tag)
    if m.pending.Count() > 0 then return
    m.loading = false
    ' Each read replaces its own rows; a failed one keeps its prior rows, so "Your requests" failing
    ' never hides Discover (or the other way round). The error shows only with nothing to show.
    if m.discoverError = invalid then m.discover = m.newDiscover
    if m.mineError = invalid then m.mine = m.newMine
    if m.discoverError <> invalid then print "[siku-requests] discover failed status="; Int(Num_or(m.discoverError.status, 0)); "; keeping "; m.discover.Count(); " row(s)"
    if m.mineError <> invalid then print "[siku-requests] your requests failed status="; Int(Num_or(m.mineError.status, 0)); "; keeping "; m.mine.Count(); " item(s)"
    m.hubError = m.discoverError
    if m.hubError = invalid then m.hubError = m.mineError
    m.loaded = true
    settleRemoveCheck()
    render()
end sub

sub render()
    ' Request administration (approve, decline, retry) stays in web admin, as on Android TV.
    rows = []
    if m.mine.Count() > 0 then rows.Push(rowSpec("mine", Tx("Your requests"), "record", m.mine))
    for each s in m.discover
        rows.Push(rowSpec("discover:" + s.key, s.title, "result", s.results))
    end for

    if rows.Count() = 0 then
        m.rowsSpec = []
        m.lastSig = ""
        m.marquee.visible = false
        if m.hubError <> invalid then
            m.feed.errorText = Req_failureText(m.hubError, Tx("Failed to load requests"))
            m.feed.state = "error"
        else
            m.feed.rows = []
            m.feed.state = "empty"
        end if
        if m.top.isInFocusChain() then m.feed.focusRequested = true
        return
    end if

    sig = FormatJson(rows)
    if sig = m.lastSig and m.feed.state = "ready" then return
    m.lastSig = sig
    m.rowsSpec = rows
    m.feed.rows = rows
    m.feed.state = "ready"
    showMarquee(0, 0)
    if m.top.isInFocusChain() and not m.menu.visible then m.feed.focusRequested = true
end sub

function rowSpec(id as string, title as string, kind as string, items as object) as object
    cards = []
    for each it in items
        cards.Push(Req_card(kind, it, id))
    end for
    return { id: id, title: title, style: "poster", items: cards }
end function

sub onFeedState()
    m.marquee.visible = m.feed.state = "ready" and m.rowsSpec.Count() > 0
end sub

' ---------- Marquee ----------

function cardAt(rowIndex as integer, itemIndex as integer) as dynamic
    if rowIndex < 0 or rowIndex >= m.rowsSpec.Count() then return invalid
    items = m.rowsSpec[rowIndex].items
    if itemIndex < 0 or itemIndex >= items.Count() then return invalid
    return items[itemIndex]
end function

sub onFocusedCard()
    fc = m.feed.focusedCard
    if fc = invalid then return
    showMarquee(fc.rowIndex, fc.itemIndex)
end sub

sub showMarquee(rowIndex as integer, itemIndex as integer)
    card = cardAt(rowIndex, itemIndex)
    if card = invalid then
        m.marquee.visible = false
        return
    end if
    data = card.req
    meta = []
    progress = invalid
    statusText = ""
    if Req_num(data.year) > 0 then meta.Push(Str_orEmpty(data.year))
    meta.Push(Req_mediaTypeLabel(data.media_type))
    if card.req_kind = "result" then
        progress = Req_progressOfAnnotation(data.availability, data.request)
        ' A title that can't be requested has no track.
        if progress <> invalid and progress.display.kind = "unavailable" then progress = invalid
        if progress <> invalid then statusText = progress.long
        meta.Push(Req_tmdbRating(data.vote_average))
    else
        progress = Req_progressOfRecord(data)
        statusText = Req_statusLine(data, progress)
        day = Req_day(data.created_at)
        if day <> "" then meta.Push(TxF("Requested {0}", [day]))
    end if
    m.mqTitle.text = Str_orEmpty(data.title)
    m.mqMeta.text = Str_joinDots(meta)
    m.mqSynopsis.text = Str_orEmpty(data.overview)
    m.mqStatus.visible = progress <> invalid
    if progress <> invalid then
        m.mqDot.blendColor = progress.tint
        m.mqStatusText.text = statusText
        m.mqStatusText.width = 0
        w = Int(Label_width(m.mqStatusText))
        if w > 560 then w = 560
        m.mqStatusText.width = w
        m.mqTrack.progress = progress
        m.mqTrack.translation = [24 + w + 22, 15]
    end if
    m.marquee.visible = m.feed.state = "ready"
    layoutMarquee()
end sub

' Stacks the marquee bottom-up so it ends 30 px above the row band, like the feed's own.
sub layoutMarquee()
    y = m.feed.bandTop - 30
    gap = 12
    if m.mqStatus.visible then
        y = y - 36
        m.mqStatus.translation = [0, y]
        y = y - gap
    end if
    hasSyn = m.mqSynopsis.text <> ""
    m.mqSynopsis.visible = hasSyn
    if hasSyn then
        sh = Label_height(m.mqSynopsis)
        if sh < 36 then sh = 36
        y = y - sh
        m.mqSynopsis.translation = [0, y]
        y = y - gap
    end if
    m.mqMeta.visible = m.mqMeta.text <> ""
    if m.mqMeta.visible then
        y = y - 36
        m.mqMeta.translation = [0, y]
        y = y - gap
    end if
    th = Label_height(m.mqTitle)
    if th < 80 then th = 80
    m.mqTitle.translation = [0, y - th]
end sub

' ---------- Select (RequestRouter) ----------

sub onItemSelected()
    sel = m.feed.itemSelected
    if sel = invalid or sel.card = invalid then return
    card = sel.card
    data = card.req
    if data = invalid then return
    mt = Str_orEmpty(data.media_type)
    params = { mediaType: mt, tmdbId: data.tmdb_id, title: Str_orEmpty(data.title) }
    if card.req_kind = "result" then
        d = Req_displayOfAnnotation(data.availability, data.request)
    else
        d = Req_displayOfRecord(data)
    end if
    cid = Req_libraryItemToOpen(d, data.library_content_id)
    if cid <> "" then
        Nav_openItem(cid, mt)
    else
        Nav_push("RequestDetailScreen", params)
    end if
end sub

' ---------- Options (long-press) actions ----------

function actionsFor(card as object) as object
    out = []
    data = card.req
    if data = invalid or m.busy.DoesExist(Str_orEmpty(data.id)) then return out
    if card.req_kind = "record" then
        if Req_displayOfRecord(data).kind = "pending" then out.Push({ id: "cancel", label: Tx("Cancel Request"), icon: "close" })
        ' A failed request that delivered nothing, on a server that takes removals (Silo Android #792).
        if Req_canRemove(data, Req_removeFailedSupported(), false) then out.Push({ id: "remove", label: Tx("Remove request"), icon: "close" })
    end if
    return out
end function

sub onItemOptions()
    opt = m.feed.itemOptions
    if opt = invalid or opt.card = invalid then return
    acts = actionsFor(opt.card)
    ' A card with nothing to offer ignores the long-press.
    if acts.Count() = 0 then return
    m.menuTarget = opt.card
    m.menuMode = "actions"
    ' Close first, so a stray press doesn't cancel the request.
    rows = [{ id: "close", label: Tx("Close") }]
    rows.Append(acts)
    m.menu.title = Str_orEmpty(opt.card.req.title)
    m.menu.actions = rows
    m.menu.visible = true
    m.menu.setFocus(true)
end sub

sub onMenuChosen()
    chosen = m.menu.chosen
    target = m.menuTarget
    m.menuMode = ""
    m.menuTarget = invalid
    m.feed.focusRequested = true
    if target = invalid then return
    if chosen = "cancel" then perform(chosen, target.req)
    if chosen = "remove" then askRemove(target.req)
end sub

sub onMenuDismissed()
    m.menuMode = ""
    m.menuTarget = invalid
    m.feed.focusRequested = true
end sub

sub perform(action as string, rec as object)
    id = Str_orEmpty(rec.id)
    if id = "" or m.busy.DoesExist(id) then return
    m.busy[id] = true
    Api_send("POST", "/api/v2/requests/" + Str_urlEncode(id) + "/cancel", {}, "onMutation", { action: action, id: id })
end sub

sub onMutation(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid then return
    m.busy.Delete(ctx.id)
    if resp.ok then
        m.global.homeDirty = true
        load()
        return
    end if
    if Req_isUncertain(resp) then
        ' Never resend: re-read to see where the request stands.
        m.global.toast = Tx("We couldn't confirm the cancellation. Refresh your requests to check it.")
        load()
        return
    end if
    m.global.toast = Req_failureText(resp, Tx("Couldn't cancel the request"))
end sub

' ---------- Remove a failed request (Silo Android #792, TvRequestsPage removeTarget) ----------

' The confirmation names the title; Keep request comes first and takes focus, so a stray OK
' deletes nothing. Back answers Keep.
sub askRemove(rec as object)
    if m.removeDialog <> invalid then return
    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    if dlg <> invalid then
        dlg.title = Req_removeConfirmTitle()
        dlg.message = [Req_removeConfirmMessage(rec.title)]
    else
        dlg = CreateObject("roSGNode", "Dialog")
        dlg.title = Req_removeConfirmTitle()
        dlg.message = Req_removeConfirmMessage(rec.title)
    end if
    dlg.buttons = [Tx("Keep request"), Tx("Remove request")]
    dlg.observeField("buttonSelected", "onRemoveButton")
    dlg.observeField("wasClosed", "onRemoveClosed")
    m.removeDialog = dlg
    m.removeTarget = rec
    m.top.getScene().dialog = dlg
    print "[siku-requests] remove asked id="; Str_orEmpty(rec.id)
end sub

sub onRemoveButton()
    dlg = m.removeDialog
    if dlg = invalid then return
    choice = dlg.buttonSelected
    rec = m.removeTarget
    closeRemoveDialog()
    if choice = 1 and rec <> invalid then
        removeFailed(rec)
    else
        print "[siku-requests] remove kept"
    end if
end sub

sub onRemoveClosed()
    if m.removeDialog = invalid then return
    closeRemoveDialog()
    print "[siku-requests] remove kept"
end sub

sub closeRemoveDialog()
    dlg = m.removeDialog
    m.removeDialog = invalid
    m.removeTarget = invalid
    if dlg <> invalid then
        dlg.unobserveField("buttonSelected")
        dlg.unobserveField("wasClosed")
        dlg.close = true
        scene = m.top.getScene()
        if scene.dialog <> invalid and scene.dialog.isSameNode(dlg) then scene.dialog = invalid
    end if
    m.feed.focusRequested = true
end sub

sub removeFailed(rec as object)
    id = Str_orEmpty(rec.id)
    if id = "" or m.busy.DoesExist(id) then return
    ' The gate may have changed while the dialog was up.
    if not Req_canRemove(rec, Req_removeFailedSupported(), false) then return
    m.busy[id] = true
    Api_send("DELETE", "/api/v2/requests/" + Str_urlEncode(id), invalid, "onRemoved", { id: id, rec: rec })
end sub

sub onRemoved(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid then return
    m.busy.Delete(ctx.id)
    out = Req_removeOutcome(resp)
    print "[siku-requests] removed id="; ctx.id; " outcome="; out.kind; " status="; Int(Num_or(resp.status, 0))
    if out.kind = "removed" or out.kind = "gone" then
        ' The row leaves the page at once, and its title is requestable again (applyingRemoval); the
        ' feed keeps focus on the card that takes its place. Other pages re-read the server.
        dropRemoved(ctx.rec)
        m.global.homeDirty = true
        if out.toast <> "" then m.global.toast = out.toast
        ' Removed elsewhere: re-read to show the rest as it stands now.
        if out.kind = "gone" then load()
        return
    end if
    if out.kind = "uncertain" then
        ' Never resend: the re-read says whether it landed.
        m.removeCheck = { id: ctx.id, rec: ctx.rec }
        load()
        return
    end if
    m.global.toast = out.toast
    ' A conflict (retried or completed since the list loaded) re-reads the list to show why.
    load()
end sub

sub dropRemoved(rec as object)
    id = Str_orEmpty(rec.id)
    m.removedIds[id] = true
    m.mine = Req_recordsWithout(m.mine, id)
    discover = []
    for each s in m.discover
        discover.Push({ key: s.key, title: s.title, results: Req_resultsWithout(s.results, rec) })
    end for
    m.discover = discover
    if m.loaded and not m.loading then render()
end sub

' After an uncertain removal's re-read: gone means it landed.
sub settleRemoveCheck()
    chk = m.removeCheck
    if chk = invalid then return
    m.removeCheck = invalid
    if m.mineError <> invalid then
        print "[siku-requests] removed id="; chk.id; " unconfirmed (the re-read failed)"
        m.global.toast = Req_unconfirmedRemoveText()
        return
    end if
    for each r in m.mine
        if Str_orEmpty(r.id) = chk.id then
            print "[siku-requests] removed id="; chk.id; " unconfirmed (still listed)"
            m.global.toast = Req_unconfirmedRemoveText()
            return
        end if
    end for
    print "[siku-requests] removed id="; chk.id; " confirmed by the re-read"
    dropRemoved(chk.rec)
    m.global.homeDirty = true
    m.global.toast = Tx("Request removed")
end sub
