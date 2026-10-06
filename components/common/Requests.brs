' Media requests: presentation rules shared by RequestsPage, RequestDetailScreen and SearchScreen.
' Ports the Android TV client's shared request model (RequestDisplayState, RequestProgress,
' RequestRowCopy, RequestCarouselMerge, RequestRouter) so every surface agrees on a request's state.
' Needs Utils.brs. Pure functions except Req_gate*, which read/write m.global.requests.
' SPDX-License-Identifier: AGPL-3.0-or-later

' ---------- Feature gate (m.global.requests) ----------
' {enabled, canModerate, resolved}. enabled = requests_enabled and allowed and state "available"
' (GET /api/v2/requests/status); canModerate = GET /api/v2/admin/requests/capabilities → available.

function Req_gate() as object
    if m.global.hasField("requests") then
        g = m.global.requests
        if g <> invalid then return g
    end if
    return { enabled: false, canModerate: false, resolved: false }
end function

sub Req_setGate(g as object)
    if not m.global.hasField("requests") then m.global.addFields({ requests: {} })
    m.global.requests = g
end sub

function Req_statusAvailable(data as dynamic) as boolean
    if data = invalid then return false
    return data.requests_enabled = true and data.allowed = true and Str_orEmpty(data.state) = "available"
end function

' ---------- Display state (RequestDisplayState) ----------
' {kind: "pending"|"ontheway"|"inlibrary"|"attention"|"unavailable", attention: "declined"|"failed"|"", reason}

function Req_display(kind as string, attention = "" as string, reason = "" as dynamic) as object
    return { kind: kind, attention: attention, reason: Str_orEmpty(reason) }
end function

' From a full request record.
function Req_displayOfRecord(rec as object) as object
    st = Str_orEmpty(rec.state)
    oc = Str_orEmpty(rec.outcome)
    closed = st = "declined" or st = "cancelled" or (st = "" and (oc = "declined" or oc = "cancelled"))
    reason = Str_orEmpty(rec.outcome_reason)
    if not closed and not Str_isEmpty(rec.last_error) then reason = rec.last_error
    return Req_displayOf(st, Str_orEmpty(rec.status), oc, reason)
end function

function Req_displayOf(state as string, status as string, outcome as string, reason as string) as object
    d = Req_fromUserState(state, reason)
    if d <> invalid then return d
    return Req_fromStatus(status, outcome, reason)
end function

' From a search/discover/detail annotation; invalid when the title is requestable and never requested.
function Req_displayOfAnnotation(availability as dynamic, request as dynamic) as dynamic
    rq = request
    if rq = invalid then rq = {}
    d = Req_fromUserState(Str_orEmpty(rq.state), "")
    if d <> invalid then return d
    if Str_orEmpty(availability) = "available" then return Req_display("inlibrary")
    if not Str_isEmpty(rq.status) then return Req_fromStatus(rq.status, "active", "")
    if rq.requestable = true then return invalid
    return Req_display("unavailable", "", Str_orEmpty(rq.reason))
end function

function Req_fromUserState(state as string, reason as string) as dynamic
    if state = "pending" then return Req_display("pending")
    if state = "approved" or state = "processing" or state = "partially_available" then return Req_display("ontheway")
    if state = "available" then return Req_display("inlibrary")
    if state = "declined" then return Req_display("attention", "declined", reason)
    if state = "failed" then return Req_display("attention", "failed", reason)
    if state = "cancelled" then return Req_display("unavailable", "", reason)
    return invalid
end function

function Req_fromStatus(status as string, outcome as string, reason as string) as object
    if outcome = "declined" then return Req_display("attention", "declined", reason)
    if outcome = "failed" then return Req_display("attention", "failed", reason)
    if outcome = "cancelled" then return Req_display("unavailable", "", reason)
    if status = "pending" then return Req_display("pending")
    if status = "completed" then return Req_display("inlibrary")
    if status = "failed" then return Req_display("attention", "failed", reason)
    return Req_display("ontheway")
end function

function Req_label(d as object) as string
    k = d.kind
    if k = "pending" then return "Pending"
    if k = "ontheway" then return "On the way"
    if k = "inlibrary" then return "In library"
    if k = "attention" then return "Needs attention"
    return "Unavailable"
end function

function Req_attentionTitle(d as object) as string
    if d.attention = "declined" then return "Declined"
    return "Request failed"
end function

' The detail page's status line.
function Req_detailTitle(d as object) as string
    k = d.kind
    if k = "pending" then return "Requested · Pending"
    if k = "ontheway" then return "On the way"
    if k = "inlibrary" then return "In your library"
    if k = "attention" then
        copy = Req_reasonCopy(d.reason)
        if copy <> "" then return Req_attentionTitle(d) + " · " + copy
        return Req_attentionTitle(d)
    end if
    copy = Req_reasonCopy(d.reason)
    if copy <> "" then return copy
    return "Unavailable"
end function

' Status colors (RequestColors): amber, sky, emerald, rose; neutral = secondary text.
function Req_tint(d as object) as string
    k = d.kind
    if k = "pending" then return "0xF59E0BFF"
    if k = "ontheway" then return "0x38BDF8FF"
    if k = "inlibrary" then return "0x34D399FF"
    if k = "attention" then return "0xFB7185FF"
    return "0xEDEDEDB3"
end function

' The catalog item to open instead of the request: only "In library" with a known item.
function Req_libraryItemToOpen(d as dynamic, contentId as dynamic) as string
    if d = invalid then return ""
    if d.kind <> "inlibrary" then return ""
    return Str_orEmpty(contentId)
end function

' ---------- Progress (RequestProgress) ----------
' {display, completed (0..4), current (0..3, -1 = none), short, long, tint}
' Steps: 0 Requested, 1 Approved, 2 Downloading, 3 In your library.

function Req_steps() as object
    return ["Requested", "Approved", "Downloading", "In your library"]
end function

function Req_progress(d as object, state as string, status as string) as object
    k = d.kind
    if k = "pending" then return Req_mkProgress(d, 1, 1, "Pending", "Waiting for approval")
    if k = "ontheway" then
        if state = "partially_available" then return Req_mkProgress(d, 3, 3, "Partly in library", "Partly in your library")
        if status = "downloading" then return Req_mkProgress(d, 2, 2, "Downloading", "Downloading")
        if status = "completed" then return Req_mkProgress(d, 3, 3, "Adding to library", "Adding to your library")
        if status = "approved" or status = "queued" then return Req_mkProgress(d, 2, 2, "Queued", "Queued for download")
        return Req_mkProgress(d, 2, 2, "On the way", "On the way")
    end if
    if k = "inlibrary" then return Req_mkProgress(d, 4, -1, "In library", "In your library")
    if k = "attention" then
        if d.attention = "declined" then return Req_mkProgress(d, 1, 1, "Declined", "Declined")
        return Req_mkProgress(d, 2, 2, "Failed", "Request failed")
    end if
    return Req_mkProgress(d, 0, -1, Req_label(d), Req_detailTitle(d))
end function

function Req_mkProgress(d as object, completed as integer, current as integer, shortLabel as string, longLabel as string) as object
    return { display: d, completed: completed, current: current, short: shortLabel, long: longLabel, tint: Req_tint(d) }
end function

function Req_progressOfRecord(rec as object) as object
    return Req_progress(Req_displayOfRecord(rec), Str_orEmpty(rec.state), Str_orEmpty(rec.status))
end function

function Req_progressOfAnnotation(availability as dynamic, request as dynamic) as dynamic
    d = Req_displayOfAnnotation(availability, request)
    if d = invalid then return invalid
    rq = request
    if rq = invalid then rq = {}
    return Req_progress(d, Str_orEmpty(rq.state), Str_orEmpty(rq.status))
end function

' ---------- Copy ----------

function Req_reasonCopy(token as dynamic) as string
    v = Str_orEmpty(token).Trim()
    if v = "" then return ""
    if v = "already_requested" then return "Already requested"
    if v = "already_available" then return "Already in your library"
    if v = "quota_exceeded" or v = "limit_reached" then return "Request limit reached"
    if v = "requests_disabled" then return "Requests are turned off"
    if v = "blocked" or v = "requesting_blocked" then return "You can't request media right now"
    if v = "validation_failed" then return "That request couldn't be submitted"
    if v = "invalid_state" then return "This request can no longer be changed"
    if v = "not_found" then return "This title is no longer available"
    if v = "request_unconfirmed" then return "Not confirmed yet"
    ' An unknown code ([a-z0-9_]+) shows nothing; a server sentence shows as written.
    re = CreateObject("roRegex", "^[a-z0-9_]+$", "")
    if re.IsMatch(v) then return ""
    return UCase(Left(v, 1)) + Mid(v, 2)
end function

function Req_mediaTypeLabel(mt as dynamic) as string
    v = Str_orEmpty(mt)
    if v = "movie" then return "Movie"
    if v = "series" then return "Series"
    return "Title"
end function

' "1080p downloading · 4K queued" for multi-target requests; "" otherwise.
function Req_targetSummary(targets as dynamic) as string
    list = Arr_or(targets)
    if list.Count() <= 1 then return ""
    parts = []
    for each tg in list
        q = Str_orEmpty(tg.quality)
        st = Str_orEmpty(tg.status)
        word = ""
        if st = "completed" then
            word = "done"
        else if st = "downloading" then
            word = "downloading"
        else if st = "queued" or st = "approved" then
            word = "queued"
        else if st = "pending" then
            word = "pending"
        else if st = "failed" then
            word = "failed"
        end if
        if q <> "" and word <> "" then parts.Push(q + " " + word)
    end for
    return Str_joinDots(parts)
end function

function Req_qualities(targets as dynamic) as string
    parts = []
    for each tg in Arr_or(targets)
        if not Str_isEmpty(tg.quality) then parts.Push(tg.quality)
    end for
    return Str_joinDots(parts)
end function

' The status sentence under the stage track (RequestRowCopy.status).
function Req_statusLine(rec as object, p as object) as string
    d = p.display
    if d.kind = "attention" then
        copy = Req_reasonCopy(d.reason)
        if copy <> "" then return p.long + " · " + copy
    end if
    if d.kind = "ontheway" then
        s = Req_targetSummary(rec.targets)
        if s <> "" then return p.long + " · " + s
    end if
    return p.long
end function

' "Sep 24" in local time, or "" when unreadable.
function Req_day(ts as dynamic) as string
    d = Time_parseIso(ts)
    if d = invalid then return ""
    d.ToLocalTime()
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    mo = d.GetMonth()
    if mo < 1 or mo > 12 then return ""
    return months[mo - 1] + " " + d.GetDayOfMonth().ToStr()
end function

' "TMDB 7.9" for a vote average, "" when absent.
function Req_tmdbRating(v as dynamic) as string
    if v = invalid then return ""
    f = v * 1.0
    if f <= 0 then return ""
    tenths = Int(f * 10 + 0.5)
    return "TMDB " + Int(tenths / 10).ToStr() + "." + (tenths mod 10).ToStr()
end function

' Copy for a failed mutation (RequestActionCopy.failure).
function Req_failureText(resp as object, fallback as string) as string
    if resp = invalid or resp.error = invalid then return fallback
    code = Str_orEmpty(resp.error.code)
    if code = "validation_failed" then return "That request couldn't be submitted"
    if code = "capability_disabled" or code = "capability_not_configured" or code = "capability_unsupported" then return "Requests are turned off"
    if resp.status = 0 then return "Can't reach the server. Check your connection and try again."
    if not Str_isEmpty(resp.error.detail) then return resp.error.detail
    if not Str_isEmpty(resp.error.title) then return resp.error.title
    return fallback
end function

' A mutation sent without a usable answer (transport failure or timeout): never resend it.
function Req_isUncertain(resp as object) as boolean
    if resp = invalid then return true
    return resp.status = 0 or resp.status = 408 or resp.status >= 500
end function

' ---------- Images ----------

function Req_imageUrl(path as dynamic, size as string) as string
    v = Str_orEmpty(path)
    if v = "" then return ""
    if Left(v, 7) = "http://" or Left(v, 8) = "https://" then return v
    if Left(v, 1) = "/" then return "https://image.tmdb.org/t/p/" + size + v
    return v
end function

function Req_posterUrl(path as dynamic) as string
    return Req_imageUrl(path, "w500")
end function

function Req_backdropUrl(path as dynamic) as string
    return Req_imageUrl(path, "w780")
end function

' ---------- Lists ----------

function Req_isSupportedType(mt as dynamic) as boolean
    v = LCase(Str_orEmpty(mt).Trim())
    return v = "movie" or v = "series" or v = "audiobook" or v = "audiobooks"
end function

' RFC 3339 sort key: pads the fraction so instants compare as text.
function Req_instantKey(ts as dynamic) as string
    v = Str_orEmpty(ts)
    re = CreateObject("roRegex", "^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?Z$", "")
    parts = re.Match(v)
    if parts.Count() < 2 then return v
    frac = ""
    if parts.Count() > 2 then frac = Str_orEmpty(parts[2])
    while Len(frac) < 9
        frac = frac + "0"
    end while
    return parts[1] + "." + frac + "Z"
end function

' Sorts records by a timestamp field (newest first when descending).
function Req_sortByTime(records as object, field as string, descending as boolean) as object
    wrapped = []
    for each r in records
        wrapped.Push({ k: Req_instantKey(r[field]), r: r })
    end for
    if descending then
        wrapped.SortBy("k", "r")
    else
        wrapped.SortBy("k")
    end if
    out = []
    for each w in wrapped
        out.Push(w.r)
    end for
    return out
end function

' My Requests order (MyRequestsBucket): in motion, needs you, available; newest first in each;
' cancelled requests drop off.
function Req_bucketMine(records as object) as object
    inMotion = []
    attention = []
    landed = []
    for each r in records
        if Req_isSupportedType(r.media_type) then
            k = Req_displayOfRecord(r).kind
            if k = "pending" or k = "ontheway" then
                inMotion.Push(r)
            else if k = "attention" then
                attention.Push(r)
            else if k = "inlibrary" then
                landed.Push(r)
            end if
        end if
    end for
    out = []
    out.Append(Req_sortByTime(inMotion, "created_at", true))
    out.Append(Req_sortByTime(attention, "created_at", true))
    out.Append(Req_sortByTime(landed, "created_at", true))
    return out
end function

' The newest active request for a title, otherwise the newest unless it was cancelled.
function Req_currentRecord(records as object) as dynamic
    active = []
    for each r in records
        if Str_orEmpty(r.outcome) = "active" then active.Push(r)
    end for
    if active.Count() > 0 then
        sortedActive = Req_sortByTime(active, "created_at", true)
        return sortedActive[0]
    end if
    if records.Count() = 0 then return invalid
    sortedRecords = Req_sortByTime(records, "created_at", true)
    newest = sortedRecords[0]
    if Str_orEmpty(newest.outcome) = "cancelled" then return invalid
    return newest
end function

' Merges the server's per-media-type discover sections into "Trending now" and "Crowd favorites",
' movies and series interleaved and deduped (RequestCarouselMerge). Other sections are dropped.
function Req_mergeDiscover(sections as object) as object
    out = []
    pairs = [
        { key: "trending", title: "Trending now", movies: "trending_movies", series: "trending_series" },
        { key: "popular", title: "Crowd favorites", movies: "popular_movies", series: "popular_series" }
    ]
    for each pr in pairs
        mv = []
        sr = []
        for each s in sections
            if Str_orEmpty(s.key) = pr.movies then mv = Arr_or(s.results)
            if Str_orEmpty(s.key) = pr.series then sr = Arr_or(s.results)
        end for
        merged = []
        seen = {}
        n = mv.Count()
        if sr.Count() > n then n = sr.Count()
        for i = 0 to n - 1
            if i < mv.Count() then Req_pushUnique(merged, seen, mv[i])
            if i < sr.Count() then Req_pushUnique(merged, seen, sr[i])
        end for
        filtered = []
        for each it in merged
            if Req_isSupportedType(it.media_type) then filtered.Push(it)
        end for
        if filtered.Count() > 0 then out.Push({ key: pr.key, title: pr.title, results: filtered })
    end for
    return out
end function

sub Req_pushUnique(list as object, seen as object, item as object)
    k = Str_orEmpty(item.media_type) + ":" + Str_orEmpty(item.tmdb_id)
    if seen.DoesExist(k) then return
    seen[k] = true
    list.Push(item)
end sub

' ---------- Cards ----------
' Builds a card AA for MediaCardItem rows (Content_cardNode reads title/year/poster_url/backdrop_url).
' kind: "record" (the user's own request), "approval" (someone's, for an admin), "result" (TMDB title).
function Req_card(kind as string, data as object, rowId as string) as object
    if kind = "result" then
        key = "tmdb:" + Str_orEmpty(data.media_type) + ":" + Str_orEmpty(data.tmdb_id)
    else
        key = "request:" + Str_orEmpty(data.id)
    end if
    card = {
        content_id: rowId + "|" + key
        type: "request"
        title: Str_orEmpty(data.title)
        poster_url: Req_posterUrl(data.poster_path)
        backdrop_url: Req_backdropUrl(data.backdrop_path)
        req_kind: kind
        req: data
    }
    if kind = "result" then
        if data.year <> invalid and data.year > 0 then card.year = data.year
    else
        ' A request card's caption is its status.
        card.year = Req_progressOfRecord(data).short
    end if
    return card
end function
