' Maps Silo API objects to ContentNodes for RowList / MarkupGrid / MediaCardItem.
' SPDX-License-Identifier: AGPL-3.0-or-later

' Card fields on every node built here:
'   TITLE, HDPosterUrl (poster or still), FHDPosterUrl (backdrop), contentId, itemType,
'   subtitle, progress (0..1), watched, cardStyle ("poster"|"landscape"|"circle"|"square"), raw (the API object),
'   initials (placeholder text when there is no image; the title when empty),
'   cardInsetX / cardInsetY (room inside a grid cell so the focused 1.10 card is not clipped at the grid's edge)
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

    poster = Str_orEmpty(card.poster_url)
    backdrop = Str_orEmpty(card.backdrop_url)
    still = Str_orEmpty(card.still_url)
    if style = "landscape" then
        img = still
        if img = "" then img = backdrop
        if img = "" then img = poster
    else if style = "circle" then
        img = Str_orEmpty(card.photo_url)
    else
        img = poster
    end if
    if t = "audiobook_group" then
        node.initials = Content_initials(title)
        if card.group <> invalid then node.subtitle = Content_groupSubtitle(card.group)
    end if
    node.HDPosterUrl = Url_resolve(img)
    node.backdropUrl = Url_resolve(backdrop)
    node.logoUrl = Url_resolve(card.logo_url)

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
    node.progress = progress

    watched = false
    if card.user_state <> invalid and card.user_state.played = true then watched = true
    if card.user_data <> invalid and card.user_data.played = true then watched = true
    if card.watched = true then watched = true
    node.watched = watched
end sub

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

' Builds a RowList content tree: rows = [{title, items: [card...], style}]
' insetY pads each card down inside its cell. A real Roku clips RowList items to their cell, so
' without it the focused card's 1.10 scale and glow are cut off at the top (the simulator does not
' clip). Lists that pass it add the same amount to their item height.
function Content_rows(rows as object, insetY = 0 as integer) as object
    root = CreateObject("roSGNode", "ContentNode")
    for each r in rows
        row = root.createChild("ContentNode")
        row.title = r.title
        row.addFields({ rowId: Str_orEmpty(r.id), rowStyle: r.style, raw: r })
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
    if n = 1 then
        parts.Push("1 book")
    else if n > 1 then
        parts.Push(n.ToStr() + " books")
    end if
    if Content_num(group.total_duration_seconds) > 0 then parts.Push(Time_runtime(group.total_duration_seconds))
    if Int(Content_num(group.in_progress_count)) > 0 then parts.Push(Str_orEmpty(group.in_progress_count) + " in progress")
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
        if remaining > 60 then parts.Push(Time_runtime(remaining) + " left")
    end if
    if not Str_isEmpty(card.content_rating) then parts.Push(card.content_rating)
    return Str_joinDots(parts)
end function

' A JSON number as a float; 0 for anything else (a string, a bool, invalid).
function Content_num(v as dynamic) as float
    if v = invalid then return 0.0
    t = Type(v)
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" or t = "roLongInteger" or t = "LongInteger" then return v * 1.0
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
