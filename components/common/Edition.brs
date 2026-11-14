' Editions (cuts) of a title and the file Version Auto picks within one (Silo Android #899,
' shared/.../playback/DetailVersionSelector.kt and model/catalog/PlaybackEditions.kt; the same
' rule as Silo's web, Apple and Roku apps, silo-roku 7bb02a9). Pure: no SceneGraph, no Tx, so the
' host tests run it (tests/test_edition.py). Include with
' <script uri="pkg:/components/common/Edition.brs" />; needs Utils.
'
' Edition picks the cut; Version picks the file. Version Auto is the edition's best first-part
' file for the quality preference and never changes the edition:
' - an explicit Version pick (pinned file id) wins;
' - the edition is the viewer's pick, else the one last played (user_data.last_edition_key, where
'   a present "" names the unnamed edition, then the edition of last_file_id), else the edition
'   whose Auto file compares best across the cuts (Edition_opening);
' - Auto is the best file at or below the preference, else the closest above it, else a file of
'   unknown resolution, ranked in the server's version order (resolution, HDR, file size);
' - while the title has a resume point, a later part of a multi-part copy the viewer stopped in is
'   kept, so Resume continues that part; otherwise Auto starts at part 1.
' SPDX-License-Identifier: AGPL-3.0-or-later

' The server's resolution rank (its `access` quality order, with the 4K and 8K aliases); 0 = unknown.
function Edition_rank(value as dynamic) as integer
    r = LCase(Str_orEmpty(value)).Trim()
    if r = "480p" then return 1
    if r = "720p" then return 2
    if r = "1080p" then return 3
    if r = "2160p" or r = "4k" then return 4
    if r = "4320p" or r = "8k" then return 5
    return 0
end function

' The rank a quality preference caps Auto at; 0 = no cap (Auto, Original, or no resolution).
function Edition_cap(quality as dynamic) as integer
    q = LCase(Str_orEmpty(quality)).Trim()
    dash = Instr(1, q, "-")
    if dash > 0 then q = Left(q, dash - 1)
    return Edition_rank(q)
end function

' An edition key as it names an edition: trimmed, with a missing key the unnamed edition "".
function Edition_key(key as dynamic) as string
    return Str_orEmpty(key).Trim()
end function

' An edition's display name: its raw name, else its key in words ("directors_cut" → "Directors Cut",
' "imax" → "IMAX"), else "" (the caller says "Standard").
function Edition_label(raw as dynamic, key as dynamic) as string
    r = Str_orEmpty(raw).Trim()
    if r <> "" then return r
    k = Str_orEmpty(key).Trim()
    if k = "" then return ""
    words = []
    for each part in CreateObject("roRegex", "[_\-]+", "").Split(k)
        if part <> "" then
            if LCase(part) = "imax" then
                words.Push("IMAX")
            else
                words.Push(UCase(Left(part, 1)) + Mid(part, 2))
            end if
        end if
    end for
    return words.Join(" ")
end function

function Edition_hdr(v as object) as boolean
    f = LCase(Str_orEmpty(v.hdr)).Trim()
    return f = "true" or f = "1"
end function

' ---------- Parts (PlaybackParts.kt) ----------

function Edition_isPart(v as object) as boolean
    k = Str_orEmpty(v.presentation_kind)
    return (k = "multipart_movie" or k = "split_episode") and v.presentation_part_index <> invalid
end function

function Edition_partIndex(v as object) as integer
    return Int(Num_or(v.presentation_part_index, 0))
end function

function Edition_samePresentation(a as object, b as object) as boolean
    return Str_orEmpty(a.presentation_kind) = Str_orEmpty(b.presentation_kind) and Str_orEmpty(a.presentation_group_key) = Str_orEmpty(b.presentation_group_key) and Str_orEmpty(a.edition_key) = Str_orEmpty(b.edition_key)
end function

' The first part of sel's presentation (preferring sel's resolution); anything that is not a later
' part is returned as it is.
function Edition_firstPart(all as object, sel as object) as object
    ' Index loops throughout: callers walk the same array (brs-engine shares one for-each position).
    if not Edition_isPart(sel) then return sel
    first = invalid
    for i = 0 to all.Count() - 1
        v = all[i]
        if Edition_isPart(v) and Edition_samePresentation(v, sel) then
            n = Edition_partIndex(v)
            if first = invalid then
                first = n
            else if n < first then
                first = n
            end if
        end if
    end for
    if first = invalid then return sel
    if Edition_partIndex(sel) = first then return sel
    pick = invalid
    for i = 0 to all.Count() - 1
        v = all[i]
        if Edition_isPart(v) and Edition_samePresentation(v, sel) and Edition_partIndex(v) = first then
            if Str_orEmpty(v.resolution) = Str_orEmpty(sel.resolution) then return v
            if pick = invalid then pick = v
        end if
    end for
    if pick = invalid then return sel
    return pick
end function

' The files of list that start their presentation (Auto never starts on a later part); all of
' them when none does.
function Edition_firstParts(list as object) as object
    out = []
    for i = 0 to list.Count() - 1
        v = list[i]
        if Str_orEmpty(Edition_firstPart(list, v).file_id) = Str_orEmpty(v.file_id) then out.Push(v)
    end for
    if out.Count() = 0 then return list
    return out
end function

' ---------- Editions (PlaybackEditions.kt) ----------

' The editions of a title, one per edition key in server order (playback_variants' order, else
' first appearance in versions), every presentation of a cut merged:
'   { id: trimmed key ("" = unnamed), label: Edition_label ("" = Standard), raw,
'     files: the files the Version menu offers, in server order (each presentation's first part
'            with variants, else every file of the edition),
'     fileIds: { "<file_id>": true } for every file of the edition, all parts }
function Edition_list(versions as dynamic, variants as dynamic) as object
    versions = Arr_or(versions)
    variants = Arr_or(variants)
    byId = {}
    for i = 0 to versions.Count() - 1
        v = versions[i]
        if Type(v) = "roAssociativeArray" then
            fid = Str_orEmpty(v.file_id)
            if fid <> "" and not byId.DoesExist(fid) then byId[fid] = v
        end if
    end for
    keys = []
    groups = {}
    out = []
    if variants.Count() > 0 then
        for each pv in variants
            if Type(pv) = "roAssociativeArray" then
                k = Edition_key(pv.edition_key)
                gk = "k" + k ' "k" keeps the unnamed edition's empty key a usable AA key
                if not groups.DoesExist(gk) then
                    groups[gk] = { raws: [], choiceIds: {}, fileIds: {} }
                    keys.Push(k)
                end if
                g = groups[gk]
                g.raws.Push(pv.edition_raw)
                firstPart = invalid
                for each part in Arr_or(pv.parts)
                    if Type(part) = "roAssociativeArray" then
                        for each pf in Arr_or(part.versions)
                            if Type(pf) = "roAssociativeArray" and not Str_isEmpty(pf.file_id) then g.fileIds[Str_orEmpty(pf.file_id)] = true
                        end for
                        if firstPart = invalid or Num_or(part.part_index, 0) < Num_or(firstPart.part_index, 0) then firstPart = part
                    end if
                end for
                if firstPart <> invalid then
                    for each pf in Arr_or(firstPart.versions)
                        if Type(pf) = "roAssociativeArray" then
                            fid = Str_orEmpty(pf.file_id)
                            if byId.DoesExist(fid) then g.choiceIds[fid] = true
                        end if
                    end for
                end if
            end if
        end for
        for each k in keys
            g = groups["k" + k]
            files = []
            for each v in versions
                if Type(v) = "roAssociativeArray" and g.choiceIds.DoesExist(Str_orEmpty(v.file_id)) and Edition_indexOf(files, v) < 0 then files.Push(v)
            end for
            if files.Count() > 0 then out.Push(Edition_make(k, g.raws, files, g.fileIds))
        end for
        return out
    end if
    for each v in versions
        if Type(v) = "roAssociativeArray" then
            k = Edition_key(v.edition_key)
            gk = "k" + k
            if not groups.DoesExist(gk) then
                groups[gk] = { raws: [], files: [], fileIds: {} }
                keys.Push(k)
            end if
            g = groups[gk]
            g.raws.Push(v.edition_raw)
            g.files.Push(v)
            g.fileIds[Str_orEmpty(v.file_id)] = true
        end if
    end for
    for each k in keys
        g = groups["k" + k]
        out.Push(Edition_make(k, g.raws, g.files, g.fileIds))
    end for
    return out
end function

function Edition_make(key as string, raws as object, files as object, fileIds as object) as object
    raw = ""
    for each r in raws
        if raw = "" then raw = Str_orEmpty(r).Trim()
    end for
    return { id: key, label: Edition_label(raw, key), raw: raw, files: files, fileIds: fileIds }
end function

function Edition_indexOf(list as object, v as object) as integer
    fid = Str_orEmpty(v.file_id)
    for i = 0 to list.Count() - 1
        if Str_orEmpty(list[i].file_id) = fid then return i
    end for
    return -1
end function

' The place of the edition holding fileId, else -1.
function Edition_holding(editions as object, fileId as string) as integer
    if fileId = "" then return -1
    for i = 0 to editions.Count() - 1
        if editions[i].fileIds.DoesExist(fileId) then return i
    end for
    return -1
end function

function Edition_find(editions as object, id as dynamic) as integer
    if id = invalid then return -1
    k = Edition_key(id)
    for i = 0 to editions.Count() - 1
        if editions[i].id = k then return i
    end for
    return -1
end function

' ---------- Version Auto ----------

' The server's version order: resolution, HDR before SDR, larger file; stable otherwise.
function Edition_serverOrder(list as object) as object
    out = []
    for each v in list
        at = out.Count()
        for i = 0 to out.Count() - 1
            if at = out.Count() and Edition_before(v, out[i]) then at = i
        end for
        out.Push(invalid)
        j = out.Count() - 1
        while j > at
            out[j] = out[j - 1]
            j = j - 1
        end while
        out[at] = v
    end for
    return out
end function

function Edition_before(a as object, b as object) as boolean
    ra = Edition_rank(a.resolution)
    rb = Edition_rank(b.resolution)
    if ra <> rb then return ra > rb
    ha = Edition_hdr(a)
    hb = Edition_hdr(b)
    if ha <> hb then return ha
    return Num_or(a.file_size, 0) > Num_or(b.file_size, 0)
end function

' Version Auto among candidates for cap (0 = none): the best file at or below it, else the closest
' above it; a file of unknown resolution only when no file's resolution is known.
function Edition_autoAmong(candidates as object, cap as integer) as dynamic
    if candidates.Count() = 0 then return invalid
    ordered = Edition_serverOrder(candidates)
    known = []
    for each v in ordered
        if Edition_rank(v.resolution) > 0 then known.Push(v)
    end for
    if known.Count() = 0 then return ordered[0]
    if cap <= 0 then return known[0]
    for each v in known
        if Edition_rank(v.resolution) <= cap then return v
    end for
    closest = invalid
    for each v in known
        r = Edition_rank(v.resolution)
        if closest = invalid or r < Edition_rank(closest.resolution) then closest = v
    end for
    return closest
end function

' The file Version Auto picks in an edition (picking the edition keeps it).
function Edition_autoFile(edition as object, quality as dynamic) as dynamic
    return Edition_autoAmong(Edition_firstParts(edition.files), Edition_cap(quality))
end function

' 0 for the unnamed or standard edition, 1 for a theatrical one, 2 for any other cut.
function Edition_preference(edition as object) as integer
    names = []
    for each n in [edition.id, edition.raw]
        t = LCase(Str_orEmpty(n)).Trim()
        if t <> "" then names.Push(t)
    end for
    if names.Count() = 0 then return 0
    for each t in names
        if t = "standard" or t = "default" or Left(t, 9) = "standard " or Right(t, 9) = " standard" then return 0
    end for
    for each t in names
        if Instr(1, t, "theatrical") > 0 then return 1
    end for
    return 2
end function

' The edition a page opens on with no history: each edition's Auto file compared across the cuts
' by fit (within the cap or no cap, then above it, then unknown resolution), resolution (higher
' within the cap, lower above it), HDR, then the edition's preference and server order. File size
' is not compared across cuts.
function Edition_opening(editions as object, quality as dynamic) as integer
    cap = Edition_cap(quality)
    best = invalid
    for i = 0 to editions.Count() - 1
        auto = Edition_autoFile(editions[i], quality)
        if auto <> invalid then
            r = Edition_rank(auto.resolution)
            fit = 0
            if r = 0 then
                fit = 2
            else if cap > 0 and r > cap then
                fit = 1
            end if
            c = { at: i, fit: fit, rank: r, hdr: Edition_hdr(auto), pref: Edition_preference(editions[i]) }
            if best = invalid then
                best = c
            else if Edition_opensBefore(c, best) then
                best = c
            end if
        end if
    end for
    if best = invalid then return 0
    return best.at
end function

function Edition_opensBefore(a as object, b as object) as boolean
    if a.fit <> b.fit then return a.fit < b.fit
    if a.rank <> b.rank then
        if a.fit = 1 then return a.rank < b.rank
        return a.rank > b.rank
    end if
    if a.hdr <> b.hdr then return a.hdr
    if a.pref <> b.pref then return a.pref < b.pref
    return a.at < b.at
end function

' Whether the title has a resume point: a saved position above 0 (the played flag is ignored; the
' server resets the position when a title finishes and keeps played set during a rewatch).
function Edition_inProgress(userData as dynamic) as boolean
    if Type(userData) <> "roAssociativeArray" then return false
    return Num_or(userData.position_seconds, 0) > 0
end function

' What the page shows for an item detail (versions, playback_variants, user_data):
'   { version: the file shown and played (invalid without versions), editions: Edition_list,
'     edition: the place of the current edition (-1 with no editions),
'     source: "pinned" | "picked" | "last_edition" | "last_file" | "best" | "none" (how the
'             edition was chosen; "none" without editions),
'     laterPart: true when Auto kept the later part being resumed }
' pinnedFileId: the Version pick ("" = Auto). editionId: the Edition pick (invalid = none).
function Edition_resolve(detail as dynamic, pinnedFileId as string, editionId as dynamic, quality as dynamic) as object
    out = { version: invalid, editions: [], edition: -1, source: "none", laterPart: false }
    if Type(detail) <> "roAssociativeArray" then return out
    versions = []
    for each v in Arr_or(detail.versions)
        if Type(v) = "roAssociativeArray" then versions.Push(v)
    end for
    if versions.Count() = 0 then return out
    editions = Edition_list(versions, detail.playback_variants)
    out.editions = editions
    if pinnedFileId <> "" then
        for each v in versions
            if Str_orEmpty(v.file_id) = pinnedFileId then
                out.version = v
                out.edition = Edition_holding(editions, pinnedFileId)
                out.source = "pinned"
                return out
            end if
        end for
    end if
    if editions.Count() = 0 then
        out.version = Edition_autoAmong(Edition_firstParts(versions), Edition_cap(quality))
        return out
    end if
    ud = detail.user_data
    if Type(ud) <> "roAssociativeArray" then ud = {}
    lastFileId = Str_orEmpty(ud.last_file_id)
    at = Edition_find(editions, editionId)
    out.source = "picked"
    ' A present last_edition_key, "" included (the unnamed edition), names the last-played edition.
    lastKey = ud.last_edition_key
    hasLastKey = Type(lastKey) = "roString" or Type(lastKey) = "String"
    if at < 0 and hasLastKey then
        at = Edition_find(editions, lastKey)
        out.source = "last_edition"
    end if
    if at < 0 then
        at = Edition_holding(editions, lastFileId)
        out.source = "last_file"
    end if
    if at < 0 then
        at = Edition_opening(editions, quality)
        out.source = "best"
    end if
    out.edition = at
    edition = editions[at]
    if Edition_inProgress(ud) and edition.fileIds.DoesExist(lastFileId) then
        for i = 0 to versions.Count() - 1
            v = versions[i]
            if Str_orEmpty(v.file_id) = lastFileId then
                if Str_orEmpty(Edition_firstPart(versions, v).file_id) <> lastFileId then
                    out.version = v
                    out.laterPart = true
                    return out
                end if
            end if
        end for
    end if
    out.version = Edition_autoFile(edition, quality)
    return out
end function

' The file id Play sends for the shown file, so Play starts the file the page shows: always for
' a Version pick or a file whose tracks were picked; for an Auto file unless it is the last-played
' file (the player picks that one itself and keeps a multi-part start on part 1). "" = send none.
function Edition_playFileId(shown as dynamic, pinned as boolean, tracksPicked as boolean, lastFileId as dynamic) as string
    if Type(shown) <> "roAssociativeArray" then return ""
    fid = Str_orEmpty(shown.file_id)
    if fid = "" then return ""
    if pinned or tracksPicked or fid <> Str_orEmpty(lastFileId) then return fid
    return ""
end function
