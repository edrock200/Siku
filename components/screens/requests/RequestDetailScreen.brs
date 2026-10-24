' SPDX-License-Identifier: AGPL-3.0-or-later
' Ports RequestDetailViewModel / RequestDetailUiState: the page reads the title
' (GET /api/v2/requests/detail/{media_type}/{tmdb_id}), then the user's own requests for it
' (GET /api/v2/requests/mine). Every button is derived from those reads. Request administration
' (approve, decline, retry) stays in web admin, as on Android TV.

sub init()
    m.page = m.top.findNode("page")
    m.backdrop = m.top.findNode("backdrop")
    m.hero = m.top.findNode("hero")
    m.titleLabel = m.top.findNode("heroTitle")
    m.metaRow = m.top.findNode("metaRow")
    m.metaLabel = m.top.findNode("metaLabel")
    m.ratingChip = m.top.findNode("ratingChip")
    m.ratingRing = m.top.findNode("ratingRing")
    m.ratingLabel = m.top.findNode("ratingLabel")
    m.tagline = m.top.findNode("tagline")
    m.overview = m.top.findNode("overview")
    m.facts = m.top.findNode("facts")
    m.credit = m.top.findNode("credit")
    m.statusStrip = m.top.findNode("statusStrip")
    m.fieldStatusDot = m.top.findNode("fieldStatusDot")
    m.fieldStatusValue = m.top.findNode("fieldStatusValue")
    m.fieldRequested = m.top.findNode("fieldRequested")
    m.fieldRequestedValue = m.top.findNode("fieldRequestedValue")
    m.fieldQuality = m.top.findNode("fieldQuality")
    m.fieldQualityValue = m.top.findNode("fieldQualityValue")
    m.track = m.top.findNode("track")
    m.actions = m.top.findNode("actions")
    m.primaryBtn = m.top.findNode("primaryBtn")
    m.cancelBtn = m.top.findNode("cancelBtn")
    m.actionError = m.top.findNode("actionError")
    m.moreSection = m.top.findNode("moreSection")
    m.moreRow = m.top.findNode("moreRow")
    m.spinner = m.top.findNode("spinner")
    m.errorGroup = m.top.findNode("errorGroup")
    m.errorBody = m.top.findNode("errorBody")
    m.errorRetry = m.top.findNode("errorRetry")
    m.scrollAnim = m.top.findNode("scrollAnim")
    m.scrollInterp = m.top.findNode("scrollInterp")

    m.primaryBtn.observeField("buttonSelected", "onPrimary")
    m.cancelBtn.observeField("buttonSelected", "onCancel")
    m.errorRetry.observeField("buttonSelected", "load")
    m.moreRow.observeField("rowItemSelected", "onMoreSelected")
    m.backdrop.observeField("loadStatus", "onBackdropStatus")

    m.detail = invalid
    m.record = invalid           ' the user's own current record for this title
    m.isSubmitting = false
    m.isCancelling = false
    m.submissionUnconfirmed = false
    m.cancelUnconfirmed = false
    m.actionErrorText = ""
    m.recommendations = []
    m.moreSig = ""
    m.focusZone = "actions"      ' actions | more
    m.actionIndex = 0
    m.shownOnce = false
    m.fetchSeq = 0
    m.top.focusable = true
end sub

sub onScreenShown()
    if not m.shownOnce then
        m.shownOnce = true
        p = m.top.params
        if p = invalid then p = {}
        m.mediaType = LCase(Str_orEmpty(p.mediaType))
        m.tmdbId = Str_orEmpty(p.tmdbId)
        if m.mediaType = "" and not Str_isEmpty(p.itemId) then
            parts = Str_orEmpty(p.itemId).Split(":")
            if parts.Count() = 2 then
                m.mediaType = LCase(parts[0])
                m.tmdbId = parts[1]
            end if
        end if
        load()
    else if m.detail <> invalid then
        ' Back from another page (a recommendation, the library item): re-read what may have changed.
        fetch()
    end if
    restoreFocus()
end sub

' ---------- Loading ----------

sub load()
    m.errorGroup.visible = false
    if m.detail = invalid then
        m.spinner.visible = true
        m.top.setFocus(true)
    end if
    fetch()
end sub

sub fetch()
    m.fetchSeq = m.fetchSeq + 1
    path = "/api/v2/requests/detail/" + Str_urlEncode(m.mediaType) + "/" + Str_urlEncode(m.tmdbId)
    Api_get(path, invalid, "onDetail", { seq: m.fetchSeq })
end sub

sub onDetail(event as object)
    resp = Api_result(event)
    if resp.context = invalid or resp.context.seq <> m.fetchSeq then return
    m.spinner.visible = false
    if not resp.ok or resp.data = invalid then
        m.isSubmitting = false
        m.isCancelling = false
        if m.detail = invalid then
            m.errorBody.text = Req_failureText(resp, "Failed to load request details")
            m.errorGroup.visible = true
            m.errorRetry.translation = [(1920 - m.errorRetry.width) / 2, 560]
            m.errorRetry.setFocus(true)
        else
            render()
        end if
        return
    end if
    m.detail = resp.data
    render()
    ' The user's list keeps its previous value on failure, so a slow list never blocks the page.
    m.pendingReads = { mine: true }
    ReqApi_loadList("mine", "/api/v2/requests/mine", invalid, 100)
end sub

sub onRequestsListLoaded(tag as string, ok as boolean, items as object, resp as object)
    ' resp is part of the RequestsApi callback signature; this screen only needs ok/items.
    if resp = invalid then resp = {}
    if m.pendingReads = invalid or not m.pendingReads.DoesExist(tag) then return
    m.pendingReads.Delete(tag)
    if tag = "mine" and ok then
        own = []
        for each r in items
            if Str_orEmpty(r.media_type) = m.mediaType and Str_orEmpty(r.tmdb_id) = m.tmdbId then own.Push(r)
        end for
        m.record = Req_currentRecord(own)
        if m.cancelUnconfirmed and (m.record = invalid or Req_displayOfRecord(m.record).kind <> "pending") then
            m.cancelUnconfirmed = false
            clearMessage("We couldn't confirm the cancellation. Refresh your requests to check it.")
        end if
    end if
    if m.pendingReads.Count() = 0 then
        m.isSubmitting = false
        m.isCancelling = false
        if m.submissionUnconfirmed and primaryAction().kind <> "request" then
            m.submissionUnconfirmed = false
            clearMessage("We couldn't confirm the request. Check My Requests before trying again.")
        end if
    end if
    render()
end sub

sub clearMessage(text as string)
    if m.actionErrorText = text then m.actionErrorText = ""
end sub

' ---------- State (RequestDetailUiState) ----------

function annotation() as dynamic
    if m.detail = invalid then return invalid
    return Req_displayOfAnnotation(m.detail.availability, m.detail.request)
end function

function detailRequest() as object
    if m.detail = invalid or m.detail.request = invalid then return {}
    return m.detail.request
end function

function currentOwnRecord() as dynamic
    rec = m.record
    if rec = invalid then return invalid
    if Str_orEmpty(rec.outcome) = "active" or m.detail = invalid then return rec
    ann = annotation()
    if ann <> invalid and ann.kind = "inlibrary" then return invalid
    cur = Str_orEmpty(detailRequest().request_id)
    if cur <> "" and cur <> Str_orEmpty(rec.id) then return invalid
    return rec
end function

function activeRecordState() as dynamic
    rec = m.record
    if rec = invalid or Str_orEmpty(rec.outcome) <> "active" then return invalid
    d = Req_displayOfRecord(rec)
    if d.kind = "pending" or d.kind = "ontheway" then return d
    return invalid
end function

' The user's own request for this title that ended without landing (failed or declined), when
' that's the latest word on it.
function endedRequest() as dynamic
    own = currentOwnRecord()
    if own <> invalid and Req_displayOfRecord(own).kind = "attention" then return own
    return invalid
end function

' {kind: "loading"|"request"|"submitting"|"status"|"open", state?, contentId?}
function primaryAction() as object
    if m.detail = invalid then return { kind: "loading" }
    st = annotation()
    cid = Req_libraryItemToOpen(st, m.detail.library_content_id)
    if cid <> "" then return { kind: "open", contentId: cid }
    if m.isSubmitting then return { kind: "submitting" }
    if m.submissionUnconfirmed then return { kind: "status", state: Req_display("unavailable", "", "request_unconfirmed") }
    endedButRequestable = st <> invalid and st.kind = "attention" and detailRequest().requestable = true
    if st <> invalid and not endedButRequestable then return { kind: "status", state: st }
    act = activeRecordState()
    if act <> invalid then return { kind: "status", state: act }
    return { kind: "request" }
end function

function currentProgress() as dynamic
    own = currentOwnRecord()
    if own <> invalid then
        ended = endedRequest()
        endedOwn = ended <> invalid and Str_orEmpty(ended.id) = Str_orEmpty(own.id)
        if activeRecordState() <> invalid or endedOwn or Str_orEmpty(detailRequest().request_id) = Str_orEmpty(own.id) then
            return Req_progressOfRecord(own)
        end if
    end if
    if m.detail = invalid then return invalid
    p = Req_progressOfAnnotation(m.detail.availability, m.detail.request)
    if p <> invalid and p.display.kind = "unavailable" then return invalid
    return p
end function

function canCancel() as boolean
    if m.record = invalid or m.isCancelling or m.cancelUnconfirmed then return false
    return Req_displayOfRecord(m.record).kind = "pending"
end function

function primaryTitle(action as object, p as dynamic) as string
    k = action.kind
    if k = "loading" then return ""
    if k = "request" then
        if endedRequest() = invalid then return "Request"
        return "Request Again"
    end if
    if k = "submitting" then return "Requesting…"
    if k = "open" then return "Open in Library"
    st = action.state
    if p <> invalid and st.kind <> "pending" and st.kind = p.display.kind and st.attention = p.display.attention then return p.long
    return Req_detailTitle(st)
end function

' ---------- Render ----------

sub render()
    d = m.detail
    if d = invalid then return
    m.hero.visible = true
    m.errorGroup.visible = false

    url = Req_backdropUrl(d.backdrop_path)
    if url = "" then url = Req_posterUrl(d.poster_path)
    if m.backdrop.uri <> url then
        m.backdrop.opacity = 0
        m.backdrop.uri = url
    end if

    y = 0
    gap = 18
    m.titleLabel.text = Str_orEmpty(d.title)
    m.titleLabel.translation = [0, y]
    th = Label_height(m.titleLabel)
    if th < 80 then th = 80
    y = y + th + gap

    ' Source tokens (up to three genres) and the outlined rating chip.
    genres = []
    for each g in Arr_or(d.genres)
        if genres.Count() < 3 then genres.Push(g)
    end for
    m.metaLabel.text = Str_joinDots(genres)
    m.metaLabel.width = 0
    mw = 0
    if m.metaLabel.text <> "" then mw = Int(Label_width(m.metaLabel))
    rating = Str_orEmpty(d.content_rating)
    m.ratingChip.visible = rating <> ""
    if rating <> "" then
        m.ratingLabel.text = rating
        m.ratingLabel.width = 0
        rw = Int(Label_width(m.ratingLabel)) + 20
        m.ratingLabel.width = rw
        m.ratingRing.width = rw
        cx = 0
        if mw > 0 then cx = mw + 16
        m.ratingChip.translation = [cx, 0]
    end if
    m.metaRow.visible = m.metaLabel.text <> "" or rating <> ""
    if m.metaRow.visible then
        m.metaRow.translation = [0, y]
        y = y + 34 + gap
    end if

    y = placeLabel(m.tagline, Str_orEmpty(d.tagline), y, gap)
    y = placeLabel(m.overview, Str_orEmpty(d.overview), y, gap)
    y = placeLabel(m.facts, factsLine(d), y, gap)
    y = placeLabel(m.credit, creditText(d), y, gap)

    ' Status strip: shown while a request exists and the title isn't in the library yet.
    p = currentProgress()
    showsStatus = p <> invalid and p.display.kind <> "inlibrary"
    m.statusStrip.visible = showsStatus
    if showsStatus then
        m.statusStrip.translation = [0, y + 4]
        m.fieldStatusDot.blendColor = p.tint
        m.fieldStatusValue.text = p.long
        rec = m.record
        day = ""
        quality = ""
        if rec <> invalid then
            day = Req_day(rec.created_at)
            quality = Req_targetSummary(rec.targets)
            if quality = "" then quality = Req_qualities(rec.targets)
        end if
        m.fieldRequested.visible = day <> ""
        m.fieldRequestedValue.text = day
        m.fieldQuality.visible = quality <> ""
        m.fieldQualityValue.text = quality
        if not m.fieldRequested.visible then
            m.fieldQuality.translation = [308, 0]
        else
            m.fieldQuality.translation = [616, 0]
        end if
        m.track.progress = p
        y = y + 4 + 86 + 6 + 44 + gap
    end if

    renderActions(p)
    m.actions.translation = [0, y + 4]
    heroBottom = 116 + y + 4 + 76

    renderMore(heroBottom)
    restoreFocus()
end sub

function placeLabel(lbl as object, text as string, y as integer, gap as integer) as integer
    lbl.text = text
    lbl.visible = text <> ""
    if text = "" then return y
    lbl.translation = [0, y]
    h = Int(Label_height(lbl))
    if h < 30 then h = 30
    return y + h + gap
end function

' "2026 · 2h 25m · TMDB 7.9" (series: "3 seasons").
function factsLine(d as object) as string
    parts = []
    if Req_num(d.year) > 0 then parts.Push(Str_orEmpty(d.year))
    if Str_orEmpty(d.media_type) = "series" then
        n = Int(Req_num(d.number_of_seasons))
        if n > 0 then
            if n = 1 then parts.Push("1 season") else parts.Push(n.ToStr() + " seasons")
        end if
    else
        rt = Int(Req_num(d.runtime))
        if rt > 0 then
            if rt >= 60 then
                parts.Push(Int(rt / 60).ToStr() + "h " + (rt mod 60).ToStr() + "m")
            else
                parts.Push(rt.ToStr() + "m")
            end if
        end if
    end if
    parts.Push(Req_tmdbRating(d.vote_average))
    return Str_joinDots(parts)
end function

function creditText(d as object) as string
    if not Str_isEmpty(d.director) then return "Directed by " + d.director
    creators = Arr_or(d.creators)
    if creators.Count() > 0 then
        names = [creators[0]]
        if creators.Count() > 1 then names.Push(creators[1])
        return "Created by " + names.Join(", ")
    end if
    return ""
end function

sub renderActions(p as dynamic)
    action = primaryAction()
    m.primaryAction = action
    m.primaryBtn.text = primaryTitle(action, p)
    if action.kind = "request" then
        m.primaryBtn.iconUri = "pkg:/images/icons/add.png"
    else if action.kind = "open" then
        m.primaryBtn.iconUri = "pkg:/images/icons/chevron_right.png"
    else
        m.primaryBtn.iconUri = ""
    end if
    m.cancelBtn.visible = canCancel()
    m.actionButtons = [m.primaryBtn]
    x = m.primaryBtn.width + 18
    if m.cancelBtn.visible then
        m.cancelBtn.translation = [x, 0]
        x = x + m.cancelBtn.width + 18
        m.actionButtons.Push(m.cancelBtn)
    end if
    m.actionError.text = m.actionErrorText
    m.actionError.visible = m.actionErrorText <> ""
    m.actionError.translation = [x + 6, 4]
    if m.actionIndex >= m.actionButtons.Count() then m.actionIndex = m.actionButtons.Count() - 1
end sub

sub renderMore(top as integer)
    recs = []
    if m.detail <> invalid then
        for each r in Arr_or(m.detail.recommendations)
            mt = Str_orEmpty(r.media_type)
            if mt = "movie" or mt = "series" then recs.Push(r)
        end for
    end if
    sig = FormatJson(recs)
    if sig <> m.moreSig then
        m.moreSig = sig
        m.recommendations = recs
        if recs.Count() > 0 then
            cards = []
            for each r in recs
                cards.Push(Req_card("result", r, "more"))
            end for
            m.moreRow.content = Content_rows([{ id: "more", title: "", style: "poster", items: cards }], 32)
        end if
    end if
    m.moreSection.visible = recs.Count() > 0
    m.moreTop = top + 64
    m.moreSection.translation = [0, m.moreTop]
    if not m.moreSection.visible and m.focusZone = "more" then m.focusZone = "actions"
end sub

sub onBackdropStatus()
    if m.backdrop.loadStatus = "ready" then m.backdrop.opacity = 1
end sub

' ---------- Focus ----------

sub restoreFocus()
    if m.errorGroup.visible then
        m.errorRetry.setFocus(true)
        return
    end if
    if m.detail = invalid then
        m.top.setFocus(true)
        return
    end if
    if m.focusZone = "more" and m.moreSection.visible then
        m.moreRow.setFocus(true)
        scrollTo(-(m.moreTop - 300))
    else
        m.focusZone = "actions"
        if m.actionButtons = invalid or m.actionButtons.Count() = 0 then return
        if m.actionIndex < 0 then m.actionIndex = 0
        m.actionButtons[m.actionIndex].setFocus(true)
        scrollTo(0)
    end if
end sub

sub scrollTo(y as integer)
    cur = m.page.translation
    if cur[1] = y then return
    m.scrollAnim.control = "stop"
    m.scrollInterp.keyValue = [cur, [0, y]]
    m.scrollAnim.control = "start"
end sub

' ---------- Actions ----------

sub onPrimary()
    action = m.primaryAction
    if action = invalid then return
    if action.kind = "request" then
        submitRequest()
    else if action.kind = "open" then
        Nav_openItem(action.contentId, m.mediaType)
    end if
    ' Presses on a status do nothing.
end sub

' One press, no confirmation: the button is the confirmation.
sub submitRequest()
    d = m.detail
    if d = invalid or m.isSubmitting then return
    body = {
        media_type: Str_orEmpty(d.media_type)
        tmdb_id: d.tmdb_id
        imdb_id: Str_orEmpty(d.imdb_id)
        title: Str_orEmpty(d.title)
        overview: Str_orEmpty(d.overview)
    }
    if d.tvdb_id <> invalid then body.tvdb_id = d.tvdb_id
    if d.year <> invalid then body.year = d.year
    if not Str_isEmpty(d.poster_path) then body.poster_path = d.poster_path
    if not Str_isEmpty(d.backdrop_path) then body.backdrop_path = d.backdrop_path
    m.isSubmitting = true
    m.actionErrorText = ""
    render()
    Api_send("POST", "/api/v2/requests", body, "onSubmitted")
end sub

sub onSubmitted(event as object)
    resp = Api_result(event)
    if resp.ok and resp.data <> invalid then
        ' The server's answer stands even if the re-read fails.
        applyOwn(resp.data)
        m.global.homeDirty = true
        fetch()
        return
    end if
    m.isSubmitting = false
    if Req_isUncertain(resp) then
        ' Never resend: hold the action until a read shows the request.
        m.submissionUnconfirmed = true
        m.actionErrorText = "We couldn't confirm the request. Check My Requests before trying again."
        m.global.homeDirty = true
        render()
        fetch()
        return
    end if
    m.actionErrorText = Req_failureText(resp, "Failed to submit request")
    render()
end sub

' The page as the server's answer to the user's own create or cancel leaves it.
sub applyOwn(rec as object)
    m.record = rec
    if m.detail = invalid then return
    d = AA_copy(m.detail)
    oc = Str_orEmpty(rec.outcome)
    if oc = "cancelled" then
        d.request = { requestable: true }
    else if oc = "declined" or oc = "failed" then
        d.request = { status: rec.status, state: rec.state, requestable: true, request_id: rec.id }
    else
        d.request = { status: rec.status, state: rec.state, requestable: false, request_id: rec.id }
    end if
    m.detail = d
end sub

sub onCancel()
    if not canCancel() then return
    m.isCancelling = true
    m.actionErrorText = ""
    render()
    Api_send("POST", "/api/v2/requests/" + Str_urlEncode(Str_orEmpty(m.record.id)) + "/cancel", {}, "onCancelled")
end sub

sub onCancelled(event as object)
    resp = Api_result(event)
    if resp.ok and resp.data <> invalid then
        applyOwn(resp.data)
        m.global.homeDirty = true
        fetch()
        return
    end if
    m.isCancelling = false
    if Req_isUncertain(resp) then
        m.cancelUnconfirmed = true
        m.actionErrorText = "We couldn't confirm the cancellation. Refresh your requests to check it."
        render()
        fetch()
        return
    end if
    m.actionErrorText = Req_failureText(resp, "Couldn't cancel the request")
    render()
end sub

' "More like this": the same routing rule as every request card.
sub onMoreSelected()
    sel = m.moreRow.rowItemSelected
    if sel = invalid or sel.Count() < 2 or sel[1] >= m.recommendations.Count() then return
    r = m.recommendations[sel[1]]
    mt = Str_orEmpty(r.media_type)
    cid = Req_libraryItemToOpen(Req_displayOfAnnotation(r.availability, r.request), r.library_content_id)
    if cid <> "" then
        Nav_openItem(cid, mt)
    else
        Nav_push("RequestDetailScreen", { mediaType: mt, tmdbId: r.tmdb_id, title: Str_orEmpty(r.title) })
    end if
end sub

' ---------- Keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.detail = invalid then return false
    if m.focusZone = "more" then
        if key = "up" then
            m.focusZone = "actions"
            restoreFocus()
            return true
        end if
        return false
    end if
    if key = "left" then
        if m.actionIndex > 0 then
            m.actionIndex = m.actionIndex - 1
            restoreFocus()
        end if
        return true
    else if key = "right" then
        if m.actionIndex < m.actionButtons.Count() - 1 then
            m.actionIndex = m.actionIndex + 1
            restoreFocus()
        end if
        return true
    else if key = "down" then
        if m.moreSection.visible then
            m.focusZone = "more"
            restoreFocus()
        end if
        return true
    else if key = "up" then
        return true
    end if
    return false
end function
