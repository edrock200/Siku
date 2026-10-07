' Notifications inbox (Android TV TvInboxScreen.kt, TvInboxFormatters.kt; shared
' NotificationsRepository.kt). Endpoints (silo-server contracts/api/v2/openapi.json):
'   GET  /api/v2/notifications?limit=25&status=all[&cursor=]  -> {items[], page{has_more,next_cursor}, read_cutoff}
'   GET  /api/v2/notifications/unread-count                   -> {count}
'   POST /api/v2/notifications/{id}/read                      -> 204
'   POST /api/v2/notifications/read-all {through: read_cutoff} -> 204
' Realtime (events websocket) and forward sync are not ported; the inbox rereads on every show.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.list = m.top.findNode("list")
    m.headerBg = m.top.findNode("headerBg")
    m.errorCard = m.top.findNode("errorCard")
    m.spinner = m.top.findNode("spinner")
    m.empty = m.top.findNode("empty")
    m.scrollAnim = m.top.findNode("scrollAnim")
    m.scrollInterp = m.top.findNode("scrollInterp")

    m.pageSize = 25
    m.listX = 80
    m.listTopBase = 329     ' contentTopInset 94 dp + eyebrow + 8 dp + title + 18 dp
    m.rowGap = 24           ' LazyColumn spacedBy(12.dp)
    m.bottomPad = 112       ' contentPadding bottom 56.dp

    m.rows = []             ' raw API rows, newest first
    m.unreadCount = 0
    m.nextCursor = ""
    m.readCutoff = ""
    m.errorText = ""
    m.refreshing = false
    m.loadingMore = false
    m.refreshSeq = 0
    m.loaded = false

    m.items = []            ' focusable list entries: {kind, id, node, top, height}
    m.focusIdx = -1
    m.errorFocused = false
    m.scrollY = 0
    m.pendingMarkAllRefocus = false
    m.initialFocusDone = false
end sub

sub onScreenShown()
    ' LaunchedEffect(Unit) { repository.refresh() } runs each time the inbox is composed.
    refresh()
    applyFocus()
end sub

' ---------- Loading ----------

sub refresh()
    m.refreshSeq = m.refreshSeq + 1
    m.refreshing = true
    m.errorText = ""
    m.pendingCount = invalid
    m.pendingPage = invalid
    m.pendingParts = 2
    ctx = { seq: m.refreshSeq }
    Api_get("/api/v2/notifications/unread-count", invalid, "onUnreadCount", ctx)
    Api_get("/api/v2/notifications", { limit: m.pageSize, status: "all" }, "onFirstPage", ctx)
    render()
end sub

sub onUnreadCount(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.refreshSeq then return
    m.pendingCount = resp
    refreshPartDone()
end sub

sub onFirstPage(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.refreshSeq then return
    m.pendingPage = resp
    refreshPartDone()
end sub

sub refreshPartDone()
    m.pendingParts = m.pendingParts - 1
    if m.pendingParts > 0 then return
    page = m.pendingPage
    count = m.pendingCount
    if page.ok and page.data <> invalid then
        m.rows = dedupeById(Arr_or(page.data.items))
        if count.ok and count.data <> invalid and count.data.count <> invalid then m.unreadCount = Int(Content_num(count.data.count))
        m.nextCursor = pageCursor(page.data)
        m.readCutoff = Str_orEmpty(page.data.read_cutoff)
    end if
    if not page.ok or not count.ok then
        m.errorText = "Notifications could not be refreshed. Retry when connected."
    end if
    m.refreshing = false
    m.loaded = true
    rebuild()
end sub

function pageCursor(data as object) as string
    pg = data.page
    if pg = invalid or pg.has_more <> true then return ""
    return Str_orEmpty(pg.next_cursor)
end function

sub maybeLoadMore()
    if m.nextCursor = "" or m.loadingMore or m.refreshing then return
    if lastVisibleIndex() < m.items.Count() - 4 then return
    m.loadingMore = true
    cursor = m.nextCursor
    Api_get("/api/v2/notifications", { limit: m.pageSize, status: "all", cursor: cursor }, "onMorePage", { cursor: cursor, seq: m.refreshSeq })
end sub

sub onMorePage(event as object)
    resp = Api_result(event)
    m.loadingMore = false
    if resp.context = invalid or resp.context.cursor <> m.nextCursor then return
    if not resp.ok or resp.data = invalid then
        m.errorText = "Older notifications could not be loaded. Retry to continue."
        rebuild()
        return
    end if
    merged = []
    merged.Append(m.rows)
    merged.Append(Arr_or(resp.data.items))
    m.rows = dedupeById(merged)
    m.nextCursor = pageCursor(resp.data)
    rebuild()
end sub

function dedupeById(rows as object) as object
    seen = {}
    out = []
    for each r in rows
        if type(r) = "roAssociativeArray" then
            rid = Str_orEmpty(r.id)
            if rid <> "" and not seen.DoesExist(rid) then
                seen[rid] = true
                out.Push(r)
            end if
        end if
    end for
    return out
end function

' ---------- Mutations ----------

sub markAllRead()
    ' Mark all read sends the exact read_cutoff of the displayed list, then rereads.
    if m.readCutoff = "" then
        m.errorText = "Refresh the inbox before marking it read."
        rebuild()
        return
    end if
    m.pendingMarkAllRefocus = true
    Api_send("POST", "/api/v2/notifications/read-all", { through: m.readCutoff }, "onMarkedAllRead")
end sub

sub onMarkedAllRead(event as object)
    resp = Api_result(event)
    if not resp.ok then
        m.pendingMarkAllRefocus = false
        m.errorText = "Mark all read could not be confirmed. Refresh before trying again."
        rebuild()
        return
    end if
    refresh()
end sub

sub openRow(row as object)
    rid = Str_orEmpty(row.id)
    Api_send("POST", "/api/v2/notifications/" + Str_urlEncode(rid) + "/read", invalid, "onMarkedRead", { id: rid })
    ' targetContentId = series_id ?: episode_id ?: library_id
    seriesId = Str_orEmpty(row.series_id)
    episodeId = Str_orEmpty(row.episode_id)
    if seriesId <> "" then
        Nav_openItem(seriesId, "series")
    else if episodeId <> "" then
        Nav_openItem(episodeId, "episode")
    end if
    ' A library-only delivery has no detail page to open on Roku; it is just marked read.
end sub

sub onMarkedRead(event as object)
    resp = Api_result(event)
    if not resp.ok then
        m.errorText = "Notification read status could not be confirmed."
        rebuild()
        return
    end if
    rid = ""
    if resp.context <> invalid then rid = Str_orEmpty(resp.context.id)
    found = false
    for each r in m.rows
        if Str_orEmpty(r.id) = rid then
            found = true
            if Str_isEmpty(r.read_at) then
                r.read_at = Str_orEmpty(r.created_at)
                if r.read_at = "" then r.read_at = "read"
            end if
        end if
    end for
    if not found then return
    n = 0
    for each r in m.rows
        if Str_isEmpty(r.read_at) then n = n + 1
    end for
    m.unreadCount = n
    rebuild()
end sub

' ---------- Card models (TvInboxFormatters.kt) ----------

function cardModel(row as object, nowSec as integer) as object
    rawType = Str_orEmpty(row.type)
    isEpisode = rawType = "episode.available"
    seriesTitle = Str_orEmpty(row.series_title)
    episodeTitle = Str_orEmpty(row.episode_title)
    posterUrl = Str_orEmpty(row.poster_url)
    sxey = ""
    if row.season_number <> invalid and row.episode_number <> invalid then
        sxey = "S" + numText(row.season_number) + "E" + numText(row.episode_number)
    end if
    subtitle = ""
    if isEpisode then
        parts = []
        if sxey <> "" then parts.Push(sxey)
        if episodeTitle <> "" then parts.Push(episodeTitle)
        subtitle = parts.Join(" • ")
    else if episodeTitle <> "" then
        subtitle = episodeTitle
    else
        subtitle = seriesTitle
    end if
    title = ""
    if isEpisode then
        title = seriesTitle
        if title = "" then title = "New episode available"
    else
        title = fallbackTitleForType(rawType)
    end if
    uri = ""
    if posterUrl <> "" then uri = Url_resolve(posterUrl)
    return {
        kind: "row"
        id: Str_orEmpty(row.id)
        isRich: isEpisode and (posterUrl <> "" or seriesTitle <> "")
        title: title
        subtitle: subtitle
        posterUrl: uri
        relativeTime: relativeTime(Str_orEmpty(row.created_at), nowSec)
        isUnread: Str_isEmpty(row.read_at)
    }
end function

function numText(v as dynamic) as string
    if type(v) = "roString" or type(v) = "String" then return v
    return Int(v).ToStr()
end function

function fallbackTitleForType(rawType as string) as string
    if rawType = "request.fulfilled" then return "Request fulfilled"
    if rawType = "webhook.auto_disabled" then return "Webhook disabled"
    head = rawType
    dot = Instr(1, head, ".")
    if dot > 0 then head = Left(head, dot - 1)
    head = head.Replace("_", " ")
    if head.Trim() = "" then return "Notification"
    return UCase(Left(head, 1)) + head.Mid(1)
end function

' now / Nm / Nh / Nd up to a week, then "MMM d" (local). Unparseable -> "".
function relativeTime(createdAt as string, nowSec as integer) as string
    d = Time_parseIso(createdAt)
    if d = invalid then return ""
    delta = nowSec - d.AsSeconds()
    if delta < 0 then delta = 0
    if delta < 60 then return "now"
    if delta < 3600 then return Int(delta / 60).ToStr() + "m"
    if delta < 86400 then return Int(delta / 3600).ToStr() + "h"
    if delta < 7 * 86400 then return Int(delta / 86400).ToStr() + "d"
    d.ToLocalTime()
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return months[d.GetMonth() - 1] + " " + d.GetDayOfMonth().ToStr()
end function

' ---------- Rendering ----------

sub render()
    hasItems = m.items.Count() > 0
    m.spinner.visible = m.refreshing and not hasItems and m.rows.Count() = 0
    m.empty.visible = m.loaded and not m.refreshing and m.rows.Count() = 0 and m.errorText = ""
end sub

sub rebuild()
    prevId = ""
    prevKind = ""
    if m.focusIdx >= 0 and m.focusIdx < m.items.Count() then
        prevId = m.items[m.focusIdx].id
        prevKind = m.items[m.focusIdx].kind
    end if

    ' Error card ("<error> Retry"), above the list.
    listTop = m.listTopBase
    if m.errorText <> "" then
        m.errorCard.card = { kind: "error", title: m.errorText + " Retry" }
        m.errorCard.visible = true
        listTop = listTop + m.errorCard.rowHeight + 16
    else
        m.errorCard.visible = false
        m.errorFocused = false
    end if
    m.listTop = listTop
    m.headerBg.height = listTop

    m.list.removeChildrenIndex(m.list.getChildCount(), 0)
    m.items = []
    nowSec = Time_nowSeconds()
    y = 0
    if m.rows.Count() > 0 and m.unreadCount > 0 then
        node = m.list.createChild("NotificationRow")
        node.card = { kind: "markAll", title: "Mark all read" }
        node.translation = [0, y]
        m.items.Push({ kind: "markAll", id: "mark-all-read", node: node, top: y, height: node.rowHeight })
        y = y + node.rowHeight + m.rowGap
    end if
    for each row in m.rows
        node = m.list.createChild("NotificationRow")
        node.width = 1760
        node.card = cardModel(row, nowSec)
        node.translation = [0, y]
        m.items.Push({ kind: "row", id: Str_orEmpty(row.id), node: node, top: y, height: node.rowHeight, row: row })
        y = y + node.rowHeight + m.rowGap
    end for
    m.contentHeight = y - m.rowGap + m.bottomPad

    ' Keep focus on the same entry; after Mark all read, land on the first notification.
    idx = -1
    if m.pendingMarkAllRefocus and m.unreadCount = 0 then
        m.pendingMarkAllRefocus = false
        idx = 0
    else if prevId <> "" then
        for i = 0 to m.items.Count() - 1
            if m.items[i].id = prevId and m.items[i].kind = prevKind then idx = i
        end for
        if idx < 0 then idx = m.focusIdx
    end if
    if m.items.Count() = 0 then
        idx = -1
    else if idx < 0 then
        idx = 0
    else if idx > m.items.Count() - 1 then
        idx = m.items.Count() - 1
    end if
    m.focusIdx = idx
    if m.items.Count() = 0 and m.errorCard.visible then m.errorFocused = true
    render()
    applyFocus()
    scrollToFocus(false)
end sub

sub applyFocus()
    if not m.top.active then return
    for i = 0 to m.items.Count() - 1
        m.items[i].node.focused = (not m.errorFocused) and i = m.focusIdx
    end for
    m.errorCard.focused = m.errorFocused
    m.top.setFocus(true)
end sub

function viewportHeight() as integer
    return 1080 - m.listTop
end function

sub scrollToFocus(animate as boolean)
    target = m.scrollY
    if m.focusIdx >= 0 and m.focusIdx < m.items.Count() then
        it = m.items[m.focusIdx]
        vh = viewportHeight()
        if it.top < target + 8 then target = it.top - 8
        if it.top + it.height > target + vh - 40 then target = it.top + it.height - vh + 40
        if m.focusIdx = m.items.Count() - 1 then
            maxScroll = m.contentHeight - vh
            if target > maxScroll then target = maxScroll
        end if
    end if
    if target < 0 or m.focusIdx <= 0 then target = 0
    m.scrollY = target
    dest = [m.listX, m.listTop - target]
    if animate then
        m.scrollInterp.keyValue = [m.list.translation, dest]
        m.scrollAnim.control = "start"
    else
        m.list.translation = dest
    end if
    maybeLoadMore()
end sub

function lastVisibleIndex() as integer
    last = -1
    bottom = m.scrollY + viewportHeight()
    for i = 0 to m.items.Count() - 1
        if m.items[i].top < bottom then last = i
    end for
    return last
end function

' ---------- Keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then return false
    if key = "up" then
        if m.errorFocused then return true
        if m.focusIdx > 0 then
            m.focusIdx = m.focusIdx - 1
            applyFocus()
            scrollToFocus(true)
        else if m.errorCard.visible then
            m.errorFocused = true
            applyFocus()
        end if
        return true
    end if
    if key = "down" then
        if m.errorFocused then
            if m.items.Count() > 0 then
                m.errorFocused = false
                if m.focusIdx < 0 then m.focusIdx = 0
                applyFocus()
                scrollToFocus(true)
            end if
            return true
        end if
        if m.focusIdx < m.items.Count() - 1 then
            m.focusIdx = m.focusIdx + 1
            applyFocus()
            scrollToFocus(true)
        end if
        return true
    end if
    if key = "OK" then
        if m.errorFocused then
            refresh()
            return true
        end if
        if m.focusIdx < 0 or m.focusIdx >= m.items.Count() then return true
        it = m.items[m.focusIdx]
        if it.kind = "markAll" then
            markAllRead()
        else
            openRow(it.row)
        end if
        return true
    end if
    return key = "left" or key = "right"
end function
