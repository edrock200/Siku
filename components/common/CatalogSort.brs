' SPDX-License-Identifier: AGPL-3.0-or-later
'
' Library sort options that match Silo's web client (Silo Android #843, CatalogSortField /
' CatalogSortRelevance; silo-roku d4303e5 does the same): one shared list with the web's names,
' order and default directions, and the rules for which options a sort list shows.
'   - A library lists the fields that order its media (a series library gains Latest Episode Added
'     and Latest Episode Air Date; a mixed library with no side picked lists only the fields that
'     order movies, series and episodes alike).
'   - Favorites, Watchlist and library collections leave out the per-viewer sorts (Progress, Date
'     Viewed, Plays), as Android TV does.
'   - The Rotten Tomatoes sorts appear only while the server shows that rating source
'     (GET /api/v2/capabilities/ratings, kept on m.global.ratingSources per server and profile).
'   - The field a list is sorted by now is always listed, so a restored sort stays visible.
' Pure functions apart from the m.global cache at the end; host-tested in tests/test_catalog_sort.py.

' Media scopes as AA keys: movie, series, episode, audiobook, ebook, manga.
function CatalogSort_scopes(names as object) as object
    s = {}
    for each n in names
        s[n] = true
    end for
    return s
end function

' The fields in the web client's order (silo-server web/src/lib/querySortOptions.ts). style names the
' direction words: alpha (A–Z / Z–A), chrono (Oldest / Newest), length (Shortest / Longest),
' magnitude (Lowest / Highest), count (Fewest / Most).
function CatalogSort_fields() as object
    media = ["movie", "series", "episode", "audiobook", "ebook"]
    mediaManga = ["movie", "series", "episode", "audiobook", "ebook", "manga"]
    video = ["movie", "series", "episode"]
    f = []
    f.Push(CatalogSort_field("title", false, false, mediaManga, "alpha", ""))
    f.Push(CatalogSort_field("added_at", true, false, mediaManga, "chrono", ""))
    f.Push(CatalogSort_field("release_date", true, false, mediaManga, "chrono", ""))
    f.Push(CatalogSort_field("last_air_date", true, false, ["series", "episode"], "chrono", ""))
    f.Push(CatalogSort_field("latest_episode_added", true, false, ["series"], "chrono", ""))
    f.Push(CatalogSort_field("year", true, false, mediaManga, "chrono", ""))
    f.Push(CatalogSort_field("content_rating", false, false, video, "alpha", ""))
    f.Push(CatalogSort_field("runtime", true, false, media, "length", ""))
    f.Push(CatalogSort_field("rating_imdb", true, false, video, "magnitude", ""))
    f.Push(CatalogSort_field("rating_tmdb", true, false, video, "magnitude", ""))
    f.Push(CatalogSort_field("rating_rt_critic", true, false, video, "magnitude", "rt_critic"))
    f.Push(CatalogSort_field("rating_rt_audience", true, false, video, "magnitude", "rt_audience"))
    f.Push(CatalogSort_field("resolution", true, false, video, "magnitude", ""))
    f.Push(CatalogSort_field("bitrate", true, false, media, "magnitude", ""))
    f.Push(CatalogSort_field("progress", true, true, mediaManga, "magnitude", ""))
    f.Push(CatalogSort_field("date_viewed", true, true, mediaManga, "chrono", ""))
    f.Push(CatalogSort_field("plays", true, true, mediaManga, "count", ""))
    f.Push(CatalogSort_field("author", false, false, ["audiobook", "ebook", "manga"], "alpha", ""))
    f.Push(CatalogSort_field("narrator", false, false, ["audiobook"], "alpha", ""))
    f.Push(CatalogSort_field("series", false, false, ["audiobook", "ebook"], "alpha", ""))
    return f
end function

function CatalogSort_field(id as string, defaultDesc as boolean, personalized as boolean, scopes as object, style as string, ratingSource as string) as object
    return { id: id, defaultDesc: defaultDesc, personalized: personalized, scopes: CatalogSort_scopes(scopes), style: style, ratingSource: ratingSource }
end function

' The canonical field for a sort value, or "" for one this client does not know. Legacy aliases map
' as the web client maps them.
function CatalogSort_canonical(value as dynamic) as string
    v = LCase(Str_orEmpty(value).Trim())
    if Left(v, 1) = "-" then v = Mid(v, 2)
    if v = "sort_title" then v = "title"
    if v = "recently_added" then v = "added_at"
    if v = "rating" then v = "rating_imdb"
    for each fd in CatalogSort_fields()
        if fd.id = v then return v
    end for
    return ""
end function

function CatalogSort_find(id as string) as dynamic
    for each fd in CatalogSort_fields()
        if fd.id = id then return fd
    end for
    return invalid
end function

' The relevance of a library's sort list from Siku's library mode (Library_mode) and a mixed
' library's Movies / Series side: "movie", "series", "audiobook", "ebook" (one scope), "video" (a
' mixed library with no side) or "any" (every field). Music and podcast libraries read as "video",
' as CatalogSortRelevance.forLibrary does for a type it does not know.
function CatalogSort_relevance(mode as dynamic, mediaType as dynamic) as string
    md = LCase(Str_orEmpty(mode))
    if md = "movies" then return "movie"
    if md = "series" then return "series"
    if md = "audiobooks" then return "audiobook"
    if md = "reading" then return "ebook"
    mt = LCase(Str_orEmpty(mediaType))
    if mt = "movie" then return "movie"
    if mt = "series" then return "series"
    return "video"
end function

function CatalogSort_appliesTo(fd as object, relevance as string) as boolean
    if relevance = "any" then return true
    if relevance = "video" then return fd.scopes.movie = true and fd.scopes.series = true and fd.scopes.episode = true
    return fd.scopes[relevance] = true
end function

' The fields one sort list offers, in display order: [{id, label, defaultDesc}]. shown is the
' server's shown rating sources (an array of names); keep, the field sorted by now, is always listed.
function CatalogSort_options(relevance as string, includePersonalized as boolean, shown as dynamic, keep as dynamic) as object
    keepId = CatalogSort_canonical(keep)
    shownSet = {}
    if Type(shown) = "roArray" then
        for each s in shown
            shownSet[Str_orEmpty(s)] = true
        end for
    end if
    out = []
    for each fd in CatalogSort_fields()
        ok = fd.id = keepId
        if not ok then
            ok = (includePersonalized or not fd.personalized) and CatalogSort_appliesTo(fd, relevance)
            if ok and fd.ratingSource <> "" then ok = shownSet[fd.ratingSource] = true
        end if
        if ok then out.Push({ id: fd.id, label: CatalogSort_label(fd.id, relevance), defaultDesc: fd.defaultDesc })
    end for
    return out
end function

' A field's name in a sort list. Ebook and manga lists call Date Viewed and Plays "Date Read" and
' "Reads", as the web client does.
function CatalogSort_label(id as string, relevance as string) as string
    reading = relevance = "ebook" or relevance = "manga"
    if id = "title" then return Tx("Title")
    if id = "added_at" then return Tx("Date Added")
    if id = "release_date" then return Tx("Release Date")
    if id = "last_air_date" then return Tx("Latest Episode Air Date")
    if id = "latest_episode_added" then return Tx("Latest Episode Added")
    if id = "year" then return Tx("Year")
    if id = "content_rating" then return Tx("Content Rating")
    if id = "runtime" then return Tx("Duration")
    if id = "rating_imdb" then return Tx("IMDb Rating")
    if id = "rating_tmdb" then return Tx("TMDB Rating")
    if id = "rating_rt_critic" then return Tx("RT Critic Rating")
    if id = "rating_rt_audience" then return Tx("RT Audience Rating")
    if id = "resolution" then return Tx("Resolution")
    if id = "bitrate" then return Tx("Bitrate")
    if id = "progress" then return Tx("Progress")
    if id = "date_viewed" then
        if reading then return Tx("Date Read")
        return Tx("Date Viewed")
    end if
    if id = "plays" then
        if reading then return Tx("Reads")
        return Tx("Plays")
    end if
    if id = "author" then return Tx("Author")
    if id = "narrator" then return Tx("Narrator")
    if id = "series" then return Tx("Series")
    return id
end function

' The direction word for a field ("A–Z", "Newest", "Most", ...); "" for an unknown field.
function CatalogSort_directionLabel(id as string, desc as boolean) as string
    fd = CatalogSort_find(id)
    if fd = invalid then return ""
    if fd.style = "alpha" then
        if desc then return "Z–A"
        return "A–Z"
    else if fd.style = "length" then
        if desc then return Tx("Longest")
        return Tx("Shortest")
    else if fd.style = "magnitude" then
        if desc then return Tx("Highest")
        return Tx("Lowest")
    else if fd.style = "count" then
        if desc then return Tx("Most")
        return Tx("Fewest")
    end if
    if desc then return Tx("Newest")
    return Tx("Oldest")
end function

' The shown rating sources in a GET /api/v2/capabilities/ratings answer: the `source` names while
' its state is "available", else none.
function CatalogSort_parseRatings(data as dynamic) as object
    out = []
    if Type(data) <> "roAssociativeArray" then return out
    if LCase(Str_orEmpty(data.state)) <> "available" then return out
    srcs = data.sources
    if Type(srcs) <> "roArray" then return out
    for each s in srcs
        if Type(s) = "roAssociativeArray" then
            name = LCase(Str_orEmpty(s.source))
            if name <> "" then out.Push(name)
        end if
    end for
    return out
end function

' ---------- The server's shown rating sources (m.global.ratingSources) ----------
' { owner: "<server>|<profile>", sources: [...] }, read once per server and profile.

function CatalogSort_owner() as string
    s = m.global.session
    if s = invalid then return ""
    return Str_orEmpty(s.serverUrl) + "|" + Str_orEmpty(s.profileId)
end function

' The cached sources for the active profile, or invalid while they have not been read.
function CatalogSort_cachedSources() as dynamic
    if not m.global.hasField("ratingSources") then return invalid
    c = m.global.ratingSources
    if c = invalid or Str_orEmpty(c.owner) <> CatalogSort_owner() then return invalid
    if Type(c.sources) <> "roArray" then return invalid
    return c.sources
end function

' Reads the capability unless this profile's answer is cached; the answer goes to callback.
function CatalogSort_requestSources(callback as string) as boolean
    if CatalogSort_cachedSources() <> invalid then return false
    Api_call({ method: "GET", path: "/api/v2/capabilities/ratings", timeout: 5, context: { owner: CatalogSort_owner() } }, callback)
    return true
end function

' Stores an answer from CatalogSort_requestSources; the sources, or invalid when it no longer applies.
' A failed read caches nothing shown (the RT sorts stay hidden) and is not retried this session.
function CatalogSort_storeSources(resp as object) as dynamic
    owner = ""
    if resp.context <> invalid then owner = Str_orEmpty(resp.context.owner)
    if owner = "" or owner <> CatalogSort_owner() then return invalid
    sources = []
    if resp.ok then
        sources = CatalogSort_parseRatings(resp.data)
        print "[siku-library] rating sources shown=" + Str_joinDots(sources, ",")
    else
        print "[siku-library] rating sources read failed status=" + Str_orEmpty(resp.status) + "; Rotten Tomatoes sorts hidden"
    end if
    if not m.global.hasField("ratingSources") then m.global.addFields({ ratingSources: {} })
    m.global.ratingSources = { owner: owner, sources: sources }
    return sources
end function
