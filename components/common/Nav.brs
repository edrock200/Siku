' Navigation helpers for screens. SPDX-License-Identifier: AGPL-3.0-or-later

' Opens a screen on top of this one.
sub Nav_push(screen as string, params = {} as object)
    m.top.navigateTo = { screen: screen, params: params }
end sub

' Replaces this screen with another.
sub Nav_replace(screen as string, params = {} as object)
    m.top.navigateTo = { screen: screen, params: params, replace: true }
end sub

' Clears the whole stack and opens a screen.
sub Nav_reset(screen as string, params = {} as object)
    m.top.navigateTo = { screen: screen, params: params, reset: true }
end sub

' Closes this screen, optionally passing a result to the one below.
sub Nav_close(result = invalid as dynamic)
    if result <> invalid then m.top.result = result
    m.top.close = true
end sub

' Starts playback. params.itemType routes audio items to the audio player:
' audiobooks resume as a book, tracks play as a one-item queue, and albums/artists
' open their detail page (which builds the queue).
sub Nav_play(params as object)
    t = LCase(Str_orEmpty(params.itemType))
    if t = "audiobook" then
        p = { itemId: params.itemId }
        if params.startPosition <> invalid then p.startPosition = params.startPosition
        m.top.navigateTo = { screen: "AudioPlayerScreen", params: p }
    else if t = "track" or t = "song" then
        m.top.navigateTo = { screen: "AudioPlayerScreen", params: { queue: [{ contentId: params.itemId, title: Str_orEmpty(params.title) }], index: 0 } }
    else if Nav_isAudioType(t) then
        Nav_openItem(params.itemId, t)
    else
        m.top.navigateTo = { screen: "PlayerScreen", params: params }
    end if
end sub

' True for item types that open the audio detail page instead of the video one.
function Nav_isAudioType(itemType as dynamic) as boolean
    t = LCase(Str_orEmpty(itemType))
    return t = "album" or t = "artist" or t = "track" or t = "audiobook" or t = "song" or t = "musicalbum" or t = "musicartist"
end function

' Opens the right detail page for a catalog item. card: the card that was picked, if any; a movie
' or series card seeds the page (Nav_detailSeed), so it draws the card's title, facts and artwork at
' once and fills in when its detail request answers (Silo Android #971).
sub Nav_openItem(itemId as string, itemType = "" as dynamic, card = invalid as dynamic)
    t = Str_orEmpty(itemType)
    if Nav_isAudioType(t) then
        Nav_push("AudioDetailScreen", { itemId: itemId, itemType: LCase(t) })
    else
        p = { itemId: itemId, itemType: t }
        seed = Nav_detailSeed(card, itemId)
        if seed <> invalid then p.seed = seed
        Nav_push("DetailScreen", p)
    end if
end sub

' A provisional detail from the card that opens `openingId` (Android's detailSeed, DetailSeed.kt):
' only the card's own movie or series page, only with a title, and only the fields a card carries
' (title, facts, overview, artwork). Files, watch state, cast and crew wait for the detail. An
' episode card, or anything else, seeds nothing. Returns invalid then.
function Nav_detailSeed(card as dynamic, openingId as string) as dynamic
    if card = invalid or Type(card) <> "roAssociativeArray" or openingId = "" then return invalid
    if Str_orEmpty(card.content_id) <> openingId or Str_isEmpty(card.title) then return invalid
    t = LCase(Str_orEmpty(card["type"]))
    if t <> "movie" and t <> "series" then return invalid
    seed = { "type": t }
    for each k in ["content_id", "title", "year", "release_date", "first_air_date", "overview", "machine_translated_fields", "runtime", "content_rating", "genres", "season_count", "poster_url", "backdrop_url", "logo_url", "poster_is_episode_still", "backdrop_is_episode_still"]
        if card[k] <> invalid then seed[k] = card[k]
    end for
    return seed
end function

' A "More Like This" pick on a detail page (Silo Android #737): the first pick from a page opens a
' new page, and every later pick replaces the page a rail opened, so Back goes to the title the
' chain started from, then to wherever that title was opened. Picking the starting title again
' goes back to it; picking the title on screen does nothing (a repeat Select while the page is
' changing). chainStartId is "" on a page not opened from a rail.
' Returns "ignore", "push", "replace" or "back".
function Nav_chainAction(currentId as string, chainStartId as string, pickedId as string) as string
    if pickedId = "" or pickedId = currentId then return "ignore"
    if chainStartId = "" then return "push"
    if pickedId = chainStartId then return "back"
    return "replace"
end function

