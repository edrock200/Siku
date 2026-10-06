' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.field = m.top.findNode("field")
    m.fieldBg = m.top.findNode("fieldBg")
    m.fieldRing = m.top.findNode("fieldRing")
    m.fieldIcon = m.top.findNode("fieldIcon")
    m.fieldText = m.top.findNode("fieldText")
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
        { id: "all", label: "All", scope: "video" },
        { id: "movie", label: "Movies", scope: "movie" },
        { id: "series", label: "Series", scope: "series" }
    ]
    prefs = m.global.prefs
    if prefs <> invalid and prefs.showAudiobooks = true then
        m.chipDefs.Push({ id: "audiobook", label: "Audiobooks", scope: "audiobook" })
    end if
    m.chipIndex = 0
    m.chipFocus = 0
    m.focusArea = "field"      ' field | chips | people | grid | retry
    m.query = ""
    m.pendingText = ""
    m.searchSeq = 0
    m.titles = []
    m.peopleItems = []
    m.titlesDone = false
    m.peopleDone = false
    m.fontChip = ThemeFont("medium", 24)
    m.keyboard = invalid
    m.top.focusable = true
    m.top.observeField("focusedChild", "applyFocusVisuals")
    m.debounce.observeField("fire", "onDebounce")
    m.people.observeField("rowItemSelected", "onPersonSelected")
    m.grid.observeField("itemSelected", "onTitleSelected")
    m.reqRow.observeField("rowItemSelected", "onRequestSelected")
    m.reqSeq = 0
    m.reqQuery = ""
    m.reqResults = []
    m.reqState = ""        ' "" (hidden) | loading | ready | error
    m.reqError = ""
    ' Opened before the shell's probe answered (or without the shell): ask the server ourselves.
    if Req_gate().resolved <> true then Api_get("/api/v2/requests/status", invalid, "onRequestsStatus")
    m.retryBtn.observeField("buttonSelected", "retry")
    buildChips()
    showIdle()
    updateField()
end sub

function placeholder() as string
    names = "movies and series"
    if m.chipDefs.Count() > 3 then names = "movies, series and audiobooks"
    return "Search " + names
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
end sub

sub buildChips()
    x = 0
    for i = 0 to m.chipDefs.Count() - 1
        g = m.chips.createChild("Group")
        g.translation = [x, 0]
        lbl = CreateObject("roSGNode", "Label")
        lbl.font = m.fontChip
        lbl.text = m.chipDefs[i].label
        w = Int(lbl.boundingRect().width) + 80
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
    else
        m.fieldBg.blendColor = "0xFFFFFF0E"
        m.fieldRing.blendColor = "0xFFFFFF1F"
        m.fieldIcon.blendColor = c.inkMuted
    end if
    for i = 0 to m.chipDefs.Count() - 1
        g = m.chips.getChild(i)
        bg = g.findNode("bg")
        ring = g.findNode("ring")
        lbl = g.findNode("label")
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
    kb.title = "Search"
    kb.text = m.query
    kb.buttons = ["Search", "Cancel"]
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
    if q = "" then
        showIdle()
        return
    end if
    m.titlesDone = false
    m.peopleDone = false
    m.titles = []
    m.peopleItems = []
    m.status.visible = false
    m.statusLine.text = "Searching…"
    m.spinner.visible = not m.grid.visible and not m.people.visible
    chip = m.chipDefs[m.chipIndex]
    params = { source: "query", q: q, limit: 40, image_size: "medium" }
    if chip.id <> "all" then params["type"] = chip.id
    ctx = { seq: m.searchSeq }
    Api_get("/api/v2/catalog", params, "onTitles", ctx)
    Api_get("/api/v2/catalog/people", { q: q, limit: 20, media_scope: chip.scope }, "onPeople", ctx)
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
        end if
    end if
    render()
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
    m.statusTitle.text = "Search your library"
    m.statusBody.text = "Find " + Mid(placeholder(), 8) + " in one place."
    m.retryBtn.visible = false
    layoutRequests()
end sub

sub render()
    renderResults()
    layoutRequests()
    if m.focusArea = "requests" and not requestRowFocusable() then focusArea(firstResultsArea())
end sub

sub renderResults()
    if not m.titlesDone then return
    m.spinner.visible = false
    if not Str_isEmpty(m.titlesError) and m.titles.Count() = 0 and m.peopleItems.Count() = 0 then
        m.people.visible = false
        m.grid.visible = false
        m.statusLine.text = ""
        m.status.visible = true
        m.statusTitle.text = "Search is unavailable"
        m.statusBody.text = m.titlesError
        m.retryBtn.visible = true
        m.retryBtn.translation = [(1920 - m.retryBtn.width) / 2, 690]
        if m.focusArea = "people" or m.focusArea = "grid" then focusArea("retry")
        return
    end if
    hasPeople = m.peopleItems.Count() > 0
    hasTitles = m.titles.Count() > 0
    if not hasPeople and not hasTitles then
        m.people.visible = false
        m.grid.visible = false
        m.statusLine.text = "No results"
        m.status.visible = true
        m.statusTitle.text = "No matches for “" + m.query.Trim() + "”"
        m.statusBody.text = "Try a shorter title or a different filter."
        m.retryBtn.visible = false
        if m.focusArea = "people" or m.focusArea = "grid" or m.focusArea = "retry" then focusArea("chips")
        return
    end if
    m.status.visible = false
    if hasTitles then
        n = m.titles.Count()
        if m.titlesTotal <> invalid then n = Int(m.titlesTotal)
        if m.titlesExact then
            m.statusLine.text = n.ToStr() + " results"
        else
            m.statusLine.text = "About " + n.ToStr() + " results"
        end if
    else
        m.statusLine.text = "No matching titles"
    end if
    if hasPeople then
        m.people.content = Content_rows([{ id: "people", title: "People", style: "circle", items: m.peopleItems }])
        m.people.visible = true
        gridY = 740
    else
        m.people.visible = false
        gridY = 420
    end if
    if hasTitles then
        m.grid.translation = [74, gridY]
        m.grid.content = Content_grid(m.titles, "poster")
        m.grid.visible = true
    else
        m.grid.visible = false
    end if
    if m.focusArea = "grid" and not hasTitles then focusArea("people")
    if m.focusArea = "people" and not hasPeople then focusArea("grid")
    if m.focusArea = "retry" then focusArea("chips")
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
    if idx < 0 or idx >= m.titles.Count() then return
    card = m.titles[idx]
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

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
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
        else if key = "back" then
            focusArea("field")
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
        else if key = "back" then
            focusArea("field")
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
        else if key = "back" then
            focusArea("field")
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
        else if key = "back" then
            focusArea("field")
            return true
        end if
        return false
    end if
    if not m.top.hasFocus() then return false
    if m.focusArea = "field" then
        if key = "OK" then
            openKeyboard()
            return true
        else if key = "down" then
            focusArea("chips")
            return true
        else if key = "up" then
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
        else if key = "back" then
            focusArea("field")
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
        m.reqError = Req_failureText(resp, "Search is unavailable")
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
    sig = FormatJson(results)
    changed = sig <> FormatJson(m.reqResults) or m.reqState <> "ready"
    m.reqResults = results
    m.reqState = "ready"
    if changed and results.Count() > 0 then
        cards = []
        for each r in results
            cards.Push(Req_card("result", r, "search-requests"))
        end for
        m.reqRow.content = Content_rows([{ id: "search-requests", title: "", style: "poster", items: cards }])
    end if
    layoutRequests()
end sub

sub onRequestsStatus(event as object)
    resp = Api_result(event)
    if Req_gate().resolved = true or not resp.ok then return
    g = AA_copy(Req_gate())
    g.enabled = Req_statusAvailable(resp.data)
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
    shown = m.reqState <> ""
    m.reqSection.visible = shown
    if not shown then
        setResultsDimmed(false)
        return
    end if
    m.reqRow.visible = m.reqState = "ready" and m.reqResults.Count() > 0
    m.reqFeedback.visible = not m.reqRow.visible
    if m.reqState = "loading" then
        m.reqFeedback.text = "Checking requestable titles..."
    else if m.reqState = "error" then
        m.reqFeedback.text = m.reqError
    else
        m.reqFeedback.text = "No requestable matches found."
    end if
    focused = m.focusArea = "requests" and m.reqRow.visible
    if focused then
        y = 412
    else if m.grid.visible then
        y = m.grid.translation[1] + 2 * 486 + 40 + 24
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
