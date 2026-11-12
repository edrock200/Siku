' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.field = m.top.findNode("field")
    m.fieldBg = m.top.findNode("fieldBg")
    m.fieldRing = m.top.findNode("fieldRing")
    m.fieldIcon = m.top.findNode("fieldIcon")
    m.fieldText = m.top.findNode("fieldText")
    m.clearBtn = m.top.findNode("clearBtn")
    m.clearBtn.observeField("buttonSelected", "onClearSelected")
    m.clearBtn.a11yLabel = Tx("Clear search")
    m.chips = m.top.findNode("chips")
    m.statusLine = m.top.findNode("statusLine")
    m.people = m.top.findNode("people")
    m.grid = m.top.findNode("grid")
    m.spinner = m.top.findNode("spinner")
    m.status = m.top.findNode("status")
    m.statusTitle = m.top.findNode("statusTitle")
    m.statusBody = m.top.findNode("statusBody")
    m.retryBtn = m.top.findNode("retryBtn")
    m.debounce = m.top.findNode("debounce")
    m.reqSection = m.top.findNode("reqSection")
    m.reqFeedback = m.top.findNode("reqFeedback")
    m.reqRow = m.top.findNode("reqRow")

    m.chipDefs = [
        { id: "all", label: Tx("All"), scope: "video" },
        { id: "movie", label: Tx("Movies"), scope: "movie" },
        { id: "series", label: Tx("Series"), scope: "series" }
    ]
    prefs = m.global.prefs
    if prefs <> invalid and prefs.showAudiobooks = true then
        m.chipDefs.Push({ id: "audiobook", label: Tx("Audiobooks"), scope: "audiobook" })
    end if
    m.chipIndex = 0
    m.chipFocus = 0
    m.focusArea = "field"      ' field | clear | chips | people | grid | retry | requests
    m.query = ""
    m.pendingText = ""
    m.searchSeq = 0
    m.titles = []
    m.gridCards = []         ' what the grid shows: matching box sets, then the titles
    m.peopleItems = []
    m.titlesDone = false
    m.peopleDone = false
    ' Title paging (Android TV TvSearchViewModel.loadMore: 40 a page, more as focus nears the end).
    m.titlesCursor = ""
    m.titlesLoadingMore = false
    m.titlesFailures = 0
    m.titlesRetryAt = 0
    m.boxSets = []
    m.boxSetsPending = false
    m.boxGrace = m.top.findNode("boxGrace")
    m.boxGrace.observeField("fire", "onBoxSetGrace")
    m.searchedQuery = ""      ' the query last sent (box sets re-run only that one)
    ' Box sets are asked for only while some library has them on (the shell reads the library list;
    ' opened without the shell, Search reads it itself).
    if m.global.hasField("boxSetsAvailable") then
        m.boxSetsAvailable = m.global.boxSetsAvailable = true
    else
        m.boxSetsAvailable = false
        Api_get("/api/v2/user/libraries", invalid, "onLibrariesForBoxSets")
    end if
    m.keyboard = invalid
    m.top.focusable = true
    m.top.observeField("focusedChild", "applyFocusVisuals")
    m.debounce.observeField("fire", "onDebounce")
    m.people.observeField("rowItemSelected", "onPersonSelected")
    m.grid.observeField("itemSelected", "onTitleSelected")
    m.grid.observeField("itemFocused", "onGridFocused")
    m.reqRow.observeField("rowItemSelected", "onRequestSelected")
    m.reqSeq = 0
    m.reqQuery = ""
    m.reqResults = []
    m.reqState = ""        ' "" (hidden) | loading | ready | error
    m.reqOnlyLibrary = false ' every requestable match is already in the library (row hidden)
    m.reqError = ""
    ' Opened before the shell's probe answered (or without the shell): ask the server ourselves.
    if Req_gate().resolved <> true then Api_get("/api/v2/requests/status", invalid, "onRequestsStatus")
    m.retryBtn.observeField("buttonSelected", "retry")
    buildChips()
    showIdle()
    updateField()
end sub

function placeholder() as string
    if m.chipDefs.Count() > 3 then return Tx("Search movies, series and audiobooks")
    return Tx("Search movies and series")
end function

sub onScreenShown()
    p = m.top.params
    if p <> invalid and not Str_isEmpty(p.query) and m.query = "" then
        m.query = p.query
        updateField()
        runSearch()
    else if m.reqQuery <> "" and m.reqState = "ready" then
        ' Back from a request detail: the statuses on these cards may have changed.
        runRequestSearch(true)
    end if
    focusArea(m.focusArea)
end sub

sub onScreenHidden()
end sub

' ---------- Field & chips ----------

sub updateField()
    if m.query = "" then
        m.fieldText.text = placeholder()
        m.fieldText.color = "0xEDEDED9E"
    else
        m.fieldText.text = m.query
        m.fieldText.color = Theme().colors.ink
    end if
    ' The clear button exists only while there is something to clear.
    m.clearBtn.visible = m.query <> ""
    if m.focusArea = "clear" and not m.clearBtn.visible then focusArea("field")
end sub

' The X beside the field (Silo Android #798): clearing starts a new query, so focus goes back to the
' field first (the button is about to disappear) and the keyboard opens at once.
sub onClearSelected()
    m.debounce.control = "stop"
    focusArea("field")
    m.query = ""
    m.pendingText = ""
    m.searchedQuery = ""
    updateField()
    runSearch() ' an empty query: results, status and the request row go back to idle
    Diag_log("[siku-search] cleared; keyboard opened")
    openKeyboard()
end sub

sub buildChips()
    x = 0
    for i = 0 to m.chipDefs.Count() - 1
        g = m.chips.createChild("Group")
        g.translation = [x, 0]
        lbl = CreateObject("roSGNode", "Label")
        Label_setFont(lbl, "medium", 24)
        lbl.text = m.chipDefs[i].label
        w = Int(Label_width(lbl)) + 80
        bg = g.createChild("Poster")
        bg.id = "bg"
        bg.uri = "pkg:/images/ui/r28.9.png"
        bg.width = w
        bg.height = 56
        ring = g.createChild("Poster")
        ring.id = "ring"
        ring.uri = "pkg:/images/ui/r28_ring2.9.png"
        ring.width = w
        ring.height = 56
        ring.blendColor = "0xFFFFFF1F"
        lbl.id = "label"
        lbl.width = w
        lbl.height = 56
        lbl.horizAlign = "center"
        lbl.vertAlign = "center"
        g.appendChild(lbl)
        x = x + w + 16
    end for
end sub

sub applyFocusVisuals()
    c = Theme().colors
    pageFocused = m.top.hasFocus()
    fieldFocused = pageFocused and m.focusArea = "field"
    if fieldFocused then
        m.fieldBg.blendColor = "0x15171CCC"
        m.fieldRing.blendColor = "0xFFFFFFF0"
        m.fieldIcon.blendColor = c.ink
        A11y_say("search:field", Tx("Search"), Tx("text field"), -1, 0, m.field)
    else
        A11y_blur("search:field")
        m.fieldBg.blendColor = "0xFFFFFF0E"
        m.fieldRing.blendColor = "0xFFFFFF1F"
        m.fieldIcon.blendColor = c.inkMuted
    end if
    for i = 0 to m.chipDefs.Count() - 1
        g = m.chips.getChild(i)
        bg = Node_find(g, "bg")
        ring = Node_find(g, "ring")
        lbl = Node_find(g, "label")
        isF = pageFocused and m.focusArea = "chips" and m.chipFocus = i
        isS = m.chipIndex = i
        if isF or isS then
            bg.visible = true
            bg.blendColor = c.ink
            ring.visible = false
            lbl.color = c.onInk
            if isS and not isF then bg.blendColor = "0xEDEDEDD9"
        else
            bg.visible = false
            ring.visible = true
            lbl.color = c.ink
        end if
    end for
end sub

sub focusArea(area as string)
    m.focusArea = area
    if area = "people" and m.people.visible then
        m.people.setFocus(true)
    else if area = "grid" and m.grid.visible then
        m.grid.setFocus(true)
    else if area = "retry" and m.retryBtn.visible then
        m.retryBtn.setFocus(true)
    else if area = "requests" and requestRowFocusable() then
        m.reqRow.setFocus(true)
    else if area = "clear" and m.clearBtn.visible then
        m.clearBtn.setFocus(true)
    else
        if area <> "field" and area <> "chips" then m.focusArea = "field"
        m.top.setFocus(true)
    end if
    layoutRequests()
    applyFocusVisuals()
end sub

' ---------- Keyboard ----------

sub openKeyboard()
    kb = CreateObject("roSGNode", "KeyboardDialog")
    kb.title = Tx("Search")
    kb.text = m.query
    kb.buttons = [Tx("Search"), Tx("Cancel")]
    kb.observeField("text", "onKeyboardText")
    kb.observeField("buttonSelected", "onKeyboardButton")
    kb.observeField("wasClosed", "onKeyboardClosed")
    m.keyboard = kb
    m.top.getScene().dialog = kb
end sub

sub onKeyboardText()
    if m.keyboard = invalid then return
    m.pendingText = m.keyboard.text
    m.query = m.pendingText
    updateField()
    m.debounce.control = "stop"
    m.debounce.control = "start"
end sub

sub onDebounce()
    runSearch()
end sub

sub onKeyboardButton()
    if m.keyboard = invalid then return
    if m.keyboard.buttonSelected = 0 then
        m.query = m.keyboard.text
        updateField()
        m.debounce.control = "stop"
        runSearch()
    end if
    m.keyboard.close = true
end sub

sub onKeyboardClosed()
    if m.keyboard <> invalid then
        m.keyboard.unobserveField("text")
        m.keyboard.unobserveField("buttonSelected")
        m.keyboard.unobserveField("wasClosed")
    end if
    m.keyboard = invalid
    focusArea("field")
end sub

' ---------- Search ----------

sub runSearch()
    q = m.query.Trim()
    m.searchSeq = m.searchSeq + 1
    m.boxSets = []
    m.boxSetsPending = false
    m.boxGrace.control = "stop"
    if q = "" then
        showIdle()
        return
    end if
    m.titlesDone = false
    m.peopleDone = false
    m.titles = []
    m.peopleItems = []
    m.titlesCursor = ""
    m.titlesLoadingMore = false
    m.titlesFailures = 0
    m.searchedQuery = q
    m.status.visible = false
    m.statusLine.text = Tx("Searching…")
    m.spinner.visible = not m.grid.visible and not m.people.visible
    chip = m.chipDefs[m.chipIndex]
    params = Artwork_query({ source: "query", q: q, limit: 40, image_size: "medium" }, "browse", Theme_posterScale())
    if chip.id <> "all" then params["type"] = chip.id
    ctx = { seq: m.searchSeq }
    m.titlesParams = params
    Api_get("/api/v2/catalog", params, "onTitles", ctx)
    Api_get("/api/v2/catalog/people", { q: q, limit: 20, media_scope: chip.scope }, "onPeople", ctx)
    ' Box sets are movies: the Series and Audiobooks chips leave them out.
    if m.boxSetsAvailable and (chip.id = "all" or chip.id = "movie") and Len(q) <= 200 then
        m.boxSetsPending = true
        Api_get("/api/v2/catalog/box-sets", { q: q, limit: 5 }, "onBoxSets", ctx)
    end if
    runRequestSearch(false)
end sub

sub retry()
    runSearch()
end sub

sub onTitles(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.searchSeq then return
    m.titlesDone = true
    if not resp.ok then
        m.titlesError = Api_errorText(resp)
        m.titles = []
    else
        m.titlesError = ""
        m.titles = []
        m.titlesTotal = invalid
        m.titlesExact = true
        if resp.data <> invalid then
            m.titles = Arr_or(resp.data.items)
            m.titlesTotal = resp.data.total
            if resp.data.total_exact = false then m.titlesExact = false
            m.titlesCursor = Paging_nextCursor(resp.data)
        end if
    end if
    ' Matching box sets lead the grid; they land with the first titles so the grid never shifts
    ' under focus, but a slow answer holds the titles back at most 1.5 s.
    if m.boxSetsPending then
        m.boxGrace.control = "stop"
        m.boxGrace.control = "start"
        return
    end if
    render()
end sub

sub onBoxSets(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.searchSeq or not m.boxSetsPending then return
    m.boxSetsPending = false
    m.boxGrace.control = "stop"
    ' A failed read answers none: it never fails the search it sits beside.
    m.boxSets = []
    if resp.ok then m.boxSets = BoxSet_searchCards(resp.data)
    Diag_log(Diag_join(["[siku-boxsets] search box sets=", m.boxSets.Count(), " status=", Int(Num_or(resp.status, 0))]))
    if m.titlesDone then render()
end sub

' The titles are in and the box sets are still out: this query shows none.
sub onBoxSetGrace()
    if not m.boxSetsPending or not m.titlesDone then return
    m.boxSetsPending = false
    m.boxSets = []
    Diag_log("[siku-boxsets] search box sets late; showing the titles without them")
    render()
end sub

' Opened without the shell: whether any library has box sets on. A list that says so re-runs a query
' already searched (one still waiting out the debounce gets box sets when it runs).
sub onLibrariesForBoxSets(event as object)
    resp = Api_result(event)
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then return
    available = BoxSet_anyEnabled(resp.data.items)
    changed = available <> m.boxSetsAvailable
    m.boxSetsAvailable = available
    if changed and m.searchedQuery <> "" and m.query.Trim() = m.searchedQuery then runSearch()
end sub

sub onPeople(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.searchSeq then return
    m.peopleDone = true
    m.peopleItems = []
    if resp.ok and resp.data <> invalid then m.peopleItems = Arr_or(resp.data.items)
    render()
end sub

sub showIdle()
    m.reqSeq = m.reqSeq + 1
    m.reqState = ""
    m.reqQuery = ""
    m.reqResults = []
    m.spinner.visible = false
    m.people.visible = false
    m.grid.visible = false
    m.statusLine.text = ""
    m.status.visible = true
    m.statusTitle.text = Tx("Search your library")
    if m.chipDefs.Count() > 3 then
        m.statusBody.text = Tx("Find movies, series and audiobooks in one place.")
    else
        m.statusBody.text = Tx("Find movies and series in one place.")
    end if
    m.retryBtn.visible = false
    layoutRequests()
    ' The results are gone; do not leave focus on one of them.
    if m.focusArea <> "field" and m.focusArea <> "chips" then focusArea("field")
end sub

sub render()
    renderResults()
    layoutRequests()
    if m.focusArea = "requests" and not requestRowFocusable() then focusArea(firstResultsArea())
end sub

sub renderResults()
    if not m.titlesDone or m.boxSetsPending then return
    m.spinner.visible = false
    m.gridCards = []
    m.gridCards.Append(m.boxSets)
    m.gridCards.Append(m.titles)
    if not Str_isEmpty(m.titlesError) and m.gridCards.Count() = 0 and m.peopleItems.Count() = 0 then
        m.people.visible = false
        m.grid.visible = false
        m.statusLine.text = ""
        m.status.visible = true
        m.statusTitle.text = Tx("Search is unavailable")
        m.statusBody.text = m.titlesError
        m.retryBtn.visible = true
        m.retryBtn.translation = [(1920 - m.retryBtn.width) / 2, 690]
        if m.focusArea = "people" or m.focusArea = "grid" then focusArea("retry")
        return
    end if
    hasPeople = m.peopleItems.Count() > 0
    hasTitles = m.gridCards.Count() > 0
    if not hasPeople and not hasTitles then
        m.people.visible = false
        m.grid.visible = false
        m.statusLine.text = Tx("No results")
        m.status.visible = true
        m.statusTitle.text = TxF("No matches for “{0}”", [m.query.Trim()])
        m.statusBody.text = Tx("Try a shorter title or a different filter.")
        m.retryBtn.visible = false
        if m.focusArea = "people" or m.focusArea = "grid" or m.focusArea = "retry" then focusArea("chips")
        return
    end if
    m.status.visible = false
    if hasTitles then
        n = m.titles.Count()
        if m.titlesTotal <> invalid then n = Int(Content_num(m.titlesTotal))
        n = n + m.boxSets.Count()
        if m.titlesExact then
            m.statusLine.text = TxF("{0} results", [n])
        else
            m.statusLine.text = TxF("About {0} results", [n])
        end if
    else
        m.statusLine.text = Tx("No matching titles")
    end if
    if hasPeople then
        m.people.content = Content_rows([{ id: "people", title: Tx("People"), style: "circle", items: m.peopleItems }], 20)
        m.people.visible = true
        gridY = 740
    else
        m.people.visible = false
        gridY = 420
    end if
    if hasTitles then
        ' Cells carry a 14 / 30 px inset so the focused card's zoom is not clipped at the grid's edge (pitfall 12).
        m.grid.translation = [74 - 14, gridY - 30]
        m.grid.content = Content_grid(m.gridCards, "poster", 14, 30)
        m.grid.visible = true
    else
        m.grid.visible = false
    end if
    if m.focusArea = "grid" and not hasTitles then focusArea("people")
    if m.focusArea = "people" and not hasPeople then focusArea("grid")
    if m.focusArea = "retry" then focusArea("chips")
end sub

' ---------- Paging ----------

' The next page of titles is read once focus is within two rows of the end; a failed read waits
' 5 s, doubling to 60 s, before focus moves may ask again.
sub onGridFocused()
    if m.titlesCursor = "" or m.titlesLoadingMore or not m.titlesDone then return
    if m.titlesFailures > 0 and Time_nowSeconds() < m.titlesRetryAt then return
    if not Paging_nearEnd(m.grid.itemFocused, m.gridCards.Count(), 6, 2) then return
    m.titlesLoadingMore = true
    q = AA_copy(m.titlesParams)
    q.cursor = m.titlesCursor
    Api_get("/api/v2/catalog", q, "onMoreTitles", { seq: m.searchSeq })
end sub

' A later page: its cards join the grid where they are, so focus stays on the card it was on.
sub onMoreTitles(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.searchSeq then return
    m.titlesLoadingMore = false
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then
        m.titlesFailures = m.titlesFailures + 1
        m.titlesRetryAt = Time_nowSeconds() + Paging_retryDelay(m.titlesFailures)
        print "[siku-search] titles page failed status="; Int(Num_or(resp.status, 0)); " retry in "; Paging_retryDelay(m.titlesFailures); " s"
        return
    end if
    m.titlesFailures = 0
    items = Arr_or(resp.data.items)
    m.titlesCursor = Paging_nextCursor(resp.data)
    m.titles.Append(items)
    m.gridCards.Append(items)
    if m.grid.content <> invalid then Content_appendCards(m.grid.content, items, "poster", 14, 30)
    print "[siku-search] titles page cards="; items.Count(); " loaded="; m.titles.Count(); " more="; m.titlesCursor <> ""
end sub

' ---------- Selection ----------

sub onPersonSelected()
    sel = m.people.rowItemSelected
    if sel = invalid or sel.Count() < 2 or sel[1] >= m.peopleItems.Count() then return
    person = m.peopleItems[sel[1]]
    Nav_push("PersonScreen", { personId: Str_orEmpty(person.id), name: Str_orEmpty(person.name) })
end sub

sub onTitleSelected()
    idx = m.grid.itemSelected
    if idx < 0 or idx >= m.gridCards.Count() then return
    card = m.gridCards[idx]
    bs = BoxSet_of(card)
    if bs <> invalid then
        Diag_log("[siku-boxsets] open box set from search")
        Nav_push("BoxSetScreen", BoxSet_screenParams(bs, ""))
        return
    end if
    Nav_openItem(Str_orEmpty(card.content_id), card.type)
end sub

' ---------- Keys ----------

function firstResultsArea() as string
    if m.people.visible then return "people"
    if m.grid.visible then return "grid"
    if m.retryBtn.visible then return "retry"
    if requestRowFocusable() then return "requests"
    return ""
end function

' Closes Search and returns to whatever opened it (the shell, with the top bar's Search icon still
' focused). Android TV's Back pops Search from anywhere except a raised keyboard, which handles its
' own Back (the Roku KeyboardDialog closes itself and focus returns to the field).
sub leaveSearch()
    m.debounce.control = "stop"
    Nav_close()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    ' Back is answered here, before looking at which part has focus, so no focus state (a hidden
    ' people row or grid, a button that vanished, a stale area name) can trap the user in Search.
    if key = "back" then
        leaveSearch()
        return true
    end if
    if m.reqRow.hasFocus() then
        if key = "up" then
            ' Same precedence as Android TV: the results, else "Try again", else people, else the chips.
            if m.grid.visible then
                focusArea("grid")
            else if m.retryBtn.visible then
                focusArea("retry")
            else if m.people.visible then
                focusArea("people")
            else
                focusArea("chips")
            end if
            return true
        end if
        return false
    end if
    if m.people.hasFocus() then
        if key = "up" then
            focusArea("chips")
            return true
        else if key = "down" then
            if m.grid.visible then
                focusArea("grid")
            else if requestRowFocusable() then
                focusArea("requests")
            end if
            return true
        end if
        return false
    end if
    if m.grid.hasFocus() then
        if key = "up" then
            if m.people.visible then focusArea("people") else focusArea("chips")
            return true
        else if key = "down" then
            ' Down past the last grid row reaches the request row.
            if requestRowFocusable() then focusArea("requests")
            return true
        end if
        return false
    end if
    if m.retryBtn.hasFocus() then
        if key = "up" then
            focusArea("chips")
            return true
        else if key = "down" then
            if requestRowFocusable() then focusArea("requests")
            return true
        end if
        return false
    end if
    if m.clearBtn.hasFocus() then
        if key = "left" then
            focusArea("field")
            return true
        else if key = "down" then
            focusArea("chips")
            return true
        else if key = "up" then
            leaveSearch()
            return true
        end if
        return true ' Right: nothing past the button
    end if
    if m.focusArea = "field" then
        if key = "OK" then
            openKeyboard()
            return true
        else if key = "right" then
            if m.clearBtn.visible then focusArea("clear")
            return true
        else if key = "down" then
            focusArea("chips")
            return true
        else if key = "up" then
            ' Up from the field reaches the top bar, as on Android TV (where Search sits under the bar).
            leaveSearch()
            return true
        end if
        return false
    else if m.focusArea = "chips" then
        if key = "left" then
            if m.chipFocus > 0 then m.chipFocus = m.chipFocus - 1
            applyFocusVisuals()
            return true
        else if key = "right" then
            if m.chipFocus < m.chipDefs.Count() - 1 then m.chipFocus = m.chipFocus + 1
            applyFocusVisuals()
            return true
        else if key = "OK" then
            if m.chipIndex <> m.chipFocus then
                m.chipIndex = m.chipFocus
                applyFocusVisuals()
                if m.query.Trim() <> "" then runSearch()
            end if
            return true
        else if key = "up" then
            focusArea("field")
            return true
        else if key = "down" then
            area = firstResultsArea()
            if area <> "" then focusArea(area)
            return true
        end if
    end if
    return false
end function

' ---------- Available to request (Android TV TvRequestSearchSection) ----------

' The chip's request media type: All → all (omitted), Movies → movie, Series → series.
' The v2 request search accepts only movie | series | all, so the Audiobooks chip has no request row.
function requestMediaType() as string
    id = m.chipDefs[m.chipIndex].id
    if id = "movie" or id = "series" then return id
    if id = "all" then return "all"
    return ""
end function

sub runRequestSearch(inPlace as boolean)
    q = m.query.Trim()
    mt = requestMediaType()
    m.reqSeq = m.reqSeq + 1
    if Req_gate().enabled <> true or Len(q) < 2 or mt = "" then
        m.reqState = ""
        m.reqQuery = ""
        m.reqResults = []
        layoutRequests()
        return
    end if
    m.reqQuery = q
    if not inPlace then
        m.reqResults = []
        m.reqState = "loading"
    end if
    params = { q: q, page: 1 }
    if mt <> "all" then params.media_type = mt
    Api_get("/api/v2/requests/search", params, "onRequestSearch", { seq: m.reqSeq, mediaType: mt })
    layoutRequests()
end sub

sub onRequestSearch(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.reqSeq then return
    if not resp.ok or resp.data = invalid then
        if m.reqState = "ready" and m.reqResults.Count() > 0 then return
        m.reqState = "error"
        m.reqError = Req_failureText(resp, Tx("Search is unavailable"))
        m.reqResults = []
        layoutRequests()
        return
    end if
    mt = resp.context.mediaType
    results = []
    for each r in Arr_or(resp.data.results)
        rmt = Str_orEmpty(r.media_type)
        if Req_isSupportedType(rmt) and (mt = "all" or rmt = mt) then results.Push(r)
    end for
    ' Every match already in the library: the row has nothing to say, so it hides (Silo Android #773).
    m.reqOnlyLibrary = false
    matching = results.Count()
    results = Req_withoutLibraryTitles(results)
    if matching > 0 and results.Count() = 0 then m.reqOnlyLibrary = true
    sig = FormatJson(results)
    changed = sig <> FormatJson(m.reqResults) or m.reqState <> "ready"
    m.reqResults = results
    m.reqState = "ready"
    if changed and results.Count() > 0 then
        cards = []
        for each r in results
            cards.Push(Req_card("result", r, "search-requests"))
        end for
        m.reqRow.content = Content_rows([{ id: "search-requests", title: "", style: "poster", items: cards }], 32)
    end if
    layoutRequests()
end sub

sub onRequestsStatus(event as object)
    resp = Api_result(event)
    if Req_gate().resolved = true or not resp.ok then return
    g = AA_copy(Req_gate())
    g.enabled = Req_statusAvailable(resp.data)
    if Type(resp.data) = "roAssociativeArray" then
        g.followSupported = Req_flag(resp.data.follow_supported)
        g.removeFailedSupported = Req_flag(resp.data.remove_failed_supported)
    end if
    g.resolved = true
    Req_setGate(g)
    if g.enabled and m.query.Trim() <> "" then runRequestSearch(false)
end sub

function requestRowFocusable() as boolean
    return m.reqState = "ready" and m.reqResults.Count() > 0 and m.reqSection.visible
end function

' Places the section below whatever the page shows; while its row has focus it moves up to the
' results area and the results above it step aside (the page "scrolls" to the footer).
sub layoutRequests()
    shown = m.reqState <> "" and not (m.reqState = "ready" and m.reqOnlyLibrary = true)
    m.reqSection.visible = shown
    if not shown then
        setResultsDimmed(false)
        return
    end if
    m.reqRow.visible = m.reqState = "ready" and m.reqResults.Count() > 0
    m.reqFeedback.visible = not m.reqRow.visible
    if m.reqState = "loading" then
        m.reqFeedback.text = Tx("Checking requestable titles...")
    else if m.reqState = "error" then
        m.reqFeedback.text = m.reqError
    else
        m.reqFeedback.text = Tx("No requestable matches found.")
    end if
    focused = m.focusArea = "requests" and m.reqRow.visible
    if focused then
        y = 412
    else if m.grid.visible then
        y = m.grid.translation[1] + 2 * 546 + 24
    else if m.people.visible then
        y = 740
    else if m.retryBtn.visible then
        y = 790
    else if m.status.visible then
        y = 720
    else
        y = 420
    end if
    m.reqSection.translation = [0, y]
    setResultsDimmed(focused)
end sub

sub setResultsDimmed(hidden as boolean)
    op = 1.0
    if hidden then op = 0.0
    m.people.opacity = op
    m.grid.opacity = op
    m.status.opacity = op
end sub

' The routing rule every request card shares: "In library" opens the library item, anything else
' opens the request detail.
sub onRequestSelected()
    sel = m.reqRow.rowItemSelected
    if sel = invalid or sel.Count() < 2 or sel[1] >= m.reqResults.Count() then return
    r = m.reqResults[sel[1]]
    mt = Str_orEmpty(r.media_type)
    cid = Req_libraryItemToOpen(Req_displayOfAnnotation(r.availability, r.request), r.library_content_id)
    if cid <> "" then
        Nav_openItem(cid, mt)
    else
        Nav_push("RequestDetailScreen", { mediaType: mt, tmdbId: r.tmdb_id, title: Str_orEmpty(r.title) })
    end if
end sub
