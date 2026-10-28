' Movie / series / season / episode detail page (docs/design-spec.md §4.3, docs/api-spec.md §4.4–4.8).
' SPDX-License-Identifier: AGPL-3.0-or-later

sub init()
    m.page = m.top.findNode("page")
    m.hero = m.top.findNode("hero")
    m.backdrop = m.top.findNode("backdrop")
    m.logo = m.top.findNode("logo")
    m.titleLabel = m.top.findNode("titleLabel")
    m.episodeLine = m.top.findNode("episodeLine")
    m.metaRow = m.top.findNode("metaRow")
    m.metaLabel = m.top.findNode("metaLabel")
    m.ratingChip = m.top.findNode("ratingChip")
    m.ratingRing = m.top.findNode("ratingRing")
    m.ratingLabel = m.top.findNode("ratingLabel")
    m.tagline = m.top.findNode("tagline")
    m.overview = m.top.findNode("overview")
    m.facts = m.top.findNode("facts")
    m.aiMarker = m.top.findNode("aiMarker")
    m.actions = m.top.findNode("actions")
    m.playBtn = m.top.findNode("playBtn")
    m.startOverBtn = m.top.findNode("startOverBtn")
    m.trailerBtn = m.top.findNode("trailerBtn")
    m.versionBtn = m.top.findNode("versionBtn")
    m.audioBtn = m.top.findNode("audioBtn")
    m.subtitlesBtn = m.top.findNode("subtitlesBtn")
    m.watchlistBtn = m.top.findNode("watchlistBtn")
    m.favBtn = m.top.findNode("favBtn")
    m.moreBtn = m.top.findNode("moreBtn")
    m.body = m.top.findNode("body")
    m.episodesSection = m.top.findNode("episodesSection")
    m.chipsGroup = m.top.findNode("chips")
    m.episodesMsg = m.top.findNode("episodesMsg")
    m.episodeRow = m.top.findNode("episodeRow")
    m.episodesRetryBtn = m.top.findNode("episodesRetryBtn")
    m.castSection = m.top.findNode("castSection")
    m.castRow = m.top.findNode("castRow")
    m.trailersSection = m.top.findNode("trailersSection")
    m.trailersRow = m.top.findNode("trailersRow")
    m.ytDialog = m.top.findNode("ytDialog")
    m.relatedSection = m.top.findNode("relatedSection")
    m.relatedHeader = m.top.findNode("relatedHeader")
    m.relatedRow = m.top.findNode("relatedRow")
    m.detailsSection = m.top.findNode("detailsSection")
    m.detailsBox = m.top.findNode("detailsBox")
    m.detailsBg = m.top.findNode("detailsBg")
    m.factRows = m.top.findNode("factRows")
    m.spinner = m.top.findNode("spinner")
    m.errorGroup = m.top.findNode("errorGroup")
    m.errorLabel = m.top.findNode("errorLabel")
    m.retryBtn = m.top.findNode("retryBtn")
    m.menu = m.top.findNode("menu")
    m.scrollAnim = m.top.findNode("scrollAnim")
    m.scrollInterp = m.top.findNode("scrollInterp")

    m.item = invalid
    m.itemType = ""
    m.loading = false
    m.seasons = []
    m.episodes = []
    m.selectedSeason = invalid
    m.nextUp = invalid
    m.recomputeNextUp = false
    m.currentEpisodeId = ""
    m.episodesFailed = false
    m.seasonsFailed = false
    m.episodesShownSeason = invalid
    m.zones = []
    m.zoneIndex = 0
    m.actionButtons = []
    m.actionIndex = 0
    m.chips = []
    m.chipIndex = 0
    m.heroBottom = 690
    m.menuKind = "more"
    ' Playback selections for the title the selectors describe (the item, or a series' next-up episode).
    m.selFileId = ""            ' "" = Auto
    m.selAudio = invalid        ' ordinal into audio_tracks; invalid = Auto
    m.selSubtitle = invalid     ' combined subtitle index; invalid = Auto; -1 = Off
    m.playDetail = invalid      ' the next-up episode's item detail (series/season pages)
    m.trailers = []             ' Trailer_entries(m.item)
    m.ytTask = invalid
    m.onTop = false
    ThemeMusic_init(m.top.findNode("themeAudio"))

    m.playBtn.observeField("buttonSelected", "onPlay")
    m.startOverBtn.observeField("buttonSelected", "onStartOver")
    m.trailerBtn.observeField("buttonSelected", "onTrailerButton")
    m.watchlistBtn.observeField("buttonSelected", "onWatchlistToggle")
    m.favBtn.observeField("buttonSelected", "onFavoriteToggle")
    m.moreBtn.observeField("buttonSelected", "onMore")
    m.versionBtn.observeField("buttonSelected", "onVersionButton")
    m.audioBtn.observeField("buttonSelected", "onAudioButton")
    m.subtitlesBtn.observeField("buttonSelected", "onSubtitlesButton")
    for each b in [m.startOverBtn, m.trailerBtn, m.versionBtn, m.audioBtn, m.subtitlesBtn, m.watchlistBtn, m.favBtn, m.moreBtn]
        b.observeField("width", "layoutActions")
    end for
    m.playBtn.observeField("width", "layoutActions")
    m.episodeRow.observeField("rowItemSelected", "onEpisodeSelected")
    m.castRow.observeField("rowItemSelected", "onCastSelected")
    m.relatedRow.observeField("rowItemSelected", "onRelatedSelected")
    m.trailersRow.observeField("rowItemSelected", "onTrailerSelected")
    m.ytDialog.observeField("dismissed", "onYouTubeDialogDismissed")
    m.detailsBox.observeField("focusedChild", "onDetailsFocus")
    m.retryBtn.observeField("buttonSelected", "load")
    m.episodesRetryBtn.observeField("buttonSelected", "retryEpisodes")
    m.menu.observeField("chosen", "onMenuChosen")
    m.menu.observeField("dismissed", "onMenuDismissed")
end sub

' ---------- Lifecycle ----------

sub onScreenShown()
    m.onTop = true
    if m.item = invalid then
        if not m.loading then load()
        return
    end if
    if m.global.homeDirty = true then refreshUserState()
    if m.ytDialog.visible then
        m.ytDialog.setFocus(true)
    else
        focusZone(m.zoneIndex)
    end if
    ThemeMusic_show(m.item)
end sub

' Covered (the player, another page) or closed: theme music never plays under anything else.
sub onScreenHidden()
    m.onTop = false
    ThemeMusic_stop()
end sub

' Opened without the shell (a deep link): the profile's settings were never read, and theme music
' and spoiler protection depend on them. Read them once; the answer lands in onSettingsLoaded.
sub ensureSettings()
    if Settings_available() or m.settingsRequested = true then return
    m.settingsRequested = true
    Settings_load()
end sub

function itemPath() as string
    return "/api/v2/catalog/items/" + Str_urlEncode(Str_orEmpty(m.top.params.itemId))
end function

sub load()
    m.loading = true
    m.errorGroup.visible = false
    m.spinner.visible = true
    ensureSettings()
    m.spoilerSig = spoilerSignature()
    Api_get(itemPath(), Artwork_query({ image_size: "large" }, "detail"), "onItem")
end sub

function spoilerSignature() as string
    prefs = Spoilers_prefs()
    return Str_orEmpty(prefs.hideImages) + "|" + Str_orEmpty(prefs.hideOverviews)
end function

' The settings snapshot landed: start theme music if it is now on, and redraw what spoiler
' protection changes (hero, episode rail).
sub onSettingsLoaded()
    if m.onTop = true and m.item <> invalid then ThemeMusic_show(m.item)
    sig = spoilerSignature()
    if sig = m.spoilerSig then return
    m.spoilerSig = sig
    if m.item = invalid then return
    renderHero()
    if m.selectedSeason <> invalid then loadEpisodes(m.selectedSeason)
end sub

sub showError(msg as string)
    m.spinner.visible = false
    m.errorGroup.visible = true
    m.errorLabel.text = msg
    m.retryBtn.setFocus(true)
    Launch_ready("detail")
end sub

sub onItem(event as object)
    resp = Api_result(event)
    m.loading = false
    if not resp.ok or resp.data = invalid or Type(resp.data) <> "roAssociativeArray" then
        showError(Api_errorText(resp))
        return
    end if
    m.spinner.visible = false
    ' Series audio/subtitle picks that have not landed: resend them, and show them meanwhile.
    SeriesChoice_flush()
    m.item = SeriesChoice_overlay(resp.data)
    m.itemType = LCase(Str_orEmpty(m.item.type))
    renderHero()
    renderCast()
    renderTrailers()
    renderDetails()
    layoutBody()
    buildZones()
    m.zoneIndex = 0
    m.actionIndex = 0
    focusZone(0)
    Launch_ready("detail")
    ensureSettings()
    ThemeMusic_show(m.item)

    seriesId = Str_orEmpty(m.item.series_id)
    if m.itemType = "series" then seriesId = Str_orEmpty(m.item.content_id)
    if m.itemType = "series" or m.itemType = "season" or m.itemType = "episode" then
        if seriesId <> "" then
            m.episodesSection.visible = true
            m.episodesMsg.visible = true
            m.episodesMsg.text = "Loading episodes…"
            layoutBody()
            buildZones()
            loadSeasons()
        end if
    end if
    if m.itemType = "movie" or m.itemType = "series" then
        Api_get("/api/v2/recommendations/similar/" + Str_urlEncode(Str_orEmpty(m.item.content_id)), Artwork_query({ limit: 12, image_size: "medium" }, "similar", Theme_posterScale()), "onSimilar")
    end if
    ' Shuffle entry points in the More menu depend on the server's capability.
    Shuffle_refreshCaps("onShuffleCaps")
end sub

sub onShuffleCaps(event as object)
    Shuffle_storeCaps(event)
end sub

' After playback or a state change elsewhere: refetch user state silently.
sub refreshUserState()
    Api_get(itemPath(), Artwork_query({ image_size: "large" }, "detail"), "onItemRefreshed")
end sub

sub onItemRefreshed(event as object)
    resp = Api_result(event)
    if not resp.ok or resp.data = invalid then return
    m.item = SeriesChoice_overlay(resp.data)
    updatePrimary()
    updateToggles()
    ' Watched flags and the server's next-up may have moved (TvItemDetailViewModel.refreshOnReturn
    ' reloads the season and re-resolves next-up): pick it again when the episodes land.
    if m.selectedSeason <> invalid then
        m.recomputeNextUp = true
        loadEpisodes(m.selectedSeason)
    end if
end sub

' ---------- Hero ----------

function seriesIdOf() as string
    if m.itemType = "series" then return Str_orEmpty(m.item.content_id)
    return Str_orEmpty(m.item.series_id)
end function

function namesOf(list as dynamic) as object
    out = []
    for each e in Arr_or(list)
        if Type(e) = "roAssociativeArray" then
            n = Str_orEmpty(e.name)
            if n = "" then n = Str_orEmpty(e.title)
            if n <> "" then out.Push(n)
        else
            s = Str_orEmpty(e)
            if s <> "" then out.Push(s)
        end if
    end for
    return out
end function

function joinNames(names as object, maxCount as integer) as string
    out = ""
    n = 0
    for each s in names
        if n >= maxCount then exit for
        if out <> "" then out = out + ", "
        out = out + s
        n = n + 1
    end for
    return out
end function

function crewNames(job as string) as object
    out = []
    for each c in Arr_or(m.item.crew)
        if LCase(Str_orEmpty(c.job)) = LCase(job) and not Str_isEmpty(c.name) then out.Push(c.name)
    end for
    return out
end function

function toInt(v as dynamic) as integer
    if v = invalid then return 0
    t = Type(v)
    if t = "roInt" or t = "Integer" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" then return Int(v)
    return Int(Val(Str_orEmpty(v)))
end function

function yearOf(it as object) as string
    if it.year <> invalid then return Str_orEmpty(it.year)
    for each k in ["release_date", "first_air_date", "air_date"]
        d = Str_orEmpty(it[k])
        if Len(d) >= 4 then return Left(d, 4)
    end for
    return ""
end function

sub renderHero()
    it = m.item
    t = m.itemType
    ' Spoiler protection: an unwatched episode's still (or a backdrop the server does not mark as
    ' series art) is not shown (Spoilers.brs).
    m.backdrop.uri = Url_resolve(Spoilers_imageUrl(it, "backdrop"))
    if m.backdrop.uri = "" and t = "episode" then m.backdrop.uri = Url_resolve(Spoilers_imageUrl(it, "still"))

    heading = Str_orEmpty(it.title)
    epLine = ""
    if t = "episode" then
        if not Str_isEmpty(it.series_title) then heading = it.series_title
        epLine = Str_joinDots([Content_seShort(it.season_number, it.episode_number), it.title])
    else if t = "season" then
        if not Str_isEmpty(it.series_title) then
            heading = it.series_title
            epLine = Str_orEmpty(it.title)
        end if
    else if t = "series" and m.nextUp <> invalid then
        epLine = Str_joinDots([Content_seShort(m.nextUp.season_number, m.nextUp.episode_number), m.nextUp.title])
    end if

    logoUrl = Url_resolve(it.logo_url)
    if not Settings_showTitleArt() then logoUrl = "" ' Settings → General → Show title art
    m.logo.visible = logoUrl <> ""
    m.logo.uri = logoUrl
    m.titleLabel.visible = logoUrl = ""
    m.titleLabel.text = heading
    m.episodeLine.text = epLine
    m.episodeLine.visible = epLine <> ""

    tokens = []
    y = yearOf(it)
    if y <> "" then tokens.Push(y)
    if toInt(it.runtime) > 0 then tokens.Push(Time_runtime(toInt(it.runtime) * 60))
    if t = "series" and it.season_count <> invalid then
        sc = toInt(it.season_count)
        if sc = 1 then tokens.Push("1 season") else tokens.Push(sc.ToStr() + " seasons")
    end if
    genres = namesOf(it.genres)
    if genres.Count() > 0 then tokens.Push(joinNames(genres, 3))
    ratings = Arr_or(it.ratings)
    if ratings.Count() > 0 and not Str_isEmpty(ratings[0].display) then
        tokens.Push(Str_orEmpty(ratings[0].name) + " " + ratings[0].display)
    end if
    m.metaLabel.text = Str_joinDots(tokens)
    rating = Str_orEmpty(it.content_rating)
    m.ratingChip.visible = rating <> ""
    m.ratingLabel.text = rating
    m.metaRow.visible = m.metaLabel.text <> "" or rating <> ""

    m.tagline.text = Str_orEmpty(it.tagline)
    m.tagline.visible = m.tagline.text <> ""
    m.overview.text = heroOverviewText(it)
    m.overview.visible = m.overview.text <> ""
    m.aiMarker.visible = m.overview.visible and overviewMachineTranslated(it)

    factParts = []
    cast = Arr_or(it.cast)
    if cast.Count() > 0 then factParts.Push("Starring " + joinNames(namesOf(cast), 3))
    directors = crewNames("Director")
    if directors.Count() > 0 then factParts.Push("Directed by " + joinNames(directors, 2))
    m.facts.text = Str_joinDots(factParts)
    m.facts.visible = m.facts.text <> ""

    m.actions.visible = true
    updateToggles()
    updatePrimary()
    layoutHero()
end sub

' The hero's description; spoiler protection may hide it (Spoilers.brs).
function heroOverviewText(it as object) as string
    return Spoilers_overview(it)
end function

' "Translated by AI" marks only a machine-translated overview (upstream hasMachineTranslatedOverview).
function overviewMachineTranslated(it as dynamic) as boolean
    if it = invalid or Type(it) <> "roAssociativeArray" then return false
    for each f in Arr_or(it.machine_translated_fields)
        if LCase(Str_orEmpty(f)) = "overview" then return true
    end for
    return false
end function

sub layoutHero()
    x = 100
    y = 116
    gap = 18
    if m.logo.visible then
        m.logo.translation = [x, y]
        y = y + 160 + gap
    else
        m.titleLabel.translation = [x, y]
        y = y + Label_height(m.titleLabel) + gap
    end if
    if m.episodeLine.visible then
        m.episodeLine.translation = [x, y]
        y = y + 40 + gap
    end if
    if m.metaRow.visible then
        m.metaRow.translation = [x, y]
        m.metaLabel.width = 0
        mw = Label_width(m.metaLabel)
        m.metaLabel.height = 34
        m.metaLabel.vertAlign = "center"
        if m.ratingChip.visible then
            m.ratingLabel.width = 0
            rw = Label_width(m.ratingLabel) + 20
            m.ratingLabel.width = rw
            m.ratingRing.width = rw
            cx = 0
            if mw > 0 then cx = mw + 16
            m.ratingChip.translation = [cx, 0]
        end if
        y = y + 34 + gap
    end if
    if m.tagline.visible then
        m.tagline.translation = [x, y]
        y = y + 34 + gap
    end if
    if m.overview.visible then
        m.overview.translation = [x, y]
        y = y + Label_height(m.overview) + gap
    end if
    if m.aiMarker.visible then
        m.aiMarker.translation = [x, y - 8]
        y = y + 30 + gap - 8
    end if
    if m.facts.visible then
        m.facts.translation = [x, y]
        y = y + 30 + gap
    end if
    actionsY = y + 14
    if actionsY < 560 then actionsY = 560
    m.actions.translation = [x, actionsY]
    layoutActions()
    m.heroBottom = actionsY + 76 + 64
    layoutBody()
end sub

sub layoutActions()
    x = 0
    gap = 18
    m.actionButtons = []
    for each b in [m.playBtn, m.startOverBtn, m.trailerBtn, m.versionBtn, m.audioBtn, m.subtitlesBtn, m.watchlistBtn, m.favBtn, m.moreBtn]
        if b.visible then
            b.translation = [x, 0]
            x = x + b.width + gap
            m.actionButtons.Push(b)
        end if
    end for
end sub

' Resume position of an item or episode from its user_data (seconds), 0 if none.
function resumeOf(it as dynamic) as float
    if it = invalid or it.user_data = invalid then return 0
    p = Content_num(it.user_data.position_seconds)
    if p <= 0 then return 0
    d = Content_num(it.user_data.duration_seconds)
    if d > 0 and p >= d - 5 then return 0
    return p
end function

sub updatePrimary()
    t = m.itemType
    resume = 0.0
    label = "Play"
    canPlay = true
    if t = "series" or t = "season" then
        ep = m.nextUp
        if ep <> invalid then
            resume = resumeOf(ep)
            verb = "Play"
            if resume > 0 then verb = "Resume"
            if t = "series" then
                label = verb + " S" + Str_orEmpty(ep.season_number) + ":E" + Str_orEmpty(ep.episode_number)
            else
                label = verb + " E" + Str_orEmpty(ep.episode_number)
            end if
        else
            canPlay = not Str_isEmpty(m.item.play_content_id) or m.episodes.Count() > 0
        end if
        m.playBtn.fixedWidth = 340
    else
        resume = resumeOf(m.item)
        if resume > 0 then label = "Resume " + Time_clock(resume)
        versions = Arr_or(m.item.versions)
        canPlay = versions.Count() > 0 or m.item.user_data <> invalid
    end if
    m.playBtn.text = label
    m.playBtn.disabled = not canPlay
    m.startOverBtn.visible = resume > 0
    updateSelectors()
end sub

' ---------- Version / Audio / Subtitles selectors (design-spec §4.3) ----------

' The item whose playback the selectors describe: the title itself, or a series' next-up episode.
function selectorTargetId() as string
    if m.itemType = "series" or m.itemType = "season" then
        if m.nextUp = invalid then return ""
        return Str_orEmpty(m.nextUp.content_id)
    end if
    return Str_orEmpty(m.item.content_id)
end function

function playVersions() as object
    if m.itemType = "series" or m.itemType = "season" then
        if m.playDetail = invalid or Str_orEmpty(m.playDetail.content_id) <> selectorTargetId() then return []
        return Arr_or(m.playDetail.versions)
    end if
    return Arr_or(m.item.versions)
end function

' The version the selectors show: the chosen file, else the last played file, else the default
' variant, else the first version.
function displayVersion() as dynamic
    versions = playVersions()
    if versions.Count() = 0 then return invalid
    src = m.item
    if m.itemType = "series" or m.itemType = "season" then src = m.playDetail
    want = m.selFileId
    if want = "" and src <> invalid and src.user_data <> invalid then want = Str_orEmpty(src.user_data.last_file_id)
    if want = "" and src <> invalid then
        for each pv in Arr_or(src.playback_variants)
            if want = "" and not Str_isEmpty(pv.default_file_id) then want = Str_orEmpty(pv.default_file_id)
        end for
    end if
    if want <> "" then
        for each v in versions
            if Str_orEmpty(v.file_id) = want then return v
        end for
    end if
    return versions[0]
end function

' Fetches the next-up episode's detail (its versions and tracks) for series/season pages.
sub loadPlayDetail()
    target = selectorTargetId()
    if target = "" then return
    if m.playDetail <> invalid and Str_orEmpty(m.playDetail.content_id) = target then return
    m.playDetail = invalid
    m.selFileId = ""
    m.selAudio = invalid
    m.selSubtitle = invalid
    updateSelectors()
    Api_get("/api/v2/catalog/items/" + Str_urlEncode(target), { image_size: "small" }, "onPlayDetail", { target: target })
end sub

sub onPlayDetail(event as object)
    resp = Api_result(event)
    if not resp.ok or resp.data = invalid or Type(resp.data) <> "roAssociativeArray" then return
    if resp.context = invalid or resp.context.target <> selectorTargetId() then return
    m.playDetail = SeriesChoice_overlay(resp.data)
    updateSelectors()
end sub

function audioValueLabel(v as object) as string
    tracks = Arr_or(v.audio_tracks)
    if m.selAudio <> invalid and m.selAudio >= 0 and m.selAudio < tracks.Count() then return Tracks_audioSummary(tracks[m.selAudio], m.selAudio)
    o = Tracks_autoAudioOrdinal(v)
    if o < 0 then return "Auto"
    return "Auto · " + Tracks_audioSummary(tracks[o], o)
end function

function subtitleValueLabel(v as object) as string
    tracks = Arr_or(v.subtitle_tracks)
    if m.selSubtitle = invalid then return "Auto"
    if m.selSubtitle = -1 then return "Off"
    o = Tracks_subtitleOrdinal(tracks, m.selSubtitle)
    if o < 0 then return "On"
    return Tracks_subtitleSummary(tracks[o], o)
end function

' Each selector shows only when there is more than one real choice ("Auto" and "Off" don't count).
sub updateSelectors()
    versions = playVersions()
    v = displayVersion()
    m.versionBtn.visible = versions.Count() > 1
    if v <> invalid then
        compact = Tracks_versionCompact(v)
        if m.selFileId = "" and compact <> "Auto" then compact = "Auto · " + compact
        m.versionBtn.label = "Version · " + compact
        audio = Arr_or(v.audio_tracks)
        m.audioBtn.visible = audio.Count() > 1
        m.audioBtn.label = "Audio · " + audioValueLabel(v)
        subs = Arr_or(v.subtitle_tracks)
        m.subtitlesBtn.visible = subs.Count() > 1
        m.subtitlesBtn.label = "Subtitles · " + subtitleValueLabel(v)
    else
        m.audioBtn.visible = false
        m.subtitlesBtn.visible = false
    end if
    layoutActions()
end sub

sub openSelectorMenu(kind as string, title as string, acts as object)
    m.menuKind = kind
    m.menu.title = title
    m.menu.actions = acts
    m.menu.visible = true
    m.menu.setFocus(true)
end sub

sub onVersionButton()
    acts = [{ id: "auto", label: "Auto", detail: "Best match for this device", checked: m.selFileId = "" }]
    for each v in playVersions()
        fid = Str_orEmpty(v.file_id)
        acts.Push({ id: "v:" + fid, label: Tracks_versionShort(v), detail: Tracks_versionDetail(v), checked: fid = m.selFileId })
    end for
    openSelectorMenu("version", "Version", acts)
end sub

sub onAudioButton()
    v = displayVersion()
    if v = invalid then return
    acts = [{ id: "auto", label: "Auto", detail: "Use your Playback audio preference", checked: m.selAudio = invalid }]
    tracks = Arr_or(v.audio_tracks)
    for i = 0 to tracks.Count() - 1
        t = tracks[i]
        acts.Push({ id: "a:" + i.ToStr(), label: Tracks_audioTitle(t, i), detail: Tracks_audioDetail(t), checked: m.selAudio = i })
    end for
    openSelectorMenu("audio", "Audio", acts)
end sub

sub onSubtitlesButton()
    v = displayVersion()
    if v = invalid then return
    acts = [
        { id: "auto", label: "Auto", detail: "Use your subtitle preferences", checked: m.selSubtitle = invalid }
        { id: "off", label: "Off", detail: "Start without subtitles", checked: m.selSubtitle = -1 }
    ]
    tracks = Arr_or(v.subtitle_tracks)
    comb = Tracks_subtitleCombined(tracks)
    for i = 0 to tracks.Count() - 1
        t = tracks[i]
        acts.Push({ id: "s:" + comb[i].ToStr(), label: Tracks_subtitleTitle(t, i), detail: Tracks_subtitleDetail(t), checked: m.selSubtitle = comb[i] })
    end for
    openSelectorMenu("subtitle", "Subtitles", acts)
end sub

sub onSelectorChosen(kind as string, id as string)
    if kind = "version" then
        if id = "auto" then
            m.selFileId = ""
        else if Left(id, 2) = "v:" then
            m.selFileId = Mid(id, 3)
            ' Tracks are per file; a new file starts from Auto again.
            m.selAudio = invalid
            m.selSubtitle = invalid
        end if
    else if kind = "audio" then
        if id = "auto" then m.selAudio = invalid else if Left(id, 2) = "a:" then m.selAudio = Int(Val(Mid(id, 3)))
        rememberSeriesAudio()
    else if kind = "subtitle" then
        if id = "auto" then
            m.selSubtitle = invalid
        else if id = "off" then
            m.selSubtitle = -1
        else if Left(id, 2) = "s:" then
            m.selSubtitle = Int(Val(Mid(id, 3)))
        end if
        rememberSeriesSubtitle()
    end if
    updateSelectors()
end sub

' The series (or movie) a selector pick is remembered for (Silo Android #680): the episode the
' selectors describe on a series or season page, else this movie or episode; "" for anything else.
function selectorSeriesKey() as string
    d = m.item
    if m.itemType = "series" or m.itemType = "season" then d = m.playDetail
    if d = invalid then return ""
    if Str_orEmpty(d.content_id) <> selectorTargetId() then return ""
    t = LCase(Str_orEmpty(d["type"]))
    if t = "" then t = m.itemType
    if t <> "movie" and t <> "episode" then return ""
    return SeriesChoice_key(d.series_id, d.content_id)
end function

' A selector pick applies to the whole series and the profile's other devices, like a pick in
' the player: a track or Off is saved on the server, Auto deletes the saved choice.
sub rememberSeriesSubtitle()
    key = selectorSeriesKey()
    v = displayVersion()
    if key = "" or v = invalid then return
    if m.selSubtitle = invalid then
        SeriesChoice_saveSubtitle(key, invalid)
    else if m.selSubtitle = -1 then
        SeriesChoice_saveSubtitle(key, SeriesChoice_subtitleOff())
    else
        tracks = Arr_or(v.subtitle_tracks)
        o = Tracks_subtitleOrdinal(tracks, m.selSubtitle)
        if o >= 0 then SeriesChoice_saveSubtitle(key, SeriesChoice_subtitleFromCatalog(tracks[o], m.selSubtitle))
    end if
end sub

sub rememberSeriesAudio()
    key = selectorSeriesKey()
    v = displayVersion()
    if key = "" or v = invalid then return
    if m.selAudio = invalid then
        SeriesChoice_saveAudio(key, invalid)
        return
    end if
    tracks = Arr_or(v.audio_tracks)
    o = Int(m.selAudio)
    if o >= 0 and o < tracks.Count() then SeriesChoice_saveAudio(key, SeriesChoice_audioFromCatalog(tracks[o], o))
end sub

' Adds the selectors' choices to player params when `targetId` is the title they describe.
' The player turns indexes into "file:<id>:audio:<n>" / "file:<id>:subtitle:<n>" ids; Off sends nothing.
sub applySelections(params as object, targetId as string)
    if targetId = "" or targetId <> selectorTargetId() then return
    v = displayVersion()
    if v = invalid then return
    fid = Str_orEmpty(v.file_id)
    hasTrack = m.selAudio <> invalid or (m.selSubtitle <> invalid and m.selSubtitle >= 0)
    if m.selFileId <> "" or hasTrack then params.fileId = fid
    if m.selAudio <> invalid then
        params.audioTrackIndex = m.selAudio
        params.audioTrackId = Tracks_audioId(fid, m.selAudio)
    end if
    if m.selSubtitle <> invalid then
        params.subtitleTrackIndex = m.selSubtitle
        if m.selSubtitle >= 0 then params.subtitleTrackId = Tracks_subtitleId(fid, m.selSubtitle)
    end if
end sub

sub updateToggles()
    st = m.item.user_state
    if st = invalid then st = {}
    m.watchlistBtn.active = st.in_watchlist = true
    m.favBtn.active = st.is_favorite = true
end sub

' ---------- Body: layout and zones ----------

sub layoutBody()
    if m.item = invalid then return
    x = 100
    y = m.heroBottom
    gap = 64
    if m.episodesSection.visible then
        m.episodesSection.translation = [x, y]
        y = y + 130 + 420 + gap
    end if
    if m.castSection.visible then
        m.castSection.translation = [x, y]
        y = y + 60 + 300 + gap
    end if
    if m.trailersSection.visible then
        m.trailersSection.translation = [x, y]
        y = y + 60 + 338 + gap
    end if
    if m.relatedSection.visible then
        m.relatedSection.translation = [x, y]
        y = y + 60 + 364 + gap
    end if
    if m.detailsSection.visible then
        m.detailsSection.translation = [x, y]
        y = y + 50 + m.detailsBg.height + gap
    end if
    m.pageHeight = y + 140
end sub

sub buildZones()
    zones = [{ name: "actions", y: 0 }]
    if m.episodesSection.visible then
        sy = m.episodesSection.translation[1]
        if m.chips.Count() > 0 then zones.Push({ name: "chips", y: sy })
        if m.episodes.Count() > 0 then zones.Push({ name: "episodes", y: sy })
        if m.episodesFailed then zones.Push({ name: "episodesRetry", y: sy })
    end if
    if m.castSection.visible then zones.Push({ name: "cast", y: m.castSection.translation[1] })
    if m.trailersSection.visible then zones.Push({ name: "trailers", y: m.trailersSection.translation[1] })
    if m.relatedSection.visible then zones.Push({ name: "related", y: m.relatedSection.translation[1] })
    if m.detailsSection.visible then zones.Push({ name: "details", y: m.detailsSection.translation[1] })
    m.zones = zones
    if m.zoneIndex >= zones.Count() then m.zoneIndex = zones.Count() - 1
end sub

function zoneName() as string
    if m.zones.Count() = 0 then return "actions"
    return m.zones[m.zoneIndex].name
end function

function zoneIndexOf(name as string) as integer
    for i = 0 to m.zones.Count() - 1
        if m.zones[i].name = name then return i
    end for
    return -1
end function

sub focusZone(i as integer)
    if m.zones.Count() = 0 then return
    if i < 0 then i = 0
    if i >= m.zones.Count() then i = m.zones.Count() - 1
    changed = i <> m.zoneIndex
    m.zoneIndex = i
    z = m.zones[i]
    if z.name = "actions" then
        if changed then m.actionIndex = 0
        if m.actionButtons.Count() = 0 then layoutActions()
        if m.actionIndex >= m.actionButtons.Count() then m.actionIndex = 0
        if m.actionButtons.Count() > 0 then m.actionButtons[m.actionIndex].setFocus(true)
        scrollTo(0)
    else
        if z.name = "chips" then
            if m.chipIndex >= m.chips.Count() then m.chipIndex = 0
            m.chips[m.chipIndex].setFocus(true)
            scrollChips()
        else if z.name = "episodes" then
            m.episodeRow.setFocus(true)
        else if z.name = "episodesRetry" then
            m.episodesRetryBtn.setFocus(true)
        else if z.name = "cast" then
            m.castRow.setFocus(true)
        else if z.name = "trailers" then
            m.trailersRow.setFocus(true)
        else if z.name = "related" then
            m.relatedRow.setFocus(true)
        else if z.name = "details" then
            m.detailsBox.setFocus(true)
        end if
        scrollTo(-(z.y - 100))
    end if
end sub

sub scrollTo(targetY as float)
    cur = m.page.translation
    if Abs(cur[1] - targetY) < 1 then return
    m.scrollInterp.keyValue = [[0, cur[1]], [0, targetY]]
    m.scrollAnim.control = "start"
end sub

sub onDetailsFocus()
    m.detailsBg.visible = m.detailsBox.hasFocus()
end sub

' ---------- Seasons and episodes ----------

sub loadSeasons()
    sid = seriesIdOf()
    if sid = "" then return
    m.seasonsFailed = false
    Api_get("/api/v2/catalog/series/" + Str_urlEncode(sid) + "/seasons", { image_size: "medium", include_artwork: "false" }, "onSeasons")
end sub

sub onSeasons(event as object)
    resp = Api_result(event)
    if not resp.ok or resp.data = invalid or Type(resp.data) <> "roAssociativeArray" then
        m.seasonsFailed = true
        showEpisodesRetry("Couldn't load seasons")
        return
    end if
    m.seasons = Arr_or(resp.data.items)
    buildChips()
    ' After a retry the chips zone now sits above the focused Retry button.
    if m.episodesRetryBtn.hasFocus() then m.zoneIndex = zoneIndexOf("episodesRetry")

    ' Initial season: the item's own season, else play_season_number, else the first regular season.
    sel = invalid
    if m.itemType = "season" or m.itemType = "episode" then
        sel = m.item.season_number
    else if m.item.play_season_number <> invalid then
        sel = m.item.play_season_number
    end if
    if sel = invalid then
        for each s in m.seasons
            if s.is_specials <> true and s.season_number <> invalid then
                sel = s.season_number
                exit for
            end if
        end for
    end if
    if sel = invalid and m.seasons.Count() > 0 then sel = m.seasons[0].season_number
    if sel = invalid then
        hideEpisodesRetry()
        m.episodesMsg.text = "No episodes available"
        return
    end if
    selectSeason(toInt(sel))
end sub

function seasonLabel(s as object) as string
    if s.is_specials = true or (s.season_number <> invalid and toInt(s.season_number) = 0) then return "Specials"
    if not Str_isEmpty(s.title) then return s.title
    return "Season " + Str_orEmpty(s.season_number)
end function

sub buildChips()
    m.chipsGroup.removeChildrenIndex(m.chipsGroup.getChildCount(), 0)
    m.chips = []
    x = 0
    for i = 0 to m.seasons.Count() - 1
        s = m.seasons[i]
        chip = m.chipsGroup.createChild("DetailChip")
        chip.text = seasonLabel(s)
        chip.translation = [x, 0]
        chip.addFields({ seasonNumber: toInt(s.season_number) })
        chip.observeField("buttonSelected", "onChipSelected")
        x = x + chip.width + 16
        m.chips.Push(chip)
    end for
    buildZones()
end sub

sub scrollChips()
    if m.chips.Count() = 0 then return
    chip = m.chips[m.chipIndex]
    cx = chip.translation[0]
    offset = m.chipsGroup.translation[0]
    if cx + offset + chip.width > 1820 then offset = 1820 - cx - chip.width
    if cx + offset < 0 then offset = -cx
    m.chipsGroup.translation = [offset, 50]
end sub

sub onChipSelected(event as object)
    chip = event.getRoSGNode()
    selectSeason(chip.seasonNumber)
end sub

sub selectSeason(n as integer)
    m.selectedSeason = n
    ' Browsing another season never moves the series' next-up; only a refresh does.
    m.recomputeNextUp = false
    for i = 0 to m.chips.Count() - 1
        m.chips[i].selected = (m.chips[i].seasonNumber = n)
        if m.chips[i].seasonNumber = n then m.chipIndex = i
    end for
    loadEpisodes(n)
end sub

sub loadEpisodes(n as integer)
    sid = seriesIdOf()
    if sid = "" then return
    if m.episodes.Count() = 0 then
        m.episodesMsg.visible = true
        m.episodesMsg.text = "Loading episodes…"
    end if
    m.episodesRequestSeason = n
    Api_get("/api/v2/catalog/series/" + Str_urlEncode(sid) + "/seasons/" + n.ToStr() + "/episodes", Artwork_query({ image_size: "medium" }, "episodes"), "onEpisodes")
end sub

function airDateText(d as dynamic) as string
    dt = Time_parseIso(d)
    if dt = invalid then return ""
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    mi = dt.GetMonth() - 1
    if mi < 0 or mi > 11 then return ""
    return months[mi] + " " + dt.GetDayOfMonth().ToStr() + ", " + dt.GetYear().ToStr()
end function

sub onEpisodes(event as object)
    resp = Api_result(event)
    if m.episodesRequestSeason <> m.selectedSeason then return
    if not resp.ok or resp.data = invalid or Type(resp.data) <> "roAssociativeArray" then
        ' A quiet refresh of the season on screen keeps what it shows (Android TV does the same).
        if m.episodes.Count() > 0 and m.episodesShownSeason = m.selectedSeason then
            m.recomputeNextUp = false
            return
        end if
        ' Otherwise the row would show another season's episodes: clear it and offer a retry.
        m.episodes = []
        m.episodeRow.content = invalid
        m.episodesShownSeason = invalid
        showEpisodesRetry("Couldn't load episodes")
        return
    end if
    m.episodes = Arr_or(resp.data.items)
    m.episodesShownSeason = m.selectedSeason
    hideEpisodesRetry()
    if m.episodes.Count() = 0 then
        m.episodesMsg.visible = true
        m.episodesMsg.text = "No episodes available"
        m.episodeRow.content = invalid
        buildZones()
        return
    end if
    m.episodesMsg.visible = false

    ' Which episode is "current": the episode page's own item, or the series/season next-up.
    if m.itemType = "episode" then
        m.currentEpisodeId = Str_orEmpty(m.item.content_id)
    else if m.nextUp = invalid or m.itemType = "season" or m.recomputeNextUp then
        m.recomputeNextUp = false
        playId = Str_orEmpty(m.item.play_content_id)
        if m.itemType = "season" then
            for each s in m.seasons
                if toInt(s.season_number) = m.selectedSeason and not Str_isEmpty(s.play_content_id) then playId = s.play_content_id
            end for
        end if
        found = invalid
        for each ep in m.episodes
            if Str_orEmpty(ep.content_id) = playId then found = ep
        end for
        if found = invalid then
            ' Fall back to the first unwatched episode, else the first one.
            for each ep in m.episodes
                if found = invalid and (ep.user_data = invalid or ep.user_data.played <> true) then found = ep
            end for
            if found = invalid then found = m.episodes[0]
        end if
        m.nextUp = found
        m.currentEpisodeId = Str_orEmpty(found.content_id)
        updatePrimary()
        loadPlayDetail()
        if m.itemType = "series" then
            m.episodeLine.text = Str_joinDots([Content_seShort(found.season_number, found.episode_number), found.title])
            m.episodeLine.visible = m.episodeLine.text <> ""
            layoutHero()
        end if
    end if

    root = CreateObject("roSGNode", "ContentNode")
    row = root.createChild("ContentNode")
    focusIdx = 0
    for i = 0 to m.episodes.Count() - 1
        ep = m.episodes[i]
        ' Spoiler protection drops an unwatched episode's still (Content_cardNode) and description.
        node = Content_cardNode(ep, "landscape")
        node.title = Content_episodeCaptionTitle(ep)
        node.description = Content_episodeCaptionMeta(airDateText(ep.air_date), toInt(ep.runtime)) ' read by the screen reader
        node.addFields({
            eyebrow: ""
            meta: Content_episodeCaptionMeta(airDateText(ep.air_date), toInt(ep.runtime))
            synopsis: episodeSynopsis(ep)
            aiTranslated: overviewMachineTranslated(ep) and episodeSynopsis(ep) <> ""
            isCurrent: Str_orEmpty(ep.content_id) = m.currentEpisodeId
        })
        if node.isCurrent then focusIdx = i
        row.appendChild(node)
    end for
    m.episodeRow.content = root
    m.episodeRow.jumpToRowItem = [0, focusIdx]
    buildZones()
end sub

' An episode card's synopsis; spoiler protection may hide it (Spoilers.brs).
function episodeSynopsis(ep as object) as string
    return Spoilers_overview(ep)
end function

sub onEpisodeSelected()
    sel = m.episodeRow.rowItemSelected
    if sel = invalid or sel.Count() < 2 then return
    if sel[1] >= m.episodes.Count() then return
    ep = m.episodes[sel[1]]
    if m.itemType = "series" then
        playEpisode(ep)
    else
        Nav_push("DetailScreen", { itemId: ep.content_id, itemType: "episode" })
    end if
end sub

sub playEpisode(ep as object)
    params = { itemId: Str_orEmpty(ep.content_id), title: Str_orEmpty(ep.title) }
    r = resumeOf(ep)
    if r > 0 then params.startPosition = r
    applySelections(params, params.itemId)
    ThemeMusic_stop()
    Nav_play(params)
end sub

' ---------- Cast, related, details ----------

sub renderCast()
    cast = Arr_or(m.item.cast)
    crew = Arr_or(m.item.crew)
    if cast.Count() = 0 and crew.Count() = 0 then
        m.castSection.visible = false
        return
    end if
    root = CreateObject("roSGNode", "ContentNode")
    row = root.createChild("ContentNode")
    m.castPeople = []
    for each p in cast
        appendPerson(row, p, Str_orEmpty(p.character))
    end for
    for each p in crew
        appendPerson(row, p, Str_orEmpty(p.job))
    end for
    m.castRow.content = root
    m.castSection.visible = true
end sub

sub appendPerson(row as object, p as object, role as string)
    node = row.createChild("ContentNode")
    Content_ensureFields(node)
    node.title = Str_orEmpty(p.name)
    node.subtitle = role
    node.description = role ' read by the screen reader
    node.cardStyle = "circle"
    node.cardInsetY = 32
    node.HDPosterUrl = Url_resolve(p.photo_url)
    node.contentId = Str_orEmpty(p.person_id)
    node.itemType = "person"
    node.raw = p
    m.castPeople.Push(p)
end sub

sub onCastSelected()
    sel = m.castRow.rowItemSelected
    if sel = invalid or sel.Count() < 2 or m.castPeople = invalid then return
    if sel[1] >= m.castPeople.Count() then return
    p = m.castPeople[sel[1]]
    if Str_isEmpty(p.person_id) then return
    Nav_push("PersonScreen", { personId: Str_orEmpty(p.person_id), name: Str_orEmpty(p.name) })
end sub

sub onSimilar(event as object)
    resp = Api_result(event)
    if not resp.ok or resp.data = invalid then return
    items = Arr_or(resp.data.items)
    m.similar = items
    if items.Count() = 0 then return
    if m.itemType = "series" then m.relatedHeader.text = "Recommended Series" else m.relatedHeader.text = "Related Movies"
    m.relatedRow.content = Content_rows([{ id: "similar", title: "", style: "poster", items: items }], 32)
    m.relatedSection.visible = true
    layoutBody()
    buildZones()
end sub

sub onRelatedSelected()
    sel = m.relatedRow.rowItemSelected
    if sel = invalid or sel.Count() < 2 or m.similar = invalid then return
    if sel[1] >= m.similar.Count() then return
    card = m.similar[sel[1]]
    Nav_push("DetailScreen", { itemId: Str_orEmpty(card.content_id), itemType: Str_orEmpty(card.type) })
end sub

' ---------- Trailers & More (TvDetailTrailersSection, silo-android #640 / #641) ----------

sub renderTrailers()
    t = m.itemType
    m.trailers = []
    if t = "movie" or t = "series" or t = "season" or t = "episode" then m.trailers = Trailer_entries(m.item)
    m.trailerBtn.visible = primaryTrailerIndex() >= 0
    layoutActions()
    if m.trailers.Count() = 0 then
        m.trailersSection.visible = false
        return
    end if
    root = CreateObject("roSGNode", "ContentNode")
    row = root.createChild("ContentNode")
    for each e in m.trailers
        node = row.createChild("ContentNode")
        Content_ensureFields(node)
        node.addFields({ playGlyph: true })
        node.title = e.title
        node.subtitle = e.subtitle
        node.description = e.subtitle ' read by the screen reader
        node.cardStyle = "landscape"
        node.cardInsetY = 32
        node.HDPosterUrl = e.thumbUrl
        node.contentId = e.key
        node.itemType = "trailer"
    end for
    m.trailersRow.content = root
    m.trailersSection.visible = true
end sub

sub onTrailerSelected()
    sel = m.trailersRow.rowItemSelected
    if sel = invalid or sel.Count() < 2 or sel[1] >= m.trailers.Count() then return
    openTrailerEntry(m.trailers[sel[1]])
end sub

sub openTrailerEntry(e as object)
    if e.isLocal then
        playExtra(e)
    else
        openYouTube(e)
    end if
end sub

' The Trailer button (a Siku addition; Android TV has only the row): the first local trailer, else
' the first YouTube trailer, else a teaser (local first). Featurettes and clips don't count.
function primaryTrailerIndex() as integer
    for each wanted in ["trailer", "teaser"]
        for each localFirst in [true, false]
            for i = 0 to m.trailers.Count() - 1
                e = m.trailers[i]
                if e.isLocal = localFirst and LCase(Str_orEmpty(e.raw.kind).Trim()) = wanted then return i
            end for
        end for
    end for
    return -1
end function

sub onTrailerButton()
    i = primaryTrailerIndex()
    if i >= 0 then openTrailerEntry(m.trailers[i])
end sub

' A local extra plays in Siku's player from the beginning, like Android TV's onPlay(..., "extra",
' 0.0): no resume, and the player offers no next episode or Up Next for it.
sub playExtra(e as object)
    ex = e.raw
    params = { itemId: Str_orEmpty(ex.content_id), title: e.title, itemType: "extra", source: "extra", startPosition: 0 }
    fid = Str_orEmpty(ex.file_id)
    if fid <> "" then params.fileId = fid
    d = Num_or(ex.duration_seconds, 0)
    if d > 0 then params.durationSeconds = d
    print "[siku-trailer] play local extra " + params.itemId + " file=" + fid
    ThemeMusic_stop()
    Nav_play(params)
end sub

' YouTube trailers go to the YouTube channel; Roku has no WebView, and streaming YouTube in Siku
' would need stream extraction, which YouTube's terms forbid.
sub openYouTube(e as object)
    if m.ytTask <> invalid then return
    m.ytEntry = e
    print "[siku-trailer] open YouTube video=" + e.videoId
    m.global.toast = "Opening YouTube…"
    task = CreateObject("roSGNode", "YouTubeLaunchTask")
    task.request = { videoId: e.videoId, title: e.title }
    task.observeField("result", "onYouTubeResult")
    m.ytTask = task
    task.control = "RUN"
end sub

' Only arrives when the hand-off did not happen (a launch exits Siku).
sub onYouTubeResult(event as object)
    r = event.getData()
    if m.ytTask <> invalid then m.ytTask.unobserveField("result")
    m.ytTask = invalid
    e = m.ytEntry
    if e = invalid or Type(r) <> "roAssociativeArray" then return
    msg = "Siku couldn't open the YouTube channel on this Roku."
    if r.outcome = "not_installed" then msg = "The YouTube channel isn't installed on this Roku."
    msg = msg + " Scan the code or open the link on your phone to watch it."
    m.ytDialog.videoTitle = e.title
    m.ytDialog.message = msg
    m.ytDialog.url = Trailer_watchUrl(e.videoId)
    m.ytDialog.visible = true
    m.ytDialog.setFocus(true)
end sub

sub onYouTubeDialogDismissed()
    m.ytDialog.visible = false
    focusZone(m.zoneIndex)
end sub

sub renderDetails()
    it = m.item
    rows = []
    d = crewNames("Director")
    if d.Count() > 0 then rows.Push(["Director", joinNames(d, 4)])
    w = crewNames("Writer")
    label = "Writer"
    if w.Count() = 0 then
        w = crewNames("Screenplay")
        label = "Written by"
    end if
    if w.Count() > 0 then rows.Push([label, joinNames(w, 4)])
    s = namesOf(it.studios)
    if s.Count() > 0 then rows.Push(["Studio", joinNames(s, 3)])
    n = namesOf(it.networks)
    if n.Count() > 0 then rows.Push(["Network", joinNames(n, 3)])
    c = namesOf(it.countries)
    if c.Count() > 0 then rows.Push(["Country", joinNames(c, 3)])
    g = namesOf(it.genres)
    if g.Count() > 0 then rows.Push(["Genres", joinNames(g, 6)])
    if not Str_isEmpty(it.release_date) then rows.Push(["Released", airDateText(it.release_date)])
    if not Str_isEmpty(it.first_air_date) then rows.Push(["First Aired", airDateText(it.first_air_date)])
    if not Str_isEmpty(it.last_air_date) then rows.Push(["Last Aired", airDateText(it.last_air_date)])

    m.factRows.removeChildrenIndex(m.factRows.getChildCount(), 0)
    if rows.Count() = 0 then
        m.detailsSection.visible = false
        return
    end if
    y = 0
    for each r in rows
        if Str_orEmpty(r[1]) <> "" then
            l = m.factRows.createChild("Label")
            l.text = r[0]
            l.translation = [0, y]
            l.width = 240
            l.color = "0xEDEDED9E"
            lf = CreateObject("roSGNode", "Font")
            lf.uri = "pkg:/fonts/Inter-medium.otf"
            lf.size = 24
            l.font = lf
            v = m.factRows.createChild("Label")
            v.text = r[1]
            v.translation = [260, y - 3]
            v.width = 1130
            v.wrap = true
            v.maxLines = 2
            v.color = "0xEDEDEDFF"
            vf = CreateObject("roSGNode", "Font")
            vf.uri = "pkg:/fonts/Inter-regular.otf"
            vf.size = 27
            v.font = vf
            h = Label_height(v)
            if h < 36 then h = 36
            y = y + h + 16
        end if
    end for
    m.detailsBg.height = y + 48 - 16
    m.detailsSection.visible = true
end sub

' ---------- Actions ----------

function playTargetId() as string
    if m.itemType = "series" or m.itemType = "season" then
        if m.nextUp <> invalid then return Str_orEmpty(m.nextUp.content_id)
        if not Str_isEmpty(m.item.play_content_id) then return m.item.play_content_id
        if m.episodes.Count() > 0 then return Str_orEmpty(m.episodes[0].content_id)
        return ""
    end if
    return Str_orEmpty(m.item.content_id)
end function

function playTitle() as string
    if (m.itemType = "series" or m.itemType = "season") and m.nextUp <> invalid then return Str_orEmpty(m.nextUp.title)
    return Str_orEmpty(m.item.title)
end function

sub onPlay()
    id = playTargetId()
    if id = "" then
        m.global.toast = "Nothing to play yet"
        return
    end if
    params = { itemId: id, title: playTitle() }
    if m.itemType = "series" or m.itemType = "season" then
        r = resumeOf(m.nextUp)
    else
        r = resumeOf(m.item)
    end if
    if r > 0 then params.startPosition = r
    applySelections(params, id)
    ThemeMusic_stop()
    Nav_play(params)
end sub

sub onStartOver()
    id = playTargetId()
    if id = "" then return
    params = { itemId: id, title: playTitle(), startPosition: 0 }
    applySelections(params, id)
    ThemeMusic_stop()
    Nav_play(params)
end sub

sub onWatchlistToggle()
    st = m.item.user_state
    if st = invalid then
        st = {}
        m.item.user_state = st
    end if
    id = Str_urlEncode(Str_orEmpty(m.item.content_id))
    if st.in_watchlist = true then
        st.in_watchlist = false
        Api_fire("DELETE", "/api/v2/watchlist/" + id)
        m.global.toast = "Removed from Watchlist"
    else
        st.in_watchlist = true
        Api_fire("PUT", "/api/v2/watchlist/" + id)
        m.global.toast = "Added to Watchlist"
    end if
    m.global.homeDirty = true
    updateToggles()
end sub

sub onFavoriteToggle()
    st = m.item.user_state
    if st = invalid then
        st = {}
        m.item.user_state = st
    end if
    id = Str_urlEncode(Str_orEmpty(m.item.content_id))
    if st.is_favorite = true then
        st.is_favorite = false
        Api_fire("DELETE", "/api/v2/favorites/" + id)
        m.global.toast = "Removed from Favorites"
    else
        st.is_favorite = true
        Api_fire("PUT", "/api/v2/favorites/" + id)
        m.global.toast = "Added to Favorites"
    end if
    m.global.homeDirty = true
    updateToggles()
end sub

function isPlayed() as boolean
    if m.item.user_state <> invalid and m.item.user_state.played = true then return true
    if m.item.user_data <> invalid and m.item.user_data.played = true then return true
    return false
end function

function typeNoun() as string
    if m.itemType = "series" then return "Series"
    if m.itemType = "season" then return "Season"
    if m.itemType = "episode" then return "Episode"
    if m.itemType = "movie" then return "Movie"
    return ""
end function

' The selected season's entry in m.seasons, or invalid.
function selectedSeasonEntry() as dynamic
    if m.selectedSeason = invalid then return invalid
    for each s in m.seasons
        if toInt(s.season_number) = m.selectedSeason then return s
    end for
    return invalid
end function

' A season shuffles only when it has two or more playable episodes.
function canShuffleSeason() as boolean
    n = 0
    for each ep in m.episodes
        if toInt(ep.season_number) = m.selectedSeason and Arr_or(ep.files).Count() > 0 then n = n + 1
    end for
    return n > 1
end function

sub onMore()
    acts = []
    noun = typeNoun()
    ' Shuffle leads the menu (shuffle-api-v2.md): the series, then the season on screen.
    if seriesIdOf() <> "" and Shuffle_supports("series") then
        acts.Push({ id: "shuffle_series", label: "Shuffle Series" })
    end if
    season = selectedSeasonEntry()
    if season <> invalid and not Str_isEmpty(season.content_id) and Shuffle_supports("season") and canShuffleSeason() then
        acts.Push({ id: "shuffle_season", label: "Shuffle " + seasonLabel(season) })
    end if
    if isPlayed() then
        acts.Push({ id: "unwatched", label: ("Mark " + noun + " Unwatched").Replace("  ", " ").Trim() })
    else
        acts.Push({ id: "watched", label: ("Mark " + noun + " Watched").Replace("  ", " ").Trim() })
    end if
    if m.item.user_state <> invalid and m.item.user_state.is_favorite = true then
        acts.Push({ id: "favorite", label: "Remove from Favorites" })
    else
        acts.Push({ id: "favorite", label: "Add to Favorites" })
    end if
    if m.item.user_state <> invalid and m.item.user_state.in_watchlist = true then
        acts.Push({ id: "watchlist", label: "Remove from Watchlist" })
    else
        acts.Push({ id: "watchlist", label: "Add to Watchlist" })
    end if
    if m.itemType = "episode" then
        seasonId = ""
        for each s in m.seasons
            if toInt(s.season_number) = toInt(m.item.season_number) then seasonId = Str_orEmpty(s.content_id)
        end for
        if seasonId <> "" then acts.Push({ id: "season", label: "Go to Season " + Str_orEmpty(m.item.season_number) })
    end if
    if (m.itemType = "episode" or m.itemType = "season") and not Str_isEmpty(m.item.series_id) then
        acts.Push({ id: "series", label: "Go to Series" })
    end if
    m.menuKind = "more"
    m.menu.title = "More Actions"
    m.menu.actions = acts
    m.menu.visible = true
    m.menu.setFocus(true)
end sub

sub onShuffleStarted(event as object)
    resp = Api_result(event)
    Shuffle_play(resp)
end sub

sub closeMenu()
    m.menu.visible = false
    focusZone(m.zoneIndex)
end sub

sub onMenuDismissed()
    closeMenu()
end sub

sub onMenuChosen()
    id = m.menu.chosen
    closeMenu()
    if m.menuKind <> "more" then
        onSelectorChosen(m.menuKind, id)
        return
    end if
    cid = Str_urlEncode(Str_orEmpty(m.item.content_id))
    if id = "shuffle_series" then
        Shuffle_start("series", seriesIdOf(), "onShuffleStarted")
    else if id = "shuffle_season" then
        season = selectedSeasonEntry()
        if season <> invalid then Shuffle_start("season", Str_orEmpty(season.content_id), "onShuffleStarted")
    else if id = "watched" or id = "unwatched" then
        if m.item.user_state = invalid then m.item.user_state = {}
        if id = "watched" then
            Api_call({ method: "POST", path: "/api/v2/watched/" + cid }, "onWatchedWritten")
            m.item.user_state.played = true
            m.global.toast = "Marked as Watched"
        else
            Api_call({ method: "DELETE", path: "/api/v2/watched/" + cid }, "onWatchedWritten")
            m.item.user_state.played = false
            m.global.toast = "Marked as Unwatched"
        end if
        if m.item.user_data <> invalid then m.item.user_data.played = (id = "watched")
        m.global.homeDirty = true
    else if id = "favorite" then
        onFavoriteToggle()
    else if id = "watchlist" then
        onWatchlistToggle()
    else if id = "series" then
        Nav_push("DetailScreen", { itemId: Str_orEmpty(m.item.series_id), itemType: "series" })
    else if id = "season" then
        for each s in m.seasons
            if toInt(s.season_number) = toInt(m.item.season_number) then
                Nav_push("DetailScreen", { itemId: Str_orEmpty(s.content_id), itemType: "season" })
            end if
        end for
    end if
end sub

' Once the watched write has landed, refetch the item and its episodes: their watched flags and
' the next-up episode change with it (refreshing before the write could read the old state).
sub onWatchedWritten(event as object)
    resp = Api_result(event)
    if not resp.ok and resp.error <> invalid then print "[Api] "; resp.status; " "; resp.error.title
    if m.item <> invalid then refreshUserState()
end sub

' The first seasons or episodes request failed: say so and put a focusable Retry button there.
sub showEpisodesRetry(msg as string)
    rowHadFocus = m.episodeRow.hasFocus()
    m.episodesFailed = true
    m.episodesMsg.visible = true
    m.episodesMsg.text = msg
    m.episodesRetryBtn.visible = true
    buildZones()
    if rowHadFocus then focusZone(zoneIndexOf("episodesRetry"))
end sub

sub hideEpisodesRetry()
    if not m.episodesFailed then return
    hadFocus = m.episodesRetryBtn.hasFocus()
    m.episodesFailed = false
    m.episodesRetryBtn.visible = false
    buildZones()
    ' Focus moves to what replaced the button: the episode row, or the season chips.
    if hadFocus then
        zi = zoneIndexOf("episodes")
        if zi < 0 then zi = zoneIndexOf("chips")
        if zi < 0 then zi = 0
        focusZone(zi)
    end if
end sub

' Retry: the seasons when they never loaded, else the selected season's episodes.
sub retryEpisodes()
    m.episodesMsg.text = "Loading episodes…"
    if m.seasonsFailed or m.selectedSeason = invalid then
        loadSeasons()
    else
        loadEpisodes(m.selectedSeason)
    end if
end sub

' ---------- Keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.menu.visible or m.ytDialog.visible then return true
    if m.item = invalid then
        if key = "back" then return false
        return true
    end if
    z = zoneName()
    if key = "down" then
        if m.zoneIndex < m.zones.Count() - 1 then focusZone(m.zoneIndex + 1)
        return true
    else if key = "up" then
        if m.zoneIndex > 0 then focusZone(m.zoneIndex - 1)
        return true
    else if key = "left" or key = "right" then
        delta = 1
        if key = "left" then delta = -1
        if z = "actions" then
            ni = m.actionIndex + delta
            if ni >= 0 and ni < m.actionButtons.Count() then
                m.actionIndex = ni
                m.actionButtons[ni].setFocus(true)
            end if
            return true
        else if z = "chips" then
            ni = m.chipIndex + delta
            if ni >= 0 and ni < m.chips.Count() then
                m.chipIndex = ni
                m.chips[ni].setFocus(true)
                scrollChips()
            end if
            return true
        end if
        ' Row lists handle their own horizontal movement; swallow the overflow.
        return true
    else if key = "OK" then
        if z = "details" then return true
        return false
    else if key = "play" then
        onPlay()
        return true
    end if
    return false
end function
