' A bounded window over a paged grid (the library grid): the grid keeps one cell per item ever
' loaded, so positions and focus never move, but only a budget of pages hold their cards. Pages far
' from focus are emptied (their cells show default artwork and their data is let go) and read again
' by their own cursor when focus comes back within reach. Pure (host-tested in
' tests/test_grid_window.py); LibraryPage owns the requests and the ContentNodes.
' Idea from Silo-Server/silo-roku, AGPL-3.0 (source/catalog/grid.bs: bounded pages, cursor
' checkpoints, re-reading dropped pages when scrolled back).
'   w = { pages: [{ start, size, cursor, loaded }] }   cursor "" reads the first page
' SPDX-License-Identifier: AGPL-3.0-or-later

function GridWindow_new() as object
    return { pages: [] }
end function

' A page was appended at start with size items, read with cursor.
sub GridWindow_added(w as object, start as integer, size as integer, cursor as string)
    if size <= 0 then return
    w.pages.Push({ start: start, size: size, cursor: cursor, loaded: true })
end sub

function GridWindow_loadedCount(w as object) as integer
    n = 0
    for each p in w.pages
        if p.loaded then n = n + 1
    end for
    return n
end function

' Items between focus and the page (0 when focus is on it).
function GridWindow_distance(p as object, focus as integer) as integer
    if focus < p.start then return p.start - focus
    last = p.start + p.size - 1
    if focus > last then return focus - last
    return 0
end function

' Pages to empty so that at most maxPages stay loaded, furthest from focus first. A page within
' reach items of focus is never emptied (that would read it again at once), so the budget can be
' exceeded by the pages around focus. Marks them unloaded and returns their indices.
function GridWindow_toDrop(w as object, focus as integer, reach as integer, maxPages as integer) as object
    out = []
    if maxPages < 1 then maxPages = 1
    loaded = GridWindow_loadedCount(w)
    while loaded > maxPages
        best = -1
        bestDist = -1
        for i = 0 to w.pages.Count() - 1
            p = w.pages[i]
            if p.loaded then
                d = GridWindow_distance(p, focus)
                if d > reach and d > bestDist then
                    best = i
                    bestDist = d
                end if
            end if
        end for
        if best < 0 then exit while
        w.pages[best].loaded = false
        out.Push(best)
        loaded = loaded - 1
    end while
    return out
end function

' The emptied page to read again (the nearest to focus within reach items), or -1.
function GridWindow_toReload(w as object, focus as integer, reach as integer) as integer
    best = -1
    bestDist = -1
    for i = 0 to w.pages.Count() - 1
        p = w.pages[i]
        if not p.loaded then
            d = GridWindow_distance(p, focus)
            if d <= reach and (best < 0 or d < bestDist) then
                best = i
                bestDist = d
            end if
        end if
    end for
    return best
end function

sub GridWindow_reloaded(w as object, index as integer)
    if index >= 0 and index < w.pages.Count() then w.pages[index].loaded = true
end sub
