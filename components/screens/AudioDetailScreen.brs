' Album / artist / audiobook detail. See AudioDetailScreen.xml for the contract.
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.backdrop = m.top.findNode("backdrop")
    m.page = m.top.findNode("page")
    m.hero = m.top.findNode("hero")
    m.artIcon = m.top.findNode("artIcon")
    m.artMask = m.top.findNode("artMask")
    m.artImage = m.top.findNode("artImage")
    m.artPlaceholder = m.top.findNode("artPlaceholder")
    m.column = m.top.findNode("column")
    m.eyebrow = m.top.findNode("eyebrow")
    m.eyebrowLabel = m.top.findNode("eyebrowLabel")
    m.titleLabel = m.top.findNode("titleLabel")
    m.subtitleLabel = m.top.findNode("subtitleLabel")
    m.metaLabel = m.top.findNode("metaLabel")
    m.overview = m.top.findNode("overview")
    m.actions = m.top.findNode("actions")
    m.playBtn = m.top.findNode("playBtn")
    m.shuffleBtn = m.top.findNode("shuffleBtn")
    m.startOverBtn = m.top.findNode("startOverBtn")
    m.favBtn = m.top.findNode("favBtn")
    m.body = m.top.findNode("body")
    m.listSection = m.top.findNode("listSection")
    m.listHeader = m.top.findNode("listHeader")
    m.listMsg = m.top.findNode("listMsg")
    m.list = m.top.findNode("list")
    m.partsSection = m.top.findNode("partsSection")
    m.parts = m.top.findNode("parts")
    m.railSection = m.top.findNode("railSection")
    m.railHeader = m.top.findNode("railHeader")
    m.rail = m.top.findNode("rail")
    m.spinner = m.top.findNode("spinner")
    m.errorGroup = m.top.findNode("errorGroup")
    m.errorLabel = m.top.findNode("errorLabel")
    m.retryBtn = m.top.findNode("retryBtn")
    m.scrollAnim = m.top.findNode("scrollAnim")
    m.scrollInterp = m.top.findNode("scrollInterp")

    m.item = invalid
    m.kind = ""
    m.tracks = []
    m.albums = []
    m.timeline = invalid
    m.resume = -1.0
    m.finished = false
    m.isFavorite = false
    m.loaded = false
    m.reloadOnShow = false
    m.zone = "actions"
    m.actionIndex = 0
    m.lastFocus = invalid
    m.pageY = 0
    m.artistTracks = invalid

    m.playBtn.observeField("buttonSelected", "onPlay")
    m.shuffleBtn.observeField("buttonSelected", "onShuffle")
    m.startOverBtn.observeField("buttonSelected", "onStartOver")
    m.favBtn.observeField("buttonSelected", "onFavorite")
    m.retryBtn.observeField("buttonSelected", "load")
    for each b in [m.playBtn, m.shuffleBtn, m.startOverBtn, m.favBtn]
        b.observeField("width", "layoutActions")
    end for
    m.list.observeField("itemSelected", "onListSelected")
    m.parts.observeField("itemSelected", "onPartSelected")
    m.rail.observeField("rowItemSelected", "onRailSelected")
end sub

' ---------- Lifecycle ----------

sub onScreenShown()
    if not m.loaded then
        load()
        return
    end if
    if m.reloadOnShow or m.global.homeDirty = true then
        m.reloadOnShow = false
        reload()
    end if
    restoreFocus()
end sub

sub onScreenHidden()
    m.lastFocus = focusedZoneNode()
end sub

sub load()
    m.errorGroup.visible = false
    m.spinner.visible = true
    fetchItem()
end sub

' Refresh after playback without blanking the page (resume label, favorite state).
sub reload()
    fetchItem()
end sub

sub fetchItem()
    p = m.top.params
    query = { image_size: "medium" }
    if not Str_isEmpty(p.libraryId) then query.library_id = p.libraryId
    Api_get("/api/v2/catalog/items/" + Str_urlEncode(Str_orEmpty(p.itemId)), query, "onItem")
end sub

sub onItem(event as object)
    resp = Api_result(event)
    m.spinner.visible = false
    if not resp.ok or resp.data = invalid then
        if m.loaded then return
        m.hero.visible = false
        m.errorLabel.text = Api_errorText(resp)
        m.errorGroup.visible = true
        m.retryBtn.setFocus(true)
        return
    end if
    firstLoad = not m.loaded
    m.loaded = true
    m.item = resp.data
    kind = Audio_itemType(m.item)
    if kind = "" then kind = LCase(Str_orEmpty(m.top.params.itemType))
    m.kind = kind
    render()
    if firstLoad then
        m.zone = "actions"
        m.actionIndex = 0
        m.playBtn.setFocus(true)
        scrollTo(0)
    else
        restoreFocus()
    end if
end sub

' ---------- Rendering ----------

sub render()
    it = m.item
    m.hero.visible = true
    m.errorGroup.visible = false
    poster = Url_resolve(Str_orEmpty(it.poster_url))
    m.artImage.uri = poster
    m.backdrop.uri = Url_resolve(Str_orEmpty(it.backdrop_url))
    if m.backdrop.uri = "" then m.backdrop.uri = poster
    m.titleLabel.text = Str_orEmpty(it.title)
    m.overview.text = Str_orEmpty(it.overview)
    m.isFavorite = it.user_state <> invalid and it.user_state.is_favorite = true
    m.favBtn.active = m.isFavorite

    if m.kind = "artist" then
        m.artMask.maskUri = "pkg:/images/ui/mask_circle.png"
        m.artPlaceholder.uri = "pkg:/images/ui/circle.png"
        m.artIcon.uri = "pkg:/images/icons/person.png"
    else
        m.artMask.maskUri = "pkg:/images/ui/mask_square.png"
        m.artPlaceholder.uri = "pkg:/images/ui/r16.9.png"
        if m.kind = "audiobook" then m.artIcon.uri = "pkg:/images/icons/audiobook.png" else m.artIcon.uri = "pkg:/images/icons/album.png"
    end if

    m.listSection.visible = false
    m.partsSection.visible = false
    m.railSection.visible = false
    m.startOverBtn.visible = false
    m.shuffleBtn.visible = false
    m.playBtn.text = "Play"

    if m.kind = "audiobook" then
        renderAudiobook()
    else if m.kind = "artist" then
        renderArtist()
    else
        renderAlbum()
    end if
    layoutColumn()
    layoutActions()
    layoutBody()
end sub

sub renderAlbum()
    it = m.item
    if m.kind = "album" then m.eyebrowLabel.text = "ALBUM" else m.eyebrowLabel.text = UCase(m.kind)
    if m.kind = "" then m.eyebrowLabel.text = "AUDIO"
    artist = albumArtist(it)
    m.subtitleLabel.text = artist
    m.shuffleBtn.visible = true

    if m.kind = "album" then
        m.tracks = Arr_or(it.tracks)
        if m.tracks.Count() = 0 then m.tracks = Arr_or(it.items)
    else
        ' A single track / audio item: its own one-row list.
        m.tracks = [it]
    end if
    fillTrackList()
    if m.tracks.Count() = 0 and m.kind = "album" then
        ' Not inline: try the generic child listing.
        m.listMsg.text = "Loading tracks…"
        m.listMsg.visible = true
        Api_get("/api/v2/catalog/items/" + Str_urlEncode(Str_orEmpty(it.content_id)) + "/episodes", { image_size: "medium" }, "onChildren")
    end if
end sub

sub onChildren(event as object)
    resp = Api_result(event)
    if resp.ok and resp.data <> invalid then m.tracks = Arr_or(resp.data.items)
    fillTrackList()
    layoutBody()
end sub

sub fillTrackList()
    it = m.item
    m.listHeader.text = "Tracks"
    m.listSection.visible = true
    total = 0.0
    artist = albumArtist(it)
    root = CreateObject("roSGNode", "ContentNode")
    for i = 0 to m.tracks.Count() - 1
        t = m.tracks[i]
        num = Str_orEmpty(t.track_number)
        if num = "" then num = (i + 1).ToStr()
        if t.disc_number <> invalid and t.disc_number > 1 then num = Str_orEmpty(t.disc_number) + "-" + num
        sub2 = Str_orEmpty(t.artist)
        if sub2 = artist then sub2 = ""
        dur = trackDuration(t)
        total = total + dur
        trailing = ""
        if dur > 0 then trailing = Time_clock(dur)
        AudioList_rowNode(root, { id: Str_orEmpty(t.content_id), title: Str_orEmpty(t.title), number: num, subtitle: sub2, trailing: trailing })
    end for
    m.list.content = root
    if m.tracks.Count() = 0 then
        m.listMsg.text = "No tracks available"
        m.listMsg.visible = true
        m.list.visible = false
    else
        m.listMsg.visible = false
        m.list.visible = true
    end if
    parts = []
    if it.year <> invalid then parts.Push(Str_orEmpty(it.year))
    if m.kind = "album" and m.tracks.Count() > 0 then
        if m.tracks.Count() = 1 then parts.Push("1 track") else parts.Push(m.tracks.Count().ToStr() + " tracks")
    end if
    if total <= 0 then total = AudioTimeline_num(it.duration_seconds)
    if total > 0 then parts.Push(Time_runtime(total))
    genres = Arr_or(it.genres)
    if genres.Count() > 0 then parts.Push(genres[0])
    m.metaLabel.text = Str_joinDots(parts)
end sub

sub renderArtist()
    it = m.item
    m.eyebrowLabel.text = "ARTIST"
    genres = Arr_or(it.genres)
    gs = []
    for i = 0 to genres.Count() - 1
        if i < 3 then gs.Push(genres[i])
    end for
    m.subtitleLabel.text = Str_joinDots(gs)
    m.albums = Arr_or(it.albums)
    n = m.albums.Count()
    if n = 1 then m.metaLabel.text = "1 album" else m.metaLabel.text = n.ToStr() + " albums"
    if n = 0 then m.metaLabel.text = ""
    m.shuffleBtn.visible = n > 0
    m.playBtn.disabled = n = 0
    if n > 0 then
        m.railHeader.text = "Albums"
        cards = []
        for each a in m.albums
            c = AA_copy(a)
            if Str_isEmpty(c.type) then c.type = "album"
            cards.Push(c)
        end for
        setRail(cards, "year")
    end if
end sub

sub renderAudiobook()
    it = m.item
    m.eyebrowLabel.text = "AUDIOBOOK"
    ab = it.audiobook
    if ab = invalid then ab = {}
    m.subtitleLabel.text = personNames(ab.authors)
    ud = it.user_data
    if ud = invalid then ud = {}
    lastFile = Str_orEmpty(ud.last_file_id)
    m.timeline = AudioTimeline_build(it.versions, ab.total_duration_seconds, lastFile)
    total = AudioTimeline_num(ab.total_duration_seconds)
    if m.timeline <> invalid and m.timeline.total > total then total = m.timeline.total
    if total <= 0 then total = AudioTimeline_num(ud.duration_seconds)

    meta = []
    narr = personNames(ab.narrators)
    if narr <> "" then meta.Push("Narrated by " + narr)
    if total > 0 then meta.Push(Time_runtime(total))
    if it.year <> invalid then meta.Push(Str_orEmpty(it.year))
    if not Str_isEmpty(ab.publisher) then meta.Push(ab.publisher)
    m.metaLabel.text = Str_joinDots(meta)

    ' Resume / finished, as TvAudiobookDetailHero: resume when 30 s < position < duration - 5 s.
    posSec = AudioTimeline_num(ud.position_seconds)
    dur = AudioTimeline_num(ud.duration_seconds)
    if dur <= 0 then dur = total
    m.resume = -1.0
    m.finished = ud.played = true or (dur > 0 and posSec > 0 and posSec >= dur - 5)
    if posSec > 30 and dur > 0 and posSec < dur - 5 then m.resume = posSec
    chapters = []
    if m.timeline <> invalid then chapters = m.timeline.chapters
    if m.resume > 0 then
        ci = AudioTimeline_chapterAt(chapters, m.resume)
        if chapters.Count() > 1 and ci >= 0 then
            m.playBtn.text = "Resume Chapter " + (ci + 1).ToStr()
        else
            m.playBtn.text = "Resume " + Time_clock(m.resume)
        end if
        m.startOverBtn.visible = true
    else if m.finished then
        m.playBtn.text = "Play Again"
    else
        m.playBtn.text = "Play"
    end if
    m.playBtn.disabled = m.timeline = invalid and Arr_or(it.versions).Count() = 0

    ' Chapters
    if chapters.Count() > 0 then
        m.listHeader.text = "Chapters"
        m.listSection.visible = true
        m.listMsg.visible = false
        m.list.visible = true
        current = -1
        if m.resume > 0 then current = AudioTimeline_chapterAt(chapters, m.resume)
        root = CreateObject("roSGNode", "ContentNode")
        for i = 0 to chapters.Count() - 1
            ch = chapters[i]
            sub2 = ""
            if ch["end"] > ch.start then sub2 = Time_runtime(ch["end"] - ch.start)
            AudioList_rowNode(root, { id: i.ToStr(), title: ch.title, number: (i + 1).ToStr(), subtitle: sub2, trailing: Time_clock(ch.start), isCurrent: i = current })
        end for
        m.list.content = root
        if current >= 0 then m.list.jumpToItem = current
    end if

    ' Parts (multi-part books only)
    if m.timeline <> invalid and m.timeline.tracks.Count() > 1 then
        m.partsSection.visible = true
        root = CreateObject("roSGNode", "ContentNode")
        curTrack = -1
        if m.resume > 0 then curTrack = AudioTimeline_trackIndexAt(m.timeline, m.resume)
        for each tr in m.timeline.tracks
            AudioList_rowNode(root, { id: tr.index.ToStr(), title: "Part " + (tr.index + 1).ToStr(), number: (tr.index + 1).ToStr(), subtitle: "Starts at " + Time_clock(tr.offset), trailing: Time_clock(tr.duration), isCurrent: tr.index = curTrack })
        end for
        m.parts.content = root
    end if

    ' More by Author
    rel = ab.related
    more = []
    if rel <> invalid then more = Arr_or(rel.also_by_author)
    if more.Count() > 0 then
        m.railHeader.text = "More by " + firstPersonName(ab.authors, "Author")
        cards = []
        for each r in more
            c = AA_copy(r)
            c.type = "audiobook"
            cards.Push(c)
        end for
        setRail(cards, "year")
    end if
end sub

sub setRail(cards as object, subtitleKind as string)
    m.railSection.visible = true
    root = Content_rows([{ id: "rail", title: "", style: "poster", items: cards }])
    row = root.getChild(0)
    for i = 0 to row.getChildCount() - 1
        node = row.getChild(i)
        c = cards[i]
        if subtitleKind = "artist" then node.subtitle = albumArtist(c)
    end for
    m.rail.content = root
end sub

function albumArtist(it as object) as string
    a = Str_orEmpty(it.artist)
    if a = "" then a = Str_orEmpty(it.artist_name)
    if a = "" then a = Str_orEmpty(it.album_artist)
    if a = "" and Type(it.artists) = "roArray" and it.artists.Count() > 0 then
        f = it.artists[0]
        if Type(f) = "roAssociativeArray" then a = Str_orEmpty(f.name) else a = Str_orEmpty(f)
    end if
    return a
end function

function personNames(people as dynamic) as string
    names = []
    for each p in Arr_or(people)
        if Type(p) = "roAssociativeArray" then
            names.Push(Str_orEmpty(p.name))
        else
            names.Push(Str_orEmpty(p))
        end if
    end for
    return Str_joinDots(names, ", ")
end function

function firstPersonName(people as dynamic, fallback as string) as string
    arr = Arr_or(people)
    if arr.Count() = 0 then return fallback
    p = arr[0]
    if Type(p) = "roAssociativeArray" then return Str_orEmpty(p.name)
    return Str_orEmpty(p)
end function

function trackDuration(t as object) as float
    d = AudioTimeline_num(t.duration_seconds)
    if d <= 0 then d = AudioTimeline_num(t.duration)
    if d <= 0 and t.runtime <> invalid then d = AudioTimeline_num(t.runtime) * 60
    return d
end function

' Stacks the editorial column (variable title height).
sub layoutColumn()
    y = 0
    m.eyebrow.translation = [0, y]
    y = y + 46
    m.titleLabel.translation = [0, y]
    th = Int(Label_height(m.titleLabel))
    if th < 80 then th = 80
    y = y + th + 8
    if m.subtitleLabel.text <> "" then
        m.subtitleLabel.visible = true
        m.subtitleLabel.translation = [0, y]
        y = y + 50
    else
        m.subtitleLabel.visible = false
    end if
    if m.metaLabel.text <> "" then
        m.metaLabel.visible = true
        m.metaLabel.translation = [0, y]
        y = y + 44
    else
        m.metaLabel.visible = false
    end if
    y = y + 10
    if m.overview.text <> "" then
        m.overview.visible = true
        m.overview.translation = [0, y]
        y = y + Int(Label_height(m.overview)) + 28
    else
        m.overview.visible = false
    end if
    ' Keep the actions level with or below the cover's lower edge area.
    if y < 340 then y = 340
    m.actions.translation = [0, y]
    m.heroBottom = 116 + y + 76
    if m.heroBottom < 116 + 440 then m.heroBottom = 116 + 440
end sub

function actionButtons() as object
    out = []
    for each b in [m.playBtn, m.shuffleBtn, m.startOverBtn, m.favBtn]
        if b.visible then out.Push(b)
    end for
    return out
end function

sub layoutActions()
    x = 0
    for each b in actionButtons()
        b.translation = [x, 0]
        x = x + b.width + 18
    end for
end sub

' Stacks the visible body sections under the hero.
sub layoutBody()
    y = m.heroBottom + 72
    m.sectionY = {}
    if m.listSection.visible then
        m.listSection.translation = [0, y]
        m.sectionY.list = y
        rows = m.list.content
        n = 0
        if rows <> invalid then n = rows.getChildCount()
        if n = 0 then n = 1
        if n > 8 then n = 8
        y = y + 60 + n * 88 + 56
    end if
    if m.partsSection.visible then
        m.partsSection.translation = [0, y]
        m.sectionY.parts = y
        n = m.parts.content.getChildCount()
        if n > 6 then n = 6
        y = y + 60 + n * 88 + 56
    end if
    if m.railSection.visible then
        m.railSection.translation = [0, y]
        m.sectionY.rail = y
        y = y + 64 + 380 + 56
    end if
    m.pageBottom = y
end sub

' ---------- Focus zones ----------

function zones() as object
    out = ["actions"]
    if m.listSection.visible and m.list.visible then out.Push("list")
    if m.partsSection.visible then out.Push("parts")
    if m.railSection.visible then out.Push("rail")
    return out
end function

function zoneNode(z as string) as object
    if z = "list" then return m.list
    if z = "parts" then return m.parts
    if z = "rail" then return m.rail
    btns = actionButtons()
    if m.actionIndex >= btns.Count() then m.actionIndex = 0
    return btns[m.actionIndex]
end function

function focusedZoneNode() as dynamic
    if m.errorGroup.visible then return m.retryBtn
    return zoneNode(m.zone)
end function

sub focusZone(z as string)
    m.zone = z
    zoneNode(z).setFocus(true)
    if z = "actions" then
        scrollTo(0)
    else
        sy = m.sectionY[z]
        if sy = invalid then sy = 0
        ' Bring the section header near the top of the screen.
        target = Int(sy) - 120
        ' Don't scroll past the end of the page.
        maxScroll = Int(m.pageBottom) - 1040
        if target > maxScroll then target = maxScroll
        if target < 0 then target = 0
        scrollTo(-target)
    end if
end sub

sub restoreFocus()
    if m.errorGroup.visible then
        m.retryBtn.setFocus(true)
        return
    end if
    if not m.hero.visible then return
    focusZone(m.zone)
end sub

sub scrollTo(y as integer)
    if y = m.pageY then return
    m.scrollAnim.control = "stop"
    m.scrollInterp.keyValue = [m.page.translation, [0, y]]
    m.pageY = y
    m.scrollAnim.control = "start"
end sub

sub moveZone(delta as integer)
    zs = zones()
    idx = 0
    for i = 0 to zs.Count() - 1
        if zs[i] = m.zone then idx = i
    end for
    idx = idx + delta
    if idx < 0 or idx >= zs.Count() then return
    focusZone(zs[idx])
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then return false
    if m.errorGroup.visible or not m.hero.visible then return false
    if key = "down" then
        moveZone(1)
        return true
    else if key = "up" then
        moveZone(-1)
        return true
    else if m.zone = "actions" and (key = "left" or key = "right") then
        btns = actionButtons()
        if key = "left" and m.actionIndex > 0 then m.actionIndex = m.actionIndex - 1
        if key = "right" and m.actionIndex < btns.Count() - 1 then m.actionIndex = m.actionIndex + 1
        btns[m.actionIndex].setFocus(true)
        return true
    else if key = "play" then
        onPlay()
        return true
    end if
    return false
end function

' ---------- Actions ----------

sub onPlay()
    if m.item = invalid or m.playBtn.disabled then return
    if m.kind = "audiobook" then
        params = { itemId: Str_orEmpty(m.item.content_id), itemType: "audiobook" }
        if m.resume > 0 then
            params.startPosition = m.resume
        else if m.finished then
            params.startPosition = 0
        end if
        openPlayer(params)
    else if m.kind = "artist" then
        playArtist(false)
    else
        playTracks(0, false)
    end if
end sub

sub onShuffle()
    if m.kind = "artist" then
        playArtist(true)
    else
        playTracks(0, true)
    end if
end sub

sub onStartOver()
    if m.item = invalid then return
    openPlayer({ itemId: Str_orEmpty(m.item.content_id), itemType: "audiobook", startPosition: 0 })
end sub

sub onFavorite()
    if m.item = invalid then return
    id = Str_orEmpty(m.item.content_id)
    m.isFavorite = not m.isFavorite
    m.favBtn.active = m.isFavorite
    if m.isFavorite then
        Api_fire("PUT", "/api/v2/favorites/" + Str_urlEncode(id))
        m.global.toast = "Added to Favorites"
    else
        Api_fire("DELETE", "/api/v2/favorites/" + Str_urlEncode(id))
        m.global.toast = "Removed from Favorites"
    end if
    m.global.homeDirty = true
end sub

sub openPlayer(params as object)
    m.reloadOnShow = true
    m.lastFocus = focusedZoneNode()
    Nav_push("AudioPlayerScreen", params)
end sub

' Queue entries for the album's tracks, filling album / artist / cover from the album.
function trackQueue(tracks as object, album as object) as object
    q = []
    for each t in tracks
        e = Audio_queueEntry(t)
        if e.contentId <> "" then
            if e.album = "" and Audio_itemType(album) = "album" then e.album = Str_orEmpty(album.title)
            if e.artist = "" then e.artist = albumArtist(album)
            if e.posterUrl = "" then e.posterUrl = Str_orEmpty(album.poster_url)
            if e.durationSeconds <= 0 then e.durationSeconds = trackDuration(t)
            q.Push(e)
        end if
    end for
    return q
end function

sub playTracks(index as integer, shuffle as boolean)
    q = trackQueue(m.tracks, m.item)
    if q.Count() = 0 then
        m.global.toast = "Nothing to play"
        return
    end if
    if index >= q.Count() then index = 0
    openPlayer({ queue: q, index: index, shuffle: shuffle })
end sub

' Artist Play / Shuffle: fetch each album's tracks (up to 20 albums), then queue them in album order.
sub playArtist(shuffle as boolean)
    if m.albums.Count() = 0 or m.artistTracks <> invalid then return
    m.artistShuffle = shuffle
    m.artistTracks = []
    n = m.albums.Count()
    if n > 20 then n = 20
    m.artistPending = n
    for i = 0 to n - 1
        m.artistTracks.Push([])
        a = m.albums[i]
        Api_get("/api/v2/catalog/items/" + Str_urlEncode(Str_orEmpty(a.content_id)), { image_size: "medium" }, "onArtistAlbum", { index: i })
    end for
    m.spinner.visible = true
end sub

sub onArtistAlbum(event as object)
    resp = Api_result(event)
    if m.artistTracks = invalid then return
    i = resp.context.index
    if resp.ok and resp.data <> invalid then
        m.artistTracks[i] = trackQueue(Arr_or(resp.data.tracks), resp.data)
    end if
    m.artistPending = m.artistPending - 1
    if m.artistPending > 0 then return
    m.spinner.visible = false
    q = []
    for each group in m.artistTracks
        q.Append(group)
    end for
    m.artistTracks = invalid
    if q.Count() = 0 then
        m.global.toast = "Nothing to play"
        return
    end if
    openPlayer({ queue: q, index: 0, shuffle: m.artistShuffle })
end sub

sub onListSelected()
    i = m.list.itemSelected
    if m.kind = "audiobook" then
        if m.timeline = invalid or i < 0 or i >= m.timeline.chapters.Count() then return
        openPlayer({ itemId: Str_orEmpty(m.item.content_id), itemType: "audiobook", startPosition: m.timeline.chapters[i].start })
    else
        playTracks(i, false)
    end if
end sub

sub onPartSelected()
    i = m.parts.itemSelected
    if m.timeline = invalid or i < 0 or i >= m.timeline.tracks.Count() then return
    openPlayer({ itemId: Str_orEmpty(m.item.content_id), itemType: "audiobook", startPosition: m.timeline.tracks[i].offset })
end sub

sub onRailSelected()
    sel = m.rail.rowItemSelected
    if sel = invalid then return
    row = m.rail.content.getChild(sel[0])
    if row = invalid then return
    node = row.getChild(sel[1])
    if node = invalid then return
    t = node.itemType
    if t = "" then t = "album"
    m.lastFocus = m.rail
    Nav_push("AudioDetailScreen", { itemId: node.contentId, itemType: t })
end sub
