' Roku deep links (certification 5.1 / 5.2): what a launch or roInput link asks for, and what it
' plays once its item is read. Pure helpers (no SceneGraph); MainScene runs the flow
' (handleDeepLink, DeepLink_* subs there). Adapted from Silo-Server/silo-roku, AGPL-3.0
' (source/deeplink/parse.bs, source/deeplink/route.bs playableId).
'   - A movie or episode plays at once, resuming where the profile left off (as Siku's Play).
'   - A series or season plays its next episode (`play_content_id`).
'   - Music and audiobooks open their audio page, as before.
'   - A content ID longer than 255 characters, or a mediaType Roku does not document, is refused
'     before any request.
' SPDX-License-Identifier: AGPL-3.0-or-later

function DeepLink_maxIdLength() as integer
    return 255
end function

' The link in a launch or input event: invalid when the event carries no contentId (an ordinary
' launch, or an input that is not a deep link), else { valid, contentId, mediaType, kind, reason }.
' mediaType is lower case; kind is "video" or "audio"; reason is "" when valid, else
' missing_content_id, content_id_too_long or unsupported_media_type. An empty mediaType is read
' as video and resolved from the item's own type.
function DeepLink_parse(args as dynamic) as dynamic
    if Type(args) <> "roAssociativeArray" then return invalid
    cid = args.contentId
    if cid = invalid then return invalid
    link = { valid: false, contentId: "", mediaType: "", kind: "", reason: "" }
    t = Type(cid)
    if t <> "String" and t <> "roString" then
        link.reason = "missing_content_id"
        return link
    end if
    if cid.Trim() = "" then
        link.reason = "missing_content_id"
        return link
    end if
    if Len(cid) > DeepLink_maxIdLength() then
        link.reason = "content_id_too_long"
        return link
    end if
    mt = ""
    raw = args.mediaType
    if Type(raw) = "String" or Type(raw) = "roString" then mt = LCase(raw.Trim())
    kind = DeepLink_kindOf(mt)
    if kind = "" then
        link.reason = "unsupported_media_type"
        return link
    end if
    return { valid: true, contentId: cid, mediaType: mt, kind: kind, reason: "" }
end function

' "video", "audio" or "" (refused) for a lower-case mediaType.
function DeepLink_kindOf(mt as string) as string
    if mt = "" then return "video"
    video = { "movie": true, "episode": true, "series": true, "season": true, "shortformvideo": true, "tvspecial": true, "special": true }
    audio = { "album": true, "artist": true, "audiobook": true, "track": true }
    if video.DoesExist(mt) then return "video"
    if audio.DoesExist(mt) then return "audio"
    return ""
end function

' What to do with a catalog item body (GET /api/v2/catalog/items/{id}):
'   { action: "play", itemId, title }       a movie, episode or other video plays itself
'   { action: "next", itemId }               a series or season: read its next episode, then play it
'   { action: "detail", itemId }             a series or season with no next episode: its page
'   { action: "audio", itemId, itemType }    an audio item (an untyped link to one)
'   { action: "drop", reason }               nothing to open
function DeepLink_route(item as dynamic) as object
    if Type(item) <> "roAssociativeArray" then return { action: "drop", reason: "unavailable" }
    cid = Str_orEmpty(item.content_id)
    if cid = "" then return { action: "drop", reason: "unavailable" }
    t = LCase(Str_orEmpty(item.type))
    if t = "series" or t = "season" then
        nextId = Str_orEmpty(item.play_content_id)
        if nextId = "" then return { action: "detail", itemId: cid }
        return { action: "next", itemId: nextId }
    end if
    if t = "album" or t = "artist" or t = "audiobook" or t = "track" or t = "song" then return { action: "audio", itemId: cid, itemType: t }
    return { action: "play", itemId: cid, title: Str_orEmpty(item.title) }
end function

' Where the profile left the item (seconds), 0 when it was not started or is finished: the same
' rule as DetailScreen's Play (resumeOf).
function DeepLink_resume(item as dynamic) as float
    if Type(item) <> "roAssociativeArray" or Type(item.user_data) <> "roAssociativeArray" then return 0
    p = Num_or(item.user_data.position_seconds, 0)
    if p <= 0 then return 0
    d = Num_or(item.user_data.duration_seconds, 0)
    if d > 0 and p >= d - 5 then return 0
    return p
end function

' PlayerScreen params for a playable item body.
function DeepLink_playerParams(item as object) as object
    params = { itemId: Str_orEmpty(item.content_id), title: Str_orEmpty(item.title) }
    r = DeepLink_resume(item)
    if r > 0 then params["startPosition"] = r
    return params
end function
