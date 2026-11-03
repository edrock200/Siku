' Movie box sets (Silo Android #646): the movies TMDB lists in one collection (a franchise such as
' Harry Potter) that the viewer can see in one library (GET /api/v2/user/libraries
' `box_sets_enabled: true`). Library grids no longer group them (Silo Android #796: the server
' answers `group=box_set` with 422); a "box_set" card carrying `box_set` {id, library_id, title,
' overview, poster_url, backdrop_url, movie_count, played_count, first_year, last_year} can still
' arrive in other lists and opens BoxSetScreen (GET /api/v2/catalog/box-sets/{id}?library_id=), and Search lists the box sets
' of GET /api/v2/catalog/box-sets?q=&limit= ahead of the titles. Servers without box sets report
' no library with them on, so they are never asked. Port of shared BoxSetModels.kt; pure functions
' (host-tested in tests/test_box_sets.py).
' SPDX-License-Identifier: AGPL-3.0-or-later

' The box set a card stands for (a "box_set" card with its `box_set` object), or invalid.
function BoxSet_of(card as dynamic) as dynamic
    if Type(card) <> "roAssociativeArray" then return invalid
    if LCase(Str_orEmpty(card["type"])) <> "box_set" then return invalid
    bs = card.box_set
    if Type(bs) <> "roAssociativeArray" then return invalid
    if Str_orEmpty(bs.id) = "" then return invalid
    return bs
end function

' Some library in a GET /api/v2/user/libraries list has box sets on (a JSON true; anything else,
' or a server without the field, is off).
function BoxSet_anyEnabled(libraries as dynamic) as boolean
    for each lib in Arr_or(libraries)
        if Type(lib) = "roAssociativeArray" then
            if BoxSet_isTrue(lib.box_sets_enabled) then return true
        end if
    end for
    return false
end function

' A wire flag that is a real boolean true (skill pitfall 16: never compare invalid with a boolean).
function BoxSet_isTrue(v as dynamic) as boolean
    t = Type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function

' "8 films", or "1 film".
function BoxSet_filmCount(count as dynamic) as string
    n = Int(Num_or(count, 0))
    if n = 1 then return "1 film"
    return n.ToStr() + " films"
end function

' "2001 – 2011", one year when the box set spans one, or "" with no year.
function BoxSet_yearsLabel(bs as object) as string
    first = Int(Num_or(bs.first_year, 0))
    last = Int(Num_or(bs.last_year, 0))
    if first > 0 and last > 0 and first <> last then return first.ToStr() + " – " + last.ToStr()
    if first > 0 then return first.ToStr()
    if last > 0 then return last.ToStr()
    return ""
end function

' A card's caption: watched progress once started, else the years or the film count.
function BoxSet_cardCaption(bs as object) as string
    played = Int(Num_or(bs.played_count, 0))
    total = Int(Num_or(bs.movie_count, 0))
    if played > 0 then return played.ToStr() + " / " + total.ToStr() + " watched"
    years = BoxSet_yearsLabel(bs)
    if years <> "" then return years
    return BoxSet_filmCount(total)
end function

' The box set page's facts: "Box set", the film count, the years, and watched progress once started.
function BoxSet_heroFacts(bs as object) as object
    facts = ["Box set", BoxSet_filmCount(bs.movie_count)]
    years = BoxSet_yearsLabel(bs)
    if years <> "" then facts.Push(years)
    played = Int(Num_or(bs.played_count, 0))
    if played > 0 then facts.Push(played.ToStr() + " of " + Int(Num_or(bs.movie_count, 0)).ToStr() + " watched")
    return facts
end function

' Share of the box set's movies the profile has played (0..1), 0 before the first.
function BoxSet_watchedFraction(bs as object) as float
    played = Num_or(bs.played_count, 0)
    total = Num_or(bs.movie_count, 0)
    if played <= 0 or total <= 0 then return 0.0
    f = played / total
    if f > 1 then f = 1.0
    return f
end function

' A movie the profile has played (user_state.played, a JSON true).
function BoxSet_played(movie as dynamic) as boolean
    if Type(movie) <> "roAssociativeArray" then return false
    us = movie.user_state
    if Type(us) <> "roAssociativeArray" then return false
    return BoxSet_isTrue(us.played)
end function

' Index of the movie Play starts: the first one in collection order the profile hasn't played (an
' in-progress movie is not played yet), or the first once all are played; -1 for no movies.
function BoxSet_nextIndex(items as dynamic) as integer
    list = Arr_or(items)
    for i = 0 to list.Count() - 1
        if not BoxSet_played(list[i]) then return i
    end for
    if list.Count() > 0 then return 0
    return -1
end function

' Where that movie resumes (seconds), or 0 to start it from the beginning.
function BoxSet_resumePosition(movie as dynamic) as float
    if Type(movie) <> "roAssociativeArray" or BoxSet_played(movie) then return 0.0
    p = Num_or(movie.position_seconds, 0)
    if p <= 0 and Type(movie.user_data) = "roAssociativeArray" then p = Num_or(movie.user_data.position_seconds, 0)
    if p > 0 then return p
    return 0.0
end function

' The Play button's label for the next movie: "Continue · <title>" once the box set is started or
' that movie has a resume point, else "Play <title>".
function BoxSet_playLabel(bs as object, nextMovie as object) as string
    played = Int(Num_or(bs.played_count, 0))
    total = Int(Num_or(bs.movie_count, 0))
    started = played >= 1 and played < total
    title = Str_orEmpty(nextMovie.title)
    if started or BoxSet_resumePosition(nextMovie) > 0 then return "Continue · " + title
    return "Play " + title
end function

' A search result's box set as a grid card. Search can return one collection from two libraries,
' so the card's content id names the library too.
function BoxSet_searchCard(bs as object) as object
    return {
        "content_id": "box_set:" + Str_orEmpty(bs.library_id) + ":" + Str_orEmpty(bs.id)
        "type": "box_set"
        "title": Str_orEmpty(bs.title)
        "overview": bs.overview
        "poster_url": bs.poster_url
        "backdrop_url": bs.backdrop_url
        "box_set": bs
    }
end function

' The box set search's answer ({items: [CatalogBoxSet]}) as grid cards, best match first, skipping
' rows without an id.
function BoxSet_searchCards(data as dynamic) as object
    out = []
    if Type(data) <> "roAssociativeArray" then return out
    for each bs in Arr_or(data.items)
        if Type(bs) = "roAssociativeArray" and Str_orEmpty(bs.id) <> "" then out.Push(BoxSet_searchCard(bs))
    end for
    return out
end function

' BoxSetScreen params for a box set: its id and library (the browsing library when the card
' carries none).
function BoxSet_screenParams(bs as object, fallbackLibraryId as dynamic) as object
    lib = Str_orEmpty(bs.library_id)
    if lib = "" then lib = Str_orEmpty(fallbackLibraryId)
    return { "boxSetId": Str_orEmpty(bs.id), "libraryId": lib, "title": Str_orEmpty(bs.title) }
end function

' A movie with its watched mark changed: a watched mutation clears resume progress too
' (BrowseItem.withWatched).
function BoxSet_withWatched(movie as object, watched as boolean) as object
    out = AA_copy(movie)
    us = {}
    if Type(movie.user_state) = "roAssociativeArray" then us = AA_copy(movie.user_state)
    us["played"] = watched
    out["user_state"] = us
    out["position_seconds"] = 0
    return out
end function

' How many of the movies are played.
function BoxSet_playedCount(items as dynamic) as integer
    n = 0
    for each it in Arr_or(items)
        if BoxSet_played(it) then n = n + 1
    end for
    return n
end function

' A box set read ({box set fields..., items}) with the watched changes it cannot show put back on it
' (BoxSetViewModel.withChangesSince). changes: {contentId: {n, watched, pending}}, numbered in the
' order the viewer made them; readStart: the newest number when the read started. A read answers
' with the state from before any change made after it started, or whose write had not landed when
' it ran, so those go back on its answer. A pending change made before the read that the answer
' already shows has landed: it settles (pending false) and is no longer put back. Returns the
' patched detail; `changes` is updated in place.
function BoxSet_withChangesSince(detail as object, changes as object, readStart as integer) as object
    items = Arr_or(detail.items)
    for each movie in items
        if Type(movie) = "roAssociativeArray" then
            id = Str_orEmpty(movie.content_id)
            ch = changes[id]
            if ch <> invalid then
                shown = BoxSet_played(movie) = BoxSet_isTrue(ch.watched)
                if BoxSet_isTrue(ch.pending) and Int(Num_or(ch.n, 0)) <= readStart and shown then ch["pending"] = false
            end if
        end if
    end for
    changed = false
    out = []
    for each movie in items
        patched = movie
        if Type(movie) = "roAssociativeArray" then
            ch = changes[Str_orEmpty(movie.content_id)]
            if ch <> invalid then
                if Int(Num_or(ch.n, 0)) > readStart or BoxSet_isTrue(ch.pending) then
                    patched = BoxSet_withWatched(movie, BoxSet_isTrue(ch.watched))
                    changed = true
                end if
            end if
        end if
        out.Push(patched)
    end for
    if not changed then return detail
    result = AA_copy(detail)
    result["items"] = out
    result["played_count"] = BoxSet_playedCount(out)
    return result
end function

' The films a movie page's box set row shows when filmSlots of its count films fit across the screen
' (boxSetRowWindow): [start, end) indexes. The row starts at the first film; when the film being
' viewed (currentIndex) falls past the slots, the window slides so the film before it leads, and
' stops at the end of the set. A film that is not in the set (-1) leaves the window at the start.
function BoxSet_rowWindow(count as integer, currentIndex as integer, filmSlots as integer) as object
    shown = filmSlots
    if shown < 0 then shown = 0
    if shown > count then shown = count
    start = 0
    if currentIndex >= shown then
        start = currentIndex - 1
        if start > count - shown then start = count - shown
        if start < 0 then start = 0
    end if
    return [start, start + shown]
end function
