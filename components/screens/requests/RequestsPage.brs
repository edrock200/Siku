' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.feed = m.top.findNode("feed")
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
    m.awaiting = []        ' admin: pending, oldest first
    m.failed = []          ' admin: failed, most recently updated first
    m.rowsSpec = []
    m.lastSig = ""
    m.busy = {}            ' request ids with an action in flight
    m.menuMode = ""
    m.menuTarget = invalid
    m.top.focusable = true
end sub

' Re-read on every return, as the TV page does; unchanged rows are not re-applied, so focus stays put.
sub onPageShown()
    if not m.loading then load()
end sub

sub focusContent()
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
    gate = Req_gate()
    m.canModerate = gate.canModerate = true
    m.pending = { discover: true, mine: true }
    m.hubError = invalid
    m.approvalsError = false
    m.newDiscover = invalid
    m.newMine = invalid
    m.newAwaiting = invalid
    m.newFailed = invalid
    Api_get("/api/v2/requests/discover", invalid, "onDiscover", { seq: m.loadSeq })
    ReqApi_loadList("mine", "/api/v2/requests/mine", invalid, 100)
    if m.canModerate then
        m.pending.approvals = true
        m.pending.failed = true
        ReqApi_loadList("approvals", "/api/v2/admin/requests", { status: "pending", outcome: "active" }, 40)
        ReqApi_loadList("failed", "/api/v2/admin/requests", { outcome: "failed" }, 40)
    end if
end sub

sub onRetry()
    load()
end sub

sub onDiscover(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.loadSeq then return
    if resp.ok and resp.data <> invalid then
        m.newDiscover = Req_mergeDiscover(Arr_or(resp.data.items))
    else
        m.hubError = resp
    end if
    readDone("discover")
end sub

sub onRequestsListLoaded(tag as string, ok as boolean, items as object, resp as object)
    if tag = "mine" then
        if ok then
            m.newMine = Req_bucketMine(items)
        else
            m.hubError = resp
        end if
    else if tag = "approvals" then
        if ok then
            m.newAwaiting = Req_sortByTime(items, "created_at", false)
        else
            m.approvalsError = true
        end if
    else if tag = "failed" then
        if ok then
            m.newFailed = Req_sortByTime(items, "updated_at", true)
        else
            m.approvalsError = true
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
    ' The hub keeps prior content on a failure; it shows the error only with nothing to show.
    if m.hubError = invalid then
        m.discover = m.newDiscover
        m.mine = m.newMine
    end if
    if m.canModerate then
        if not m.approvalsError then
            m.awaiting = m.newAwaiting
            m.failed = m.newFailed
        else
            m.global.toast = "Couldn't load requests waiting for approval"
        end if
    else
        m.awaiting = []
        m.failed = []
    end if
    m.loaded = true
    render()
end sub

sub render()
    rows = []
    if m.canModerate and m.awaiting.Count() > 0 then
        rows.Push(rowSpec("approvals", "Waiting for your approval", "approval", m.awaiting))
    end if
    if m.mine.Count() > 0 then rows.Push(rowSpec("mine", "Your requests", "record", m.mine))
    if m.canModerate and m.failed.Count() > 0 then
        rows.Push(rowSpec("failed", "Failed requests", "approval", m.failed))
    end if
    for each s in m.discover
        rows.Push(rowSpec("discover:" + s.key, s.title, "result", s.results))
    end for

    if rows.Count() = 0 then
        m.rowsSpec = []
        m.lastSig = ""
        m.marquee.visible = false
        if m.hubError <> invalid then
            m.feed.errorText = Req_failureText(m.hubError, "Failed to load requests")
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
        if day <> "" then meta.Push("Requested " + day)
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
    if card.req_kind = "approval" then
        ' From an approval queue: the page decides on that exact request.
        params.moderationRequestId = Str_orEmpty(data.id)
        Nav_push("RequestDetailScreen", params)
        return
    end if
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
        if Req_displayOfRecord(data).kind = "pending" then out.Push({ id: "cancel", label: "Cancel Request", icon: "close" })
    else if card.req_kind = "approval" then
        d = Req_displayOfRecord(data)
        if d.kind = "pending" then
            out.Push({ id: "approve", label: "Approve", icon: "check" })
            out.Push({ id: "decline", label: "Decline", icon: "close" })
        else if d.kind = "attention" and d.attention = "failed" then
            out.Push({ id: "retry", label: "Retry", icon: "refresh" })
        end if
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
    ' Close first, so a stray press doesn't send a non-retryable action.
    rows = [{ id: "close", label: "Close" }]
    rows.Append(acts)
    m.menu.title = Str_orEmpty(opt.card.req.title)
    m.menu.actions = rows
    m.menu.visible = true
    m.menu.setFocus(true)
end sub

sub onMenuChosen()
    chosen = m.menu.chosen
    target = m.menuTarget
    if m.menuMode = "actions" and chosen = "decline" and target <> invalid then
        ' Decline asks first; Keep comes first so a stray press doesn't decide on someone's request.
        m.menuMode = "confirmDecline"
        m.menu.title = "Decline this request?"
        m.menu.actions = [{ id: "keep", label: "Keep" }, { id: "decline", label: "Decline", icon: "close" }]
        m.menu.visible = true
        m.menu.setFocus(true)
        return
    end if
    m.menuMode = ""
    m.menuTarget = invalid
    m.feed.focusRequested = true
    if target = invalid then return
    if chosen = "cancel" or chosen = "approve" or chosen = "decline" or chosen = "retry" then perform(chosen, target.req)
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
    enc = Str_urlEncode(id)
    if action = "cancel" then
        path = "/api/v2/requests/" + enc + "/cancel"
    else
        path = "/api/v2/admin/requests/" + enc + "/" + action
    end if
    Api_send("POST", path, {}, "onMutation", { action: action, id: id })
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
        if ctx.action = "cancel" then
            m.global.toast = "We couldn't confirm the cancellation. Refresh your requests to check it."
        else
            m.global.toast = "We couldn't confirm that decision. Refresh to see where the request stands."
        end if
        load()
        return
    end if
    if ctx.action = "cancel" then
        m.global.toast = Req_failureText(resp, "Couldn't cancel the request")
    else
        m.global.toast = Req_failureText(resp, "Something went wrong")
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    ' Parameters are part of the SceneGraph signature; this screen handles no keys itself.
    if key = "" and press then return false
    return false
end function
