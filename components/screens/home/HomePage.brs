' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.feed = m.top.findNode("feed")
    ' The feed's default empty-state copy in the interface language (field defaults are not translated).
    m.feed.emptyTitle = Tx("Nothing to watch yet")
    m.feed.emptyBody = Tx("Add media to your libraries or start watching to see it here.")
    m.feed.emptyAction = Tx("Refresh")
    m.menu = m.top.findNode("menu")
    m.feed.observeField("itemSelected", "onItemSelected")
    m.feed.observeField("itemOptions", "onItemOptions")
    m.feed.observeField("actionSelected", "load")
    m.feed.observeField("exploreSelected", "onExploreSelected")
    m.feed.observeField("artworkFailed", "onArtworkFailed")
    m.loadedAt = 0
    m.artReloadAt = 0
    m.menu.observeField("chosen", "onMenuChosen")
    m.menu.observeField("dismissed", "onMenuDismissed")
    m.loaded = false
    m.loading = false
    m.rows = []
    m.pendingSections = 0
    m.loadSeq = 0
    m.loadedRev = -1         ' DataRev_current() when the rows were last requested
    m.optionsTarget = invalid
    ' Home cache (HomeCache.brs): asked once per page, drawn only until the server answers.
    m.cacheAsked = false
    m.cacheTask = invalid
    m.cacheWriteTask = invalid
    m.cacheWritePending = invalid
    m.serverAnswered = false
    m.serverSections = []
    ' Watch state (Silo Android #1009): a read on every return, a queued read while one runs, and
    ' retries of a refresh that failed for a transient reason (HomeWatch_retryDelay).
    m.shownBefore = false
    m.refreshPending = false
    m.refreshRetries = 0
    m.retrying = false
    m.loadTransient = false
    m.loadFailStatus = 0
    m.loadRefresh = false
    m.prevSections = invalid
    m.prevServerSections = invalid
    m.retryTimer = CreateObject("roSGNode", "Timer")
    m.retryTimer.repeat = false
    m.retryTimer.observeField("fire", "onRefreshRetry")
    HomeLive_init()
    m.top.focusable = true
end sub

function libraryId() as string
    p = m.top.params
    if p = invalid then return ""
    return Str_orEmpty(p.libraryId)
end function

sub onPageHidden()
    m.feed.overlaysWatched = false
    watchCollectionInputs(false)
    if m.global.hasField("playbackStopsLanded") then m.global.unobserveFieldScoped("playbackStopsLanded")
    ' Nothing reads while the page is covered; the read on return covers what changed meanwhile.
    m.retryTimer.control = "stop"
    m.refreshPending = false
    HomeLive_hide()
end sub

sub onPageShown()
    m.feed.overlaysWatched = true
    watchCollectionInputs(true)
    if m.global.hasField("playbackStopsLanded") then m.global.observeFieldScoped("playbackStopsLanded", "onStopLanded")
    returning = m.shownBefore
    m.shownBefore = true
    ' Read again after playback or a watched / favorite / watchlist change made anywhere; a
    ' library's Recommended page follows too (DataRevision.brs).
    if DataRev_current() <> m.loadedRev then
        load()
    else if not m.loaded and not m.loading then
        load()
    else if m.loaded and not m.loading and Fresh_isStale(m.loadedAt, Time_nowSeconds()) then
        ' Signed artwork in an old answer may have expired (Freshness.brs): read again quietly.
        Fresh_log(pageName(), "stale", m.loadedAt)
        load()
    else if returning then
        ' Shown again (back from a detail page, the player, another tab): read quietly, since watch
        ' state may have changed on another device or in another app meanwhile (Silo Android #1009;
        ' Silo's Roku app re-reads on every return). The feed keeps the focused card.
        requestRefresh("return")
    end if
    HomeLive_show()
end sub

' A playback stop the server took after this page read (the player's stop timeout ran out, or a
' retry delivered it; Silo Android #954): the progress rows may be out of date.
sub onStopLanded()
    if not m.top.active then return
    requestRefresh("stop_landed")
end sub

' A quiet re-read for reason (return, stop_landed, changed, reconnect, poll, access_changed): at once,
' or after the read that is running when one is (Android's pending realtime refresh).
sub requestRefresh(reason as string)
    if not m.top.active then return
    if m.loading then
        if not m.refreshPending then Diag_log("[siku-home] watch state refresh queued reason=" + reason + " (a read is running)")
        m.refreshPending = true
        return
    end if
    m.retryTimer.control = "stop"
    Diag_log("[siku-home] watch state refresh reason=" + reason + " page=" + pageName())
    load()
end sub

sub onRefreshRetry()
    if not m.top.active then return
    if m.loading then
        m.refreshPending = true
        return
    end if
    m.retrying = true
    load()
end sub

' A refresh failed for a transient reason (HomeWatch_isTransient): try again after 1, 2 and 4 s
' while the page shows. Returns false once the retries are used up.
function scheduleRefreshRetry(what as string, status as integer) as boolean
    delay = HomeWatch_retryDelay(m.refreshRetries)
    if delay < 0 or not m.top.active then
        if delay < 0 then Diag_log("[siku-home] refresh retries used up (" + what + " status=" + status.ToStr() + "); keeping the drawn rows")
        m.refreshRetries = 0
        return false
    end if
    m.refreshRetries = m.refreshRetries + 1
    Diag_log("[siku-home] refresh retry " + m.refreshRetries.ToStr() + "/3 in " + delay.ToStr() + " s (" + what + " status=" + status.ToStr() + ")")
    m.retryTimer.duration = delay
    m.retryTimer.control = "start"
    return true
end function

' A read ended (drawn, kept or failed): open the events socket once Home has a server answer, and
' run a refresh that waited for this read unless a retry is already due.
sub loadSettled(retryScheduled as boolean)
    HomeLive_open()
    if not m.refreshPending then return
    m.refreshPending = false
    if retryScheduled or not m.top.active then return
    Diag_log("[siku-home] watch state refresh reason=queued page=" + pageName())
    load()
end sub

function pageName() as string
    if libraryId() = "" then return "home"
    return "library-home"
end function

' A card image failed: when the answer is old enough for its signatures to have run out, read it
' again (the feed keeps the focused card).
sub onArtworkFailed()
    now = Time_nowSeconds()
    if m.loading or not Fresh_artReloadDue(m.loadedAt, m.artReloadAt, now) then return
    m.artReloadAt = now
    Fresh_log(pageName(), "image-failed", m.loadedAt)
    load()
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
    if not m.retrying then m.refreshRetries = 0
    m.retrying = false
    m.loadTransient = false
    m.loadFailStatus = 0
    HomeLive_noteLoad()
    m.loadedRev = DataRev_current()
    ' A refresh keeps the rows already drawn (from the cache or the last answer) instead of a
    ' spinner; buildRows swaps them in place and the feed keeps the focused card.
    if m.rows.Count() = 0 then m.feed.state = "loading"
    if libraryId() = "" and not m.cacheAsked then
        m.cacheAsked = true
        readHomeCache()
    end if
    ' Artwork at drawn size (Artwork.brs): ask the server once whether it takes per-slot widths;
    ' and whether its section lists take item_limit (SectionRows.brs). Both reads run at once and
    ' Home waits for them (at most 3 s each) so its first read is already sized and capped.
    if m.capsPending = invalid then m.capsPending = 0
    if not Artwork_capsSettled() and m.artCapsAsked <> true then
        m.artCapsAsked = true
        m.capsPending = m.capsPending + 1
        Artwork_fetchCaps("onArtworkCaps")
    end if
    if not SectionRows_capsSettled() and m.rowCapsAsked <> true then
        m.rowCapsAsked = true
        m.rowCapsWaiting = true
        m.capsPending = m.capsPending + 1
        SectionRows_fetchCaps("onRowCaps")
        ' The request has its own 3 s timeout; this 20 s backstop on the render thread makes "slow =
        ' unsupported" hold even if the Task's wait overruns. brs-engine does not honour the Task's
        ' timeout, and a busy simulator took over 8 s to deliver even an instant answer, so the
        ' backstop is generous; on a Roku the 3 s request timeout decides.
        m.rowCapsTimer = CreateObject("roSGNode", "Timer")
        m.rowCapsTimer.duration = 20
        m.rowCapsTimer.repeat = false
        m.rowCapsTimer.observeField("fire", "onRowCapsTimeout")
        m.rowCapsTimer.control = "start"
    end if
    if m.capsPending > 0 then return
    requestSections()
end sub

' GET the section list, with item_limit only for a server that advertised it.
sub requestSections()
    q = artworkQuery()
    limit = SectionRows_activeLimit()
    if limit > 0 then q.item_limit = limit
    ctx = { seq: m.loadSeq, itemLimit: limit }
    lib = libraryId()
    if lib <> "" then
        Api_get("/api/v2/library/" + Str_urlEncode(lib) + "/sections", q, "onSections", ctx)
    else
        Api_get("/api/v2/home/sections", q, "onSections", ctx)
    end if
end sub

sub onArtworkCaps(event as object)
    Artwork_storeCaps(event)
    capsAnswered()
end sub

sub onRowCaps(event as object)
    if m.rowCapsWaiting <> true then
        ' Answered after the page stopped waiting: the session already counts it unsupported.
        Api_result(event)
        Diag_log("[siku-home] section item limit answer arrived late; ignored")
        return
    end if
    m.rowCapsWaiting = false
    if m.rowCapsTimer <> invalid then m.rowCapsTimer.control = "stop"
    SectionRows_storeCaps(event)
    capsAnswered()
end sub

sub onRowCapsTimeout()
    if m.rowCapsWaiting <> true then return
    m.rowCapsWaiting = false
    Diag_log("[siku-home] section item limit read timed out; sending none")
    SectionRows_setLimit(Str_orEmpty(m.global.session.serverUrl), 0)
    capsAnswered()
end sub

sub capsAnswered()
    m.capsPending = m.capsPending - 1
    if m.capsPending <= 0 then
        m.capsPending = 0
        load()
    end if
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
    ' A server that advertised item_limit but refuses it (422 unknown_parameter): read again
    ' once without it; SectionRows_markUnsupported keeps it off for the session.
    if not resp.ok and Int(Num_or(resp.context.itemLimit, 0)) > 0 and SectionRows_rejectsItemLimit(resp.status, resp.data) then
        Diag_log("[siku-home] item_limit rejected by the server; reading the rows again without it")
        SectionRows_markUnsupported()
        requestSections()
        return
    end if
    if not resp.ok then
        m.loading = false
        retried = false
        if m.rows.Count() > 0 then
            ' Keep what is drawn (the cached Home or the last answer); the next visit tries again.
            Diag_log(Diag_join(["[siku-home] refresh failed status=", resp.status, ", keeping the drawn rows"]))
            m.loaded = false
            ' No answer, 408, 429 or 5xx: try again quietly first (Silo Android #1009).
            if HomeWatch_isTransient(resp.status) then retried = scheduleRefreshRetry("list", Int(Num_or(resp.status, 0)))
            if not retried and m.top.active then m.global.toast = TxF("Couldn't refresh Home. {0}", [Api_errorText(resp)])
        else
            m.feed.errorText = Api_errorText(resp)
            m.feed.state = "error"
        end if
        Launch_ready("home")
        loadSettled(retried)
        return
    end if
    ' A refresh of rows drawn from an earlier server answer keeps that answer until this one is
    ' complete: a row whose own read fails for a transient reason must not drop out of view.
    m.loadRefresh = m.serverAnswered and m.rows.Count() > 0
    if m.loadRefresh then
        m.prevSections = m.sections
        m.prevServerSections = m.serverSections
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
        if CollRows_isRow(s) then
            ' A row of collections (silo-server #4410): its cards come in `collections`, all of them,
            ' never later; no section items read, no hide-watched or Movies / Series filter. Each
            ' card is read on its own (CollRows_cards); buildRows picks Home's and captions them.
            m.sections.Push({ section: s, items: CollRows_cards(s), rawItems: [] })
        else
            items = hideWatchedItems(s, Arr_or(s.items))
            total = Content_num(s.total_count)
            entry = { section: s, items: items, rawItems: Arr_or(s.items) }
            m.sections.Push(entry)
            if scope <> "" then
                if scopeSection(entry, m.sections.Count() - 1, scope) then m.pendingSections = m.pendingSections + 1
            else if entry.rawItems.Count() = 0 and total > 0 then
                ' Only a section the server sent without its cards is read on its own: a row that
                ' hide-watched emptied would come back just as watched (the server filters the same way).
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
        end if
    end for
    pumpRefills()
    if m.pendingSections = 0 then sectionsSettled()
end sub

' Every section's cards are in. A refresh in which a row's own read failed for a transient reason
' keeps the rows drawn (and the answer they came from) and tries again (Silo Android #1009: a partial
' refresh must not clobber a good Home); a row that is gone (404) drops out as before.
sub sectionsSettled()
    if m.loadTransient and m.loadRefresh and m.prevSections <> invalid then
        m.sections = m.prevSections
        m.serverSections = m.prevServerSections
        m.loading = false
        Diag_log("[siku-home] refresh incomplete: a row's read failed status=" + m.loadFailStatus.ToStr() + "; keeping the drawn rows")
        loadSettled(scheduleRefreshRetry("row", m.loadFailStatus))
        return
    end if
    buildRows()
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
    ' A row shows at most 20 cards (the rest are on its "Explore all" page), so a refill never
    ' looks for more than that, whatever the shelf's own limit.
    if target > SectionRows_max() then target = SectionRows_max()
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
    if m.pendingSections <= 0 then sectionsSettled()
end sub

sub onSectionItems(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid or ctx.seq <> m.loadSeq then return
    if resp.ok and resp.data <> invalid then
        idx = ctx.index
        if idx >= 0 and idx < m.sections.Count() then
            m.sections[idx].rawItems = Arr_or(resp.data.items)
            ' The row's own answer counts its list (the Explore all rule reads it).
            m.sections[idx].total = resp.data.total_count
            m.sections[idx].items = hideWatchedItems(m.sections[idx].section, m.sections[idx].rawItems)
        end if
    else if not resp.ok and HomeWatch_isTransient(resp.status) then
        m.loadTransient = true
        m.loadFailStatus = Int(Num_or(resp.status, 0))
    end if
    m.pendingSections = m.pendingSections - 1
    if m.pendingSections <= 0 then sectionsSettled()
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

sub buildRows(fromCache = false as boolean, redraw = false as boolean)
    rows = []
    m.collSig = collectionInputsSig()
    defaultStyle = "poster"
    if squareLibrary() then defaultStyle = "square"
    for each e in m.sections
        s = e.section
        ' At most 20 cards a row, whatever the server sent (an older server sends up to 100); a row
        ' of collections shows every card it has (CollRows_max) and no "Explore all": it has no page.
        ' A row of collections is drawn even when the server flags it featured: it is never a hero.
        isCollections = CollRows_isRow(s)
        if isCollections then
            cards = collectionRowCards(Str_orEmpty(s.id), e.items)
            if cards.Count() > 0 then rows.Push({ id: Str_orEmpty(s.id), title: TxKey(s.title_key, s.title_args, Str_orEmpty(s.title)), style: "poster", items: cards, exploreSectionId: "", exploreTitle: "" })
            items = []
        else
            items = SectionRows_capped(e.items)
        end if
        if items.Count() > 0 then
            st = LCase(Str_orEmpty(s.section_type))
            sid = Str_orEmpty(s.id)
            ' Every non-featured row ends with "Explore all", opening the section's full page, unless
            ' a Continue Watching or Next Up row shows its whole list (counted before the cut to 20).
            sent = Arr_or(e.rawItems).Count()
            explore = SectionRows_offersExploreAll(s, items.Count(), sent, e.total)
            if not explore and SectionRows_showsWholeList(s, sent, e.total) then Diag_log("[siku-home] explore all left out row=" + sid + ": the row shows its whole list")
            isProgress = st = "continue_watching" or st = "next_up" or sid = "continue_watching" or sid = "next_up"
            if isProgress then
                video = []
                audio = []
                for each c in items
                    if isAudiobook(c) then audio.Push(c) else video.Push(c)
                end for
                ' The section's page goes on the first row drawn from it (Continue Listening
                ' when the section holds only audiobooks).
                if video.Count() > 0 then rows.Push({ id: sid, title: TxKey(s.title_key, s.title_args, Str_orEmpty(s.title)), style: "landscape", items: video, exploreSectionId: exploreId(explore, sid), exploreTitle: TxKey(s.title_key, s.title_args, Str_orEmpty(s.title)) })
                if audio.Count() > 0 then rows.Push({ id: "continue_listening", title: Tx("Continue Listening"), style: "square", items: audio, exploreSectionId: exploreId(explore and video.Count() = 0, sid), exploreTitle: TxKey(s.title_key, s.title_args, Str_orEmpty(s.title)) })
            else
                rows.Push({ id: sid, title: TxKey(s.title_key, s.title_args, Str_orEmpty(s.title)), style: defaultStyle, items: items, exploreSectionId: exploreId(explore, sid), exploreTitle: TxKey(s.title_key, s.title_args, Str_orEmpty(s.title)) })
            end if
        end if
    end for
    m.rows = rows
    if fromCache then
        Diag_log(Diag_join(["[siku-home] cache drawn rows=", rows.Count()]))
    else if not redraw then
        m.loading = false
        m.loaded = true
        m.loadedAt = Time_nowSeconds()
        m.refreshRetries = 0
        m.prevSections = invalid
        m.prevServerSections = invalid
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
    closeStaleMenu(m.rows)
    if m.scopeIncomplete = true then
        m.scopeIncomplete = false
        m.global.toast = Tx("Some shelves could not be fully loaded for this media type. Retry or open Browse.")
    end if
    if not fromCache and not redraw then loadSettled(false)
end sub

'' ---------- Rows of collections (CollectionRows.brs) ----------

' The libraries this Roku shows the profile, as ShellScreen published them: { known, libs }.
function collectionLibraries() as object
    v = invalid
    if m.global.hasField("collectionLibraries") then v = m.global.collectionLibraries
    if v = invalid or Type(v) <> "roAssociativeArray" then return { known: false, libs: {} }
    if v.libs = invalid or Type(v.libs) <> "roAssociativeArray" then v.libs = {}
    return v
end function

function rememberedProfileNames() as dynamic
    if m.global.hasField("profileNames") then return m.global.profileNames
    return invalid
end function

' A row's cards as drawn: on Home only the server collections of libraries this Roku shows (none
' until those are known; personal ones always), then each card's caption: "by Name" for a
' collection another profile shared, else its count (none on a Movies / Series scoped page).
function collectionRowCards(sectionId as string, cards as object) as object
    shown = cards
    if libraryId() = "" then shown = CollRows_shownOnHome(cards, collectionLibraries())
    s = m.global.session
    out = CollRows_withCaptions(shown, CollRows_profileNames(s, rememberedProfileNames()), s.profileId, mediaScope() = "")
    Diag_log(CollRows_rowLog(sectionId, out, cards.Count() - shown.Count()))
    return out
end function

' What the rows of collections depend on besides the answer: the shown libraries and the names.
function collectionInputsSig() as string
    return FormatJson({ libs: collectionLibraries(), names: rememberedProfileNames() })
end function

function hasCollectionRows() as boolean
    if m.sections = invalid then return false
    for each e in m.sections
        if CollRows_isRow(e.section) then return true
    end for
    return false
end function

' Watched only while the page shows, so nothing on m.global holds a page let go.
sub watchCollectionInputs(watch as boolean)
    if not m.global.hasField("collectionLibraries") or not m.global.hasField("profileNames") then return
    if watch then
        m.global.observeFieldScoped("collectionLibraries", "onCollectionInputs")
        m.global.observeFieldScoped("profileNames", "onCollectionInputs")
        onCollectionInputs()
    else
        m.global.unobserveFieldScoped("collectionLibraries")
        m.global.unobserveFieldScoped("profileNames")
    end if
end sub

' The libraries became known (or changed) or the profile names arrived: redraw the drawn rows of
' collections from the answer already held (the feed keeps the focused card and its hero).
sub onCollectionInputs()
    if not m.loaded or m.loading or not hasCollectionRows() then return
    if collectionInputsSig() = m.collSig then return
    Diag_log("[siku-home] rows of collections redrawn: libraries or profile names changed")
    buildRows(false, true)
end sub

function exploreId(offered as boolean, sectionId as string) as string
    if offered then return sectionId
    return ""
end function

' "Explore all" on a row: the row's full page (TvSectionBrowseScreen), paged through
' GET /api/v2/catalog?source=section (scope home, or library with library_id). A mixed library's
' Movies or Series view keeps its filter on the page. Back returns to the same card (the feed's
' RowList keeps its focus while the page is covered).
sub onExploreSelected()
    sel = m.feed.exploreSelected
    if sel = invalid then return
    sid = Str_orEmpty(sel.sectionId)
    if sid = "" then return
    title = Str_orEmpty(sel.title)
    params = { section: "section", sectionId: sid, title: title }
    lib = libraryId()
    scope = "home"
    if lib <> "" then scope = "library"
    Diag_log(Diag_join(["[siku-home] explore all scope=", scope, " row=", Int(Num_or(sel.rowIndex, 0))]))
    if lib <> "" then
        p = m.top.params
        params.scope = "library"
        params.libraryId = lib
        params.libraryName = Str_orEmpty(p.libraryName)
        params.mode = Str_orEmpty(p.mode)
        params.mediaType = mediaScope()
    else
        params.scope = "home"
    end if
    Nav_push("LibraryScreen", params)
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
        Diag_log("[siku-home] cache dropped reason=session")
        return
    end if
    if m.serverAnswered then
        Diag_log("[siku-home] cache dropped reason=server-first")
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
    if CollRows_isCard(sel.card) then
        openCollection(sel.card)
        return
    end if
    CardActions_openDetail(sel.card)
end sub

' A row of collections' card opens the collection's page as Android TV opens it
' (CollRows_openParams): from Home a server collection in its own library and a personal one without
' one; on a library page that library (and its Movies / Series scope), a personal collection on an
' unscoped page without one.
sub openCollection(card as object)
    p = m.top.params
    libName = ""
    libMode = ""
    if p <> invalid then
        libName = Str_orEmpty(p.libraryName)
        libMode = Str_orEmpty(p.mode)
    end if
    params = CollRows_openParams(card, libraryId(), libName, libMode, mediaScope(), collectionLibraries().libs)
    scope = "home"
    if libraryId() <> "" then scope = "library"
    Diag_log("[siku-home] collection opened scope=" + scope + " kind=" + params.collectionKind + " library=" + Str_orEmpty(params.libraryId) + " type=" + Str_orEmpty(params.mediaType))
    Nav_push("LibraryScreen", params)
end sub

sub onItemOptions()
    opt = m.feed.itemOptions
    if opt = invalid or opt.card = invalid then return
    ' No card menu on a collection's card (the feed keeps * from sending one; a long OK still could).
    if CollRows_isCard(opt.card) then return
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
    patch = CardActions_perform(m.menu.chosen, target.card, Str_orEmpty(target.rowId), target)
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
    if not resp.ok then m.global.toast = TxF("Couldn't remove it: {0}", [Api_errorText(resp)])
    m.global.homeDirty = true
    if m.top.active and libraryId() = "" then load()
end sub

' A refresh replaced the card a menu left open was opened on (Silo Android #803): close the menu,
' since its actions belonged to the old card, and give the feed its focus back.
sub closeStaleMenu(rows as object)
    if not m.menu.visible or m.optionsTarget = invalid then return
    if CardActions_targetCurrent(rows, m.optionsTarget) then return
    Diag_log("[siku-cards] card menu closed: its card changed in a refresh")
    hadFocus = m.menu.isInFocusChain()
    m.optionsTarget = invalid
    m.menu.visible = false
    if hadFocus then m.feed.focusRequested = true
end sub

sub onMenuDismissed()
    m.feed.focusRequested = true
end sub

' A refused Mark as Watched / Unwatched (HomeCardActions.brs): put the card back. The feed skips
' the patch when another card now sits at that place (contentId).
sub CardActions_rollback(target as dynamic, patch as object)
    if target = invalid then return
    p = AA_copy(patch)
    p.rowIndex = target.rowIndex
    p.itemIndex = target.itemIndex
    m.feed.itemPatch = p
end sub
