' SPDX-License-Identifier: AGPL-3.0-or-later
' One counter for "the user's data changed" (watched, progress, favorites, watchlist, settings).
' Writers keep setting m.global.homeDirty = true. The first reader folds that flag into
' m.global.dataRevision and clears it, and every page compares the counter with the revision it
' last loaded. A single boolean that only Home cleared made For You and the detail pages refetch on
' every show until Home was visited, and library Recommended pages never refresh.

function DataRev_current() as integer
    g = m.global
    if not g.hasField("dataRevision") then g.addFields({ dataRevision: 0 })
    if g.homeDirty = true then
        g.dataRevision = g.dataRevision + 1
        g.homeDirty = false
    end if
    return g.dataRevision
end function
