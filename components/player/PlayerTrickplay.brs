' SPDX-License-Identifier: AGPL-3.0-or-later
' The player's side of the server's seek-bar previews (silo-android #695, TrickplayPreviews.kt):
' reads GET /api/v2/watch/{id}/trickplay?file_id= for the streamed file when its version reports
' trickplay_available, and shows the thumbnail for the time being scrubbed to in a card above the
' focused scrubber ("card", 320x180 like the Android TV / tvOS card on a 1080p screen) or above the
' hidden-controls hold-seek chip ("frame", 480x270, PlayerHoldSeek.brs). Missing, refused or
' unusable previews keep the time-only preview.
'
' Roku has no image-cropping API, so a thumbnail is shown by drawing its whole JPEG sprite sheet in
' a Poster inside a Group whose clippingRect is the preview window, offset so the wanted tile sits
' in the window (Trickplay_placement). A MaskGroup around the clip only rounds the corners. Sheets
' are loaded on demand into a pool of TP_POOL Posters (least recently used goes first; the wanted
' and the shown sheet are never evicted), decoded at most TP_DECODE_SIDE on a side (loadWidth /
' loadHeight) to bound texture memory, and the Posters are emptied when the player closes, the
' file changes or the layout is remade. Sheet URLs are signed and go to the Poster as they are:
' a Poster sends no Silo credentials (presigned storage refuses a second credential).
' Console: [siku-trickplay] lines (never the sheet URLs, which are credentials).
' Needs Trickplay.brs, Utils.brs, Api.brs and these nodes in PlayerScreen.xml: tpView, tpBg,
' tpSlot, tpMask, tpClip, tpRing, tpTime, tpStaleTimer.

function TP_POOL() as integer
    return 3
end function

' Decoded sheet side cap: the server's default sheet (10x8 tiles of 300 px) is 3000x1344, which is
' 16 MB of texture at full size. 2048 keeps a sheet near 7.5 MB, so the pool stays under ~23 MB.
function TP_DECODE_SIDE() as integer
    return 2048
end function

function TP_BACKOFF_S() as integer
    return 30   ' a failed manifest read or sheet load is not repeated for this long
end function

function TP_RENEW_MARGIN_S() as integer
    return 60   ' sheet URLs are renewed this long before the manifest says they expire
end function

sub Trickplay_init()
    m.tpView = m.top.findNode("tpView")
    m.tpBg = m.top.findNode("tpBg")
    m.tpSlot = m.top.findNode("tpSlot")
    m.tpMask = m.top.findNode("tpMask")
    m.tpClip = m.top.findNode("tpClip")
    m.tpRing = m.top.findNode("tpRing")
    m.tpTime = m.top.findNode("tpTime")
    m.tpStaleTimer = m.top.findNode("tpStaleTimer")
    m.tpStaleTimer.observeField("fire", "Trickplay_onStale")
    m.tpPool = []
    for i = 0 to TP_POOL() - 1
        p = m.tpClip.createChild("Poster")
        p.id = "tpSheet" + i.ToStr()
        p.visible = false
        p.loadDisplayMode = "scaleToFit"
        p.observeField("loadStatus", "Trickplay_onSheetStatus")
        m.tpPool.Push({ node: p, sheet: -1, key: 0, status: "", usedAt: 0 })
    end for
    m.tp = {
        target: invalid      ' { itemId, fileId } whose previews are shown
        manifest: invalid
        ticket: 0            ' numbers manifest reads; a late answer for an older one is dropped
        reading: false
        refused: false       ' the server will not serve previews for this file
        failedAt: 0          ' when a manifest read last failed transiently (epoch s)
        renewing: false
        renewedAt: 0
        layoutKey: 1         ' bumped whenever the Posters stop matching the manifest
        seconds: invalid     ' the time being previewed, invalid when none
        mode: ""             ' "card" | "frame"
        want: invalid        ' the tile the latest show asked for
        shownTile: invalid   ' the tile on screen (invalid when no picture)
        sheetFailedAt: {}    ' sheet index (string) -> epoch s of its last failed load
        sheetRenewed: {}     ' sheet index (string) -> true once a failed load renewed the URLs
        slotKept: false      ' frame mode: a picture has shown in this hold-seek session
        staleArmed: false    ' tpStaleTimer runs for the picture on screen
    }
    m.tpClock = 0
end sub

' Binds the previews to the file streaming from the server (invalid for none). Called after every
' start and replan; a no-op while the file stays the same.
sub Trickplay_bind(itemId as string, fileId as string)
    target = invalid
    if m.sessionId <> "" and itemId <> "" and fileId <> "" and m.watch <> invalid then
        for each v in Arr_or(m.watch.versions)
            if v <> invalid and Str_orEmpty(v.file_id) = fileId and PlaybackCaps_truthy(v.trickplay_available) then target = { itemId: itemId, fileId: fileId }
        end for
    end if
    cur = m.tp.target
    if cur = invalid and target = invalid then return
    if cur <> invalid and target <> invalid then
        if cur.itemId = target.itemId and cur.fileId = target.fileId then return
    end if
    Trickplay_reset()
    m.tp.target = target
    if target <> invalid then Trickplay_readManifest(false)
end sub

' Forgets the file and empties every Poster (leaving the player, another item, another file).
sub Trickplay_reset()
    if m.tp = invalid then return
    m.tp.ticket = m.tp.ticket + 1
    m.tp.target = invalid
    m.tp.manifest = invalid
    m.tp.reading = false
    m.tp.refused = false
    m.tp.failedAt = 0
    m.tp.renewing = false
    m.tp.renewedAt = 0
    m.tp.seconds = invalid
    Trickplay_dropSheets()
    Trickplay_hidePicture()
    m.tpView.visible = false
end sub

sub Trickplay_dropSheets()
    m.tp.layoutKey = m.tp.layoutKey + 1
    for each e in m.tpPool
        e.node.visible = false
        e.node.uri = ""
        e.sheet = -1
        e.status = ""
    end for
    m.tp.want = invalid
    m.tp.shownTile = invalid
    m.tp.sheetFailedAt = {}
    m.tp.sheetRenewed = {}
end sub

sub Trickplay_readManifest(renewal as boolean)
    t = m.tp.target
    if t = invalid or m.tp.refused then return
    if renewal then
        if m.tp.renewing then return
        m.tp.renewing = true
        m.tp.renewedAt = Time_nowSeconds()
    else
        if m.tp.reading then return
        m.tp.reading = true
        m.tp.failedAt = 0
    end if
    m.tp.ticket = m.tp.ticket + 1
    ctx = { ticket: m.tp.ticket, renewal: renewal, itemId: t.itemId, fileId: t.fileId }
    Api_get("/api/v2/watch/" + Str_urlEncode(t.itemId) + "/trickplay", { file_id: t.fileId }, "Trickplay_onManifest", ctx)
end sub

sub Trickplay_onManifest(event as object)
    resp = Api_result(event)
    c = resp.context
    if m.closing or c = invalid or m.tp.target = invalid then return
    if c.itemId <> m.tp.target.itemId or c.fileId <> m.tp.target.fileId then return
    if c.renewal then m.tp.renewing = false else m.tp.reading = false
    status = Int(Num_or(resp.status, 0))
    if resp.ok then
        man = Trickplay_fromManifest(resp.data, c.fileId, m.global.session.serverOrigin)
        if man = invalid then
            print "[siku-trickplay] file=" + c.fileId + " manifest unusable; time-only preview"
            Trickplay_refuse()
            return
        end if
        expiresIn = -1
        if man.expiresAt > 0 then expiresIn = man.expiresAt - Time_nowSeconds()
        print "[siku-trickplay] file=" + c.fileId + " manifest renewal=" + Trickplay_yesNo(c.renewal) + " interval_ms=" + man.intervalMs.ToStr() + " tile=" + man.thumbW.ToStr() + "x" + man.thumbH.ToStr() + " grid=" + man.cols.ToStr() + "x" + man.rows.ToStr() + " count=" + man.count.ToStr() + " sheets=" + man.sheetUrls.Count().ToStr() + " expires_in=" + expiresIn.ToStr()
        Trickplay_install(man)
        return
    end if
    ' A dropped connection, rate limiting or a server error may pass; anything else is the answer.
    if status = 0 or status = 429 or status >= 500 then
        print "[siku-trickplay] file=" + c.fileId + " manifest read failed status=" + status.ToStr() + "; asking again after " + TP_BACKOFF_S().ToStr() + " s"
        if not c.renewal then m.tp.failedAt = Time_nowSeconds()
        return
    end if
    print "[siku-trickplay] file=" + c.fileId + " manifest refused status=" + status.ToStr() + "; time-only preview"
    Trickplay_refuse()
end sub

function Trickplay_yesNo(v as dynamic) as string
    if PlaybackCaps_truthy(v) then return "yes"
    return "no"
end function

sub Trickplay_refuse()
    m.tp.refused = true
    m.tp.manifest = invalid
    Trickplay_dropSheets()
    Trickplay_hidePicture()
end sub

' Takes a fresh manifest. Sheets already held stay when the thumbnails are laid out the same way
' (only the URLs changed); a remade layout drops them and asks for the time being previewed again.
sub Trickplay_install(man as object)
    cur = m.tp.manifest
    m.tp.manifest = man
    if cur <> invalid and Trickplay_sameLayout(cur, man) then
        ' Failed loads get another chance with the new URLs.
        for each e in m.tpPool
            if e.status = "failed" then
                e.node.uri = ""
                e.sheet = -1
                e.status = ""
            end if
        end for
        m.tp.sheetFailedAt = {}
    else
        Trickplay_dropSheets()
        Trickplay_hidePicture()
    end if
    if m.tp.seconds <> invalid then Trickplay_show(m.tp.seconds, m.tp.mode)
end sub

' Shows the preview of `seconds` (invalid ends the preview) in `mode` ("card" or "frame").
sub Trickplay_show(seconds as dynamic, mode as string)
    if m.tp = invalid then return
    if seconds = invalid then
        m.tp.seconds = invalid
        m.tp.want = invalid
        m.tp.slotKept = false
        Trickplay_hidePicture()
        m.tpView.visible = false
        return
    end if
    if mode <> m.tp.mode then
        m.tp.mode = mode
        Trickplay_layoutView()
        if m.tp.shownTile <> invalid then Trickplay_placeSheet(Trickplay_poolFind(m.tp.shownTile.sheet), m.tp.shownTile)
    end if
    m.tp.seconds = seconds
    m.tpTime.text = Time_clock(seconds)
    man = m.tp.manifest
    if man = invalid then
        Trickplay_hidePicture()
        if m.tp.target <> invalid and m.tp.failedAt > 0 and Time_nowSeconds() - m.tp.failedAt >= TP_BACKOFF_S() then Trickplay_readManifest(false)
        return
    end if
    tile = Trickplay_tileAt(man, seconds)
    if tile = invalid then
        m.tp.want = invalid
        Trickplay_hidePicture()
        return
    end if
    tile.key = m.tp.layoutKey
    m.tp.want = tile
    e = Trickplay_poolFind(tile.sheet)
    ready = invalid
    loading = false
    if e <> invalid then
        if e.status = "ready" then ready = e
        if e.status = "loading" then loading = true
    end if
    if ready <> invalid then
        Trickplay_display(ready, tile)
    else if loading then
        ' On its way: the previous picture stands in meanwhile.
        Trickplay_markStale()
    else if Trickplay_expiresSoon(man) and (m.tp.renewing or Trickplay_mayRenew()) then
        ' Fresh URLs first: the signed ones are about to expire. The answer shows the tile.
        Trickplay_markStale()
        Trickplay_readManifest(true)
        return
    else if Trickplay_load(tile.sheet) then
        Trickplay_markStale()
    else
        Trickplay_hidePicture()   ' a sheet that failed shows no picture rather than the last one
    end if
    ' Load the sheet after it too, so a forward scrub rarely waits.
    if tile.sheet + 1 < man.sheetUrls.Count() then Trickplay_load(tile.sheet + 1)
end sub

function Trickplay_expiresSoon(man as object) as boolean
    return man.expiresAt > 0 and man.expiresAt - Time_nowSeconds() < TP_RENEW_MARGIN_S()
end function

function Trickplay_mayRenew() as boolean
    if m.tp.renewing then return false
    return m.tp.renewedAt = 0 or Time_nowSeconds() - m.tp.renewedAt >= TP_BACKOFF_S()
end function

function Trickplay_poolFind(sheet as integer) as dynamic
    for each e in m.tpPool
        if e.sheet = sheet and e.key = m.tp.layoutKey then return e
    end for
    return invalid
end function

' Starts loading a sheet into a Poster unless it is held, loading, or failed within the backoff.
' Returns false when the sheet cannot be had now.
function Trickplay_load(sheet as integer) as boolean
    man = m.tp.manifest
    if man = invalid or sheet < 0 or sheet >= man.sheetUrls.Count() then return false
    m.tpClock = m.tpClock + 1
    e = Trickplay_poolFind(sheet)
    if e <> invalid then
        e.usedAt = m.tpClock
        if e.status <> "failed" then return true
        failedAt = m.tp.sheetFailedAt[sheet.ToStr()]
        if failedAt <> invalid and Time_nowSeconds() - failedAt < TP_BACKOFF_S() then return false
    end if
    if e = invalid then e = Trickplay_victim()
    if e = invalid then return false
    size = Trickplay_decodeSize(man, TP_DECODE_SIDE())
    e.node.visible = false
    e.node.uri = ""
    e.sheet = sheet
    e.key = m.tp.layoutKey
    e.status = "loading"
    e.usedAt = m.tpClock
    e.node.loadWidth = size.w
    e.node.loadHeight = size.h
    e.node.uri = man.sheetUrls[sheet]
    return true
end function

' The Poster to reuse: an empty one, else the least recently used that is neither wanted nor shown.
function Trickplay_victim() as dynamic
    best = invalid
    for each e in m.tpPool
        if e.sheet < 0 or e.key <> m.tp.layoutKey then return e
        busy = false
        if m.tp.want <> invalid and m.tp.want.sheet = e.sheet then busy = true
        if m.tp.shownTile <> invalid and m.tp.shownTile.sheet = e.sheet then busy = true
        if not busy then
            if best = invalid then
                best = e
            else if e.usedAt < best.usedAt then
                best = e
            end if
        end if
    end for
    return best
end function

sub Trickplay_onSheetStatus(event as object)
    node = event.getRoSGNode()
    st = Str_orEmpty(event.getData())
    if node = invalid or m.tp = invalid then return
    e = invalid
    for each p in m.tpPool
        if p.node.id = node.id then e = p
    end for
    if e = invalid or e.sheet < 0 or e.status <> "loading" then return
    if st = "ready" then
        e.status = "ready"
        m.tp.sheetFailedAt.Delete(e.sheet.ToStr())
        w = m.tp.want
        if w <> invalid and w.sheet = e.sheet and w.key = e.key and m.tp.seconds <> invalid then Trickplay_display(e, w)
    else if st = "failed" then
        e.status = "failed"
        sk = e.sheet.ToStr()
        m.tp.sheetFailedAt[sk] = Time_nowSeconds()
        print "[siku-trickplay] sheet " + sk + " failed to load"
        w = m.tp.want
        wanted = w <> invalid and w.sheet = e.sheet and w.key = e.key
        ' The Poster does not say why; an expired or revoked signature is the likely cause, so the
        ' URLs are read again once per sheet (the server answers 403/404 for a stale one).
        if m.tp.sheetRenewed[sk] <> true and Trickplay_mayRenew() then
            m.tp.sheetRenewed[sk] = true
            Trickplay_readManifest(true)
        else if wanted then
            Trickplay_hidePicture()
        end if
    end if
end sub

' Puts `e`'s sheet on screen so `tile` fills the window.
sub Trickplay_display(e as object, tile as object)
    for each p in m.tpPool
        if p.node.id <> e.node.id then p.node.visible = false
    end for
    Trickplay_placeSheet(e, tile)
    e.node.visible = true
    m.tp.shownTile = tile
    m.tpStaleTimer.control = "stop"
    m.tp.staleArmed = false
    m.tpMask.visible = true
    if m.tp.mode = "frame" then m.tp.slotKept = true
    Trickplay_refreshView()
end sub

sub Trickplay_placeSheet(e as dynamic, tile as dynamic)
    if e = invalid or tile = invalid or m.tp.manifest = invalid then return
    win = Trickplay_box()
    pl = Trickplay_placement(m.tp.manifest, tile, win.w, win.h)
    e.node.width = pl.w
    e.node.height = pl.h
    e.node.translation = [pl.x, pl.y]
end sub

' Until the next thumbnail is ready the previous one stays (no flashing), but for one second at
' most: after that it no longer stands for the time being previewed.
sub Trickplay_markStale()
    if m.tp.shownTile = invalid then return
    if m.tp.staleArmed then return
    m.tp.staleArmed = true
    m.tpStaleTimer.control = "stop"
    m.tpStaleTimer.control = "start"
end sub

sub Trickplay_onStale()
    m.tpStaleTimer.control = "stop"
    m.tp.staleArmed = false
    w = m.tp.want
    s = m.tp.shownTile
    if s = invalid then return
    if w = invalid or w.index <> s.index or w.key <> s.key then Trickplay_hidePicture()
end sub

sub Trickplay_hidePicture()
    if m.tp = invalid then return
    for each p in m.tpPool
        p.node.visible = false
    end for
    m.tp.shownTile = invalid
    m.tpStaleTimer.control = "stop"
    m.tp.staleArmed = false
    m.tpMask.visible = false
    Trickplay_refreshView()
end sub

function Trickplay_shown() as boolean
    return m.tp <> invalid and m.tp.shownTile <> invalid
end function

function Trickplay_box() as object
    if m.tp.mode = "frame" then return { w: 480, h: 270 }
    return { w: 320, h: 180 }
end function

' The window's chrome. Card (Android TV TvPlayerScrubber): opaque Smoke card with a 2 px stroke,
' 10 px padding, the 320x180 thumbnail with 14 px corners and the time under it. Frame
' (TvHoldSeekIndicator): the 480x270 thumbnail with 20 px corners and a light stroke, or a
' translucent placeholder once a picture has shown in this hold-seek session.
sub Trickplay_layoutView()
    win = Trickplay_box()
    if m.tp.mode = "frame" then
        m.tpBg.visible = false
        m.tpTime.visible = false
        m.tpMask.translation = [0, 0]
        m.tpSlot.width = win.w
        m.tpSlot.height = win.h
        m.tpRing.uri = "pkg:/images/ui/r20_ring2.9.png"
        m.tpRing.blendColor = "0xFFFFFF2E"
        m.tpRing.translation = [0, 0]
        m.tpRing.width = win.w
        m.tpRing.height = win.h
    else
        m.tpBg.visible = true
        m.tpTime.visible = true
        m.tpSlot.visible = false
        m.tpBg.width = Trickplay_cardWidth()
        m.tpBg.height = Trickplay_cardHeight()
        m.tpMask.translation = [10, 10]
        m.tpRing.uri = "pkg:/images/ui/r20_ring2.9.png"
        m.tpRing.blendColor = "0xFFFFFF1A"
        m.tpRing.translation = [0, 0]
        m.tpRing.width = Trickplay_cardWidth()
        m.tpRing.height = Trickplay_cardHeight()
        m.tpTime.translation = [0, 10 + win.h + 8]
        m.tpTime.width = Trickplay_cardWidth()
        m.tpTime.height = 31
    end if
    m.tpMask.maskSize = [win.w, win.h]
    m.tpClip.clippingRect = [0, 0, win.w, win.h]
end sub

function Trickplay_cardWidth() as integer
    return 340
end function

function Trickplay_cardHeight() as integer
    return 10 + 180 + 8 + 31 + 10
end function

' Shows the window when it has something to show: the card only with a picture; the frame with a
' picture or, once one has shown in this hold-seek session, its placeholder.
sub Trickplay_refreshView()
    if m.tp.seconds = invalid then
        m.tpView.visible = false
        return
    end if
    pic = m.tp.shownTile <> invalid
    if m.tp.mode = "frame" then
        m.tpSlot.visible = not pic and m.tp.slotKept
        m.tpView.visible = pic or m.tp.slotKept
        HoldSeek_layout()
    else
        m.tpView.visible = pic
    end if
end sub

' Places the card over the scrubber's puck (scrubber at `sx`,`sy`, width `sw`, 84 px tall), its
' bottom edge 44 px above the bar's middle, or 104 px when the rate chip shows above the puck.
sub Trickplay_placeCard(sx as integer, sy as integer, sw as integer, puckX as float, chip as boolean)
    if m.tp = invalid or m.tp.mode <> "card" then return
    cw = Trickplay_cardWidth()
    x = Int(puckX - cw / 2)
    if x > sw - cw then x = sw - cw
    if x < 0 then x = 0
    lift = 44
    if chip then lift = 104
    m.tpView.translation = [sx + x, sy + 42 - lift - Trickplay_cardHeight()]
end sub
