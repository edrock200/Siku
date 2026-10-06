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
    else
        if area <> "field" and area <> "chips" then m.focusArea = "field"
        m.top.setFocus(true)
    end if
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
    m.spinner.visible = false
    m.people.visible = false
    m.grid.visible = false
    m.statusLine.text = ""
    m.status.visible = true
    m.statusTitle.text = "Search your library"
    m.statusBody.text = "Find " + Mid(placeholder(), 8) + " in one place."
    m.retryBtn.visible = false
end sub

sub render()
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
    return ""
end function

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.people.hasFocus() then
        if key = "up" then
            focusArea("chips")
            return true
        else if key = "down" then
            if m.grid.visible then focusArea("grid")
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
