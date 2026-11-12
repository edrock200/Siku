' Person detail page (docs/design-spec.md §4.4, docs/api-spec.md §4.7).
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.page = m.top.findNode("page")
    m.header = m.top.findNode("header")
    m.portrait = m.top.findNode("portrait")
    m.nameLabel = m.top.findNode("nameLabel")
    m.badges = m.top.findNode("badges")
    m.bioBox = m.top.findNode("bioBox")
    m.bioBg = m.top.findNode("bioBg")
    m.bio = m.top.findNode("bio")
    m.filmSection = m.top.findNode("filmSection")
    m.filmHeader = m.top.findNode("filmHeader")
    m.filmCount = m.top.findNode("filmCount")
    m.chips = [m.top.findNode("chipAll"), m.top.findNode("chipMovies"), m.top.findNode("chipSeries")]
    m.chipTypes = ["", "movie", "series"]
    m.grid = m.top.findNode("grid")
    m.emptyLabel = m.top.findNode("emptyLabel")
    m.gridSpinner = m.top.findNode("gridSpinner")
    m.spinner = m.top.findNode("spinner")
    m.errorGroup = m.top.findNode("errorGroup")
    m.errorLabel = m.top.findNode("errorLabel")
    m.retryBtn = m.top.findNode("retryBtn")
    m.bioModal = m.top.findNode("bioModal")
    m.bioTitle = m.top.findNode("bioTitle")
    m.fullBio = m.top.findNode("fullBio")
    m.scrollAnim = m.top.findNode("scrollAnim")
    m.scrollInterp = m.top.findNode("scrollInterp")

    m.person = invalid
    m.loading = false
    m.items = []
    m.filter = ""
    ' Filmography paging (Android TV TvPersonDetailViewModel: 60 a page, more as focus nears the end).
    m.filmSeq = 0           ' filmography reads sent; an answer carries its number and filter
    m.filmCursor = ""       ' the next page's cursor, "" when none remains
    m.filmTotal = invalid   ' the server's total, when it sent one
    m.filmLoadingMore = false
    m.filmFailures = 0      ' failed "load more" pages in a row (Paging_retryDelay)
    m.filmRetryAt = 0
    m.chipIndex = 0
    m.zones = []
    m.zoneIndex = 0

    x = 0
    for i = 0 to m.chips.Count() - 1
        m.chips[i].observeField("buttonSelected", "onChipSelected")
        ' Translated here, before the row is laid out (MainScene translates the tree after init).
        m.chips[i].text = Tx(m.chips[i].text)
        m.chips[i].translation = [x, 0]
        x = x + m.chips[i].width + 16
    end for
    m.grid.observeField("itemSelected", "onGridSelected")
    m.grid.observeField("itemFocused", "onGridFocused")
    m.bioBox.observeField("focusedChild", "onBioFocus")
    m.retryBtn.observeField("buttonSelected", "load")
end sub

sub onScreenShown()
    if m.person = invalid then
        if not m.loading then load()
        return
    end if
    if m.bioModal.visible then
        m.fullBio.setFocus(true)
    else
        focusZone(m.zoneIndex)
    end if
end sub

function personId() as string
    pid = Str_orEmpty(m.top.params.personId)
    if pid = "" then pid = Str_orEmpty(m.top.params.itemId)
    return pid
end function

sub load()
    m.loading = true
    m.errorGroup.visible = false
    m.spinner.visible = true
    m.nameLabel.text = Str_orEmpty(m.top.params.name)
    ' A real visit, so no prefetch=true: that marks a speculative read, which never queues the
    ' biography refresh, and a server without person_prefetch answers it with 422.
    Api_get("/api/v2/catalog/people/" + Str_urlEncode(personId()), invalid, "onPerson")
    loadFilmography()
end sub

sub loadFilmography()
    m.emptyLabel.visible = false
    m.gridSpinner.visible = true
    m.filmCursor = ""
    m.filmTotal = invalid
    m.filmLoadingMore = false
    m.filmFailures = 0
    m.filmCount.visible = false
    requestFilmography("")
end sub

' One page of the filmography; cursor "" is the first. The answer carries {filter, seq}, so a slow
' answer for a filter the viewer has left (or an older read of the same one) is dropped.
sub requestFilmography(cursor as string)
    m.filmSeq = m.filmSeq + 1
    q = Artwork_query({ source: "person", person_id: personId(), sort: "-year", limit: 60, image_size: "medium" }, "browse", Theme_posterScale())
    if m.filter <> "" then q["type"] = m.filter
    if cursor <> "" then q.cursor = cursor
    Api_get("/api/v2/catalog", q, "onFilmography", { filter: m.filter, seq: m.filmSeq, more: cursor <> "" })
end sub

' The count beside the header: the server's total, else the titles loaded with "+" while more remain.
sub updateFilmCount()
    txt = Paging_titleCount(m.filmTotal, m.items.Count(), m.filmCursor <> "")
    m.filmCount.text = txt
    m.filmCount.visible = txt <> ""
    m.filmCount.translation = [Label_width(m.filmHeader) + 18, 7]
end sub

' The next page is read once focus is within two rows of the end (Android TV's loadMoreIfNeeded);
' a failed read waits 5 s, doubling to 60 s, before focus moves may ask again.
sub onGridFocused()
    if m.filmCursor = "" or m.filmLoadingMore then return
    if m.filmFailures > 0 and Time_nowSeconds() < m.filmRetryAt then return
    if not Paging_nearEnd(m.grid.itemFocused, m.items.Count(), 6, 2) then return
    m.filmLoadingMore = true
    requestFilmography(m.filmCursor)
end sub

sub showError(msg as string)
    m.spinner.visible = false
    m.errorGroup.visible = true
    m.errorLabel.text = msg
    m.retryBtn.setFocus(true)
end sub

function prettyDate(d as dynamic) as string
    t = Time_longDate(d)
    if t = "" then return Str_orEmpty(d)
    return t
end function

sub onPerson(event as object)
    resp = Api_result(event)
    m.loading = false
    if not resp.ok or resp.data = invalid or Type(resp.data) <> "roAssociativeArray" then
        showError(Api_errorText(resp))
        return
    end if
    m.spinner.visible = false
    p = resp.data
    m.person = p
    m.nameLabel.text = Str_orEmpty(p.name)
    m.portrait.uri = Url_resolve(p.photo_url)

    badgeTexts = []
    if not Str_isEmpty(p.birth_date) then badgeTexts.Push(TxF("Born {0}", [prettyDate(p.birth_date)]))
    if not Str_isEmpty(p.death_date) then badgeTexts.Push(TxF("Died {0}", [prettyDate(p.death_date)]))
    if not Str_isEmpty(p.birthplace) then badgeTexts.Push(p.birthplace)
    m.badges.removeChildrenIndex(m.badges.getChildCount(), 0)
    x = 0
    for each t in badgeTexts
        g = m.badges.createChild("Group")
        g.translation = [x, 0]
        lbl = CreateObject("roSGNode", "Label")
        lbl.text = t
        f = CreateObject("roSGNode", "Font")
        f.uri = "pkg:/fonts/Inter-medium.otf"
        f.size = 24
        lbl.font = f
        w = Label_width(lbl) + 40
        bgp = g.createChild("Poster")
        bgp.uri = "pkg:/images/ui/r22.9.png"
        bgp.blendColor = "0xFFFFFF14"
        bgp.width = w
        bgp.height = 44
        ring = g.createChild("Poster")
        ring.uri = "pkg:/images/ui/r22_ring2.9.png"
        ring.blendColor = "0xFFFFFF24"
        ring.width = w
        ring.height = 44
        lbl.width = w
        lbl.height = 44
        lbl.horizAlign = "center"
        lbl.vertAlign = "center"
        lbl.color = "0xEDEDEDD9"
        g.appendChild(lbl)
        x = x + w + 12
    end for
    hasBadges = badgeTexts.Count() > 0

    bioText = Str_orEmpty(p.bio)
    m.hasBio = bioText <> ""
    if m.hasBio then
        m.bio.text = bioText
        m.bio.color = "0xEDEDEDBF"
    else if not hasBadges then
        m.bio.text = Tx("No biography or personal details are available yet.")
        m.bio.color = "0xEDEDED9E"
    else
        m.bio.text = ""
    end if
    bioY = 156
    if not hasBadges then bioY = 100
    m.bioBox.translation = [-24, bioY]
    bioH = Label_height(m.bio)
    m.bioBg.height = bioH + 32
    headerBottom = 116 + bioY + bioH + 32
    if headerBottom < 116 + 450 then headerBottom = 116 + 450
    m.filmSection.translation = [88, headerBottom + 48]
    m.bioTitle.text = m.nameLabel.text
    m.fullBio.text = bioText

    buildZones()
    m.zoneIndex = 0
    focusZone(0)
end sub

sub onFilmography(event as object)
    resp = Api_result(event)
    if not Paging_isCurrent(resp.context, "filter", m.filter, m.filmSeq) then return
    if resp.context.more = true then
        onMoreFilmography(resp)
        return
    end if
    m.gridSpinner.visible = false
    if not resp.ok or resp.data = invalid then
        m.items = []
        m.grid.content = invalid
        m.emptyLabel.text = Api_errorText(resp)
        m.emptyLabel.visible = true
        buildZones()
        return
    end if
    m.items = Arr_or(resp.data.items)
    m.filmCursor = Paging_nextCursor(resp.data)
    m.filmTotal = resp.data.total
    updateFilmCount()
    ' Cells carry a 20 / 30 px inset so the focused card's zoom is not clipped at the grid's edge (pitfall 12).
    m.grid.content = Content_grid(m.items, "poster", 20, 30)
    m.emptyLabel.text = Tx("No titles found.")
    m.emptyLabel.visible = m.items.Count() = 0
    buildZones()
    if zoneName() = "grid" and m.items.Count() = 0 then focusZone(zoneIndexOf("chips"))
end sub

' A later page: its cards join the grid where they are, so focus stays on the card it was on.
sub onMoreFilmography(resp as object)
    m.filmLoadingMore = false
    if not resp.ok or Type(resp.data) <> "roAssociativeArray" then
        m.filmFailures = m.filmFailures + 1
        m.filmRetryAt = Time_nowSeconds() + Paging_retryDelay(m.filmFailures)
        Diag_log(Diag_join(["[siku-detail] person filmography page failed status=", Int(Num_or(resp.status, 0)), " retry in ", Paging_retryDelay(m.filmFailures), " s"]))
        return
    end if
    m.filmFailures = 0
    items = Arr_or(resp.data.items)
    m.filmCursor = Paging_nextCursor(resp.data)
    if resp.data.total <> invalid then m.filmTotal = resp.data.total
    if m.grid.content <> invalid then Content_appendCards(m.grid.content, items, "poster", 20, 30)
    m.items.Append(items)
    Diag_log(Diag_join(["[siku-detail] person filmography page cards=", items.Count(), " loaded=", m.items.Count(), " more=", m.filmCursor <> ""]))
    updateFilmCount()
end sub

' ---------- Zones ----------

sub buildZones()
    zones = []
    if m.hasBio = true then zones.Push({ name: "bio" })
    zones.Push({ name: "chips" })
    if m.items.Count() > 0 then zones.Push({ name: "grid" })
    m.zones = zones
    if m.zoneIndex >= zones.Count() then m.zoneIndex = zones.Count() - 1
    if m.zoneIndex < 0 then m.zoneIndex = 0
end sub

function zoneName() as string
    if m.zones.Count() = 0 then return "chips"
    return m.zones[m.zoneIndex].name
end function

function zoneIndexOf(name as string) as integer
    for i = 0 to m.zones.Count() - 1
        if m.zones[i].name = name then return i
    end for
    return 0
end function

sub focusZone(i as integer)
    if m.zones.Count() = 0 then return
    if i < 0 then i = 0
    if i >= m.zones.Count() then i = m.zones.Count() - 1
    m.zoneIndex = i
    name = m.zones[i].name
    fy = m.filmSection.translation[1]
    if name = "bio" then
        m.bioBox.setFocus(true)
        scrollTo(0)
    else if name = "chips" then
        m.chips[m.chipIndex].setFocus(true)
        target = -(fy - 100)
        if target > 0 then target = 0
        scrollTo(target)
    else if name = "grid" then
        m.grid.setFocus(true)
        scrollTo(-(fy + 130 - 150))
    end if
end sub

sub scrollTo(targetY as float)
    cur = m.page.translation
    if Abs(cur[1] - targetY) < 1 then return
    m.scrollInterp.keyValue = [[0, cur[1]], [0, targetY]]
    m.scrollAnim.control = "start"
end sub

sub onBioFocus()
    m.bioBg.visible = m.bioBox.hasFocus()
end sub

' ---------- Interactions ----------

sub onChipSelected(event as object)
    chip = event.getRoSGNode()
    for i = 0 to m.chips.Count() - 1
        isIt = m.chips[i].isSameNode(chip)
        m.chips[i].selected = isIt
        if isIt then
            m.chipIndex = i
            m.filter = m.chipTypes[i]
        end if
    end for
    loadFilmography()
end sub

sub onGridSelected()
    idx = m.grid.itemSelected
    if idx < 0 or idx >= m.items.Count() then return
    card = m.items[idx]
    Nav_openItem(Str_orEmpty(card.content_id), card.type)
end sub

sub openBio()
    m.bioModal.visible = true
    m.fullBio.setFocus(true)
end sub

sub closeBio()
    m.bioModal.visible = false
    focusZone(m.zoneIndex)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.bioModal.visible then
        if key = "back" or key = "OK" then
            closeBio()
            return true
        end if
        return true
    end if
    if m.person = invalid then
        if key = "back" then return false
        return true
    end if
    z = zoneName()
    if key = "down" then
        if m.zoneIndex < m.zones.Count() - 1 then focusZone(m.zoneIndex + 1)
        return true
    else if key = "up" then
        if m.zoneIndex > 0 then focusZone(m.zoneIndex - 1)
        return true
    else if key = "left" or key = "right" then
        if z = "chips" then
            ni = m.chipIndex
            if key = "left" then ni = ni - 1 else ni = ni + 1
            if ni >= 0 and ni < m.chips.Count() then
                m.chipIndex = ni
                m.chips[ni].setFocus(true)
            end if
        end if
        return true
    else if key = "OK" then
        if z = "bio" then
            openBio()
            return true
        end if
        return false
    end if
    return false
end function
