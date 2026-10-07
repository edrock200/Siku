' Client-side whole-book audiobook timeline (port of the Android TV client's
' shared/audiobook/AudiobookTimeline.kt, itself a port of the Apple client).
' The server has no whole-book concept: each audiobook file is a FileVersion tagged
' presentation_kind "audiobook_part" with presentation_part_index. We stitch those parts
' into one timeline; global offsets exist only on the client. One part = one playback session.
' Also small audio helpers shared by AudioDetailScreen and AudioPlayerScreen.
' SPDX-License-Identifier: AGPL-3.0-or-later

' Returns {tracks: [{index, fileId, duration, offset}], chapters: [{index, title, start, end, trackIndex}],
'          total, isSingle} or invalid when no version is a playable audio part.
function AudioTimeline_build(versions as dynamic, serverTotal as dynamic, preferredFileId = "" as string) as dynamic
    parts = AudioTimeline_parts(Arr_or(versions), preferredFileId)
    if parts.Count() = 0 then return invalid
    tracks = []
    chapters = []
    offset = 0.0
    for each part in parts
        dur = AudioTimeline_partDuration(part)
        ' Zero-length parts would trip end-of-part detection; they add nothing to the offsets.
        if dur > 0 then
            idx = tracks.Count()
            tracks.Push({ index: idx, fileId: Str_orEmpty(part.file_id), duration: dur, offset: offset })
            for each ch in Arr_or(part.chapters)
                s = AudioTimeline_num(ch.start_seconds)
                e = AudioTimeline_num(ch.end_seconds)
                chapters.Push({ index: 0, title: Str_orEmpty(ch.title), start: offset + s, "end": offset + e, trackIndex: idx })
            end for
            offset = offset + dur
        end if
    end for
    if tracks.Count() = 0 then return invalid
    total = offset
    st = AudioTimeline_num(serverTotal)
    if st > total then total = st
    AudioTimeline_sortBy(chapters, "start")
    for i = 0 to chapters.Count() - 1
        chapters[i].index = i
        if chapters[i].title = "" then chapters[i].title = "Chapter " + (i + 1).ToStr()
    end for
    return { tracks: tracks, chapters: chapters, total: total, isSingle: tracks.Count() <= 1 }
end function

' Picks one playable file per ordered part (AudiobookTimeline.kt audioParts()).
function AudioTimeline_parts(versions as object, preferredFileId as string) as object
    candidates = []
    for each v in versions
        if Str_orEmpty(v.presentation_kind) = "audiobook_part" then
            candidates.Push(v)
        else if not Str_isEmpty(v.codec_audio) or AudioTimeline_num(v.duration) > 0 then
            candidates.Push(v)
        end if
    end for
    if candidates.Count() = 0 then return []

    preferred = invalid
    for each c in candidates
        if preferredFileId <> "" and Str_orEmpty(c.file_id) = preferredFileId then preferred = c
    end for

    indexed = []
    for each c in candidates
        if c.presentation_part_index <> invalid then indexed.Push(c)
    end for
    if indexed.Count() = 0 then
        if preferred <> invalid then return [preferred]
        return [candidates[0]]
    end if

    ' Group by part index; choose a variant key present in every part.
    byPart = {}
    partKeys = []
    for each c in indexed
        k = "p" + Str_orEmpty(c.presentation_part_index)
        if byPart[k] = invalid then
            byPart[k] = []
            partKeys.Push({ key: k, n: AudioTimeline_num(c.presentation_part_index) })
        end if
        byPart[k].Push(c)
    end for
    AudioTimeline_sortBy(partKeys, "n")
    variantKeys = []
    if preferred <> invalid then variantKeys.Push(AudioTimeline_variantKey(preferred))
    for each c in candidates
        variantKeys.Push(AudioTimeline_variantKey(c))
    end for
    selectedKey = invalid
    for each vk in variantKeys
        complete = true
        for each pk in partKeys
            found = false
            for each pv in byPart[pk.key]
                if AudioTimeline_variantKey(pv) = vk then found = true
            end for
            if not found then complete = false
        end for
        if complete then
            selectedKey = vk
            exit for
        end if
    end for

    out = []
    for each pk in partKeys
        pick = invalid
        for each pv in byPart[pk.key]
            if pick = invalid and selectedKey <> invalid and AudioTimeline_variantKey(pv) = selectedKey then pick = pv
        end for
        if pick = invalid then
            for each pv in byPart[pk.key]
                if pick = invalid and preferredFileId <> "" and Str_orEmpty(pv.file_id) = preferredFileId then pick = pv
            end for
        end if
        if pick = invalid then pick = byPart[pk.key][0]
        out.Push(pick)
    end for
    return out
end function

function AudioTimeline_variantKey(v as object) as string
    return Str_orEmpty(v.presentation_kind) + "|" + Str_orEmpty(v.presentation_group_key)
end function

' Probed duration, or the furthest chapter edge when the container has none.
function AudioTimeline_partDuration(part as object) as float
    d = AudioTimeline_num(part.duration)
    if d > 0 then return d
    edge = 0.0
    for each ch in Arr_or(part.chapters)
        e = AudioTimeline_num(ch.end_seconds)
        s = AudioTimeline_num(ch.start_seconds)
        if s > e then e = s
        if e > edge then edge = e
    end for
    return edge
end function

' Track index containing a whole-book time (past the end: the last track).
function AudioTimeline_trackIndexAt(tl as object, globalTime as float) as integer
    t = globalTime
    if t < 0 then t = 0
    for each tr in tl.tracks
        if t >= tr.offset and t < tr.offset + tr.duration then return tr.index
    end for
    return tl.tracks.Count() - 1
end function

function AudioTimeline_localTime(tr as object, globalTime as float) as float
    l = globalTime - tr.offset
    if l < 0 then l = 0
    if l > tr.duration then l = tr.duration
    return l
end function

' Index of the chapter playing at a whole-book time, or -1.
function AudioTimeline_chapterAt(chapters as object, globalTime as float) as integer
    idx = -1
    for i = 0 to chapters.Count() - 1
        if globalTime + 0.5 >= chapters[i].start then idx = i
    end for
    if idx < 0 and chapters.Count() > 0 then idx = 0
    return idx
end function

function AudioTimeline_num(v as dynamic) as float
    if v = invalid then return 0.0
    t = Type(v)
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" or t = "roLongInteger" or t = "LongInteger" then
        return v * 1.0
    end if
    return 0.0
end function

' Stable insertion sort of an array of AAs by a numeric field (ascending).
sub AudioTimeline_sortBy(arr as object, field as string)
    n = arr.Count()
    for i = 1 to n - 1
        cur = arr[i]
        j = i - 1
        while j >= 0 and arr[j][field] > cur[field]
            arr[j + 1] = arr[j]
            j = j - 1
        end while
        arr[j + 1] = cur
    end for
end sub

' Lowercase item type with legacy aliases folded ("musicalbum" -> "album").
function Audio_itemType(item as dynamic) as string
    if item = invalid then return ""
    t = LCase(Str_orEmpty(item.type))
    if t = "musicalbum" or t = "music_album" then return "album"
    if t = "musicartist" or t = "music_artist" then return "artist"
    if t = "audio" or t = "song" or t = "music_track" then return "track"
    return t
end function

' Normalizes a queue entry (our {contentId,...} form or a raw API card/track) for AudioPlayerScreen.
function Audio_queueEntry(src as object) as object
    cid = Str_orEmpty(src.contentId)
    if cid = "" then cid = Str_orEmpty(src.content_id)
    if cid = "" then cid = Str_orEmpty(src.id)
    fileId = Str_orEmpty(src.fileId)
    if fileId = "" then fileId = Str_orEmpty(src.file_id)
    if fileId = "" then
        files = Arr_or(src.files)
        if files.Count() = 0 then files = Arr_or(src.versions)
        if files.Count() > 0 then fileId = Str_orEmpty(files[0].file_id)
    end if
    artist = Str_orEmpty(src.artist)
    if artist = "" then artist = Str_orEmpty(src.artist_name)
    album = Str_orEmpty(src.album)
    if album = "" then album = Str_orEmpty(src.album_title)
    poster = Str_orEmpty(src.posterUrl)
    if poster = "" then poster = Str_orEmpty(src.poster_url)
    dur = AudioTimeline_num(src.durationSeconds)
    if dur <= 0 then dur = AudioTimeline_num(src.duration_seconds)
    return { contentId: cid, fileId: fileId, title: Str_orEmpty(src.title), artist: artist, album: album, posterUrl: poster, durationSeconds: dur }
end function

' Appends a row for an AudioListItem MarkupList. fields: {title, number?, subtitle?, trailing?, isCurrent?}
function AudioList_rowNode(parent as object, fields as object) as object
    node = parent.createChild("ContentNode")
    node.addFields({ number: "", subtitle: "", trailing: "", isCurrent: false, rowId: "" })
    node.title = Str_orEmpty(fields.title)
    node.number = Str_orEmpty(fields.number)
    node.subtitle = Str_orEmpty(fields.subtitle)
    node.trailing = Str_orEmpty(fields.trailing)
    node.isCurrent = fields.isCurrent = true
    node.rowId = Str_orEmpty(fields.id)
    return node
end function
