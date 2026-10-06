' Shuffle: server-picked random playback over /api/v2/shuffles (upstream docs/shuffle-api-v2.md).
' The server picks every item; the client starts a shuffle, moves it on, replaces its next pick
' and stops it. Include with <script uri="pkg:/components/common/Shuffle.brs" />; needs Utils,
' Api, Nav and Session (all already in BaseScreen).
'
' Capability: GET /api/v2/shuffles/capabilities, cached on m.global.shuffleCaps per server+profile.
' Entry points start hidden and appear only while state = "available", allowed = true and the
' scope kind is listed in scope_kinds. A 404 (older server) hides them; transient failures keep
' the previous value.
' SPDX-License-Identifier: AGPL-3.0-or-later

' The cache is keyed by server and profile so a switch never reuses stale state.
function Shuffle_capsKey() as string
    s = m.global.session
    if s = invalid then return ""
    return Str_orEmpty(s.serverId) + "|" + Str_orEmpty(s.profileId)
end function

' Makes sure m.global carries the capability field (observers need it to exist).
sub Shuffle_ensureField()
    if not m.global.hasField("shuffleCaps") then m.global.addFields({ shuffleCaps: {} })
end sub

' The cached capability for the current server/profile, or invalid when not probed yet.
function Shuffle_caps() as dynamic
    if not m.global.hasField("shuffleCaps") then return invalid
    c = m.global.shuffleCaps
    if c = invalid or Type(c) <> "roAssociativeArray" or c.key = invalid then return invalid
    if c.key <> Shuffle_capsKey() then return invalid
    return c
end function

' True when the server offers shuffles over `kind`:
' "library" | "series" | "season" | "library_collection" | "user_collection".
function Shuffle_supports(kind as string) as boolean
    c = Shuffle_caps()
    if c = invalid then return false
    if c.state <> "available" or c.allowed <> true then return false
    for each k in Arr_or(c.scope_kinds)
        if k = kind then return true
    end for
    return false
end function

' Probes the capability unless it is cached for this server/profile. `callback` is the
' component's observer for the response; it must call Shuffle_storeCaps(event) first and then
' refresh its entry points. When the capability is already cached nothing is fetched and the
' callback is not called, so refresh the entry points right after calling this too.
sub Shuffle_refreshCaps(callback as string, force = false as boolean)
    Shuffle_ensureField()
    if not force and Shuffle_caps() <> invalid then return
    if m.shuffleCapsPending = true then return
    m.shuffleCapsPending = true
    Api_get("/api/v2/shuffles/capabilities", invalid, callback)
end sub

' Records a capability response on m.global.shuffleCaps and returns the response.
function Shuffle_storeCaps(event as object) as object
    resp = Api_result(event)
    m.shuffleCapsPending = false
    entry = invalid
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" then
        d = resp.data
        entry = { key: Shuffle_capsKey(), state: Str_orEmpty(d.state), allowed: d.allowed = true, scope_kinds: Arr_or(d.scope_kinds), revision: Str_orEmpty(d.revision), fetchedAt: Time_nowSeconds() }
    else if resp.status = 404 then
        ' The server answered: an older server has no shuffles.
        entry = { key: Shuffle_capsKey(), state: "unsupported", allowed: false, scope_kinds: [], revision: "", fetchedAt: Time_nowSeconds() }
    end if
    if entry <> invalid then m.global.shuffleCaps = entry
    return resp
end function

' Whether a library of this type holds movies or episodes: movie, TV and mixed libraries shuffle.
function Shuffle_libraryMode(mode as dynamic) as boolean
    t = LCase(Str_orEmpty(mode))
    return t = "movies" or t = "series" or t = "mixed" or t = "movie" or t = "show" or t = "shows" or t = "tv"
end function

' Starts a shuffle: POST /api/v2/shuffles {scope:{kind,id}}. `callback` gets the response;
' hand it to Shuffle_play to open the player on the first pick.
sub Shuffle_start(kind as string, id as string, callback as string)
    if id = "" then
        m.global.toast = "Couldn't start shuffle."
        return
    end if
    Api_call({ method: "POST", path: "/api/v2/shuffles", query: { image_size: "large" }, body: { scope: { kind: kind, id: id } } }, callback)
end sub

' Plays the first pick of a create response from the beginning, or toasts why it failed.
' Returns true when the player opened.
function Shuffle_play(resp as object) as boolean
    if resp.ok and resp.data <> invalid and Type(resp.data) = "roAssociativeArray" and resp.data.current <> invalid then
        sh = resp.data
        cur = sh.current
        if not Str_isEmpty(cur.content_id) and not Str_isEmpty(sh.id) then
            Nav_play({ itemId: Str_orEmpty(cur.content_id), title: Str_orEmpty(cur.title), itemType: Str_orEmpty(cur.type), startPosition: 0, shuffleId: Str_orEmpty(sh.id), shuffle: sh })
            return true
        end if
    end if
    if resp.status = 409 then
        m.global.toast = "Nothing here can be played."
    else
        m.global.toast = "Couldn't start shuffle."
    end if
    return false
end function

' Names what a shuffle draws from: "Movies", or "Breaking Bad · Season 2" for a season.
function Shuffle_scopeLabel(sh as dynamic) as string
    if sh = invalid or sh.scope = invalid then return ""
    sc = sh.scope
    title = Str_orEmpty(sc.title)
    parent = Str_orEmpty(sc.parent_title)
    if parent <> "" then return parent + " · " + title
    return title
end function

' The pick that plays after `playingId`, or invalid when the shuffle is finished: a scope with
' one playable item announces that item again, and playing it would only restart what just played.
function Shuffle_nextAfter(sh as dynamic, playingId as string) as dynamic
    if sh = invalid or sh["next"] = invalid then return invalid
    nxt = sh["next"]
    if Str_orEmpty(nxt.content_id) = playingId then return invalid
    return nxt
end function
