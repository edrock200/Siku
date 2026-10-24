' Card long-press / options actions shared by the Skyline pages and grids.
' Include with <script uri="pkg:/components/widgets/HomeCardActions.brs" />; needs Utils, Api, Nav, Session, Content.
' A page that offers "dismiss" (Home's progress rows) defines `sub CardActions_onDismissed(event)`,
' which runs when the server answers the dismissal.
' SPDX-License-Identifier: AGPL-3.0-or-later

' Builds the action list for a card. rowId tells whether it came from a progress row.
function CardActions_build(card as object, rowId as string) as object
    actions = []
    us = card.user_state
    if us = invalid then us = {}
    if Content_num(card.position_seconds) > 0 then
        actions.Push({ id: "resume", label: "Resume", icon: "play" })
    else
        actions.Push({ id: "play", label: "Play", icon: "play" })
    end if
    if us.played = true then
        actions.Push({ id: "unwatched", label: "Mark as Unwatched", icon: "watched" })
    else
        actions.Push({ id: "watched", label: "Mark as Watched", icon: "check_circle" })
    end if
    if us.is_favorite = true then
        actions.Push({ id: "unfavorite", label: "Remove from Favorites", icon: "heart_filled" })
    else
        actions.Push({ id: "favorite", label: "Add to Favorites", icon: "heart" })
    end if
    if us.in_watchlist = true then
        actions.Push({ id: "unwatchlist", label: "Remove from Watchlist", icon: "bookmark_filled" })
    else
        actions.Push({ id: "watchlist", label: "Add to Watchlist", icon: "bookmark" })
    end if
    if CardActions_isProgressRow(rowId) then
        d = CardActions_dismissal(card)
        if d <> invalid then actions.Push({ id: "dismiss", label: d.label, icon: "close" })
    end if
    return actions
end function

' Home rows built from playback state, whose cards can be removed.
function CardActions_isProgressRow(rowId as string) as boolean
    rid = LCase(rowId)
    return rid = "continue_watching" or rid = "next_up" or rid = "in_progress" or rid = "continue_listening"
end function

' Which Home list a card's removal goes to (HomeDismissal, #632). The server keys the two lists
' differently: an in-progress card leaves Continue Watching against its exact progress_updated_at
' (playing it again brings it back); a Next Up episode has no progress row and leaves Next Up by
' its series. Progress wins when a card has both. invalid: neither list can take the card, so it
' gets no remove action.
function CardActions_dismissal(card as object) as dynamic
    anchor = Str_orEmpty(card.progress_updated_at)
    if anchor <> "" then return { surface: "continue_watching", body: { progress_updated_at: anchor }, label: "Remove from Continue Watching", toast: "Removed from Continue Watching" }
    sid = Str_orEmpty(card.series_id)
    if sid <> "" then return { surface: "next_up", body: { series_id: sid }, label: "Remove from Next Up", toast: "Removed from Next Up" }
    return invalid
end function

' The show the server drops when this card is dismissed from either list: an episode's series, or
' the series itself. Movies and books go one card at a time.
function CardActions_droppedSeriesId(card as object) as string
    t = LCase(Str_orEmpty(card["type"]))
    if t = "series" then return Str_orEmpty(card.content_id)
    if t = "episode" then return Str_orEmpty(card.series_id)
    return ""
end function

' Performs an action. Returns a patch {watched?, favorite?, inWatchlist?, remove?} for the card,
' or invalid when the action opened another screen. Fires the API calls and sets homeDirty.
function CardActions_perform(actionId as string, card as object, rowId as string) as dynamic
    id = Str_orEmpty(card.content_id)
    enc = Str_urlEncode(id)
    if actionId = "play" or actionId = "resume" then
        playId = Str_orEmpty(card.play_content_id)
        if playId = "" then playId = id
        params = { itemId: playId, title: Str_orEmpty(card.title), itemType: Str_orEmpty(card.type) }
        if actionId = "resume" and Content_num(card.position_seconds) > 0 then params.startPosition = Content_num(card.position_seconds)
        Nav_play(params)
        return invalid
    else if actionId = "watched" then
        Api_fire("POST", "/api/v2/watched/" + enc)
        m.global.homeDirty = true
        m.global.toast = "Marked as watched"
        return { watched: true, progress: 0.0 }
    else if actionId = "unwatched" then
        Api_fire("DELETE", "/api/v2/watched/" + enc)
        m.global.homeDirty = true
        m.global.toast = "Marked as unwatched"
        return { watched: false }
    else if actionId = "favorite" then
        Api_fire("PUT", "/api/v2/favorites/" + enc)
        m.global.homeDirty = true
        m.global.toast = "Added to Favorites"
        return { favorite: true }
    else if actionId = "unfavorite" then
        Api_fire("DELETE", "/api/v2/favorites/" + enc)
        m.global.homeDirty = true
        m.global.toast = "Removed from Favorites"
        return { favorite: false }
    else if actionId = "watchlist" then
        Api_fire("PUT", "/api/v2/watchlist/" + enc)
        m.global.homeDirty = true
        m.global.toast = "Added to Watchlist"
        return { inWatchlist: true }
    else if actionId = "unwatchlist" then
        Api_fire("DELETE", "/api/v2/watchlist/" + enc)
        m.global.homeDirty = true
        m.global.toast = "Removed from Watchlist"
        return { inWatchlist: false }
    else if actionId = "dismiss" then
        d = CardActions_dismissal(card)
        if d = invalid or not CardActions_isProgressRow(rowId) then return invalid
        ' The page re-reads Home once the server accepts (CardActions_onDismissed in the page);
        ' meanwhile every card of a dropped show leaves the progress rows.
        Api_send("PUT", "/api/v2/home/dismissals/" + d.surface + "/" + enc, d.body, "CardActions_onDismissed")
        m.global.toast = d.toast
        return { remove: true, removeSeries: CardActions_droppedSeriesId(card) }
    end if
    return invalid
end function

' Opens the detail page for a card.
sub CardActions_openDetail(card as object)
    id = Str_orEmpty(card.content_id)
    if id = "" then return
    Nav_openItem(id, card.type)
end sub
