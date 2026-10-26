' SPDX-License-Identifier: AGPL-3.0-or-later
' Silo seek-bar previews (trickplay_v1): manifest validation and the time-to-tile mapping.
' Pure BrightScript (Utils.brs only, no SceneGraph), so tools/trickplay_test.py can run it in
' brs-cli. Port of silo-android TrickplayManifest.kt (#695); the player side is PlayerTrickplay.brs.
'
' GET /api/v2/watch/{id}/trickplay?file_id= describes JPEG sprite sheets of tile_columns x tile_rows
' thumbnails. Thumbnail i shows [i*interval_ms, (i+1)*interval_ms); it sits on sheet
' i / (columns*rows), at column i % columns and row (i % (columns*rows)) / columns. Every sheet has
' the full grid (black after the last thumbnail). Each sheet URL carries its own authorization
' until expires_at.

' The largest sheet side, in pixels, a player cuts (TrickplayManifest.MAX_SHEET_SIDE). The server
' keeps sheets within 3200.
function Trickplay_maxSheetSide() as integer
    return 8192
end function

' A positive integer id ("42" or 42) as its canonical string, else "".
function Trickplay_positiveId(v as dynamic) as string
    s = ""
    t = Type(v)
    if t = "roString" or t = "String" then
        s = v.Trim()
    else if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roLongInteger" or t = "LongInteger" then
        s = v.ToStr()
    else
        return ""
    end if
    if s = "" or Len(s) > 18 then return ""
    for i = 1 to Len(s)
        c = Asc(Mid(s, i, 1))
        if c < 48 or c > 57 then return ""
    end for
    ' Strip leading zeros so "042" and 42 compare equal; "0" is not positive.
    while Len(s) > 1 and Left(s, 1) = "0"
        s = Mid(s, 2)
    end while
    if s = "0" then return ""
    return s
end function

' A whole number in [lo, hi] read loosely (numbers may arrive as strings), else -1.
function Trickplay_whole(v as dynamic, lo as integer, hi as integer) as integer
    if v = invalid then return -1
    t = Type(v)
    if t <> "roString" and t <> "String" and t <> "roInt" and t <> "roInteger" and t <> "Integer" and t <> "roLongInteger" and t <> "LongInteger" and t <> "roFloat" and t <> "Float" and t <> "roDouble" and t <> "Double" then return -1
    n = Num_or(v, -1)
    if n < lo or n > hi then return -1
    if n <> Int(n) then return -1
    return Int(n)
end function

' Resolves a sheet URL against the server origin; "" unless the result is http(s).
function Trickplay_resolveUrl(u as dynamic, origin as string) as string
    s = Str_orEmpty(u).Trim()
    if s = "" then return ""
    low = LCase(s)
    if Left(low, 7) = "http://" or Left(low, 8) = "https://" then return s
    if Left(s, 2) = "//" then return ""   ' a scheme-relative URL is not ours to guess
    if Instr(1, low, "://") > 0 or Left(low, 5) = "data:" or Left(low, 4) = "pkg:" or Left(low, 4) = "tmp:" then return ""
    o = origin
    while Len(o) > 0 and Right(o, 1) = "/"
        o = Left(o, Len(o) - 1)
    end while
    ol = LCase(o)
    if not (Left(ol, 7) = "http://" or Left(ol, 8) = "https://") then return ""
    if Left(s, 1) = "/" then return o + s
    return o + "/" + s
end function

' Validates a manifest for `fileId` and resolves its sheet URLs against `origin`. Returns invalid
' when it cannot be cut safely, so the player keeps its time-only preview, else
' { fileId, intervalMs, thumbW, thumbH, cols, rows, count, sheetUrls: [...], expiresAt (epoch
'   seconds, or 0 when the server's time did not parse) }.
function Trickplay_fromManifest(data as dynamic, fileId as string, origin as string) as dynamic
    if data = invalid or Type(data) <> "roAssociativeArray" then return invalid
    fid = Trickplay_positiveId(data.file_id)
    if fid = "" or fid <> Trickplay_positiveId(fileId) then return invalid
    maxSide = Trickplay_maxSheetSide()
    interval = Trickplay_whole(data.interval_ms, 1, 86400000)
    count = Trickplay_whole(data.thumbnail_count, 1, 10000000)
    tw = Trickplay_whole(data.thumbnail_width, 1, maxSide)
    th = Trickplay_whole(data.thumbnail_height, 1, maxSide)
    cols = Trickplay_whole(data.tile_columns, 1, maxSide)
    rows = Trickplay_whole(data.tile_rows, 1, maxSide)
    if interval < 1 or count < 1 or tw < 1 or th < 1 or cols < 1 or rows < 1 then return invalid
    if cols * tw > maxSide or rows * th > maxSide then return invalid
    perSheet = cols * rows
    need = Int((count + perSheet - 1) / perSheet)
    sheets = Arr_or(data.sheets)
    ' Thumbnails are cut by index, so every sheet must be there, once.
    if sheets.Count() <> need then return invalid
    urls = []
    for i = 0 to need - 1
        urls.Push("")
    end for
    for each sh in sheets
        if sh = invalid or Type(sh) <> "roAssociativeArray" then return invalid
        idx = Trickplay_whole(sh.index, 0, need - 1)
        if idx < 0 or urls[idx] <> "" then return invalid
        u = Trickplay_resolveUrl(sh.url, origin)
        if u = "" then return invalid
        urls[idx] = u
    end for
    expiresAt = 0
    expDt = Time_parseIso(Str_orEmpty(data.expires_at))
    if expDt <> invalid then expiresAt = expDt.AsSeconds()
    return { fileId: fid, intervalMs: interval, thumbW: tw, thumbH: th, cols: cols, rows: rows, count: count, sheetUrls: urls, expiresAt: expiresAt }
end function

' The thumbnail for `seconds` of media time, the last one past the end: { index, sheet, col, row };
' invalid for a time before the file.
function Trickplay_tileAt(man as object, seconds as dynamic) as dynamic
    if man = invalid or seconds = invalid then return invalid
    s = Num_or(seconds, -1)
    if s < 0 then return invalid
    position# = s * 1000# / man.intervalMs
    last = man.count - 1
    if position# >= last then
        index = last
    else
        index = Int(position#)
    end if
    perSheet = man.cols * man.rows
    cell = index mod perSheet
    return { index: index, sheet: Int(index / perSheet), col: cell mod man.cols, row: Int(cell / man.cols) }
end function

' Whether `other` cuts the same thumbnails, so its sheet URLs can stand in for `man`'s.
function Trickplay_sameLayout(man as dynamic, other as dynamic) as boolean
    if man = invalid or other = invalid then return false
    if man.fileId <> other.fileId or man.intervalMs <> other.intervalMs or man.count <> other.count then return false
    if man.thumbW <> other.thumbW or man.thumbH <> other.thumbH or man.cols <> other.cols or man.rows <> other.rows then return false
    return man.sheetUrls.Count() = other.sheetUrls.Count()
end function

' The size a sheet is decoded at: the manifest's sheet size scaled down so neither side exceeds
' maxSide (texture memory; see PlayerTrickplay.brs). Returns { w, h }.
function Trickplay_decodeSize(man as object, maxSide as integer) as object
    w = man.cols * man.thumbW
    h = man.rows * man.thumbH
    big = w
    if h > big then big = h
    if big <= maxSide then return { w: w, h: h }
    k# = maxSide / (big * 1#)
    dw = Int(w * k# + 0.5)
    dh = Int(h * k# + 0.5)
    if dw < 1 then dw = 1
    if dh < 1 then dh = 1
    return { w: dw, h: dh }
end function

' Where the sheet Poster goes so that `tile` fills a winW x winH window, cropped to fill like
' ContentScale.Crop: { w, h } of the whole sheet as drawn and { x, y } of its top-left corner.
function Trickplay_placement(man as object, tile as object, winW as integer, winH as integer) as object
    k# = winW / (man.thumbW * 1#)
    kh# = winH / (man.thumbH * 1#)
    if kh# > k# then k# = kh#
    tw# = man.thumbW * k#
    th# = man.thumbH * k#
    ox# = (winW - tw#) / 2
    oy# = (winH - th#) / 2
    return {
        w: Int(man.cols * tw# + 0.5)
        h: Int(man.rows * th# + 0.5)
        x: Int(ox# - tile.col * tw# + 0.5)
        y: Int(oy# - tile.row * th# + 0.5)
    }
end function
