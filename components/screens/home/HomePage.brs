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
    m.optionsTarget = invalid
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
    m.feed.state = "loading"
    lib = libraryId()
    if lib <> "" then
        Api_get("/api/v2/library/" + Str_urlEncode(lib) + "/sections", { image_size: "medium" }, "onSections")
    else
        Api_get("/api/v2/home/sections", { image_size: "medium" }, "onSections")
    end if
end sub

sub onSections(event as object)
    resp = Api_result(event)
    if not resp.ok then
        m.loading = false
        m.feed.errorText = Api_errorText(resp)
        m.feed.state = "error"
        return
    end if
    sections = []
    if resp.data <> invalid then sections = Arr_or(resp.data.sections)
    hidden = {}
    prefs = m.global.prefs
    if prefs <> invalid then
        for each h in Arr_or(prefs.hiddenSections)
            hidden[Str_orEmpty(h)] = true
        end for
    end if
    m.sections = []
    m.pendingSections = 0
    for each s in sections
        sid = Str_orEmpty(s.id)
        if not hidden.DoesExist(sid) then
            items = Arr_or(s.items)
            total = s.total_count
            if total = invalid then total = 0
            entry = { section: s, items: items }
            m.sections.Push(entry)
            if items.Count() = 0 and total > 0 then
                m.pendingSections = m.pendingSections + 1
                idx = m.sections.Count() - 1
                lib = libraryId()
                if lib <> "" then
                    path = "/api/v2/library/" + Str_urlEncode(lib) + "/sections/" + Str_urlEncode(sid) + "/items"
                else
                    path = "/api/v2/home/sections/" + Str_urlEncode(sid) + "/items"
                end if
                Api_get(path, { image_size: "medium" }, "onSectionItems", { index: idx })
            end if
        end if
    end for
    if m.pendingSections = 0 then buildRows()
end sub

sub onSectionItems(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if resp.ok and resp.data <> invalid and ctx <> invalid then
        idx = ctx.index
        if idx >= 0 and idx < m.sections.Count() then
            m.sections[idx].items = Arr_or(resp.data.items)
        end if
    end if
    m.pendingSections = m.pendingSections - 1
    if m.pendingSections <= 0 then buildRows()
end sub

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

sub buildRows()
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
    m.loading = false
    m.loaded = true
    m.feed.rows = rows
    if rows.Count() = 0 then
        m.feed.state = "empty"
    else
        m.feed.state = "ready"
    end if
    if m.top.hasFocus() then m.feed.focusRequested = true
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

sub onMenuDismissed()
    m.feed.focusRequested = true
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    return false
end function
