' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.segItems = m.top.findNode("segItems")
    m.monthLabel = m.top.findNode("monthLabel")
    m.stripItems = m.top.findNode("stripItems")
    m.shelves = m.top.findNode("shelves")
    m.spinner = m.top.findNode("spinner")
    m.status = m.top.findNode("status")
    m.statusTitle = m.top.findNode("statusTitle")
    m.statusBody = m.top.findNode("statusBody")
    m.retryBtn = m.top.findNode("retryBtn")

    m.filters = [
        { id: "following", label: "Following" },
        { id: "trending", label: "Trending" },
        { id: "all", label: "All" }
    ]
    m.filterIndex = 0
    m.segFocus = 0
    m.stripFocus = 1          ' 0 = prev, 1..7 = days, 8 = next, 9 = Today
    m.focusArea = "segments"  ' segments | strip | rows | retry
    m.weekDates = []          ' 7 "YYYY-MM-DD" strings
    m.eventsByDate = {}
    m.selectedDay = 0
    m.requestSeq = 0
    m.loaded = false
    m.loading = false
    m.errored = false
    m.fontSeg = ThemeFont("semibold", 24)
    m.fontDow = ThemeFont("medium", 20)
    m.fontDay = ThemeFont("bold", 29)
    m.top.focusable = true
    m.top.observeField("focusedChild", "applyFocusVisuals")
    m.shelves.observeField("rowItemSelected", "onShelfSelected")
    m.retryBtn.observeField("buttonSelected", "load")

    m.today = Cal_today()
    m.weekStart = Cal_weekStart(m.today)
    buildSegments()
    buildStrip()
    computeWeek()
end sub

' ---------- Dates ----------

function Cal_today() as object
    now = CreateObject("roDateTime")
    now.ToLocalTime()
    return Cal_fromYmd(now.GetYear(), now.GetMonth(), now.GetDayOfMonth())
end function

' A date at noon UTC, so day arithmetic is safe.
function Cal_fromYmd(y as integer, mo as integer, d as integer) as object
    dt = CreateObject("roDateTime")
    dt.FromISO8601String(y.ToStr() + "-" + Str_padLeft(mo.ToStr(), 2) + "-" + Str_padLeft(d.ToStr(), 2) + "T12:00:00Z")
    return dt
end function

function Cal_addDays(dt as object, n as integer) as object
    out = CreateObject("roDateTime")
    out.FromSeconds(dt.AsSeconds() + n * 86400)
    return out
end function

function Cal_ymd(dt as object) as string
    return dt.GetYear().ToStr() + "-" + Str_padLeft(dt.GetMonth().ToStr(), 2) + "-" + Str_padLeft(dt.GetDayOfMonth().ToStr(), 2)
end function

' Monday of the week containing dt.
function Cal_weekStart(dt as object) as object
    dow = dt.GetDayOfWeek() ' 0 = Sunday
    offset = (dow + 6) mod 7
    return Cal_addDays(dt, -offset)
end function

function Cal_dowName(dt as object, long = false as boolean) as string
    names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    n = names[dt.GetDayOfWeek()]
    if long then return n
    return Left(n, 3)
end function

function Cal_monthName(mo as integer) as string
    names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    return names[mo - 1]
end function

function Cal_timezone() as string
    di = CreateObject("roDeviceInfo")
    tz = di.GetTimeZone()
    if Str_isEmpty(tz) then return "UTC"
    return tz
end function

sub computeWeek()
    m.weekDates = []
    for i = 0 to 6
        m.weekDates.Push(Cal_ymd(Cal_addDays(m.weekStart, i)))
    end for
    anchor = Cal_addDays(m.weekStart, 3)
    m.monthLabel.text = Cal_monthName(anchor.GetMonth()) + " " + anchor.GetYear().ToStr()
    todayYmd = Cal_ymd(m.today)
    m.selectedDay = 0
    for i = 0 to 6
        if m.weekDates[i] = todayYmd then m.selectedDay = i
    end for
    updateStrip()
end sub

' ---------- Segmented control ----------

sub buildSegments()
    segW = 180
    for i = 0 to m.filters.Count() - 1
        g = m.segItems.createChild("Group")
        g.translation = [i * segW, 0]
        bg = g.createChild("Poster")
        bg.id = "bg"
        bg.uri = "pkg:/images/ui/r28.9.png"
        bg.width = segW
        bg.height = 56
        lbl = g.createChild("Label")
        lbl.id = "label"
        Label_setFont(lbl, "semibold", 24)
        lbl.width = segW
        lbl.height = 56
        lbl.horizAlign = "center"
        lbl.vertAlign = "center"
        lbl.text = m.filters[i].label
    end for
end sub

' ---------- Week strip ----------

sub buildStrip()
    x = 0
    ' prev
    g = stripCell("prev", x, 56)
    icon = g.createChild("Poster")
    icon.id = "icon"
    icon.uri = "pkg:/images/icons/chevron_left.png"
    icon.width = 36
    icon.height = 36
    icon.translation = [10, 18]
    x = x + 56 + 16
    for i = 0 to 6
        g = stripCell("day" + i.ToStr(), x, 132)
        dow = g.createChild("Label")
        dow.id = "dow"
        Label_setFont(dow, "medium", 20)
        dow.width = 132
        dow.horizAlign = "center"
        dow.translation = [0, 8]
        num = g.createChild("Label")
        num.id = "num"
        Label_setFont(num, "bold", 29)
        num.width = 132
        num.horizAlign = "center"
        num.translation = [0, 30]
        dot = g.createChild("Poster")
        dot.id = "dot"
        dot.uri = "pkg:/images/ui/circle.png"
        dot.width = 8
        dot.height = 8
        dot.translation = [62, 62]
        dot.visible = false
        x = x + 132 + 8
    end for
    x = x + 8
    g = stripCell("next", x, 56)
    icon = g.createChild("Poster")
    icon.id = "icon"
    icon.uri = "pkg:/images/icons/chevron_right.png"
    icon.width = 36
    icon.height = 36
    icon.translation = [10, 18]
    x = x + 56 + 24
    g = stripCell("today", x, 140)
    lbl = g.createChild("Label")
    lbl.id = "label"
    Label_setFont(lbl, "semibold", 24)
    lbl.width = 140
    lbl.height = 72
    lbl.horizAlign = "center"
    lbl.vertAlign = "center"
    lbl.text = "Today"
end sub

function stripCell(id as string, x as integer, w as integer) as object
    g = m.stripItems.createChild("Group")
    g.id = id
    g.translation = [x, 0]
    bg = g.createChild("Poster")
    bg.id = "bg"
    bg.uri = "pkg:/images/ui/r14.9.png"
    bg.width = w
    bg.height = 72
    bg.blendColor = "0xFFFFFF14"
    ring = g.createChild("Poster")
    ring.id = "ring"
    ring.uri = "pkg:/images/ui/r14_ring2.9.png"
    ring.width = w
    ring.height = 72
    ring.blendColor = "0xFFFFFF3D"
    ring.visible = false
    return g
end function

sub updateStrip()
    todayYmd = Cal_ymd(m.today)
    for i = 0 to 6
        dt = Cal_addDays(m.weekStart, i)
        g = m.stripItems.findNode("day" + i.ToStr())
        g.findNode("dow").text = UCase(Cal_dowName(dt))
        g.findNode("num").text = dt.GetDayOfMonth().ToStr()
        ymd = m.weekDates[i]
        g.findNode("dot").visible = m.eventsByDate.DoesExist(ymd) and m.eventsByDate[ymd].Count() > 0
        g.findNode("ring").visible = ymd = todayYmd
    end for
    applyFocusVisuals()
end sub

' ---------- Focus visuals ----------

sub applyFocusVisuals()
    c = Theme().colors
    pageFocused = m.top.hasFocus()
    ' Segments
    for i = 0 to m.filters.Count() - 1
        g = m.segItems.getChild(i)
        bg = g.findNode("bg")
        lbl = g.findNode("label")
        isF = pageFocused and m.focusArea = "segments" and m.segFocus = i
        isS = m.filterIndex = i
        if isF then
            bg.visible = true
            bg.blendColor = c.ink
            lbl.color = c.onInk
        else if isS then
            bg.visible = true
            bg.blendColor = "0xFFFFFF38"
            lbl.color = c.ink
        else
            bg.visible = false
            lbl.color = c.inkMuted
        end if
    end for
    ' Strip
    for i = 0 to 9
        g = stripNode(i)
        bg = g.findNode("bg")
        isF = pageFocused and m.focusArea = "strip" and m.stripFocus = i
        isDay = i >= 1 and i <= 7
        isSel = isDay and (i - 1) = m.selectedDay
        if isF then
            bg.blendColor = c.ink
            bg.visible = true
            tint = c.onInk
            sub1 = "0x000000B3"
        else if isSel then
            bg.blendColor = "0xFFFFFF38"
            bg.visible = true
            tint = c.ink
            sub1 = c.inkMuted
        else
            bg.blendColor = "0xFFFFFF14"
            bg.visible = isDay or true
            tint = c.ink
            sub1 = c.inkMuted
        end if
        icon = g.findNode("icon")
        if icon <> invalid then icon.blendColor = tint
        lbl = g.findNode("label")
        if lbl <> invalid then lbl.color = tint
        num = g.findNode("num")
        if num <> invalid then num.color = tint
        dow = g.findNode("dow")
        if dow <> invalid then dow.color = sub1
        dot = g.findNode("dot")
        if dot <> invalid then dot.blendColor = tint
    end for
end sub

function stripNode(i as integer) as object
    if i = 0 then return m.stripItems.findNode("prev")
    if i = 8 then return m.stripItems.findNode("next")
    if i = 9 then return m.stripItems.findNode("today")
    return m.stripItems.findNode("day" + (i - 1).ToStr())
end function

' ---------- Lifecycle ----------

sub onPageShown()
    if not m.loaded and not m.loading then load()
end sub

sub focusContent()
    if m.shelves.visible and m.focusArea = "rows" then
        m.shelves.setFocus(true)
    else if m.focusArea = "retry" and m.retryBtn.visible then
        m.retryBtn.setFocus(true)
    else
        if m.focusArea = "rows" or m.focusArea = "retry" then m.focusArea = "segments"
        m.top.setFocus(true)
    end if
    applyFocusVisuals()
end sub

' ---------- Data ----------

sub load()
    m.loading = true
    m.loaded = false
    m.errored = false
    m.requestSeq = m.requestSeq + 1
    m.spinner.visible = true
    m.status.visible = false
    m.shelves.visible = false
    q = {
        start: m.weekDates[0]
        "end": m.weekDates[6]
        filter: m.filters[m.filterIndex].id
        timezone: Cal_timezone()
    }
    Api_get("/api/v2/calendar", q, "onCalendar", { seq: m.requestSeq })
end sub

sub onCalendar(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid or ctx.seq <> m.requestSeq then return
    m.loading = false
    m.spinner.visible = false
    if not resp.ok then
        m.errored = true
        m.status.visible = true
        m.statusTitle.text = "Something went wrong"
        m.statusBody.text = "Press the week arrows to try another week."
        m.retryBtn.visible = true
        m.retryBtn.translation = [(1920 - m.retryBtn.width) / 2, 690]
        if m.focusArea = "rows" then
            m.focusArea = "retry"
            m.retryBtn.setFocus(true)
        end if
        return
    end if
    m.loaded = true
    m.eventsByDate = {}
    total = 0
    if resp.data <> invalid then
        for each ev in Arr_or(resp.data.events)
            d = Str_orEmpty(ev.date)
            items = Arr_or(ev.items)
            if d <> "" then
                if not m.eventsByDate.DoesExist(d) then m.eventsByDate[d] = []
                m.eventsByDate[d].Append(items)
                total = total + items.Count()
            end if
        end for
    end if
    updateStrip()
    buildShelves(total)
end sub

function badgeLabel(badges as dynamic) as string
    for each b in Arr_or(badges)
        s = LCase(Str_orEmpty(b))
        if s = "series_premiere" then return "PREMIERE"
        if s = "season_premiere" then return "NEW SEASON"
        if s = "finale" or s = "season_finale" or s = "series_finale" then return "FINALE"
    end for
    return ""
end function

sub buildShelves(total as integer)
    if total = 0 then
        f = m.filters[m.filterIndex].id
        if f = "following" then
            title = "Nothing from shows you follow"
            body = "No upcoming releases this week from shows you watch, favorite, or watchlist. Try Trending or All."
        else if f = "trending" then
            title = "Nothing trending this week"
            body = "No trending releases this week. Try Following or All."
        else
            title = "Nothing scheduled this week"
            body = "Use the week arrows to look at another week."
        end if
        m.status.visible = true
        m.statusTitle.text = title
        m.statusBody.text = body
        m.retryBtn.visible = false
        m.shelves.visible = false
        m.shelves.content = invalid
        if m.focusArea = "rows" or m.focusArea = "retry" then
            m.focusArea = "strip"
            m.top.setFocus(true)
        end if
        applyFocusVisuals()
        return
    end if
    m.status.visible = false
    root = CreateObject("roSGNode", "ContentNode")
    todayYmd = Cal_ymd(m.today)
    for i = 0 to 6
        ymd = m.weekDates[i]
        dt = Cal_addDays(m.weekStart, i)
        row = root.createChild("ContentNode")
        if ymd = todayYmd then
            row.title = "Today"
        else
            row.title = Cal_dowName(dt, true) + ", " + Cal_monthName(dt.GetMonth()) + " " + dt.GetDayOfMonth().ToStr()
        end if
        row.addFields({ rowId: ymd, rowStyle: "poster" })
        items = []
        if m.eventsByDate.DoesExist(ymd) then items = m.eventsByDate[ymd]
        if items.Count() = 0 then
            stub = Content_cardNode({ content_id: "", "type": "stub", title: "Nothing scheduled" }, "poster")
            stub.raw = { stub: true }
            row.appendChild(stub)
        else
            for each ev in items
                node = Content_cardNode(ev, "poster")
                t = LCase(Str_orEmpty(ev.type))
                if t = "episode" then
                    se = Content_seShort(ev.season_number, ev.episode_number)
                    node.subtitle = Str_joinDots([se, Str_orEmpty(ev.episode_title)])
                    if Str_isEmpty(node.title) then node.title = Str_orEmpty(ev.series_title)
                else if t = "movie" then
                    node.subtitle = "Movie"
                end if
                node.badge = badgeLabel(ev.badges)
                row.appendChild(node)
            end for
        end if
    end for
    m.shelves.content = root
    m.shelves.visible = true
    if m.focusArea = "rows" or m.focusArea = "retry" then
        m.focusArea = "rows"
        m.shelves.setFocus(true)
    end if
    jumpToDay(m.selectedDay)
end sub

sub jumpToDay(day as integer)
    if m.shelves.content = invalid then return
    m.shelves.jumpToRowItem = [day, 0]
end sub

sub onShelfSelected()
    sel = m.shelves.rowItemSelected
    if sel = invalid or sel.Count() < 2 or m.shelves.content = invalid then return
    row = m.shelves.content.getChild(sel[0])
    if row = invalid or sel[1] >= row.getChildCount() then return
    node = row.getChild(sel[1])
    card = node.raw
    if card = invalid or card.stub = true then return
    id = Str_orEmpty(card.series_id)
    itemType = "series"
    if id = "" then
        id = Str_orEmpty(card.content_id)
        itemType = Str_orEmpty(card.type)
    end if
    if id = "" then return
    Nav_openItem(id, itemType)
end sub

' ---------- Actions ----------

sub shiftWeek(weeks as integer)
    m.weekStart = Cal_addDays(m.weekStart, weeks * 7)
    m.eventsByDate = {}
    computeWeek()
    load()
end sub

sub goToday()
    m.today = Cal_today()
    m.weekStart = Cal_weekStart(m.today)
    m.eventsByDate = {}
    computeWeek()
    load()
end sub

sub selectFilter(i as integer)
    if i = m.filterIndex then return
    m.filterIndex = i
    applyFocusVisuals()
    load()
end sub

' ---------- Keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then return false
    if m.shelves.hasFocus() then
        if key = "up" then
            m.focusArea = "strip"
            m.stripFocus = m.selectedDay + 1
            m.top.setFocus(true)
            applyFocusVisuals()
            return true
        end if
        return false
    end if
    if m.retryBtn.hasFocus() then
        if key = "up" then
            m.focusArea = "strip"
            m.top.setFocus(true)
            applyFocusVisuals()
            return true
        end if
        return false
    end if
    if not m.top.hasFocus() then return false
    if m.focusArea = "segments" then
        if key = "left" then
            if m.segFocus > 0 then m.segFocus = m.segFocus - 1
        else if key = "right" then
            if m.segFocus < 2 then m.segFocus = m.segFocus + 1
        else if key = "OK" then
            selectFilter(m.segFocus)
        else if key = "down" then
            m.focusArea = "strip"
        else if key = "up" then
            return false
        end if
        applyFocusVisuals()
        return true
    else if m.focusArea = "strip" then
        if key = "left" then
            if m.stripFocus > 0 then m.stripFocus = m.stripFocus - 1
        else if key = "right" then
            if m.stripFocus < 9 then m.stripFocus = m.stripFocus + 1
        else if key = "up" then
            m.focusArea = "segments"
        else if key = "down" then
            if m.shelves.visible and m.shelves.content <> invalid then
                m.focusArea = "rows"
                m.shelves.setFocus(true)
            else if m.retryBtn.visible then
                m.focusArea = "retry"
                m.retryBtn.setFocus(true)
            end if
        else if key = "OK" then
            if m.stripFocus = 0 then
                shiftWeek(-1)
            else if m.stripFocus = 8 then
                shiftWeek(1)
            else if m.stripFocus = 9 then
                goToday()
            else
                m.selectedDay = m.stripFocus - 1
                jumpToDay(m.selectedDay)
                if m.shelves.visible then
                    m.focusArea = "rows"
                    m.shelves.setFocus(true)
                end if
            end if
        end if
        applyFocusVisuals()
        return true
    end if
    return false
end function
