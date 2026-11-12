' Maps Silo API objects to ContentNodes for RowList / MarkupGrid / MediaCardItem.
' SPDX-License-Identifier: AGPL-3.0-or-later

' Card fields on every node built here:
'   TITLE, HDPosterUrl (poster or still), FHDPosterUrl (backdrop), contentId, itemType,
'   subtitle, progress (0..1), watched, cardStyle ("poster"|"landscape"|"circle"|"square"), raw (the API object),
'   initials (placeholder text when there is no image; the title when empty),
'   cardInsetX / cardInsetY (room inside a grid cell so the focused 1.10 card is not clipped at the grid's edge),
'   boxSet / cornerLabel (a box set card: sleeves, a "BOX SET" pill and the film count; BoxSets.brs)
'   overlayData / overlayKey / remaining (card overlays: the fields its badges read, their key, and
'   the episodes a started series or season has left; Content_overlayData)
function Content_cardNode(card as object, style = "poster" as string) as object
    node = CreateObject("roSGNode", "ContentNode")
    Content_ensureFields(node)
    Content_fillCard(node, card, style)
    return node
end function

sub Content_ensureFields(node as object)
    node.addFields({
        contentId: ""
        itemType: ""
        subtitle: ""
        progress: 0.0
        watched: false
        cardStyle: "poster"
        backdropUrl: ""
        logoUrl: ""
        badge: ""
        initials: ""
        cardInsetX: 0
        cardInsetY: 0
        boxSet: false
        cornerLabel: ""
        overlayData: {}
        overlayKey: ""
        remaining: 0
        raw: {}
    })
end sub

sub Content_fillCard(node as object, card as object, style as string)
    t = LCase(Str_orEmpty(card.type))
    node.contentId = Str_orEmpty(card.content_id)
    if node.contentId = "" then node.contentId = Str_orEmpty(card.id)
    node.itemType = t
    node.cardStyle = style
    node.raw = card

    title = Str_orEmpty(card.title)
    subtitle = ""
    if t = "episode" then
        se = Content_seasonEpisode(card.season_number, card.episode_number)
        if style = "landscape" and not Str_isEmpty(card.series_title) then
            subtitle = Str_joinDots([se, title], " • ")
            title = card.series_title
        else
            subtitle = se
        end if
    else if card.year <> invalid then
        subtitle = Str_orEmpty(card.year)
    end if
    node.title = title
    node.subtitle = subtitle
    ' Roku's screen reader reads a focused list item's title and description (the card draws
    ' its own captions from title/subtitle, so description is for speech only).
    node.description = subtitle

    ' Spoiler protection (Spoilers.brs) drops an unwatched episode's still; the card then shows
    ' series art the server marks as such, else the default artwork. backdropUrl feeds the
    ' marquee hero, which prefers an episode's series backdrop (#711); poster-shaped episode cards
    ' prefer its season or series poster. Older servers send neither and keep the card's own art.
    backdrop = Spoilers_heroBackdropUrl(card)
    if style = "landscape" then
        img = Spoilers_wideImageUrl(card)
    else if style = "circle" then
        img = Str_orEmpty(card.photo_url)
    else
        img = Spoilers_posterUrl(card)
    end if
    if t = "audiobook_group" then
        node.initials = Content_initials(title)
        if card.group <> invalid then
            node.subtitle = Content_groupSubtitle(card.group)
            node.description = node.subtitle
        end if
    end if
    node.HDPosterUrl = Url_resolve(img)
    node.backdropUrl = Url_resolve(backdrop)
    node.logoUrl = Url_resolve(card.logo_url)

    node.progress = Content_progressOf(card)
    node.watched = Content_watchedOf(card)
    ' A box set card (Silo Android #646, BoxSets.brs): its own poster, "8 films" in the corner, the
    ' watched share as its progress bar, and its caption ("3 / 8 watched", the years or the film
    ' count) in place of the year. It has no watched mark of its own.
    bs = BoxSet_of(card)
    node.boxSet = bs <> invalid
    node.cornerLabel = ""
    if bs <> invalid then
        if node.HDPosterUrl = "" then node.HDPosterUrl = Url_resolve(bs.poster_url)
        if node.backdropUrl = "" then node.backdropUrl = Url_resolve(bs.backdrop_url)
        node.cornerLabel = BoxSet_filmCount(bs.movie_count)
        node.subtitle = BoxSet_cardCaption(bs)
        node.description = TxF("Box set, {0}", [node.subtitle])
        node.progress = BoxSet_watchedFraction(bs)
        node.watched = false
    end if
    ' Card overlays (Overlays.brs, CardOverlayCard.brs): a box set card has none (Android TV
    ' TvCatalogGrid passes no overlay data for one).
    data = {}
    if bs = invalid then data = Content_overlayData(card)
    node.overlayData = data
    node.overlayKey = Content_overlayKey(data)
    node.remaining = 0
    if bs = invalid and (t = "series" or t = "season") then node.remaining = Content_episodesLeft(card)
end sub

' ---------- Card overlays (the data part; Overlays.brs holds the rest) ----------

' The fields of a card the overlay badges read (Android OverlayDataExtractor.fromSectionItem /
' fromBrowseItem / fromEpisode), only those present so the node stays small: overlay_summary's
' tech facts, else an episode's best file; ratings, content and advisory ratings, year, runtime,
' original language, the first studio and network, the show status. Adapted from
' Silo-Server/silo-roku, AGPL-3.0 (source/catalog/overlayData.bs).
function Content_overlayData(card as object) as object
    out = {}
    summary = card.overlay_summary
    if Type(summary) = "roAssociativeArray" then
        for each k in ["resolution", "hdr", "audio", "audio_channels", "video_codec", "container", "aspect_ratio", "release_type", "edition"]
            Content_keepText(out, k, summary[k])
        end for
        if Content_isTrue(summary.multi_audio) then out.multi_audio = true
        if Content_isTrue(summary.multi_sub) then out.multi_sub = true
    else if Type(card.files) = "roArray" then
        Content_overlayFromFiles(out, card)
    end if
    for each k in ["rating_imdb", "rating_tmdb", "rating_rt_critic", "rating_rt_audience", "advisory_age", "year", "runtime"]
        v = Content_num(card[k])
        if v > 0 then out[k] = v
    end for
    for each k in ["content_rating", "original_language", "show_status"]
        Content_keepText(out, k, card[k])
    end for
    Content_keepText(out, "studio", Content_firstText(card.studios))
    Content_keepText(out, "network", Content_firstText(card.networks))
    return out
end function

' An episode without a summary: the last played file's facts, else its highest-resolution file's
' (OverlayDataExtractor.fromEpisode / bestFile; the server's audioChannelsLabel).
sub Content_overlayFromFiles(out as object, card as object)
    best = invalid
    bestRank = -1
    for each f in card.files
        if Type(f) = "roAssociativeArray" then
            r = LCase(Str_orEmpty(f.resolution)).Trim()
            if r = "4k" or r = "uhd" then r = "2160p"
            rank = 0
            if Len(r) > 1 and Right(r, 1) = "p" then rank = Int(Val(Left(r, Len(r) - 1)))
            if best = invalid or rank > bestRank then
                best = f
                bestRank = rank
            end if
        end if
    end for
    ud = card.user_data
    if Type(ud) <> "roAssociativeArray" then ud = {}
    if best = invalid then best = {}
    Content_keepText(out, "resolution", Content_firstText([ud.last_resolution, best.resolution]))
    Content_keepText(out, "video_codec", Content_firstText([ud.last_codec_video, best.codec_video]))
    hdr = ud.last_hdr
    if hdr = invalid then hdr = best.hdr
    if Content_isTrue(hdr) then out.hdr = "HDR"
    ch = Int(Content_num(best.audio_channels))
    labels = { "1": "Mono", "2": "Stereo", "6": "5.1", "7": "6.1", "8": "7.1" }
    if ch > 0 then
        lbl = labels[ch.ToStr()]
        if lbl = invalid then lbl = ch.ToStr() + "ch"
        out.audio_channels = lbl
    end if
    Content_keepText(out, "container", best.container)
end sub

' A flag that is really true (comparing invalid with a Boolean throws on a Roku, pitfall 16).
function Content_isTrue(v as dynamic) as boolean
    if Type(v) = "roBoolean" or Type(v) = "Boolean" then return v
    return false
end function

sub Content_keepText(out as object, key as string, v as dynamic)
    if Type(v) = "roString" or Type(v) = "String" then
        if v.Trim() <> "" then out[key] = v.Trim()
    end if
end sub

function Content_firstText(values as dynamic) as string
    if Type(values) <> "roArray" then return ""
    for each v in values
        if Type(v) = "roString" or Type(v) = "String" then
            if v.Trim() <> "" then return v.Trim()
        end if
    end for
    return ""
end function

' A short, stable key for a card's overlay data ("" for none): two polynomial hashes of its names
' and values, each modulo a 31-bit prime, so OverlayArtTask draws each distinct look once.
function Content_overlayKey(data as object) as string
    if data.Count() = 0 then return ""
    text = ""
    keys = []
    for each k in data
        keys.Push(k)
    end for
    keys.Sort()
    for each k in keys
        text = text + k + "=" + Str_orEmpty(data[k]) + Chr(31)
    end for
    return Content_hash(text)
end function

function Content_hash(text as string) as string
    a = 0&
    b = 0&
    for i = 1 to Len(text)
        c = Asc(Mid(text, i, 1))
        a = (a * 131& + c) mod 2147483647&
        b = (b * 257& + c) mod 2147483629&
    end for
    return a.ToStr() + "z" + b.ToStr()
end function

' The episodes a started, unfinished series or season has left, or 0: an untouched one shows
' nothing, or every new show would carry a count (web CardWatchStatus).
function Content_episodesLeft(card as object) as integer
    for each st in [card.user_data, card.user_state]
        if Type(st) = "roAssociativeArray" then
            if Content_isTrue(st.played) then return 0
            watched = Content_num(st.watched_count)
            unplayed = Content_num(st.unplayed_count)
            if watched > 0 and unplayed > 0 then return Int(unplayed)
        end if
    end for
    return 0
end function

' A card's progress bar fraction (0..1) from position_seconds / duration_seconds.
function Content_progressOf(card as object) as float
    progress = 0.0
    posSec = card.position_seconds
    dur = card.duration_seconds
    if card.user_data <> invalid then
        if posSec = invalid then posSec = card.user_data.position_seconds
        if dur = invalid then dur = card.user_data.duration_seconds
    end if
    posSec = Content_num(posSec)
    dur = Content_num(dur)
    if dur > 0 then progress = posSec / dur
    if progress < 0 then progress = 0
    if progress > 1 then progress = 1
    return progress
end function

' Whether a card shows as watched (user_state / user_data played, or the card's own flag).
function Content_watchedOf(card as object) as boolean
    watched = false
    if card.user_state <> invalid and card.user_state.played = true then watched = true
    if card.user_data <> invalid and card.user_data.played = true then watched = true
    if card.watched = true then watched = true
    return watched
end function

function Content_seasonEpisode(season as dynamic, episode as dynamic) as string
    if season = invalid and episode = invalid then return ""
    s = ""
    if season <> invalid then s = "S" + Str_padLeft(Str_orEmpty(season), 2)
    if episode <> invalid then s = s + "E" + Str_padLeft(Str_orEmpty(episode), 2)
    return s
end function

' Short "S2 · E8" form used on chips and in the marquee.
function Content_seShort(season as dynamic, episode as dynamic) as string
    parts = []
    if season <> invalid then parts.Push("S" + Str_orEmpty(season))
    if episode <> invalid then parts.Push("E" + Str_orEmpty(episode))
    return Str_joinDots(parts)
end function

' Episode card caption (EpisodeCardCaption, #644), the same on the Apple and web clients:
' "S01E02 · Pilot", or the code alone when the episode has no title.
function Content_episodeCaptionTitle(ep as object) as string
    code = "S" + Str_padLeft(Int(Num_or(ep.season_number, 0)).ToStr(), 2) + "E" + Str_padLeft(Int(Num_or(ep.episode_number, 0)).ToStr(), 2)
    title = Str_orEmpty(ep.title).Trim()
    if title = "" then return code
    return code + " · " + title
end function

' The caption's second line: "Feb 18, 2026  ·  52m" (air date, then "52m" / "1h 5m"); "" when
' neither is known.
function Content_episodeCaptionMeta(airDate as string, runtimeMinutes as integer) as string
    parts = []
    if airDate <> "" then parts.Push(airDate)
    if runtimeMinutes > 0 then
        if runtimeMinutes >= 60 then
            parts.Push(TxF("{0}h {1}m", [runtimeMinutes \ 60, runtimeMinutes mod 60]))
        else
            parts.Push(TxF("{0}m", [runtimeMinutes]))
        end if
    end if
    return Str_joinDots(parts, "  ·  ")
end function

' Builds a RowList content tree: rows = [{title, items: [card...], style}]
' insetY pads each card down inside its cell. A real Roku clips RowList items to their cell, so
' without it the focused card's 1.10 scale and glow are cut off at the top (the simulator does not
' clip). Lists that pass it add the same amount to their item height.
function Content_rows(rows as object, insetY = 0 as integer) as object
    root = CreateObject("roSGNode", "ContentNode")
    for each r in rows
        row = root.createChild("ContentNode")
        row.title = r.title
        row.addFields({ rowId: Str_orEmpty(r.id), rowStyle: r.style })
        for each c in r.items
            node = Content_cardNode(c, r.style)
            if insetY > 0 then node.cardInsetY = insetY
            row.appendChild(node)
        end for
    end for
    return root
end function

' Builds a flat grid content node from cards. insetX/insetY are the cell padding MediaCardItem
' leaves around the card (see cardInsetX/Y above).
function Content_grid(cards as object, style = "poster" as string, insetX = 0 as integer, insetY = 0 as integer) as object
    root = CreateObject("roSGNode", "ContentNode")
    Content_appendCards(root, cards, style, insetX, insetY)
    return root
end function

sub Content_appendCards(root as object, cards as object, style = "poster" as string, insetX = 0 as integer, insetY = 0 as integer)
    for each c in cards
        node = Content_cardNode(c, style)
        if insetX > 0 then node.cardInsetX = insetX
        if insetY > 0 then node.cardInsetY = insetY
        root.appendChild(node)
    end for
end sub

' "FH" for "Frank Herbert": up to two initials for an image-less group or person card.
function Content_initials(name as string) as string
    out = ""
    for each word in name.Trim().Tokenize(" ")
        if word <> "" and Len(out) < 2 then
            ch = UCase(Left(word, 1))
            if ch >= "0" and ch <= "Z" then out = out + ch
        end if
    end for
    if out = "" and Len(name) > 0 then out = UCase(Left(name.Trim(), 1))
    return out
end function

' Card for an audiobook group (GET /api/v2/catalog/audiobook-groups item): name, item_count,
' total_duration_seconds, in_progress_count, poster_urls. groupBy is "author" | "narrator" | "series".
function Content_groupCard(group as object, groupField as string) as object
    name = Str_orEmpty(group.name)
    posters = Arr_or(group.poster_urls)
    poster = ""
    for each p in posters
        if poster = "" and not Str_isEmpty(p) then poster = p
    end for
    return { content_id: "group:" + groupField + ":" + name, "type": "audiobook_group", group_by: groupField, title: name, poster_url: poster, group: group }
end function

' "3 books · 2h 5m · 1 in progress" (TvLibraryDetailScreen.audiobookGroupSubtitle).
function Content_groupSubtitle(group as object) as string
    parts = []
    n = Int(Content_num(group.item_count))
    if n >= 1 then parts.Push(TxP("1 book", "{0} books", n))
    if Content_num(group.total_duration_seconds) > 0 then parts.Push(Time_runtime(group.total_duration_seconds))
    if Int(Content_num(group.in_progress_count)) > 0 then parts.Push(TxF("{0} in progress", [Str_orEmpty(group.in_progress_count)]))
    return Str_joinDots(parts)
end function

' The marquee meta line for a card: "2025 · Science Fiction · 1h 59m" / "S2 E8 · Exodus · 52 min · 18m left"
function Content_metaLine(card as object) as string
    t = LCase(Str_orEmpty(card.type))
    parts = []
    if t = "episode" then
        parts.Push(Content_seShort(card.season_number, card.episode_number).Replace(" · ", " "))
        if not Str_isEmpty(card.episode_title) then parts.Push(card.episode_title)
    else
        if card.year <> invalid then parts.Push(Str_orEmpty(card.year))
        genres = Arr_or(card.genres)
        if genres.Count() > 0 then parts.Push(genres[0])
    end if
    dur = Content_num(card.duration_seconds)
    if dur <= 0 then dur = Content_num(card.runtime) * 60
    if dur > 0 then parts.Push(Time_runtime(dur))
    if dur > 0 and Content_num(card.position_seconds) > 0 then
        remaining = dur - Content_num(card.position_seconds)
        if remaining > 60 then parts.Push(TxF("{0} left", [Time_runtime(remaining)]))
    end if
    if not Str_isEmpty(card.content_rating) then parts.Push(card.content_rating)
    return Str_joinDots(parts)
end function

' A JSON number as a float; 0 for anything else (a string, a bool, invalid).
' A server number as a float (0 when absent). Numbers sent as strings ("3600") are parsed like
' Num_or does: the real server and TMDB data sometimes send them that way (skill pitfall 6).
function Content_num(v as dynamic) as float
    if v = invalid then return 0.0
    t = Type(v)
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" or t = "roLongInteger" or t = "LongInteger" then return v * 1.0
    if t = "roString" or t = "String" then return Val(v.Trim())
    return 0.0
end function

' Media modes from a library `type` string (docs/api-spec.md §4.1).
function Library_mode(libType as dynamic) as string
    t = LCase(Str_orEmpty(libType))
    if t = "movie" or t = "movies" then return "movies"
    if t = "series" or t = "show" or t = "shows" or t = "tv" or t = "tvshows" then return "series"
    if t = "video" or t = "mixed" then return "mixed"
    if t = "audiobook" or t = "audiobooks" then return "audiobooks"
    if t = "music" or t = "album" or t = "albums" or t = "artist" or t = "artists" or t = "audio" then return "music"
    if t = "podcast" or t = "podcasts" then return "podcasts"
    return "reading"
end function
