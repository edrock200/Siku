' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.titleLabel = m.top.findNode("titleLabel")
    m.countLabel = m.top.findNode("countLabel")
    m.controls = m.top.findNode("controls")
    m.sortPill = m.top.findNode("sortPill")
    m.filterPill = m.top.findNode("filterPill")
    m.clearPill = m.top.findNode("clearPill")
    m.shufflePill = m.top.findNode("shufflePill")
    m.grid = m.top.findNode("grid")
    ' Columns follow the poster-size preference; cells fill the 1780 px content width.
    cols = Theme_gridColumns()
    cellW = Int((1780 - (cols - 1) * 40) / cols)
    m.grid.numColumns = cols
    m.grid.itemSize = [cellW, Int(cellW * 3 / 2) + 90]
    m.spinner = m.top.findNode("spinner")
    m.status = m.top.findNode("status")
    m.statusTitle = m.top.findNode("statusTitle")
    m.statusBody = m.top.findNode("statusBody")
    m.retryBtn = m.top.findNode("retryBtn")
    m.sortPanel = m.top.findNode("sortPanel")
    m.filterPanel = m.top.findNode("filterPanel")
    m.filterFly = m.top.findNode("filterFly")
    m.menu = m.top.findNode("menu")

    m.grid.observeField("itemFocused", "onGridFocused")
    m.grid.observeField("itemSelected", "onGridSelected")
    m.sortPill.observeField("buttonSelected", "openSortPanel")
    m.filterPill.observeField("buttonSelected", "openFilterPanel")
    m.clearPill.observeField("buttonSelected", "clearFilters")
    m.shufflePill.observeField("buttonSelected", "shuffle")
    m.retryBtn.observeField("buttonSelected", "reload")
    m.sortPanel.observeField("rowSelected", "onSortChosen")
    m.filterPanel.observeField("rowSelected", "onFilterMainChosen")
    m.filterPanel.observeField("rowFocused", "onFilterMainFocused")
    m.filterPanel.observeField("exitRight", "enterFilterFly")
    m.filterFly.observeField("rowSelected", "onFilterValueChosen")
    m.filterFly.observeField("exitLeft", "leaveFilterFly")
    m.menu.observeField("chosen", "onMenuChosen")
    m.menu.observeField("dismissed", "onMenuDismissed")
    m.top.observeField("params", "onParams")

    m.sortOptions = [
        { id: "title", label: "Title", defaultDesc: false },
        { id: "added_at", label: "Date Added", defaultDesc: true },
        { id: "release_date", label: "Release Date", defaultDesc: true },
        { id: "year", label: "Year", defaultDesc: true },
        { id: "rating_imdb", label: "Rating", defaultDesc: true },
        { id: "runtime", label: "Runtime", defaultDesc: true }
    ]
    m.watchStatusOptions = [
        { id: "unwatched", label: "Unwatched" },
        { id: "in_progress", label: "In Progress" },
        { id: "watched", label: "Watched" },
        { id: "favorited", label: "Favorited" },
        { id: "watchlist", label: "Watchlist" }
    ]
    m.sortField = "title"
    m.sortDesc = false
    m.genre = ""
    m.watchStatus = ""
    m.facets = invalid
    m.filterFacet = ""
    m.cards = []
    m.nextCursor = ""
    m.hasMore = false
    m.loading = false
    m.loadingMore = false
    m.loaded = false
    m.requestSeq = 0
    m.drill = invalid        ' {collectionId, title} while showing a collection's items from the Collections list
    m.optionsTarget = invalid
    m.top.focusable = true
    m.mode = "browse"
end sub

' ---------- Params / variants ----------

function prm(key as string, default = "" as dynamic) as dynamic
    p = m.top.params
    if p = invalid then return default
    v = p[key]
    if v = invalid then return default
    return v
end function

sub onParams()
    m.mode = LCase(Str_orEmpty(prm("section", "browse")))
    if m.mode = "" then m.mode = "browse"
    if m.mode = "favorites" or m.mode = "watchlist" then m.sortField = ""
    if m.mode = "collection" then m.sortField = ""
    layoutPage()
    m.loaded = false
end sub

function currentTitle() as string
    t = Str_orEmpty(prm("title"))
    if t <> "" then return t
    if m.drill <> invalid then return Str_orEmpty(m.drill.title)
    if m.mode = "favorites" then return "Favorites"
    if m.mode = "watchlist" then return "Watchlist"
    if m.mode = "history" then return "Watch History"
    if m.mode = "collection" then return Str_orEmpty(prm("collectionTitle"))
    if m.mode = "person" then return Str_orEmpty(prm("personName"))
    name = Str_orEmpty(prm("libraryName"))
    if m.mode = "collections" then
        if name <> "" then return name + " · Collections"
        return "Collections"
    end if
    return name
end function

function showsControls() as boolean
    if m.drill <> invalid then return false
    return m.mode = "browse" or m.mode = "favorites" or m.mode = "watchlist" or m.mode = "collection" or m.mode = "person" or m.mode = "section"
end function

sub layoutPage()
    m.titleLabel.text = currentTitle()
    hosted = prm("hostedInShell", true) <> false
    if hosted then
        titleY = 128
    else
        titleY = 80
    end if
    m.titleLabel.translation = [80, titleY]
    m.titleLabel.width = 0
    tw = Int(m.titleLabel.boundingRect().width)
    m.titleLabel.width = 1400
    m.countLabel.translation = [80 + tw + 20, titleY + 14]
    hasControls = showsControls()
    m.controls.visible = hasControls
    if hasControls then
        m.controls.translation = [80, titleY + 68]
        gridY = titleY + 68 + 56 + 32
        m.filterPill.visible = m.mode = "browse"
        m.shufflePill.visible = m.mode = "browse" or m.mode = "collection"
        layoutPills()
    else
        gridY = titleY + 88
    end if
    m.grid.translation = [70, gridY]
    updateSortPill()
end sub

sub layoutPills()
    x = 0
    for each pill in [m.sortPill, m.filterPill, m.clearPill, m.shufflePill]
        if pill.visible then
            pill.translation = [x, 0]
            x = x + pill.width + 16
        end if
    end for
end sub

function visiblePills() as object
    out = []
    for each pill in [m.sortPill, m.filterPill, m.clearPill, m.shufflePill]
        if pill.visible then out.Push(pill)
    end for
    return out
end function

' ---------- Lifecycle ----------

sub onPageShown()
    if not m.loaded and not m.loading then reload()
end sub

sub focusContent()
    if m.menu.visible then
        m.menu.setFocus(true)
    else if m.sortPanel.visible then
        m.sortPanel.setFocus(true)
    else if m.filterFly.hasFocus() or (m.filterPanel.visible and not m.filterPanel.hasFocus() and m.filterFly.visible and m.flyActive = true) then
        m.filterFly.setFocus(true)
    else if m.filterPanel.visible then
        m.filterPanel.setFocus(true)
    else if m.grid.visible and m.cards.Count() > 0 then
        m.grid.setFocus(true)
    else if m.retryBtn.visible then
        m.retryBtn.setFocus(true)
    else if m.controls.visible then
        m.sortPill.setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

' ---------- Loading ----------

sub reload()
    m.cards = []
    m.nextCursor = ""
    m.hasMore = false
    m.grid.content = invalid
    m.grid.visible = false
    m.status.visible = false
    m.countLabel.visible = false
    m.loaded = false
    m.loading = true
    m.spinner.visible = true
    m.requestSeq = m.requestSeq + 1
    if m.mode = "collections" and m.drill = invalid then
        Api_get("/api/v2/library/" + Str_urlEncode(Str_orEmpty(prm("libraryId"))) + "/collections", invalid, "onCollections", { seq: m.requestSeq })
    else
        requestPage("")
    end if
end sub

function sortWire() as string
    if m.sortField = "" then return ""
    if m.sortDesc then return "-" + m.sortField
    return m.sortField
end function

function filtersActive() as boolean
    return m.genre <> "" or m.watchStatus <> ""
end function

' Sends page 1 (cursor "") or the next page. Same query every time, only the cursor changes.
sub requestPage(cursor as string)
    ctx = { seq: m.requestSeq, cursor: cursor }
    if m.mode = "history" then
        q = { limit: 40, image_size: "medium" }
        if cursor <> "" then q.cursor = cursor
        Api_get("/api/v2/history", q, "onPage", ctx)
        return
    end if
    q = { limit: 60, image_size: "medium" }
    if m.drill <> invalid then
        q.source = "library_collection"
        q.collection_id = m.drill.collectionId
        q.library_id = Str_orEmpty(prm("libraryId"))
    else if m.mode = "favorites" or m.mode = "watchlist" then
        q.source = m.mode
    else if m.mode = "collection" then
        q.source = "library_collection"
        q.collection_id = Str_orEmpty(prm("collectionId"))
        if not Str_isEmpty(prm("libraryId")) then q.library_id = prm("libraryId")
    else if m.mode = "person" then
        q.source = "person"
        q.person_id = Str_orEmpty(prm("personId"))
        if m.sortField = "title" and not m.sortDesc and m.cards.Count() = 0 and cursor = "" and m.userSorted <> true then
            m.sortField = "year"
            m.sortDesc = true
            updateSortPill()
        end if
    else if m.mode = "section" then
        q.source = "section"
        q.section_id = Str_orEmpty(prm("sectionId"))
        q.scope = Str_orEmpty(prm("scope", "home"))
        if not Str_isEmpty(prm("libraryId")) then q.library_id = prm("libraryId")
    else
        src = Str_orEmpty(prm("source"))
        if src = "" then src = "query"
        q.source = src
        if not Str_isEmpty(prm("libraryId")) then q.library_id = prm("libraryId")
    end if
    mt = Str_orEmpty(prm("mediaType"))
    if mt <> "" then q["type"] = mt
    if not Str_isEmpty(prm("query")) then q.q = prm("query")
    sw = sortWire()
    if sw <> "" then q.sort = sw
    if cursor <> "" then q.cursor = cursor

    if filtersActive() then
        groups = []
        if m.genre <> "" then groups.Push({ match: "any", rules: [{ field: "genre", op: "contains", value: m.genre }] })
        if m.watchStatus <> "" then
            ws = m.watchStatus
            if ws = "unwatched" then
                rule = { field: "watched", op: "is", value: "false" }
            else if ws = "watched" then
                rule = { field: "watched", op: "is", value: "true" }
            else if ws = "in_progress" then
                rule = { field: "in_progress", op: "is", value: "true" }
            else if ws = "favorited" then
                rule = { field: "favorited", op: "is", value: "true" }
            else
                rule = { field: "in_watchlist", op: "is", value: "true" }
            end if
            groups.Push({ match: "all", rules: [rule] })
        end if
        body = q
        body.groups = groups
        body.Delete("image_size")
        Api_call({ method: "POST", path: "/api/v2/catalog/query", query: { image_size: "medium" }, body: body, context: ctx }, "onPage")
    else
        Api_get("/api/v2/catalog", q, "onPage", ctx)
    end if
end sub

sub onPage(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid or ctx.seq <> m.requestSeq then return
    isMore = ctx.cursor <> ""
    m.loading = false
    m.loadingMore = false
    m.spinner.visible = false
    if not resp.ok then
        if isMore then
            m.global.toast = "Couldn't load more. " + Api_errorText(resp)
            m.hasMore = true
        else
            showError(Api_errorText(resp))
        end if
        return
    end if
    data = resp.data
    items = []
    if data <> invalid then items = Arr_or(data.items)
    page = invalid
    if data <> invalid then page = data.page
    m.hasMore = false
    m.nextCursor = ""
    if page <> invalid then
        if page.has_more = true and not Str_isEmpty(page.next_cursor) then
            m.hasMore = true
            m.nextCursor = page.next_cursor
        end if
    end if
    if data <> invalid and data.total <> invalid and not isMore then
        n = Int(data.total)
        txt = n.ToStr() + " titles"
        if n = 1 then txt = "1 title"
        if data.total_exact = false then txt = "About " + txt
        m.countLabel.text = txt
        m.countLabel.visible = n > 0
    end if
    if isMore then
        appendCards(items)
    else
        m.loaded = true
        setCards(items)
    end if
end sub

sub setCards(items as object)
    m.cards = items
    if items.Count() = 0 then
        showEmpty()
        return
    end if
    m.status.visible = false
    m.grid.content = Content_grid(items, "poster")
    m.grid.visible = true
    if m.top.hasFocus() then m.grid.setFocus(true)
end sub

sub appendCards(items as object)
    if m.grid.content = invalid then
        setCards(items)
        return
    end if
    m.cards.Append(items)
    Content_appendCards(m.grid.content, items, "poster")
end sub

sub onCollections(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid or ctx.seq <> m.requestSeq then return
    m.loading = false
    m.spinner.visible = false
    if not resp.ok then
        showError(Api_errorText(resp))
        return
    end if
    data = resp.data
    seen = {}
    cards = []
    lists = []
    if data <> invalid then
        lists.Push(Arr_or(data.collections))
        for each g in Arr_or(data.groups)
            lists.Push(Arr_or(g.collections))
        end for
        if data.ungrouped <> invalid then lists.Push(Arr_or(data.ungrouped.collections))
    end if
    for each lst in lists
        for each c in lst
            cid = Str_orEmpty(c.id)
            if cid <> "" and not seen.DoesExist(cid) then
                seen[cid] = true
                cards.Push({ content_id: "collection:" + cid, collection_id: cid, type: "collection", title: Str_orEmpty(c.title), poster_url: c.poster_url, item_count: c.item_count })
            end if
        end for
    end for
    m.loaded = true
    m.cards = cards
    if cards.Count() = 0 then
        showEmpty()
        return
    end if
    m.status.visible = false
    root = CreateObject("roSGNode", "ContentNode")
    for each c in cards
        node = Content_cardNode(c, "poster")
        if c.item_count <> invalid then
            n = Int(c.item_count)
            if n = 1 then node.subtitle = "1 item" else node.subtitle = n.ToStr() + " items"
        end if
        root.appendChild(node)
    end for
    m.grid.content = root
    m.grid.visible = true
    if m.top.hasFocus() then m.grid.setFocus(true)
end sub

sub showError(msg as string)
    m.grid.visible = false
    m.status.visible = true
    m.statusTitle.text = "Something went wrong"
    m.statusBody.text = msg
    m.retryBtn.visible = true
    m.retryBtn.translation = [(1920 - m.retryBtn.width) / 2, 600]
    if m.top.hasFocus() or m.grid.hasFocus() then m.retryBtn.setFocus(true)
end sub

sub showEmpty()
    m.grid.visible = false
    m.status.visible = true
    m.retryBtn.visible = false
    body = ""
    if m.mode = "favorites" then
        title = "No favorites yet"
        body = "Titles you favorite will show up here."
    else if m.mode = "watchlist" then
        title = "Your watchlist is empty"
        body = "Add titles to your watchlist to find them here."
    else if m.mode = "history" then
        title = "No watch history yet"
        body = "Things you watch will show up here."
    else if m.mode = "collections" and m.drill = invalid then
        title = "No collections"
        body = "This library has no collections yet."
    else if filtersActive() then
        title = "No titles match"
        body = "Try clearing a filter."
    else
        title = "No titles found"
        body = "This library is empty."
    end if
    m.statusTitle.text = title
    m.statusBody.text = body
    if m.top.hasFocus() or m.grid.hasFocus() then
        if m.controls.visible then m.sortPill.setFocus(true) else m.top.setFocus(true)
    end if
end sub

' ---------- Grid events ----------

sub onGridFocused()
    idx = m.grid.itemFocused
    if m.hasMore and not m.loadingMore and not m.loading and idx >= m.cards.Count() - 12 then
        m.loadingMore = true
        requestPage(m.nextCursor)
    end if
end sub

sub onGridSelected()
    idx = m.grid.itemSelected
    if idx < 0 or idx >= m.cards.Count() then return
    card = m.cards[idx]
    if m.mode = "collections" and m.drill = invalid then
        m.drill = { collectionId: Str_orEmpty(card.collection_id), title: Str_orEmpty(card.title) }
        m.collectionsCards = m.cards
        m.collectionsContent = m.grid.content
        m.collectionsIndex = idx
        layoutPage()
        reload()
        m.top.setFocus(true)
        return
    end if
    CardActions_openDetail(card)
end sub

' Back from a collection's items to the Collections list.
function leaveDrill() as boolean
    if m.drill = invalid then return false
    m.drill = invalid
    m.requestSeq = m.requestSeq + 1
    m.loading = false
    m.loadingMore = false
    m.spinner.visible = false
    m.status.visible = false
    layoutPage()
    m.cards = m.collectionsCards
    m.grid.content = m.collectionsContent
    m.grid.visible = true
    m.hasMore = false
    m.loaded = true
    m.grid.setFocus(true)
    if m.collectionsIndex <> invalid then m.grid.jumpToItem = m.collectionsIndex
    return true
end function

' ---------- Sort ----------

function sortOption(id as string) as dynamic
    for each o in m.sortOptions
        if o.id = id then return o
    end for
    return invalid
end function

function directionLabel() as string
    f = m.sortField
    if f = "" then return "Default"
    if f = "title" then
        if m.sortDesc then return "Z–A"
        return "A–Z"
    else if f = "runtime" then
        if m.sortDesc then return "Longest"
        return "Shortest"
    else if f = "rating_imdb" then
        if m.sortDesc then return "Highest"
        return "Lowest"
    end if
    if m.sortDesc then return "Newest"
    return "Oldest"
end function

sub updateSortPill()
    o = sortOption(m.sortField)
    if o = invalid then
        lbl = "Recently Saved"
        if m.mode = "collection" or m.drill <> invalid then lbl = "Collection Order"
    else
        lbl = o.label
    end if
    m.sortPill.text = "Sort · " + lbl + " · " + directionLabel()
    m.clearPill.visible = filtersActive() and m.mode = "browse"
    if filtersActive() then
        n = 0
        if m.genre <> "" then n = n + 1
        if m.watchStatus <> "" then n = n + 1
        m.filterPill.text = "Filter · " + n.ToStr()
        m.filterPill.selectedState = true
    else
        m.filterPill.text = "Filter"
        m.filterPill.selectedState = false
    end if
    layoutPills()
end sub

sub openSortPanel()
    rows = []
    personal = m.mode = "favorites" or m.mode = "watchlist"
    collectionLike = m.mode = "collection" or m.drill <> invalid
    if personal then rows.Push({ id: "__list", label: "Recently Saved", trailing: trailingFor("") })
    if collectionLike then rows.Push({ id: "__list", label: "Collection Order", trailing: trailingFor("") })
    for each o in m.sortOptions
        rows.Push({ id: o.id, label: o.label, trailing: trailingFor(o.id), sub: subFor(o.id) })
    end for
    m.sortPanel.header = "SORT BY"
    m.sortPanel.footer = "Press again to flip the direction · Menu closes"
    m.sortPanel.rows = rows
    m.sortPanel.translation = [80 + m.sortPill.translation[0], m.controls.translation[1] + 64]
    m.sortPanel.visible = true
    m.sortPanel.setFocus(true)
end sub

function trailingFor(id as string) as string
    if id = m.sortField then return "check"
    return ""
end function

function subFor(id as string) as string
    if id = m.sortField then return directionLabel()
    return ""
end function

sub onSortChosen()
    id = m.sortPanel.rowSelected
    m.userSorted = true
    if id = "__list" then
        m.sortField = ""
        m.sortDesc = false
    else if id = m.sortField then
        m.sortDesc = not m.sortDesc
    else
        m.sortField = id
        o = sortOption(id)
        m.sortDesc = o <> invalid and o.defaultDesc = true
    end if
    closePanels()
    updateSortPill()
    reload()
end sub

' ---------- Filter ----------

sub openFilterPanel()
    if m.facets = invalid and m.facetsLoading <> true then
        m.facetsLoading = true
        Api_get("/api/v2/catalog/filters", { library_id: Str_orEmpty(prm("libraryId")), skip_technical: "true" }, "onFacets")
    end if
    rows = [
        { id: "genre", label: "Genre", trailing: "chevron", sub: m.genre },
        { id: "status", label: "Watch Status", trailing: "chevron", sub: watchStatusLabel() },
        { id: "-" },
        { id: "reset", label: "Reset filters" },
        { id: "done", label: "Done" }
    ]
    m.filterPanel.header = "FILTER BY"
    m.filterPanel.footer = "→ picks a value · Menu closes"
    m.filterPanel.rows = rows
    m.filterPanel.focusIndex = 0
    m.filterPanel.translation = [80 + m.filterPill.translation[0], m.controls.translation[1] + 64]
    m.filterPanel.visible = true
    m.filterFly.visible = false
    m.flyActive = false
    m.filterPanel.setFocus(true)
    showFlyFor("genre")
end sub

function watchStatusLabel() as string
    for each o in m.watchStatusOptions
        if o.id = m.watchStatus then return o.label
    end for
    return ""
end function

sub onFacets(event as object)
    resp = Api_result(event)
    m.facetsLoading = false
    if resp.ok and resp.data <> invalid then
        m.facets = resp.data
    else
        m.facets = { genres: [] }
    end if
    if m.filterPanel.visible and m.filterFacet = "genre" then showFlyFor("genre")
end sub

function genreValues() as object
    out = []
    if m.facets = invalid then return out
    for each g in Arr_or(m.facets.genres)
        if Type(g) = "roString" or Type(g) = "String" then
            out.Push(g)
        else if g <> invalid then
            v = Str_orEmpty(g.value)
            if v = "" then v = Str_orEmpty(g.name)
            if v = "" then v = Str_orEmpty(g.label)
            if v <> "" then out.Push(v)
        end if
    end for
    return out
end function

sub onFilterMainFocused()
    i = m.filterPanel.rowFocused
    rows = m.filterPanel.rows
    if i < 0 or i >= rows.Count() then return
    id = Str_orEmpty(rows[i].id)
    if id = "genre" or id = "status" then
        showFlyFor(id)
    else
        m.filterFly.visible = false
    end if
end sub

sub showFlyFor(facet as string)
    m.filterFacet = facet
    rows = []
    if facet = "genre" then
        vals = genreValues()
        if vals.Count() = 0 then
            if m.facetsLoading = true then
                rows.Push({ id: "", label: "Loading…" })
            else
                rows.Push({ id: "", label: "No genres" })
            end if
        else
            rows.Push({ id: "__any", label: "Any genre", trailing: checkIf(m.genre = "") })
            for each v in vals
                rows.Push({ id: v, label: v, trailing: checkIf(m.genre = v) })
            end for
        end if
        m.filterFly.header = "GENRE"
    else
        rows.Push({ id: "__any", label: "Any", trailing: checkIf(m.watchStatus = "") })
        for each o in m.watchStatusOptions
            rows.Push({ id: o.id, label: o.label, trailing: checkIf(m.watchStatus = o.id) })
        end for
        m.filterFly.header = "WATCH STATUS"
    end if
    m.filterFly.footer = ""
    m.filterFly.rows = rows
    m.filterFly.focusIndex = 0
    m.filterFly.translation = [m.filterPanel.translation[0] + 460 + 12, m.filterPanel.translation[1]]
    m.filterFly.visible = true
end sub

function checkIf(cond as boolean) as string
    if cond then return "check"
    return ""
end function

sub onFilterMainChosen()
    id = m.filterPanel.rowSelected
    if id = "genre" or id = "status" then
        enterFilterFly()
    else if id = "reset" then
        m.genre = ""
        m.watchStatus = ""
        closePanels()
        updateSortPill()
        reload()
    else
        closePanels()
    end if
end sub

sub enterFilterFly()
    if not m.filterFly.visible then return
    m.flyActive = true
    m.filterFly.setFocus(true)
end sub

sub leaveFilterFly()
    m.flyActive = false
    m.filterPanel.setFocus(true)
end sub

sub onFilterValueChosen()
    id = m.filterFly.rowSelected
    if id = "" then return
    if id = "__any" then id = ""
    if m.filterFacet = "genre" then
        m.genre = id
    else
        m.watchStatus = id
    end if
    closePanels()
    updateSortPill()
    reload()
end sub

sub clearFilters()
    m.genre = ""
    m.watchStatus = ""
    updateSortPill()
    m.sortPill.setFocus(true)
    reload()
end sub

sub closePanels()
    wasSort = m.sortPanel.visible
    m.sortPanel.visible = false
    m.filterPanel.visible = false
    m.filterFly.visible = false
    m.flyActive = false
    if wasSort then m.sortPill.setFocus(true) else m.filterPill.setFocus(true)
end sub

function panelsOpen() as boolean
    return m.sortPanel.visible or m.filterPanel.visible
end function

' ---------- Shuffle ----------

sub shuffle()
    q = { source: "query", sort: "random", limit: 1 }
    if m.drill <> invalid then
        q.source = "library_collection"
        q.collection_id = m.drill.collectionId
    else if m.mode = "collection" then
        q.source = "library_collection"
        q.collection_id = Str_orEmpty(prm("collectionId"))
    end if
    if not Str_isEmpty(prm("libraryId")) then q.library_id = prm("libraryId")
    mt = Str_orEmpty(prm("mediaType"))
    if mt <> "" then q["type"] = mt
    m.global.toast = "Picking something…"
    Api_get("/api/v2/catalog", q, "onShuffle")
end sub

sub onShuffle(event as object)
    resp = Api_result(event)
    if not resp.ok or resp.data = invalid then
        m.global.toast = Api_errorText(resp)
        return
    end if
    items = Arr_or(resp.data.items)
    if items.Count() = 0 then
        m.global.toast = "Nothing to shuffle"
        return
    end if
    card = items[0]
    playId = Str_orEmpty(card.play_content_id)
    if playId = "" then playId = Str_orEmpty(card.content_id)
    Nav_play({ itemId: playId, title: Str_orEmpty(card.title) })
end sub

' ---------- Options menu ----------

sub openOptions()
    idx = m.grid.itemFocused
    if idx < 0 or idx >= m.cards.Count() then return
    card = m.cards[idx]
    if LCase(Str_orEmpty(card.type)) = "collection" then return
    m.optionsTarget = { index: idx, card: card }
    m.menu.title = Str_orEmpty(card.title)
    m.menu.actions = CardActions_build(card, "")
    m.menu.visible = true
    m.menu.setFocus(true)
end sub

sub onMenuChosen()
    target = m.optionsTarget
    m.grid.setFocus(true)
    if target = invalid then return
    patch = CardActions_perform(m.menu.chosen, target.card, "")
    if patch = invalid then return
    node = m.grid.content.getChild(target.index)
    if node = invalid then return
    raw = AA_copy(node.raw)
    us = AA_copy(raw.user_state)
    if patch.watched <> invalid then
        node.watched = patch.watched
        us.played = patch.watched
    end if
    if patch.favorite <> invalid then us.is_favorite = patch.favorite
    if patch.inWatchlist <> invalid then us.in_watchlist = patch.inWatchlist
    raw.user_state = us
    node.raw = raw
    m.cards[target.index] = raw
end sub

sub onMenuDismissed()
    m.grid.setFocus(true)
end sub

' ---------- Keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if panelsOpen() then
        if key = "back" then
            closePanels()
            return true
        end if
        return true
    end if
    if key = "back" then
        return leaveDrill()
    end if
    ' Controls row.
    pills = visiblePills()
    for i = 0 to pills.Count() - 1
        if pills[i].hasFocus() then
            if key = "left" then
                if i > 0 then pills[i - 1].setFocus(true)
                return true
            else if key = "right" then
                if i < pills.Count() - 1 then pills[i + 1].setFocus(true)
                return true
            else if key = "down" then
                if m.grid.visible and m.cards.Count() > 0 then
                    m.grid.setFocus(true)
                else if m.retryBtn.visible then
                    m.retryBtn.setFocus(true)
                end if
                return true
            end if
            return false
        end if
    end for
    if m.grid.hasFocus() then
        if key = "up" then
            if m.controls.visible then
                m.sortPill.setFocus(true)
                return true
            end if
            return false
        else if key = "options" then
            openOptions()
            return true
        end if
    end if
    if m.retryBtn.hasFocus() and key = "up" and m.controls.visible then
        m.sortPill.setFocus(true)
        return true
    end if
    return false
end function
