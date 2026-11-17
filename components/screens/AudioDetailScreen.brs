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
    ' DetailCircleButton's `label` field is not one I18n_translateTree reads (keep in step with the XML).
    m.shuffleBtn.label = Tx("Shuffle")
    m.startOverBtn.label = Tx("Start Over")
    m.favBtn.label = Tx("Favorite")
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
    m.scrimLeft = m.top.findNode("scrimLeft")
    m.scrimBottom = m.top.findNode("scrimBottom")
    ' Audiobook hero (Silo Android #975, TvAudiobookDetailHero).
    m.bookHero = m.top.findNode("bookHero")
    m.bookWash = m.top.findNode("bookWash")
    m.bookArt = m.top.findNode("bookArt")
    m.bookCover = m.top.findNode("bookCover")
    m.bookColumn = m.top.findNode("bookColumn")
    m.bookEyebrowLabel = m.top.findNode("bookEyebrowLabel")
    m.bookTitle = m.top.findNode("bookTitle")
    m.bookSeries = m.top.findNode("bookSeries")
    m.bookCredits = m.top.findNode("bookCredits")
    m.bookState = m.top.findNode("bookState")
    m.bookRing = m.top.findNode("bookRing")
    m.bookRingArc = m.top.findNode("bookRingArc")
    m.bookRingPct = m.top.findNode("bookRingPct")
    m.bookState1 = m.top.findNode("bookState1")
    m.bookState2 = m.top.findNode("bookState2")
    m.bookActions = m.top.findNode("bookActions")
    m.bookPlayBtn = m.top.findNode("bookPlayBtn")
    m.chaptersBtn = m.top.findNode("chaptersBtn")
    m.bookStartOverBtn = m.top.findNode("bookStartOverBtn")
    m.bookFavBtn = m.top.findNode("bookFavBtn")
    m.finishedBtn = m.top.findNode("finishedBtn")
    m.bookFavBtn.label = Tx("Favorite")
    m.finishedBtn.label = Tx("Finished")
    m.aboutSection = m.top.findNode("aboutSection")
    m.aboutCard = m.top.findNode("aboutCard")
    m.aboutFocus = m.top.findNode("aboutFocus")
    m.aboutText = m.top.findNode("aboutText")
    m.aboutFacts = m.top.findNode("aboutFacts")
    m.chapterPanel = m.top.findNode("chapterPanel")

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
    m.loadedRev = -1
    m.zone = "actions"
    m.actionIndex = 0
    m.lastFocus = invalid
    m.pageY = 0
    m.artistTracks = invalid
    m.artistGen = 0
    m.heroBottom = 0
    m.bookChapters = []
    m.bookTotal = 0.0
    m.bookPlayed = false        ' the saved played flag the Finished toggle shows and flips
    m.bookScroll = 0            ' how far the action row is scrolled left (it outgrows the hero)
    m.bookX = []
    m.bookRowW = 0
    m.bookActionsY = 0
    m.finishedSeq = 0           ' the newest Finished write: only its answer may roll back
    m.aboutExpanded = false
    m.aboutH = 0
    m.factsH = 0
    m.bookStateLogged = ""
    m.bookStateH = 70

    m.playBtn.observeField("buttonSelected", "onPlay")
    m.shuffleBtn.observeField("buttonSelected", "onShuffle")
    m.startOverBtn.observeField("buttonSelected", "onStartOver")
    m.favBtn.observeField("buttonSelected", "onFavorite")
    m.retryBtn.observeField("buttonSelected", "load")
    m.bookPlayBtn.observeField("buttonSelected", "onPlay")
    m.chaptersBtn.observeField("buttonSelected", "openChapters")
    m.bookStartOverBtn.observeField("buttonSelected", "onStartOver")
    m.bookFavBtn.observeField("buttonSelected", "onFavorite")
    m.finishedBtn.observeField("buttonSelected", "onFinishedToggle")
    m.chapterPanel.observeField("chosen", "onChapterChosen")
    m.chapterPanel.observeField("dismissed", "closeChapters")
    for each b in [m.playBtn, m.shuffleBtn, m.startOverBtn, m.favBtn, m.bookPlayBtn, m.chaptersBtn, m.bookStartOverBtn, m.bookFavBtn, m.finishedBtn]
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
    ' The shared data revision (DataRevision.brs), not homeDirty itself: Home may have folded the
    ' flag into the revision before this page came back.
    if m.reloadOnShow or DataRev_current() <> m.loadedRev then
        m.reloadOnShow = false
        reload()
    end if
    restoreFocus()
end sub

sub onScreenHidden()
    m.lastFocus = focusedZoneNode()
    ' Leaving the page cancels an artist Play / Shuffle that is still fetching albums, so the
    ' player does not open over another screen.
    if m.artistTracks <> invalid then
        m.artistTracks = invalid
        m.artistGen = m.artistGen + 1
        m.spinner.visible = false
    end if
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
    m.loadedRev = DataRev_current()
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
        m.bookHero.visible = false
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
        playButton().setFocus(true)
        if m.kind = "audiobook" then applyBookScroll()
        scrollTo(0)
    else
        restoreFocus()
    end if
end sub

' ---------- Rendering ----------

sub render()
    it = m.item
    ' Keep focus on the same action when the row changes (Start Over comes and goes with the state).
    prevBtn = invalid
    if m.zone = "actions" and heroShown() then prevBtn = zoneNode("actions")
    isBook = m.kind = "audiobook"
    m.hero.visible = not isBook
    m.bookHero.visible = isBook
    m.backdrop.visible = not isBook
    m.scrimLeft.visible = not isBook
    m.scrimBottom.visible = not isBook
    m.aboutSection.visible = false
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
    m.playBtn.text = Tx("Play")

    if isBook then
        renderAudiobook()
        layoutBookColumn()
    else if m.kind = "artist" then
        renderArtist()
        layoutColumn()
    else
        renderAlbum()
        layoutColumn()
    end if
    if prevBtn <> invalid then
        m.actionIndex = 0
        btns = actionButtons()
        for i = 0 to btns.Count() - 1
            if btns[i].isSameNode(prevBtn) then m.actionIndex = i
        end for
    end if
    layoutActions()
    layoutBody()
end sub

sub renderAlbum()
    it = m.item
    if m.kind = "album" then m.eyebrowLabel.text = Tx("ALBUM") else m.eyebrowLabel.text = UCase(m.kind)
    if m.kind = "" then m.eyebrowLabel.text = Tx("AUDIO")
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
        m.listMsg.text = Tx("Loading tracks…")
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
    m.listHeader.text = Tx("Tracks")
    m.listSection.visible = true
    total = 0.0
    artist = albumArtist(it)
    root = CreateObject("roSGNode", "ContentNode")
    for i = 0 to m.tracks.Count() - 1
        t = m.tracks[i]
        num = Str_orEmpty(t.track_number)
        if num = "" then num = (i + 1).ToStr()
        if AudioTimeline_num(t.disc_number) > 1 then num = Str_orEmpty(t.disc_number) + "-" + num
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
        m.listMsg.text = Tx("No tracks available")
        m.listMsg.visible = true
        m.list.visible = false
    else
        m.listMsg.visible = false
        m.list.visible = true
    end if
    parts = []
    if it.year <> invalid then parts.Push(Str_orEmpty(it.year))
    if m.kind = "album" and m.tracks.Count() > 0 then
        parts.Push(TxP("1 track", "{0} tracks", m.tracks.Count()))
    end if
    if total <= 0 then total = AudioTimeline_num(it.duration_seconds)
    if total > 0 then parts.Push(Time_runtime(total))
    genres = Arr_or(it.genres)
    if genres.Count() > 0 then parts.Push(genres[0])
    m.metaLabel.text = Str_joinDots(parts)
end sub

sub renderArtist()
    it = m.item
    m.eyebrowLabel.text = Tx("ARTIST")
    genres = Arr_or(it.genres)
    gs = []
    for i = 0 to genres.Count() - 1
        if i < 3 then gs.Push(genres[i])
    end for
    m.subtitleLabel.text = Str_joinDots(gs)
    m.albums = Arr_or(it.albums)
    n = m.albums.Count()
    m.metaLabel.text = TxP("1 album", "{0} albums", n)
    if n = 0 then m.metaLabel.text = ""
    m.shuffleBtn.visible = n > 0
    m.playBtn.disabled = n = 0
    if n > 0 then
        m.railHeader.text = Tx("Albums")
        cards = []
        for each a in m.albums
            c = AA_copy(a)
            if Str_isEmpty(c.type) then c.type = "album"
            cards.Push(c)
        end for
        setRail(cards, "year")
    end if
end sub

' The tvOS "Lounge" hero (Silo Android #975, TvAudiobookDetailHero): identity, listening state and the
' action row; then About, Parts and More by Author below. Chapters live in a panel (openChapters).
sub renderAudiobook()
    it = m.item
    ab = it.audiobook
    if Type(ab) <> "roAssociativeArray" then ab = {}
    ud = it.user_data
    if Type(ud) <> "roAssociativeArray" then ud = {}
    cid = Str_orEmpty(it.content_id)
    m.timeline = AudioTimeline_build(it.versions, ab.total_duration_seconds, Str_orEmpty(ud.last_file_id))
    ' The larger of the server's total and the stitched parts, so a stale short total can't make a
    ' position in the last parts look finished (AudiobookText.totalDurationSeconds).
    total = AudioTimeline_num(ab.total_duration_seconds)
    if m.timeline <> invalid and m.timeline.total > total then total = m.timeline.total
    if total <= 0 then total = AudioTimeline_num(ud.duration_seconds)
    m.bookTotal = total
    m.bookChapters = []
    if m.timeline <> invalid then m.bookChapters = m.timeline.chapters

    ' Identity: eyebrow, title without the baked-in series locator, gold series line, credits.
    seriesName = ""
    entries = invalid
    if Type(ab.series) = "roAssociativeArray" then
        seriesName = Str_orEmpty(ab.series.name).Trim()
        entries = ab.series.entries
    end if
    rawTitle = Str_orEmpty(it.title)
    m.bookTitle.text = AudiobookFormat_cleanTitle(rawTitle, seriesName)
    genres = Arr_or(it.genres)
    genre = ""
    if genres.Count() > 0 then genre = Str_orEmpty(genres[0]).Trim()
    ' A genre is server text: it capitalises without the interface language.
    if genre <> "" then m.bookEyebrowLabel.text = TxF("AUDIOBOOK · {0}", [UCase(genre)]) else m.bookEyebrowLabel.text = Tx("AUDIOBOOK")
    m.bookSeries.text = ""
    if seriesName <> "" then
        seriesText = seriesName
        idx = AudiobookFormat_seriesIndex(cid, rawTitle, entries)
        if idx <> invalid then
            vol = AudiobookFormat_volume(rawTitle)
            if vol.total <> invalid and vol.total >= idx and vol.total > 1 then
                seriesText = TxF("{0} · Book {1} of {2}", [seriesName, idx, vol.total])
            else
                seriesText = TxF("{0} · Book {1}", [seriesName, idx])
            end if
        end if
        m.bookSeries.text = I18n_upper(seriesText)
    end if
    author = peopleLine(ab.authors, 2)
    narrator = peopleLine(ab.narrators, 2)
    if author <> "" and narrator <> "" then
        m.bookCredits.text = TxF("by {0} · read by {1}", [author, narrator])
    else if author <> "" then
        m.bookCredits.text = TxF("by {0}", [author])
    else if narrator <> "" then
        m.bookCredits.text = TxF("read by {0}", [narrator])
    else
        m.bookCredits.text = ""
    end if

    ' Cover and wash; spoiler protection hides an image by drawing the plain surface (a book's cover
    ' is never an episode still, so today this always shows it).
    cover = Url_resolve(Spoilers_imageUrl(it, "poster"))
    m.bookCover.uri = cover
    m.bookWash.uri = cover
    m.bookWash.visible = cover <> ""

    ' Listening state. This device's record (AudioResume.brs) wins while the server still holds what
    ' we left it at: it keeps the start and the end of the book, which the server's thresholds drop.
    posSec = Num_or(ud.position_seconds)
    localPos = AudioResume_position(Settings_identity(), cid, posSec)
    if localPos >= 0 then posSec = localPos
    st = AudiobookFormat_state(posSec, total, bookPlayedFlag(it))
    m.resume = st.resume
    m.finished = st.finished
    m.bookPlayed = st.played
    renderBookState(posSec)

    ' Actions: Play / Resume / Play Again, Chapters (only with chapters), Start Over (only with progress
    ' to discard), Favorite, Finished (the saved flag, not the near-the-end guess).
    if m.resume > 0 then
        m.bookPlayBtn.text = Tx("Resume")
    else if m.finished then
        m.bookPlayBtn.text = Tx("Play Again")
    else
        m.bookPlayBtn.text = Tx("Play")
    end if
    if m.resume <= 0 and m.finished then m.bookPlayBtn.iconUri = "pkg:/images/icons/replay.png" else m.bookPlayBtn.iconUri = "pkg:/images/icons/play.png"
    m.bookPlayBtn.disabled = m.timeline = invalid and Arr_or(it.versions).Count() = 0
    m.chaptersBtn.visible = m.bookChapters.Count() > 0
    m.bookStartOverBtn.visible = m.resume > 0
    m.bookFavBtn.active = m.isFavorite
    if m.isFavorite then m.bookFavBtn.a11yLabel = Tx("Remove from Favorites") else m.bookFavBtn.a11yLabel = Tx("Add to Favorites")
    m.finishedBtn.active = m.bookPlayed
    if m.bookPlayed then m.finishedBtn.a11yLabel = Tx("Mark as Not Finished") else m.finishedBtn.a11yLabel = Tx("Mark as Finished")

    fillAbout(total)

    ' Parts (multi-part books only)
    if m.timeline <> invalid and m.timeline.tracks.Count() > 1 then
        m.partsSection.visible = true
        root = CreateObject("roSGNode", "ContentNode")
        curTrack = -1
        if m.resume > 0 then curTrack = AudioTimeline_trackIndexAt(m.timeline, m.resume)
        for each tr in m.timeline.tracks
            AudioList_rowNode(root, { id: tr.index.ToStr(), title: TxF("Part {0}", [tr.index + 1]), number: (tr.index + 1).ToStr(), subtitle: TxF("Starts at {0}", [Time_clock(tr.offset)]), trailing: Time_clock(tr.duration), isCurrent: tr.index = curTrack })
        end for
        m.parts.content = root
    end if

    ' More by Author
    rel = ab.related
    more = []
    if Type(rel) = "roAssociativeArray" then more = Arr_or(rel.also_by_author)
    if more.Count() > 0 then
        m.railHeader.text = TxF("More by {0}", [firstPersonName(ab.authors, Tx("Author"))])
        cards = []
        for each r in more
            c = AA_copy(r)
            c.type = "audiobook"
            cards.Push(c)
        end for
        setRail(cards, "year")
    end if

    stateName = "not_started"
    if m.resume > 0 then stateName = "listening"
    if m.finished then stateName = "finished"
    cleaned = "no"
    if m.bookTitle.text <> rawTitle.Trim() then cleaned = "yes"
    logLine = Diag_join(["[siku-detail] audiobook hero state=", stateName, " played=", m.bookPlayed, " resume=", Int(m.resume), " chapters=", m.bookChapters.Count(), " title_cleaned=", cleaned, " series_line=", m.bookSeries.text <> ""])
    if logLine <> m.bookStateLogged then
        m.bookStateLogged = logLine
        Diag_log(logLine)
    end if
end sub

' The saved played flag (user_data, else user_state). Read as a boolean only (pitfall 16).
function bookPlayedFlag(it as object) as boolean
    for each k in ["user_data", "user_state"]
        v = it[k]
        if Type(v) = "roAssociativeArray" then
            f = v.played
            if (Type(f) = "roBoolean" or Type(f) = "Boolean") and f then return true
        end if
    end for
    return false
end function

' "A & B", or "A, B & 3 more" past `visible` names (AudiobookText.people).
function peopleLine(people as dynamic, visible as integer) as string
    sm = AudiobookFormat_peopleSummary(people, visible)
    if sm = invalid then return ""
    if sm.remaining = 0 then return AudiobookFormat_naturalJoin(sm.shown)
    return TxF("{0} & {1} more", [Str_joinDots(sm.shown, ", "), sm.remaining])
end function

' tvOS state cluster: a ring with the chapter and time left while listening, a full ring once
' finished, the length and chapter count before the first listen. No ring for an unknown length.
sub renderBookState(posSec as float)
    chapters = m.bookChapters
    total = m.bookTotal
    frac = -1.0
    line1 = ""
    line2 = ""
    if m.resume > 0 then
        if total > 0 then
            frac = posSec / total
            if frac > 1 then frac = 1.0
            if frac < 0 then frac = 0.0
        end if
        ci = -1
        if chapters.Count() > 0 then ci = AudioTimeline_chapterAt(chapters, posSec)
        if ci >= 0 then
            line1 = TxF("Chapter {0} · {1}", [ci + 1, chapters[ci].title])
        else if Time_runtime(posSec) <> "" then
            line1 = TxF("{0} listened", [Time_runtime(posSec)])
        else
            line1 = Tx("In progress")
        end if
        parts = []
        if ci >= 0 then parts.Push(TxF("{0} into the chapter", [Time_clock(posSec - chapters[ci].start)]))
        if frac >= 0 then
            remain = total - posSec
            if remain < 0 then remain = 0
            leftText = Time_runtime(remain)
            if leftText <> "" then parts.Push(TxF("{0} left in the book", [leftText]))
        end if
        line2 = Str_joinDots(parts)
    else if m.finished then
        frac = 1.0
        line1 = Tx("Finished")
        line2 = Time_runtime(total)
    else
        line1 = Tx("Not started")
        parts = []
        rt = Time_runtime(total)
        if rt <> "" then parts.Push(rt)
        if chapters.Count() > 0 then parts.Push(TxP("{0} chapter", "{0} chapters", chapters.Count()))
        line2 = Str_joinDots(parts)
    end if
    m.bookState1.text = line1
    m.bookState2.text = line2
    m.bookRing.visible = frac >= 0
    x = 0
    if frac >= 0 then
        x = 134
        steps = Int(frac * 36 + 0.5)
        if steps = 0 and frac > 0 then steps = 1
        if steps > 0 then
            m.bookRingArc.uri = "pkg:/images/ui/ring/ring_" + Str_padLeft(steps.ToStr(), 2) + ".png"
            m.bookRingArc.visible = true
        else
            m.bookRingArc.visible = false
        end if
        m.bookRingPct.text = Int(frac * 100 + 0.5).ToStr() + "%"
    end if
    if line2 <> "" then
        y1 = 0
        if frac >= 0 then y1 = 20
        m.bookState1.translation = [x, y1]
        m.bookState2.translation = [x, y1 + 40]
        m.bookState2.visible = true
    else
        y1 = 0
        if frac >= 0 then y1 = 38
        m.bookState1.translation = [x, y1]
        m.bookState2.visible = false
    end if
    m.bookState1.width = 1040 - x
    m.bookState2.width = 1040 - x
    m.bookStateH = 70
    if frac >= 0 then
        m.bookStateH = 112
    else if line2 = "" then
        m.bookStateH = 36
    end if
end sub

' tvOS About: the description beside the book's facts (AudiobookText.facts).
sub fillAbout(total as float)
    it = m.item
    overview = Str_orEmpty(it.overview).Trim()
    facts = bookFacts(total)
    m.aboutSection.visible = overview <> "" or facts.Count() > 0
    m.aboutText.text = overview
    m.aboutText.visible = overview <> ""
    m.aboutFacts.removeChildrenIndex(m.aboutFacts.getChildCount(), 0)
    y = 0
    for each f in facts
        lbl = m.aboutFacts.createChild("Label")
        lbl.font = ThemeFont("bold", 21)
        lbl.color = "0xFFFFFF80"
        lbl.width = 480
        lbl.maxLines = 1
        lbl.text = I18n_upper(f[0])
        lbl.translation = [0, y]
        y = y + 30
        valueLbl = m.aboutFacts.createChild("Label")
        valueLbl.font = ThemeFont("regular", 24)
        valueLbl.color = "0xFFFFFFE6"
        valueLbl.width = 480
        valueLbl.wrap = true
        valueLbl.maxLines = 2
        valueLbl.text = f[1]
        valueLbl.translation = [0, y]
        vh = Int(Label_height(valueLbl))
        if vh < 30 then vh = 30
        if vh > 64 then vh = 64
        y = y + vh + 18
    end for
    m.factsH = y
    if overview = "" then m.aboutFacts.translation = [0, 0] else m.aboutFacts.translation = [1080, 0]
    layoutAbout()
end sub

' Label, value pairs: who wrote and reads it, the publisher, when it was released, how long it runs
' and the file format.
function bookFacts(total as float) as object
    it = m.item
    ab = it.audiobook
    if Type(ab) <> "roAssociativeArray" then ab = {}
    out = []
    for each role in [["authors", "Author", "Authors"], ["narrators", "Narrator", "Narrators"]]
        names = ab[role[0]]
        credit = peopleLine(names, 3)
        if credit <> "" then
            everyone = AudiobookFormat_peopleSummary(names, 1000)
            label = Tx(role[1])
            if everyone <> invalid and everyone.shown.Count() > 1 then label = Tx(role[2])
            out.Push([label, credit])
        end if
    end for
    pub = Str_orEmpty(ab.publisher).Trim()
    if pub <> "" then out.Push([Tx("Publisher"), pub])
    released = ""
    if not Str_isEmpty(it.release_date) then released = Time_longDate(it.release_date)
    if released = "" and Num_or(it.year) > 0 then released = Int(Num_or(it.year)).ToStr()
    if released <> "" then out.Push([Tx("Released"), released])
    rt = Time_runtime(total)
    if rt <> "" then out.Push([Tx("Length"), rt])
    fmt = []
    versions = Arr_or(it.versions)
    if versions.Count() > 0 and Type(versions[0]) = "roAssociativeArray" then
        codec = Str_orEmpty(versions[0].codec_audio).Trim()
        if codec <> "" then fmt.Push(UCase(codec))
        cont = Str_orEmpty(versions[0].container).Trim()
        if cont <> "" then fmt.Push(UCase(cont))
    end if
    if m.timeline <> invalid and m.timeline.tracks.Count() > 1 then fmt.Push(TxP("{0} part", "{0} parts", m.timeline.tracks.Count()))
    if fmt.Count() > 0 then out.Push([Tx("Format"), Str_joinDots(fmt)])
    return out
end function

' Collapsed: four lines of the description. Expanded (OK): up to sixteen lines; Roku cannot clip a
' scrolling Label reliably, so a longer description stays cut at sixteen.
sub layoutAbout()
    if m.aboutExpanded then m.aboutText.maxLines = 16 else m.aboutText.maxLines = 4
    th = 0
    if m.aboutText.visible then th = Int(Label_height(m.aboutText))
    h = th
    if m.factsH > h then h = m.factsH
    if h < 40 then h = 40
    m.aboutH = h
    m.aboutFocus.width = 1720 + 48
    m.aboutFocus.height = h + 40
end sub

sub setRail(cards as object, subtitleKind as string)
    m.railSection.visible = true
    root = Content_rows([{ id: "rail", title: "", style: "poster", items: cards }], 32)
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

' Stacks the audiobook hero's identity column and centres it beside the cover (tvOS: the hero is
' 860 of 1080 px, so the About heading peeks in below it).
sub layoutBookColumn()
    y = 0
    y = y + 28 + 16
    m.bookTitle.translation = [0, y]
    th = Int(Label_height(m.bookTitle))
    if th < 80 then th = 80
    y = y + th
    m.bookSeries.visible = m.bookSeries.text <> ""
    if m.bookSeries.visible then
        y = y + 14
        m.bookSeries.translation = [0, y]
        y = y + 28
    end if
    m.bookCredits.visible = m.bookCredits.text <> ""
    if m.bookCredits.visible then
        y = y + 18
        m.bookCredits.translation = [0, y]
        ch = Int(Label_height(m.bookCredits))
        if ch < 34 then ch = 34
        y = y + ch
    end if
    y = y + 50
    m.bookState.translation = [0, y]
    y = y + m.bookStateH + 50
    m.bookActionsY = y
    y = y + 76
    top = Int((860 - y) / 2)
    if top < 60 then top = 60
    m.bookColumn.translation = [644, top]
    m.bookArt.translation = [100, 200]
    m.heroBottom = 860
end sub

function actionButtons() as object
    out = []
    cands = [m.playBtn, m.shuffleBtn, m.startOverBtn, m.favBtn]
    if m.kind = "audiobook" then cands = [m.bookPlayBtn, m.chaptersBtn, m.bookStartOverBtn, m.bookFavBtn, m.finishedBtn]
    for each b in cands
        if b.visible then out.Push(b)
    end for
    return out
end function

function playButton() as object
    if m.kind = "audiobook" then return m.bookPlayBtn
    return m.playBtn
end function

function heroShown() as boolean
    return m.hero.visible or m.bookHero.visible
end function

sub layoutActions()
    gap = 18
    m.bookX = []
    x = 0
    for each b in actionButtons()
        b.translation = [x, 0]
        m.bookX.Push(x)
        x = x + b.width + gap
    end for
    m.bookRowW = x - gap
    if m.kind = "audiobook" then applyBookScroll()
end sub

' The audiobook action row may use the hero's full width; five controls (a toggle widened by its
' focused label, a longer language) can outgrow it, so it scrolls to keep the focused control in view.
' Roku has no clipping we trust on every device, so a control the scroll pushes past either edge is
' hidden (opacity 0) instead of cut.
sub applyBookScroll()
    btns = actionButtons()
    n = btns.Count()
    if n = 0 or m.bookX.Count() <> n then return
    widths = []
    for each b in btns
        widths.Push(b.width)
    end for
    r = AudiobookFormat_rowScroll(m.bookX, widths, m.actionIndex, 1920 - 100 - 644, m.bookScroll)
    if r.scroll <> m.bookScroll then Diag_log(Diag_join(["[siku-detail] audiobook action row scroll=", r.scroll, " focused=", m.actionIndex, " row=", m.bookRowW]))
    m.bookScroll = r.scroll
    m.bookActions.translation = [-m.bookScroll, m.bookActionsY]
    for j = 0 to n - 1
        if r.shown[j] then btns[j].opacity = 1.0 else btns[j].opacity = 0.0
    end for
end sub

' Stacks the visible body sections under the hero.
sub layoutBody()
    y = m.heroBottom + 72
    if m.kind = "audiobook" then y = m.heroBottom + 8
    m.sectionY = {}
    if m.aboutSection.visible then
        m.aboutSection.translation = [0, y]
        m.sectionY.about = y
        y = y + 60 + m.aboutH + 56
    end if
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
    if m.aboutSection.visible then out.Push("about")
    if m.listSection.visible and m.list.visible then out.Push("list")
    if m.partsSection.visible then out.Push("parts")
    if m.railSection.visible then out.Push("rail")
    return out
end function

function zoneNode(z as string) as object
    if z = "list" then return m.list
    if z = "about" then return m.aboutCard
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
    m.aboutFocus.visible = z = "about"
    if z = "actions" then
        if m.kind = "audiobook" then applyBookScroll()
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
    if not heroShown() then return
    if m.chapterPanel.visible then
        m.chapterPanel.setFocus(true)
        return
    end if
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
    if m.errorGroup.visible or not heroShown() or m.chapterPanel.visible then return false
    if key = "OK" and m.zone = "about" then
        ' tvOS opens the whole description; here it opens in place (OK again closes it).
        m.aboutExpanded = not m.aboutExpanded
        Diag_log(Diag_join(["[siku-detail] audiobook about expanded=", m.aboutExpanded]))
        layoutAbout()
        layoutBody()
        focusZone("about")
        return true
    else if key = "down" then
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
        if m.kind = "audiobook" then applyBookScroll()
        return true
    else if key = "play" then
        onPlay()
        return true
    end if
    return false
end function

' ---------- Actions ----------

sub onPlay()
    if m.item = invalid or playButton().disabled then return
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
    m.bookFavBtn.active = m.isFavorite
    if m.isFavorite then m.bookFavBtn.a11yLabel = Tx("Remove from Favorites") else m.bookFavBtn.a11yLabel = Tx("Add to Favorites")
    if m.isFavorite then
        Api_fire("PUT", "/api/v2/favorites/" + Str_urlEncode(id))
        m.global.toast = Tx("Added to Favorites")
    else
        Api_fire("DELETE", "/api/v2/favorites/" + Str_urlEncode(id))
        m.global.toast = Tx("Removed from Favorites")
    end if
    m.global.homeDirty = true
end sub

' The Finished toggle (TvSquareToggleButton): flips the saved played flag at once and writes it; a
' refused write rolls back with the server's reason, a landed one re-reads the page.
sub onFinishedToggle()
    if m.item = invalid or m.kind <> "audiobook" then return
    played = not m.bookPlayed
    m.finishedSeq = m.finishedSeq + 1
    method = "DELETE"
    if played then method = "POST"
    Diag_log(Diag_join(["[siku-detail] audiobook finished write played=", played]))
    Api_call({ method: method, path: "/api/v2/watched/" + Str_urlEncode(Str_orEmpty(m.item.content_id)), context: { played: played, seq: m.finishedSeq } }, "onFinishedWritten")
    setBookPlayed(played)
    m.global.homeDirty = true
end sub

sub setBookPlayed(played as boolean)
    for each k in ["user_data", "user_state"]
        if Type(m.item[k]) <> "roAssociativeArray" then m.item[k] = {}
        m.item[k].played = played
    end for
    render()
end sub

sub onFinishedWritten(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if ctx = invalid or m.item = invalid then return
    current = ctx.seq = m.finishedSeq
    if not resp.ok then
        Diag_log(Diag_join(["[siku-detail] audiobook finished write failed status=", Int(Num_or(resp.status, 0)), " current=", current]))
        if not current then return
        setBookPlayed(not ctx.played)
        head = Tx("Couldn't mark as unwatched.")
        if ctx.played = true then head = Tx("Couldn't mark as watched.")
        if not m.global.hasField("toastSeconds") then m.global.addFields({ toastSeconds: 0.0 })
        m.global.toastSeconds = 5.0
        m.global.toast = head + " " + Api_reasonText(resp, Tx("Try again."))
        return
    end if
    Diag_log(Diag_join(["[siku-detail] audiobook finished write landed played=", ctx.played, " current=", current]))
    if current then reload()
end sub

' Chapters (the hero's action row, Android TV's chapter dialog): every chapter with its start, the
' current one focused; a pick plays from that chapter.
sub openChapters()
    if m.item = invalid or m.bookChapters.Count() = 0 then return
    chapters = m.bookChapters
    cur = -1
    if m.resume > 0 then cur = AudioTimeline_chapterAt(chapters, m.resume)
    rows = []
    for i = 0 to chapters.Count() - 1
        ch = chapters[i]
        sub2 = ""
        if ch["end"] > ch.start then sub2 = Time_runtime(ch["end"] - ch.start)
        rows.Push({ id: i.ToStr(), title: ch.title, number: (i + 1).ToStr(), subtitle: sub2, trailing: Time_clock(ch.start), isCurrent: i = cur })
    end for
    Diag_log(Diag_join(["[siku-detail] audiobook chapters opened count=", chapters.Count(), " current=", cur + 1]))
    m.chapterPanel.title = Tx("Chapters")
    m.chapterPanel.rows = rows
    m.chapterPanel.visible = true
    m.chapterPanel.setFocus(true)
end sub

sub closeChapters()
    m.chapterPanel.visible = false
    restoreFocus()
end sub

sub onChapterChosen()
    i = Int(Val(m.chapterPanel.chosen))
    m.chapterPanel.visible = false
    if m.item = invalid or i < 0 or i >= m.bookChapters.Count() then
        restoreFocus()
        return
    end if
    openPlayer({ itemId: Str_orEmpty(m.item.content_id), itemType: "audiobook", startPosition: m.bookChapters[i].start })
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

' index is a row of m.tracks; the queue leaves out tracks without a content id, so the row maps to
' its queue position (a row that can't play starts the next one that can).
sub playTracks(index as integer, shuffle as boolean)
    q = trackQueue(m.tracks, m.item)
    if q.Count() = 0 then
        m.global.toast = Tx("Nothing to play")
        return
    end if
    qi = 0
    for j = 0 to m.tracks.Count() - 1
        if j >= index then exit for
        if Audio_queueEntry(m.tracks[j]).contentId <> "" then qi = qi + 1
    end for
    if qi >= q.Count() then qi = 0
    openPlayer({ queue: q, index: qi, shuffle: shuffle })
end sub

' Artist Play / Shuffle: fetch each album's tracks (up to 50 albums, three requests at a time so a
' large discography does not start dozens of tasks at once), then queue them in album order.
sub playArtist(shuffle as boolean)
    if m.albums.Count() = 0 or m.artistTracks <> invalid then return
    m.artistShuffle = shuffle
    m.artistTracks = []
    n = m.albums.Count()
    if n > 50 then n = 50
    for i = 0 to n - 1
        m.artistTracks.Push([])
    end for
    m.artistPending = n
    m.artistNext = 0
    m.artistGen = m.artistGen + 1
    m.spinner.visible = true
    fetchNextArtistAlbum()
    fetchNextArtistAlbum()
    fetchNextArtistAlbum()
end sub

sub fetchNextArtistAlbum()
    if m.artistTracks = invalid or m.artistNext >= m.artistTracks.Count() then return
    i = m.artistNext
    m.artistNext = i + 1
    a = m.albums[i]
    Api_get("/api/v2/catalog/items/" + Str_urlEncode(Str_orEmpty(a.content_id)), { image_size: "medium" }, "onArtistAlbum", { index: i, gen: m.artistGen })
end sub

sub onArtistAlbum(event as object)
    resp = Api_result(event)
    ctx = resp.context
    if m.artistTracks = invalid or ctx = invalid or ctx.gen <> m.artistGen then return
    i = ctx.index
    if resp.ok and Type(resp.data) = "roAssociativeArray" then
        m.artistTracks[i] = trackQueue(Arr_or(resp.data.tracks), resp.data)
    end if
    m.artistPending = m.artistPending - 1
    fetchNextArtistAlbum()
    if m.artistPending > 0 then return
    m.spinner.visible = false
    q = []
    for each group in m.artistTracks
        q.Append(group)
    end for
    m.artistTracks = invalid
    if q.Count() = 0 then
        m.global.toast = Tx("Nothing to play")
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
