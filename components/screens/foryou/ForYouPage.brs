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
    m.loadSeq = 0
    m.loadedRev = -1        ' DataRev_current() when the rows were last requested
    m.background = false
    m.optionsTarget = invalid
    m.top.focusable = true
end sub

sub onPageShown()
    if DataRev_current() <> m.loadedRev or (not m.loaded and not m.loading) then load()
end sub

sub focusContent()
    if m.menu.visible then
        m.menu.setFocus(true)
    else
        m.feed.focusRequested = true
    end if
end sub

sub load()
    m.loading = true
    m.loadSeq = m.loadSeq + 1
    m.loadedRev = DataRev_current()
    ' Rows already on screen stay there while the new ones load.
    m.background = m.loaded and m.feed.state = "ready"
    if m.background then
        requestDiscover()
        return
    end if
    ' Retry / Refresh hides with the status card: park focus on the page so the answer moves it
    ' to the rows (buildRows acts only while the page itself holds focus).
    if m.feed.state = "error" or m.feed.state = "empty" then
        if m.top.isInFocusChain() then m.top.setFocus(true)
    end if
    m.feed.state = "loading"
    requestDiscover()
end sub

sub requestDiscover()
    Api_get("/api/v2/recommendations/discover", { image_size: "medium" }, "onDiscover", { seq: m.loadSeq })
end sub

sub onDiscover(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.loadSeq then return
    m.loading = false
    if not resp.ok then
        ' A failed background refresh keeps the rows that are on screen.
        if m.background then return
        m.feed.errorText = Api_errorText(resp)
        m.feed.state = "error"
        return
    end if
    rows = []
    if resp.data <> invalid then
        for each r in Arr_or(resp.data.items)
            items = Arr_or(r.items)
            if items.Count() > 0 then
                rid = Str_orEmpty(r.key)
                if rid = "" then rid = Str_orEmpty(r.type)
                title = Str_orEmpty(r.title)
                if title = "" then title = "Recommended for You"
                rows.Push({ id: rid, title: title, style: "poster", items: items })
            end if
        end for
    end if
    m.loaded = true
    m.feed.rows = rows
    if rows.Count() = 0 then
        m.feed.state = "empty"
    else
        m.feed.state = "ready"
    end if
    if m.top.hasFocus() then m.feed.focusRequested = true
end sub

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
    m.menu.actions = CardActions_build(opt.card, "")
    m.menu.visible = true
    m.menu.setFocus(true)
end sub

sub onMenuChosen()
    target = m.optionsTarget
    m.feed.focusRequested = true
    if target = invalid then return
    patch = CardActions_perform(m.menu.chosen, target.card, "")
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
    ' Parameters are part of the SceneGraph signature; this screen handles no keys itself.
    if key = "" and press then return false
    return false
end function
