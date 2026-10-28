' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.feed = m.top.findNode("feed")
    m.menu = m.top.findNode("menu")
    m.feed.observeField("itemSelected", "onItemSelected")
    m.feed.observeField("itemOptions", "onItemOptions")
    m.feed.observeField("actionSelected", "load")
    m.menu.observeField("chosen", "onMenuChosen")
    m.menu.observeField("dismissed", "onMenuDismissed")
    m.loaded = false
    m.loading = false
    m.rows = []
    m.pendingSections = 0
    m.loadSeq = 0
    m.optionsTarget = invalid
    ' Home cache (HomeCache.brs): asked once per page, drawn only until the server answers.
    m.cacheAsked = false
    m.cacheTask = invalid
    m.cacheWriteTask = invalid
    m.cacheWritePending = invalid
    m.serverAnswered = false
    m.serverSections = []
    m.top.focusable = true
end sub

function libraryId() as string
    p = m.top.params
    if p = invalid then return ""
    return Str_orEmpty(p.libraryId)
end function

sub onPageShown()
    if m.global.homeDirty = true and libraryId() = "" then
        m.global.homeDirty = false
        load()
    else if not m.loaded and not m.loading then
        load()
    end if
end sub

sub focusContent()
    if m.menu.visible then
        m.menu.setFocus(true)
    else
        m.feed.focusRequested = true
    end if
end sub

' ---------- Data ----------

sub load()
    m.loading = true
    m.loadSeq = m.loadSeq + 1
    ' A refresh keeps the rows already drawn (from the cache or the last answer) instead of a
    ' spinner; buildRows swaps them in place and the feed keeps the focused card.
    if m.rows.Count() = 0 then m.feed.state = "loading"
    if libraryId() = "" and not m.cacheAsked then
        m.cacheAsked = true
        readHomeCache()
    end if
    ' Artwork at drawn size (Artwork.brs): ask the server once whether it takes per-slot widths;
    ' Home waits for that answer (at most 3 s) so its first read is already sized.
    if not Artwork_capsSettled() and m.artCapsAsked <> true then
        m.artCapsAsked = true
        Artwork_fetchCaps("onArtworkCaps")
        return
    end if
    lib = libraryId()
    if lib <> "" then
        Api_get("/api/v2/library/" + Str_urlEncode(lib) + "/sections", artworkQuery(), "onSections", { seq: m.loadSeq })
    else
        Api_get("/api/v2/home/sections", artworkQuery(), "onSections", { seq: m.loadSeq })
    end if
end sub

sub onArtworkCaps(event as object)
    Artwork_storeCaps(event)
    load()
end sub

function artworkQuery() as object
    return Artwork_query({ image_size: "medium" }, "home", Theme_posterScale())
end function

' The Movies or Series view of a mixed library ("movie" | "series"), or "" for every other page.
function mediaScope() as string
    p = m.top.params
    if p = invalid or libraryId() = "" then return ""
    mt = LCase(Str_orEmpty(p.mediaType))
    if mt = "movie" or mt = "series" then return mt
    return ""
end function

sub onSections(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.loadSeq then return
    if not resp.ok then
        m.loading = false
        if m.rows.Count() > 0 then
            ' Keep what is drawn (the cached Home or the last answer); the next visit tries again.
            print "[siku-home] refresh failed status="; resp.status; ", keeping the drawn rows"
            m.loaded = false
            if m.top.active then m.global.toast = "Couldn't refresh Home. " + Api_errorText(resp)
        else
            m.feed.errorText = Api_errorText(resp)
            m.feed.state = "error"
        end if
        Launch_ready("home")
        return
    end if
    m.serverAnswered = true
    sections = []
    if resp.data <> invalid then sections = Arr_or(resp.data.sections)
    m.serverSections = sections
    ' Settings → General → Home Sections: this Roku's saved order and hidden rows (device-local,
    ' like Android TV's TvHomeSectionPreferences). Library pages keep the server order.
    if libraryId() = "" then sections = Settings_arrangeSections(sections)
    m.sections = []
    m.pendingSections = 0
    m.refillQueue = []
    m.refillActive = 0
    m.scopeIncomplete = false
    scope = mediaScope()
    for each s in sections
        sid = Str_orEmpty(s.id)
        items = hideWatchedItems(s, Arr_or(s.items))
        total = Content_num(s.total_count)
        entry = { section: s, items: items, rawItems: Arr_or(s.items) }
        m.sections.Push(entry)
        if scope <> "" then
            if scopeSection(entry, m.sections.Count() - 1, scope) then m.pendingSections = m.pendingSections + 1
        else if items.Count() = 0 and total > 0 then
            m.pendingSections = m.pendingSections + 1
            idx = m.sections.Count() - 1
            lib = libraryId()
            if lib <> "" then
                path = "/api/v2/library/" + Str_urlEncode(lib) + "/sections/" + Str_urlEncode(sid) + "/items"
            else
                path = "/api/v2/home/sections/" + Str_urlEncode(sid) + "/items"
            end if
            Api_get(path, artworkQuery(), "onSectionItems", { index: idx, seq: m.loadSeq })
        end if
    end for
    pumpRefills()
    if m.pendingSections = 0 then buildRows()
end sub

' ---------- Mixed-library scope (Android TV TvLibraryMediaScope, upstream #441) ----------
' A mixed library's Movies or Series view shows only that type on every shelf. Section sources
' reject a type overlay, so each shelf is filtered here and, when that leaves it short of its
' target, refilled from GET /api/v2/catalog?source=section in the shelf's own order. The inline
' total_count is not an exhaustion signal; only the catalog continuation says nothing remains.

function matchesScope(card as object, scope as string) as boolean
    t = LCase(Str_orEmpty(card.type).Trim())
    if scope = "movie" then return t = "movie" or t = "movies" or t = "film"
    if scope = "series" then return t = "series" or t = "show" or t = "shows" or t = "tv" or t = "episode"
    return true
end function

function scopedItems(items as object, scope as string) as object
    out = []
    for each c in items
        if Type(c) = "roAssociativeArray" and matchesScope(c, scope) then out.Push(c)
    end for
    return out
end function

function takeFirst(items as object, n as integer) as object
    if items.Count() <= n then return items
    out = []
    for i = 0 to n - 1
        out.Push(items[i])
    end for
    return out
end function

' Filters the entry's items to the scope; returns true when a refill was queued for it.
function scopeSection(entry as object, index as integer, scope as string) as boolean
    s = entry.section
    initial = scopedItems(entry.items, scope)
    target = Int(Content_num(s.item_limit))
    if target <= 0 then
        target = Arr_or(s.items).Count()
        if target < 20 then target = 20
    end if
    if target > 100 then target = 100
    entry.target = target
    entry.items = takeFirst(initial, target)
    if initial.Count() >= target then return false
    ' Featured shelves are not drawn on TV; nothing to refill.
    if s.featured = true then return false
    ' The section source pages the stored definition, not the profile-resolved one, so a customized
    ' or profile-added shelf keeps what it has rather than losing the profile's overrides.
    if s.customized = true or s.is_custom = true then
        m.scopeIncomplete = true
        return false
    end if
    entry.refill = { initial: initial, visible: [], seen: {}, pages: 0, cursor: "" }
    m.refillQueue.Push(index)
    return true
end function

' Up to three shelves refill at once; each one's pages stay sequential.
sub pumpRefills()
    while m.refillActive < 3 and m.refillQueue.Count() > 0
        idx = m.refillQueue.Shift()
        m.refillActive = m.refillActive + 1
        fetchRefill(idx)
    end while
end sub

sub fetchRefill(idx as integer)
    e = m.sections[idx]
    q = { source: "section", scope: "library", library_id: libraryId(), section_id: Str_orEmpty(e.section.id), limit: 100, image_size: "medium" }
    if e.refill.cursor <> "" then q.cursor = e.refill.cursor
    e.refill.pages = e.refill.pages + 1
    Api_get("/api/v2/catalog", q, "onRefillPage", { index: idx, seq: m.loadSeq })
end sub

sub onRefillPage(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid or ctx.seq <> m.loadSeq then return
    idx = ctx.index
    if idx < 0 or idx >= m.sections.Count() then return
    e = m.sections[idx]
    r = e.refill
    scope = mediaScope()
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then
        finishRefill(idx, true)
        return
    end if
    pageItems = Arr_or(resp.data.items)
    for each c in hideWatchedItems(e.section, scopedItems(pageItems, scope))
        cid = Str_orEmpty(c.content_id)
        if cid <> "" and not r.seen.DoesExist(cid) then
            r.seen[cid] = true
            r.visible.Push(c)
        end if
    end for
    pg = resp.data.page
    hasMore = pg <> invalid and pg.has_more = true
    if r.visible.Count() >= e.target or not hasMore then
        finishRefill(idx, false)
        return
    end if
    nextCursor = ""
    if pg <> invalid then nextCursor = Str_orEmpty(pg.next_cursor)
    if nextCursor = "" or nextCursor = r.cursor or pageItems.Count() = 0 or r.pages >= 8 then
        finishRefill(idx, true)
        return
    end if
    r.cursor = nextCursor
    fetchRefill(idx)
end sub

sub finishRefill(idx as integer, incomplete as boolean)
    e = m.sections[idx]
    r = e.refill
    items = r.visible
    if incomplete then
        ' Keep what was found, then the inline items it missed.
        m.scopeIncomplete = true
        for each c in r.initial
            cid = Str_orEmpty(c.content_id)
            if not r.seen.DoesExist(cid) then
                r.seen[cid] = true
                items.Push(c)
            end if
        end for
    end if
    e.items = takeFirst(items, e.target)
    e.Delete("refill")
    m.refillActive = m.refillActive - 1
    m.pendingSections = m.pendingSections - 1
    pumpRefills()
    if m.pendingSections <= 0 then buildRows()
end sub

sub onSectionItems(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid or ctx.seq <> m.loadSeq then return
    if resp.ok and resp.data <> invalid then
        idx = ctx.index
        if idx >= 0 and idx < m.sections.Count() then
            m.sections[idx].rawItems = Arr_or(resp.data.items)
            m.sections[idx].items = hideWatchedItems(m.sections[idx].section, m.sections[idx].rawItems)
        end if
    end if
    m.pendingSections = m.pendingSections - 1
    if m.pendingSections <= 0 then buildRows()
end sub

' home.hide_watched_items (a profile setting other Silo clients set): drop played items from the
' Home rows, except the progress rows, which are about what is being watched.
function hideWatchedItems(section as object, items as object) as object
    if not Settings_hideWatched() then return items
    st = LCase(Str_orEmpty(section.section_type))
    sid = LCase(Str_orEmpty(section.id))
    if st = "continue_watching" or st = "next_up" or sid = "continue_watching" or sid = "next_up" then return items
    out = []
    for each c in items
        played = false
        if c.user_state <> invalid and c.user_state.played = true then played = true
        if c.user_data <> invalid and c.user_data.played = true then played = true
        if not played then out.Push(c)
    end for
    return out
end function

function isAudiobook(card as object) as boolean
    t = LCase(Str_orEmpty(card.type))
    return t = "audiobook" or t = "audiobook_part" or t = "book"
end function

' Audiobook and music libraries show square covers; everywhere else audio items get their own square row.
function squareLibrary() as boolean
    p = m.top.params
    if p = invalid then return false
    libMode = LCase(Str_orEmpty(p.mode))
    return libMode = "audiobooks" or libMode = "music"
end function

sub buildRows(fromCache = false as boolean)
    rows = []
    defaultStyle = "poster"
    if squareLibrary() then defaultStyle = "square"
    for each e in m.sections
        s = e.section
        items = e.items
        if items.Count() > 0 then
            st = LCase(Str_orEmpty(s.section_type))
            sid = Str_orEmpty(s.id)
            isProgress = st = "continue_watching" or st = "next_up" or sid = "continue_watching" or sid = "next_up"
            if isProgress then
                video = []
                audio = []
                for each c in items
                    if isAudiobook(c) then audio.Push(c) else video.Push(c)
                end for
                if video.Count() > 0 then rows.Push({ id: sid, title: Str_orEmpty(s.title), style: "landscape", items: video })
                if audio.Count() > 0 then rows.Push({ id: "continue_listening", title: "Continue Listening", style: "square", items: audio })
            else
                rows.Push({ id: sid, title: Str_orEmpty(s.title), style: defaultStyle, items: items })
            end if
        end if
    end for
    m.rows = rows
    if fromCache then
        print "[siku-home] cache drawn rows="; rows.Count()
    else
        m.loading = false
        m.loaded = true
        if libraryId() = "" then writeHomeCache()
    end if
    m.feed.rows = rows
    if rows.Count() = 0 then
        m.feed.state = "empty"
    else
        m.feed.state = "ready"
    end if
    Launch_ready("home")
    if m.top.hasFocus() then m.feed.focusRequested = true
    if m.scopeIncomplete = true then
        m.scopeIncomplete = false
        m.global.toast = "Some shelves could not be fully loaded for this media type. Retry or open Browse."
    end if
end sub

' ---------- Home cache (HomeCache.brs, HomeCacheTask) ----------

sub readHomeCache()
    owner = HomeCache_ownerSource(m.global.session)
    if owner = "" then return
    task = CreateObject("roSGNode", "HomeCacheTask")
    task.job = { action: "read", ownerSource: owner }
    task.observeField("result", "onHomeCacheRead")
    m.cacheTask = task
    task.control = "RUN"
end sub

' Draws the cached Home only while the server has not answered, for the session that asked.
sub onHomeCacheRead(event as object)
    res = event.getData()
    m.cacheTask = invalid
    if res = invalid or Type(res) <> "roAssociativeArray" or res.status <> "hit" then return
    if Str_orEmpty(res.ownerSource) <> HomeCache_ownerSource(m.global.session) then
        print "[siku-home] cache dropped reason=session"
        return
    end if
    if m.serverAnswered then
        print "[siku-home] cache dropped reason=server-first"
        return
    end if
    ' This Roku's section order, hidden rows and hide-watched apply as they are now.
    m.sections = []
    for each s in Settings_arrangeSections(Arr_or(res.sections))
        m.sections.Push({ section: s, items: hideWatchedItems(s, Arr_or(s.items)) })
    end for
    buildRows(true)
end sub

' Saves the server's Home as it came (every section, in the server's order, unfiltered).
sub writeHomeCache()
    owner = HomeCache_ownerSource(m.global.session)
    if owner = "" then return
    fetched = {}
    for each e in m.sections
        fetched[Str_orEmpty(e.section.id)] = e.rawItems
    end for
    entries = []
    for each s in m.serverSections
        items = fetched[Str_orEmpty(s.id)]
        if items = invalid then items = Arr_or(s.items)
        entries.Push({ section: s, rawItems: items })
    end for
    job = { action: "write", ownerSource: owner, payload: HomeCache_payload(entries) }
    ' One write at a time (two share the temp file): a newer answer waits for the running write.
    if m.cacheWriteTask <> invalid then
        m.cacheWritePending = job
        return
    end if
    startHomeCacheWrite(job)
end sub

sub startHomeCacheWrite(job as object)
    task = CreateObject("roSGNode", "HomeCacheTask")
    task.job = job
    task.observeField("result", "onHomeCacheWritten")
    m.cacheWriteTask = task
    task.control = "RUN"
end sub

sub onHomeCacheWritten()
    m.cacheWriteTask = invalid
    job = m.cacheWritePending
    m.cacheWritePending = invalid
    if job <> invalid then startHomeCacheWrite(job)
end sub

' ---------- Selection ----------

sub onItemSelected()
    sel = m.feed.itemSelected
    if sel = invalid or sel.card = invalid then return
    CardActions_openDetail(sel.card)
end sub

sub onItemOptions()
    opt = m.feed.itemOptions
    if opt = invalid or opt.card = invalid then return
    m.optionsTarget = opt
    m.menu.title = Str_orEmpty(opt.card.title)
    m.menu.actions = CardActions_build(opt.card, Str_orEmpty(opt.rowId))
    m.menu.visible = true
    m.menu.setFocus(true)
end sub

sub onMenuChosen()
    target = m.optionsTarget
    m.feed.focusRequested = true
    if target = invalid then return
    patch = CardActions_perform(m.menu.chosen, target.card, Str_orEmpty(target.rowId))
    if patch <> invalid then
        patch.rowIndex = target.rowIndex
        patch.itemIndex = target.itemIndex
        m.feed.itemPatch = patch
    end if
end sub

' The server answered a Home dismissal (HomeCardActions.brs). Accepted: re-read Home from the
' server, as Mark as Watched does (the server dropped the whole show); a failed re-read keeps the
' local removal. Refused: say so and re-read, which brings the card back.
sub CardActions_onDismissed(event as object)
    resp = Api_result(event)
    if not resp.ok then m.global.toast = "Couldn't remove it: " + Api_errorText(resp)
    m.global.homeDirty = true
    if m.top.active and libraryId() = "" then
        m.global.homeDirty = false
        load()
    end if
end sub

sub onMenuDismissed()
    m.feed.focusRequested = true
end sub
