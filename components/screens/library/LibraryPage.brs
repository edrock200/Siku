' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.titleLabel = m.top.findNode("titleLabel")
    m.countLabel = m.top.findNode("countLabel")
    m.controls = m.top.findNode("controls")
    m.backPill = m.top.findNode("backPill")
    m.sortPill = m.top.findNode("sortPill")
    m.filterPill = m.top.findNode("filterPill")
    m.clearPill = m.top.findNode("clearPill")
    m.shufflePill = m.top.findNode("shufflePill")
    m.chips = m.top.findNode("chips")
    m.grid = m.top.findNode("grid")
    m.rail = m.top.findNode("rail")
    m.spinner = m.top.findNode("spinner")
    m.status = m.top.findNode("status")
    m.statusTitle = m.top.findNode("statusTitle")
    m.statusBody = m.top.findNode("statusBody")
    m.retryBtn = m.top.findNode("retryBtn")
    m.sortPanel = m.top.findNode("sortPanel")
    m.filterPanel = m.top.findNode("filterPanel")
    m.filterFly = m.top.findNode("filterFly")
    m.menu = m.top.findNode("menu")
    m.pressTimer = m.top.findNode("pressTimer")
    m.pendingSelect = invalid
    LongPress_init()

    m.grid.observeField("itemFocused", "onGridFocused")
    m.grid.observeField("itemSelected", "onGridSelected")
    m.backPill.observeField("buttonSelected", "onBackPill")
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
    m.rail.observeField("prefixSelected", "onPrefixSelected")
    m.rail.observeField("exitLeft", "onRailExit")
    m.menu.observeField("chosen", "onMenuChosen")
    m.menu.observeField("dismissed", "onMenuDismissed")
    m.pressTimer.observeField("fire", "onPressHeld")
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
    m.namePrefix = ""
    m.facets = invalid
    m.filterFacet = ""
    m.cards = []
    m.nextCursor = ""
    m.hasMore = false
    m.loading = false
    m.loadingMore = false
    m.loaded = false
    m.requestSeq = 0
    ' Drill-in from a list grid: {kind: "collection", collectionId, title} from the Collections list, or
    ' {kind: "group", field: "author"|"series", name, title, subtitle} from the Authors / Series groups.
    m.drill = invalid
    m.optionsTarget = invalid
    m.chipNodes = []
    m.chipValues = []
    m.chipFocus = 0
    ' Room inside each grid cell: MarkupGrid clips to its bounds, so the scaled first column / row
    ' needs 20 px (1.10 × half the card) + glow on the left and 30 px on top; the same 30 px below
    ' keeps the focused card's caption (pushed down by the scale) inside the cell.
    m.insetX = 20
    m.insetY = 30
    m.cardStyle = "poster"
    m.gridY = 284
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
    if m.mode = "alphabet" then
        m.sortField = "title"
        m.sortDesc = false
    end if
    layoutPage()
    m.loaded = false
end sub

' Authors / Series: a grid of audiobook groups (GET /api/v2/catalog/audiobook-groups).
function isGroupsMode() as boolean
    return m.mode = "authors" or m.mode = "series"
end function

function groupBy() as string
    if m.mode = "authors" then return "author"
    if m.mode = "series" then return "series"
    return ""
end function

function groupsLabel() as string
    if m.mode = "authors" then return "Authors"
    return "Series"
end function

function inGroupDrill() as boolean
    return m.drill <> invalid and m.drill.kind = "group"
end function

' Audiobook and album covers are square; everything else is a 2:3 poster.
function gridStyle() as string
    if isGroupsMode() and m.drill = invalid then return "square"
    libMode = LCase(Str_orEmpty(prm("mode")))
    if libMode = "audiobooks" or libMode = "music" then return "square"
    return "poster"
end function

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
    suffix = ""
    if m.mode = "collections" then suffix = "Collections"
    if m.mode = "alphabet" then suffix = "A-Z"
    if m.mode = "genres" then suffix = "Genres"
    if isGroupsMode() then suffix = groupsLabel()
    if suffix <> "" then
        if name <> "" then return name + " · " + suffix
        return suffix
    end if
    return name
end function

function showsControls() as boolean
    if m.drill <> invalid then return m.drill.kind = "group"
    return m.mode = "browse" or m.mode = "favorites" or m.mode = "watchlist" or m.mode = "collection" or m.mode = "person" or m.mode = "section"
end function

' The A–Z rail: Browse (while sorted by title, like TvLibraryDetailScreen) and the A-Z section.
function railAvailable() as boolean
    if m.drill <> invalid then return false
    if m.mode <> "browse" and m.mode <> "alphabet" then return false
    return m.sortField = "title"
end function

' Columns follow the poster-size preference; cells fill the 1780 px content width and carry the inset.
sub applyGridMetrics()
    m.cardStyle = gridStyle()
    cols = Theme_gridColumns()
    cellW = Int((1780 - (cols - 1) * 40) / cols)
    if m.cardStyle = "square" then
        imgH = cellW
    else
        imgH = Int(cellW * 3 / 2)
    end if
    m.grid.numColumns = cols
    m.grid.itemSize = [cellW + 2 * m.insetX, imgH + 90 + 2 * m.insetY]
    m.grid.itemSpacing = [40 - 2 * m.insetX, 60 - 2 * m.insetY]
end sub

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
    tw = Int(Label_width(m.titleLabel))
    m.titleLabel.width = 1400
    m.countLabel.translation = [80 + tw + 20, titleY + 14]
    hasControls = showsControls()
    hasChips = m.mode = "genres" and m.drill = invalid
    m.controls.visible = hasControls
    m.chips.visible = hasChips
    if hasControls or hasChips then
        rowY = titleY + 68
        m.controls.translation = [80, rowY]
        m.chips.translation = [80, rowY]
        gridY = titleY + 68 + 56 + 32
        if hasControls then
            m.backPill.visible = inGroupDrill()
            m.sortPill.visible = not inGroupDrill()
            m.filterPill.visible = m.mode = "browse"
            m.shufflePill.visible = shuffleOffered()
            layoutPills()
        end if
    else
        gridY = titleY + 88
    end if
    m.gridY = gridY
    applyGridMetrics()
    m.grid.translation = [80 - m.insetX, gridY - m.insetY]
    m.rail.railTop = gridY
    m.rail.railBottom = 1040
    updateRail()
    updateSortPill()
end sub

function allPills() as object
    return [m.backPill, m.sortPill, m.filterPill, m.clearPill, m.shufflePill]
end function

sub layoutPills()
    x = 0
    for each pill in allPills()
        if pill.visible then
            pill.translation = [x, 0]
            x = x + pill.width + 16
        end if
    end for
end sub

function visiblePills() as object
    out = []
    if not m.controls.visible then return out
    for each pill in allPills()
        if pill.visible then out.Push(pill)
    end for
    return out
end function

sub updateRail()
    show = railAvailable()
    if not show and m.rail.hasFocus() then onRailExit()
    m.rail.visible = show
    m.rail.selected = m.namePrefix
end sub

' ---------- Lifecycle ----------

sub onPageShown()
    if not m.loaded and not m.loading then reload()
    ' The Shuffle pill follows the server's capability (hidden until it says available).
    Shuffle_refreshCaps("onShuffleCaps")
    updateShufflePill()
end sub

sub onShuffleCaps(event as object)
    Shuffle_storeCaps(event)
    updateShufflePill()
end sub

sub updateShufflePill()
    if not m.controls.visible then return
    show = shuffleOffered()
    if show <> m.shufflePill.visible then
        if m.shufflePill.hasFocus() and not show then m.sortPill.setFocus(true)
        m.shufflePill.visible = show
        layoutPills()
    end if
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
    else if m.chips.visible and m.chipNodes.Count() > 0 then
        focusChip(m.chipFocus)
    else if visiblePills().Count() > 0 then
        pills = visiblePills()
        pills[0].setFocus(true)
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
    if not inGroupDrill() then m.countLabel.visible = false
    m.loaded = false
    m.loading = true
    m.spinner.visible = true
    m.requestSeq = m.requestSeq + 1
    if m.mode = "collections" and m.drill = invalid then
        Api_get("/api/v2/library/" + Str_urlEncode(Str_orEmpty(prm("libraryId"))) + "/collections", invalid, "onCollections", { seq: m.requestSeq })
    else if isGroupsMode() and m.drill = invalid then
        requestGroups("")
    else
        if m.mode = "genres" and m.facets = invalid then loadFacets()
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
    if m.drill <> invalid and m.drill.kind = "collection" then
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
    if m.namePrefix <> "" and railAvailable() then q.name_prefix = m.namePrefix
    sw = sortWire()
    if sw <> "" then q.sort = sw
    if cursor <> "" then q.cursor = cursor

    ' Structured rules go through POST /api/v2/catalog/query (TvLibraryDetailViewModel: a chosen
    ' author / series is the rule {field, op: "is", value: name}; filters add their own groups).
    groups = []
    if inGroupDrill() then groups.Push({ match: "all", rules: [{ field: m.drill.field, op: "is", value: m.drill.name }] })
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
    if groups.Count() > 0 then
        body = q
        body.groups = groups
        body.Delete("image_size")
        Api_call({ method: "POST", path: "/api/v2/catalog/query", query: { image_size: "medium" }, body: body, context: ctx }, "onPage")
    else
        Api_get("/api/v2/catalog", q, "onPage", ctx)
    end if
end sub

' Reads the page cursor out of a catalog-style response and updates hasMore / nextCursor.
sub readPaging(data as object)
    m.hasMore = false
    m.nextCursor = ""
    if data = invalid then return
    page = data.page
    if page <> invalid and page.has_more = true and not Str_isEmpty(page.next_cursor) then
        m.hasMore = true
        m.nextCursor = page.next_cursor
    end if
end sub

sub showCount(data as object, singular as string, plural as string)
    if data = invalid or data.total = invalid then return
    n = Int(data.total)
    txt = n.ToStr() + " " + plural
    if n = 1 then txt = "1 " + singular
    if data.total_exact = false then txt = "About " + txt
    m.countLabel.text = txt
    m.countLabel.visible = n > 0
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
    readPaging(data)
    ' A group drill keeps the group's own "3 books · 2h" line.
    if not isMore and not inGroupDrill() then showCount(data, "title", "titles")
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
    m.grid.content = Content_grid(items, m.cardStyle, m.insetX, m.insetY)
    m.grid.visible = true
    if m.top.hasFocus() then m.grid.setFocus(true)
end sub

sub appendCards(items as object)
    if m.grid.content = invalid then
        setCards(items)
        return
    end if
    m.cards.Append(items)
    Content_appendCards(m.grid.content, items, m.cardStyle, m.insetX, m.insetY)
end sub

' ---------- Audiobook groups (Authors / Series) ----------

' GET /api/v2/catalog/audiobook-groups?library_id=&group_by=author|series&sort=name&limit=&cursor=
sub requestGroups(cursor as string)
    q = { library_id: Str_orEmpty(prm("libraryId")), group_by: groupBy(), sort: "name", limit: 60, image_size: "medium" }
    if cursor <> "" then q.cursor = cursor
    Api_get("/api/v2/catalog/audiobook-groups", q, "onGroups", { seq: m.requestSeq, cursor: cursor })
end sub

sub onGroups(event as object)
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
    cards = []
    if data <> invalid then
        gb = groupBy()
        for each g in Arr_or(data.items)
            if g <> invalid and not Str_isEmpty(g.name) then cards.Push(Content_groupCard(g, gb))
        end for
    end if
    readPaging(data)
    if not isMore then
        if m.mode = "authors" then
            showCount(data, "author", "authors")
        else
            showCount(data, "series", "series")
        end if
    end if
    if isMore then
        appendCards(cards)
    else
        m.loaded = true
        setCards(cards)
    end if
end sub

' OK on a group card: show the group's books (Back / "All Authors" returns to the groups).
sub enterGroup(card as object)
    g = card.group
    if g = invalid then g = { name: card.title }
    name = Str_orEmpty(card.title)
    m.drill = { kind: "group", field: groupBy(), name: name, title: name, subtitle: Content_groupSubtitle(g) }
    saveParentGrid()
    m.sortField = "title"
    m.sortDesc = false
    m.backPill.text = "All " + groupsLabel()
    m.countLabel.text = m.drill.subtitle
    m.countLabel.visible = m.drill.subtitle <> ""
    layoutPage()
    reload()
    m.top.setFocus(true)
end sub

sub saveParentGrid()
    m.parent = { cards: m.cards, content: m.grid.content, index: m.grid.itemFocused, hasMore: m.hasMore, cursor: m.nextCursor, countText: m.countLabel.text, countVisible: m.countLabel.visible }
end sub

sub onBackPill()
    leaveDrill()
end sub

' Back from a drill (a collection's items, a group's books) to the list it came from.
function leaveDrill() as boolean
    if m.drill = invalid then return false
    m.drill = invalid
    m.requestSeq = m.requestSeq + 1
    m.loading = false
    m.loadingMore = false
    m.spinner.visible = false
    m.status.visible = false
    m.countLabel.visible = false
    layoutPage()
    parent = m.parent
    m.parent = invalid
    if parent = invalid then
        reload()
        return true
    end if
    m.cards = parent.cards
    m.grid.content = parent.content
    m.grid.visible = true
    m.countLabel.text = Str_orEmpty(parent.countText)
    m.countLabel.visible = parent.countVisible = true
    m.hasMore = parent.hasMore = true
    m.nextCursor = Str_orEmpty(parent.cursor)
    m.loaded = true
    m.grid.setFocus(true)
    if parent.index <> invalid and parent.index >= 0 then m.grid.jumpToItem = parent.index
    return true
end function

' ---------- Collections ----------

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
        node = Content_cardNode(c, m.cardStyle)
        node.cardInsetX = m.insetX
        node.cardInsetY = m.insetY
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

' ---------- Status ----------

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
    else if isGroupsMode() and m.drill = invalid then
        title = "No audiobook " + LCase(groupsLabel()) + " found."
        body = ""
    else if m.namePrefix <> "" and railAvailable() then
        title = "No titles match"
        body = "Try another letter."
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
        if visiblePills().Count() > 0 then
            pills = visiblePills()
            pills[0].setFocus(true)
        else if m.chips.visible and m.chipNodes.Count() > 0 then
            focusChip(m.chipFocus)
        else
            m.top.setFocus(true)
        end if
    end if
end sub

' ---------- Grid events ----------

sub onGridFocused()
    idx = m.grid.itemFocused
    if m.hasMore and not m.loadingMore and not m.loading and idx >= m.cards.Count() - 12 then
        m.loadingMore = true
        if isGroupsMode() and m.drill = invalid then
            requestGroups(m.nextCursor)
        else
            requestPage(m.nextCursor)
        end if
    end if
end sub

' OK on a card. MarkupGrid sets itemSelected on the OK *press* and consumes the key, so a long press
' is detected from the OK *release* (LongPress_* in Utils.brs): the selection waits as `pendingSelect`;
' a release within 600 ms opens the detail, the timer firing first opens the card menu.
sub onGridSelected()
    idx = m.grid.itemSelected
    if idx < 0 or idx >= m.cards.Count() then return
    card = m.cards[idx]
    if m.mode = "collections" and m.drill = invalid then
        m.drill = { kind: "collection", collectionId: Str_orEmpty(card.collection_id), title: Str_orEmpty(card.title) }
        saveParentGrid()
        layoutPage()
        reload()
        m.top.setFocus(true)
        return
    end if
    if isGroupsMode() and m.drill = invalid then
        enterGroup(card)
        return
    end if
    if LongPress_enabled() then
        m.pendingSelect = idx
        m.pressTimer.control = "stop"
        m.pressTimer.control = "start"
    else
        CardActions_openDetail(card)
    end if
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
    if idx <> invalid and idx >= 0 and idx < m.cards.Count() then CardActions_openDetail(m.cards[idx])
end sub

' ---------- A–Z rail ----------

sub onPrefixSelected()
    prefix = m.rail.prefixSelected
    if prefix = m.namePrefix then return
    m.namePrefix = prefix
    m.rail.selected = prefix
    reload()
end sub

sub onRailExit()
    if m.grid.visible and m.cards.Count() > 0 then
        m.grid.setFocus(true)
    else if visiblePills().Count() > 0 then
        pills = visiblePills()
        pills[0].setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

' ---------- Genres chips ----------

sub loadFacets()
    if m.facets <> invalid or m.facetsLoading = true then return
    m.facetsLoading = true
    Api_get("/api/v2/catalog/filters", { library_id: Str_orEmpty(prm("libraryId")), skip_technical: "true" }, "onFacets")
end sub

sub buildChips()
    for each old in m.chipNodes
        m.chips.removeChild(old)
    end for
    m.chipNodes = []
    m.chipValues = [""]
    for each v in genreValues()
        m.chipValues.Push(v)
    end for
    x = 0
    for i = 0 to m.chipValues.Count() - 1
        pill = m.chips.createChild("PillButton")
        pill.id = "chip" + i.ToStr()
        pill.height = 56
        pill.fontSize = 24
        pill.padX = 28
        pill.scaleOnFocus = 1.04
        if i = 0 then pill.text = "All" else pill.text = m.chipValues[i]
        pill.selectedState = m.chipValues[i] = m.genre
        pill.translation = [x, 0]
        pill.observeField("buttonSelected", "onChipSelected")
        x = x + pill.width + 16
        m.chipNodes.Push(pill)
    end for
    if m.chipFocus >= m.chipNodes.Count() then m.chipFocus = 0
end sub

function focusedChipIndex() as integer
    for i = 0 to m.chipNodes.Count() - 1
        if m.chipNodes[i].hasFocus() then return i
    end for
    return -1
end function

' Focuses chip i and scrolls the line so it stays inside the 1780 px content width.
sub focusChip(i as integer)
    if i < 0 or i >= m.chipNodes.Count() then return
    m.chipFocus = i
    pill = m.chipNodes[i]
    px = pill.translation[0]
    shift = 0
    if px + pill.width > 1780 then shift = px + pill.width - 1780
    m.chips.translation = [80 - shift, m.chips.translation[1]]
    pill.setFocus(true)
end sub

sub onChipSelected(event as object)
    node = event.getRoSGNode()
    idx = -1
    for i = 0 to m.chipNodes.Count() - 1
        if m.chipNodes[i].isSameNode(node) then idx = i
    end for
    if idx < 0 then return
    m.genre = m.chipValues[idx]
    for i = 0 to m.chipNodes.Count() - 1
        m.chipNodes[i].selectedState = i = idx
    end for
    reload()
end sub

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
        if m.mode = "collection" or (m.drill <> invalid and m.drill.kind = "collection") then lbl = "Collection Order"
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
    collectionLike = m.mode = "collection" or (m.drill <> invalid and m.drill.kind = "collection")
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
    ' The A–Z jump only applies to the title order (TvLibraryDetailScreen hides the rail otherwise).
    if m.sortField <> "title" then m.namePrefix = ""
    closePanels()
    updateSortPill()
    updateRail()
    reload()
end sub

' ---------- Filter ----------

sub openFilterPanel()
    loadFacets()
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
    if m.mode = "genres" then
        hadFocus = focusedChipIndex() >= 0
        buildChips()
        if hadFocus then focusChip(m.chipFocus)
    end if
end sub

function genreValues() as object
    out = []
    if m.facets = invalid then return out
    seen = {}
    for each g in Arr_or(m.facets.genres)
        v = ""
        if Type(g) = "roString" or Type(g) = "String" then
            v = g
        else if g <> invalid then
            v = Str_orEmpty(g.value)
            if v = "" then v = Str_orEmpty(g.name)
            if v = "" then v = Str_orEmpty(g.label)
        end if
        if v <> "" and not seen.DoesExist(v) then
            seen[v] = true
            out.Push(v)
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

' ---------- Shuffle (shuffle-api-v2.md) ----------

' The shuffle scope this page browses: a movie/TV library, or a library collection.
function shuffleScope() as dynamic
    if m.drill <> invalid then
        if m.drill.kind = "collection" then return { kind: "library_collection", id: Str_orEmpty(m.drill.collectionId) }
        return invalid
    end if
    if m.mode = "collection" then return { kind: "library_collection", id: Str_orEmpty(prm("collectionId")) }
    if m.mode = "browse" and Shuffle_libraryMode(prm("mode")) then return { kind: "library", id: Str_orEmpty(prm("libraryId")) }
    return invalid
end function

' Movie, TV and mixed libraries (and collections) shuffle when the server offers it.
function shuffleOffered() as boolean
    sc = shuffleScope()
    if sc = invalid or sc.id = "" then return false
    return Shuffle_supports(sc.kind)
end function

' The server picks every item: POST /api/v2/shuffles, then play its first pick from the start.
sub shuffle()
    sc = shuffleScope()
    if sc = invalid then return
    if m.shuffleStarting = true then return
    m.shuffleStarting = true
    Shuffle_start(sc.kind, sc.id, "onShuffleStarted")
end sub

sub onShuffleStarted(event as object)
    resp = Api_result(event)
    m.shuffleStarting = false
    Shuffle_play(resp)
end sub

' ---------- Options menu ----------

sub openOptions()
    openOptionsFor(m.grid.itemFocused)
end sub

sub openOptionsFor(idx as integer)
    if idx < 0 or idx >= m.cards.Count() then return
    card = m.cards[idx]
    t = LCase(Str_orEmpty(card.type))
    if t = "collection" or t = "audiobook_group" then return
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
    if not press then
        if m.grid.hasFocus() then LongPress_sawRelease()
        if key = "OK" then flushPendingSelect()
        return false
    end if
    if m.pendingSelect <> invalid and key <> "OK" then flushPendingSelect()
    if panelsOpen() then
        if key = "back" then
            closePanels()
            return true
        end if
        return true
    end if
    if m.rail.hasFocus() or m.rail.isInFocusChain() then
        if key = "back" then
            onRailExit()
            return true
        end if
        return false
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
                if i < pills.Count() - 1 then
                    pills[i + 1].setFocus(true)
                else if m.rail.visible then
                    m.rail.setFocus(true)
                end if
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
    ' Genre chips.
    ci = focusedChipIndex()
    if ci >= 0 then
        if key = "left" then
            if ci > 0 then focusChip(ci - 1)
            return true
        else if key = "right" then
            if ci < m.chipNodes.Count() - 1 then focusChip(ci + 1)
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
    if m.grid.hasFocus() then
        if key = "up" then
            if visiblePills().Count() > 0 then
                pills = visiblePills()
                pills[0].setFocus(true)
                return true
            else if m.chips.visible and m.chipNodes.Count() > 0 then
                focusChip(m.chipFocus)
                return true
            end if
            return false
        else if key = "right" then
            ' The grid did not take Right (last column / last card): move to the A–Z rail.
            if m.rail.visible then
                m.rail.setFocus(true)
                return true
            end if
            return false
        else if key = "options" then
            openOptions()
            return true
        end if
    end if
    if m.retryBtn.hasFocus() and key = "up" then
        if visiblePills().Count() > 0 then
            pills = visiblePills()
            pills[0].setFocus(true)
            return true
        else if m.chips.visible and m.chipNodes.Count() > 0 then
            focusChip(m.chipFocus)
            return true
        end if
    end if
    return false
end function
