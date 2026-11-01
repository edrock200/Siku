' SPDX-License-Identifier: AGPL-3.0-or-later
' The library Browse filter panel's facets (Silo Android TV TvLibraryBrowseFacets.kt and the shared
' CatalogFilterState): which facets a library offers, their values, multi-select with Match all /
' any, the catalog query groups they lower to, and the saved form. Pure data (no SceneGraph), so
' tests/test_library_filters.py runs it.
'
' A selection is an AA { <facet id>: [values] } (values are strings; Watch Status holds at most one).

' The facets of a library, in Android TV's order. Server-vocabulary facets read their values from
' GET /api/v2/catalog/filters and are hidden when the server lists none; Decade, Dynamic Range and
' Watch Status have fixed values.
function LibF_facets(isAudiobook as boolean) as object
    if isAudiobook then
        return [
            LibF_def("genre", "Genre", "genres", "genre", "contains")
            LibF_def("author", "Author", "authors", "author", "is")
            LibF_def("narrator", "Narrator", "narrators", "narrator", "is")
            LibF_def("series_name", "Series", "series", "series", "is")
            LibF_def("decade", "Decade", "", "year", "between")
            LibF_def("status", "Watch Status", "", "", "is")
        ]
    end if
    return [
        LibF_def("genre", "Genre", "genres", "genre", "contains")
        LibF_def("decade", "Decade", "", "year", "between")
        LibF_def("status", "Watch Status", "", "", "is")
        LibF_def("content_rating", "Content Rating", "content_ratings", "content_rating", "is")
        LibF_def("resolution", "Resolution", "resolutions", "resolution", "is")
        LibF_def("dynamic_range", "Dynamic Range", "", "", "is")
        LibF_def("studio", "Studio", "studios", "studio", "is")
        LibF_def("network", "Network", "networks", "network", "is")
        LibF_def("country", "Country", "countries", "country", "is")
        LibF_def("audio_language", "Audio Language", "audio_languages", "audio_language", "is")
        LibF_def("subtitle_language", "Subtitle Language", "subtitle_languages", "subtitle_language", "is")
        LibF_def("original_language", "Original Language", "original_languages", "original_language", "is")
    ]
end function

function LibF_def(id as string, label as string, vocab as string, field as string, op as string) as object
    return { id: id, label: label, vocab: vocab, field: field, op: op }
end function

' The order query groups are emitted in (TvCatalogFacetSelection.toQueryGroups).
function LibF_groupOrder() as object
    return ["genre", "studio", "network", "country", "content_rating", "resolution", "audio_language", "subtitle_language", "original_language", "author", "narrator", "series_name", "decade", "dynamic_range", "status"]
end function

function LibF_watchOptions() as object
    return [
        { id: "unwatched", label: "Unwatched" }
        { id: "in_progress", label: "In Progress" }
        { id: "watched", label: "Watched" }
        { id: "favorited", label: "Favorited" }
        { id: "watchlist", label: "Watchlist" }
    ]
end function

' A server facet list: strings, or objects with value / name / label; deduplicated, in order.
function LibF_values(list as dynamic) as object
    out = []
    seen = {}
    for each g in Arr_or(list)
        v = ""
        if Type(g) = "roString" or Type(g) = "String" then
            v = g
        else if Type(g) = "roAssociativeArray" then
            v = Str_orEmpty(g.value)
            if v = "" then v = Str_orEmpty(g.name)
            if v = "" then v = Str_orEmpty(g.label)
        end if
        if v <> "" and not seen.DoesExist(v) then
            seen[v] = true
            out.Push(v)
        end if
    end for
    return out
end function

' The server's values for a vocabulary key; technical facets (resolutions, audio and subtitle
' languages) arrive under `technical` and are read from the top level too.
function LibF_vocab(filters as dynamic, key as string) as object
    if Type(filters) <> "roAssociativeArray" or key = "" then return []
    vals = LibF_values(filters[key])
    if vals.Count() = 0 and Type(filters.technical) = "roAssociativeArray" then vals = LibF_values(filters.technical[key])
    return vals
end function

' [{id, label}] for a facet.
function LibF_options(def as object, filters as dynamic) as object
    out = []
    if def.id = "decade" then
        for each y in [2020, 2010, 2000, 1990, 1980, 1970, 1960]
            out.Push({ id: y.ToStr(), label: y.ToStr() + "s" })
        end for
        return out
    end if
    if def.id = "dynamic_range" then return [{ id: "hdr", label: "HDR" }, { id: "dolby_vision", label: "Dolby Vision" }]
    if def.id = "status" then return LibF_watchOptions()
    for each v in LibF_vocab(filters, def.vocab)
        out.Push({ id: v, label: v })
    end for
    return out
end function

' The facets to list: fixed ones always, server ones when the server lists values (or when values
' are still selected from a saved state, so they can be cleared).
function LibF_available(isAudiobook as boolean, filters as dynamic, sel as dynamic) as object
    out = []
    for each def in LibF_facets(isAudiobook)
        if def.vocab = "" or LibF_options(def, filters).Count() > 0 or LibF_selected(sel, def.id).Count() > 0 then out.Push(def)
    end for
    return out
end function

function LibF_selected(sel as dynamic, facetId as string) as object
    if Type(sel) <> "roAssociativeArray" then return []
    return Arr_or(sel[facetId])
end function

function LibF_isSelected(sel as dynamic, facetId as string, value as string) as boolean
    for each v in LibF_selected(sel, facetId)
        if v = value then return true
    end for
    return false
end function

' A copy of sel with value toggled. Watch Status is single-select: picking another replaces it,
' picking the active one clears it.
function LibF_toggle(sel as dynamic, facetId as string, value as string) as object
    out = LibF_copy(sel)
    cur = LibF_selected(out, facetId)
    nextVals = []
    found = false
    for each v in cur
        if v = value then
            found = true
        else if facetId <> "status" then
            nextVals.Push(v)
        end if
    end for
    if not found then nextVals.Push(value)
    if nextVals.Count() = 0 then
        out.Delete(facetId)
    else
        out[facetId] = nextVals
    end if
    return out
end function

function LibF_clear(sel as dynamic, facetId as string) as object
    out = LibF_copy(sel)
    out.Delete(facetId)
    return out
end function

function LibF_copy(sel as dynamic) as object
    out = {}
    if Type(sel) <> "roAssociativeArray" then return out
    for each k in sel
        vals = []
        for each v in Arr_or(sel[k])
            if Type(v) = "roString" or Type(v) = "String" then vals.Push(v)
        end for
        if vals.Count() > 0 then out[k] = vals
    end for
    return out
end function

' Each facet with a value counts once (the Filter pill's badge).
function LibF_activeCount(sel as dynamic) as integer
    n = 0
    for each id in LibF_groupOrder()
        if LibF_selected(sel, id).Count() > 0 then n = n + 1
    end for
    return n
end function

' The row's summary in the panel: "", one label, or "N selected".
function LibF_summary(def as object, sel as dynamic, filters as dynamic) as string
    vals = LibF_selected(sel, def.id)
    if vals.Count() = 0 then return ""
    if vals.Count() > 1 then return vals.Count().ToStr() + " selected"
    for each o in LibF_options(def, filters)
        if o.id = vals[0] then return o.label
    end for
    if def.id = "decade" then return vals[0] + "s"
    return vals[0]
end function

function LibF_sorted(vals as object) as object
    out = []
    for each v in vals
        out.Push(v)
    end for
    out.Sort()
    return out
end function

' The selection as catalog query groups (Android TV toQueryGroups): one match=any group per facet
' (array columns `contains`, scalar `is`), decades as `year between`, dynamic range as OR'd
' boolean rules, watch status as one boolean rule (JSON booleans, never strings: Silo Android #702).
function LibF_groups(sel as dynamic, isAudiobook as boolean) as object
    defs = {}
    for each d in LibF_facets(isAudiobook)
        defs[d.id] = d
    end for
    groups = []
    for each id in LibF_groupOrder()
        vals = LibF_selected(sel, id)
        if vals.Count() > 0 and defs.DoesExist(id) then
            d = defs[id]
            rules = []
            if id = "decade" then
                for each v in LibF_sorted(vals)
                    y = Int(Val(v))
                    if y > 0 then rules.Push({ field: "year", op: "between", value: "", values: [y.ToStr(), (y + 9).ToStr()] })
                end for
                if rules.Count() > 0 then groups.Push({ match: "any", rules: rules })
            else if id = "dynamic_range" then
                if LibF_isSelected(sel, id, "hdr") then rules.Push({ field: "hdr", op: "is", value: true })
                if LibF_isSelected(sel, id, "dolby_vision") then rules.Push({ field: "dolby_vision", op: "is", value: true })
                if rules.Count() > 0 then groups.Push({ match: "any", rules: rules })
            else if id = "status" then
                groups.Push({ match: "all", rules: [LibF_watchRule(vals[0])] })
            else
                for each v in LibF_sorted(vals)
                    rules.Push({ field: d.field, op: d.op, value: v })
                end for
                groups.Push({ match: "any", rules: rules })
            end if
        end if
    end for
    return groups
end function

' The watch-status filter as a catalog rule. Flag rules carry JSON booleans: the server answers
' 500 to "true"/"false" strings (Silo Android #702; the Apple clients send booleans too).
function LibF_watchRule(ws as string) as object
    if ws = "unwatched" then return { field: "watched", op: "is", value: false }
    if ws = "watched" then return { field: "watched", op: "is", value: true }
    if ws = "in_progress" then return { field: "in_progress", op: "is", value: true }
    if ws = "favorited" then return { field: "favorited", op: "is", value: true }
    return { field: "in_watchlist", op: "is", value: true }
end function

' The saved filter state (BrowsePrefsStore): { facets: {id: [values]}, match: "all"|"any" }. An older
' save ({ genre: "Drama", watchStatus: "watched" }, Siku before v0.1.31) is read too; values a facet
' does not offer are dropped from the fixed facets.
function LibF_restore(state as dynamic) as object
    out = { "sel": {}, "matchAll": true }
    if Type(state) <> "roAssociativeArray" then return out
    sel = LibF_copy(state.facets)
    if not sel.DoesExist("genre") and not Str_isEmpty(state.genre) then sel.genre = [Str_orEmpty(state.genre)]
    if not sel.DoesExist("status") and not Str_isEmpty(state.watchStatus) then sel.status = [Str_orEmpty(state.watchStatus)]
    ' Fixed vocabularies: keep known values only (Watch Status: one).
    for each id in ["status", "decade", "dynamic_range"]
        if sel.DoesExist(id) then
            known = {}
            for each o in LibF_options({ id: id }, invalid)
                known[o.id] = true
            end for
            kept = []
            for each v in sel[id]
                if known.DoesExist(v) and not (id = "status" and kept.Count() > 0) then kept.Push(v)
            end for
            if kept.Count() > 0 then sel[id] = kept else sel.Delete(id)
        end if
    end for
    out["sel"] = sel
    out["matchAll"] = Str_orEmpty(state.match) <> "any"
    return out
end function
