' SPDX-License-Identifier: AGPL-3.0-or-later
' Cases for components/player/Trickplay.brs, after silo-android TrickplayTileTest /
' TrickplayManifestTest (#695). Run with tools/trickplay_test.py.

sub Main()
    m.fails = 0
    m.cases = 0
    man = {
        fileId: "42", intervalMs: 10000, thumbW: 300, thumbH: 126, cols: 10, rows: 10, count: 1020,
        sheetUrls: [], expiresAt: 0
    }
    for i = 0 to 10
        man.sheetUrls.Push("https://silo.example/s/" + i.ToStr() + ".jpg")
    end for
    ' A time maps to the thumbnail covering it.
    tileIs("t=0", Trickplay_tileAt(man, 0), 0, 0, 0)
    tileIs("t=9.999", Trickplay_tileAt(man, 9.999), 0, 0, 0)
    tileIs("t=10", Trickplay_tileAt(man, 10), 0, 1, 0)
    tileIs("t=1235 (thumb 123)", Trickplay_tileAt(man, 1235), 1, 3, 2)
    ' Past the end: the last thumbnail.
    tileIs("t=10195", Trickplay_tileAt(man, 10195), 10, 9, 1)
    tileIs("t=99999", Trickplay_tileAt(man, 99999), 10, 9, 1)
    tileIs("t=1e30", Trickplay_tileAt(man, 1e30), 10, 9, 1)
    check("t<0 has none", Trickplay_tileAt(man, -0.5) = invalid)

    origin = "http://127.0.0.1:8112"
    ok = fixture()
    v = Trickplay_fromManifest(ok, "42", origin)
    check("fixture validates", v <> invalid)
    if v <> invalid then
        check("fixture urls resolved", v.sheetUrls[0] = origin + "/api/v2/artwork/trickplay/42/9913/0.9913.jpg?exp=1767409445&sig=a")
        check("fixture sheet 10 in order", Right(v.sheetUrls[10], 5) = "sig=k")
        check("fixture expiry parsed", v.expiresAt = 1767409445)
        check("fixture geometry", v.cols = 10 and v.rows = 10 and v.count = 1020 and v.thumbW = 300 and v.thumbH = 126 and v.intervalMs = 10000)
    end if
    check("another file is refused", Trickplay_fromManifest(fixture(), "43", origin) = invalid)
    check("numeric file id accepted", Trickplay_fromManifest(withKey(fixture(), "file_id", 42), "42", origin) <> invalid)
    check("string numbers accepted", Trickplay_fromManifest(withKey(fixture(), "tile_columns", "10"), "42", origin) <> invalid)
    check("zero interval refused", Trickplay_fromManifest(withKey(fixture(), "interval_ms", 0), "42", origin) = invalid)
    check("zero count refused", Trickplay_fromManifest(withKey(fixture(), "thumbnail_count", 0), "42", origin) = invalid)
    check("fractional width refused", Trickplay_fromManifest(withKey(fixture(), "thumbnail_width", 300.5), "42", origin) = invalid)
    check("sheet wider than 8192 refused", Trickplay_fromManifest(withKey(fixture(), "thumbnail_width", 900), "42", origin) = invalid)
    f = fixture()
    f.sheets.Pop()
    check("missing sheet refused", Trickplay_fromManifest(f, "42", origin) = invalid)
    f = fixture()
    f.sheets[3].index = 2
    check("duplicate index refused", Trickplay_fromManifest(f, "42", origin) = invalid)
    f = fixture()
    f.sheets[1].url = "ftp://x/1.jpg"
    check("non-http url refused", Trickplay_fromManifest(f, "42", origin) = invalid)
    f = fixture()
    f.sheets[1].url = "https://cdn.example/1.jpg?X-Amz-Signature=z"
    check("absolute presigned url kept", Trickplay_fromManifest(f, "42", origin) <> invalid)
    f = fixture()
    f.sheets.Reverse()
    check("sheets sorted by index", Trickplay_fromManifest(f, "42", origin) <> invalid)
    check("bad expiry still usable", Trickplay_fromManifest(withKey(fixture(), "expires_at", "soon"), "42", origin).expiresAt = 0)

    ' Placement: a 300x168 tile cropped to fill 320x180.
    m2 = { thumbW: 300, thumbH: 168, cols: 10, rows: 8 }
    pl = Trickplay_placement(m2, { col: 2, row: 1 }, 320, 180)
    ' k = max(320/300, 180/168) = 1.0714; tile drawn 321.4x180; offset x = (320-321.4)/2 - 2*321.4 = -643.6 -> -644.
    check("placement size", pl.w = 3214 and pl.h = 1440)
    check("placement offset", pl.x = -644 and pl.y = -180)
    ds = Trickplay_decodeSize(m2, 2048)
    check("decode size capped", ds.w = 2048 and ds.h = 918)
    ds = Trickplay_decodeSize({ thumbW: 160, thumbH: 90, cols: 10, rows: 8 }, 2048)
    check("decode size kept when small", ds.w = 1600 and ds.h = 720)
    check("same layout", Trickplay_sameLayout(v, Trickplay_fromManifest(withKey(fixture(), "expires_at", "2026-01-04T00:00:00Z"), "42", origin)))
    check("remade layout", not Trickplay_sameLayout(v, Trickplay_fromManifest(withKey(fixture(), "interval_ms", 5000), "42", origin)))

    if m.fails = 0 then
        print "TRICKPLAY-TESTS RESULT pass " + m.cases.ToStr()
    else
        print "TRICKPLAY-TESTS FAIL " + m.fails.ToStr() + " of " + m.cases.ToStr()
    end if
end sub

sub check(name as string, cond as boolean)
    m.cases = m.cases + 1
    if not cond then
        m.fails = m.fails + 1
        print "TRICKPLAY-TESTS FAIL case: " + name
    end if
end sub

sub tileIs(name as string, t as dynamic, sheet as integer, col as integer, row as integer)
    if t = invalid then
        check(name + " (invalid)", false)
        return
    end if
    if not (t.sheet = sheet and t.col = col and t.row = row) then print "  got sheet=" + t.sheet.ToStr() + " col=" + t.col.ToStr() + " row=" + t.row.ToStr()
    check(name, t.sheet = sheet and t.col = col and t.row = row)
end sub

function withKey(aa as object, key as string, value as dynamic) as object
    aa[key] = value
    return aa
end function

' silo-android get_watch_trickplay_ok.json
function fixture() as object
    letters = "abcdefghijk"
    sheets = []
    for i = 0 to 10
        sheets.Push({ index: i, url: "/api/v2/artwork/trickplay/42/9913/" + i.ToStr() + ".9913.jpg?exp=1767409445&sig=" + Mid(letters, i + 1, 1) })
    end for
    return {
        file_id: "42", interval_ms: 10000, thumbnail_width: 300, thumbnail_height: 126,
        tile_columns: 10, tile_rows: 10, thumbnail_count: 1020, sheets: sheets,
        expires_at: "2026-01-03T03:04:05.000Z"
    }
end function
