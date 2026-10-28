' Home cache: an instant start for Home, as Android TV warms Home from its Room-backed
' HomeCachePort before the server answers. Home draws the last server answer for this server,
' account and profile from `cachefs:/siku-home-v1-<owner>.json`, then reads the server as before
' and replaces it. The idea and the file discipline (owner-keyed name, temp file then rename,
' corrupt / evicted / unsupported storage treated as a miss, purge on sign-out, results dropped
' when the session changed meanwhile) follow ManavA/silo-roku's HomeCacheTask
' (https://github.com/ManavA/silo-roku, AGPL-3.0), adapted to Siku.
'
' What is stored: the Home sections as the server ordered them (id, title, type, flags) with
' their cards trimmed to the fields cards, the marquee and the card actions read. Never stored:
' artwork URLs (Silo signs them with exp/sig or presigns them, and they expire within a day or
' 15 minutes), access or profile tokens, or anything from the session. A cached Home therefore
' draws titles, details and default artwork; the server answer brings the images.
'
' The pure functions here run on the render thread (HomePage) and in HomeCacheTask, and are
' host-tested (tests/test_home_cache.py). File I/O lives only in HomeCacheTask.
' SPDX-License-Identifier: AGPL-3.0-or-later

function HomeCache_schema() as integer
    return 1
end function

' A cached Home older than this is not drawn (it is deleted on the next write).
function HomeCache_maxAgeSeconds() as integer
    return 86400
end function

' Bounds that keep the file small (Roku's cachefs is shared and may be evicted at any time).
' `bytes` bounds the file in UTF-8 bytes, checked the same way on write and read (Android TV's
' Room cache allows 1.5 MB). A full Home (30 x 24 cards) is about 400 KB in English and 900 KB
' in CJK text; the overview only feeds the marquee's two-line synopsis (about 120 characters),
' so 150 are kept.
function HomeCache_limits() as object
    return { sections: 30, items: 24, overview: 150, text: 200, bytes: 1048576 }
end function

' The identity a cache belongs to: server, account and profile. "" means "do not cache" (signed
' out, no profile yet, or a phone's temporary profile borrowed for remote playback). HomeCacheTask
' hashes it (SHA-256) for the file name, so no id or address appears on storage.
function HomeCache_ownerSource(s as dynamic) as string
    if s = invalid or Type(s) <> "roAssociativeArray" then return ""
    ' A phone's borrowed profile (Session_save "temporary"); typed check, never `= true` on a
    ' value that may be missing (skill pitfall 16).
    tmp = s.temporary
    if (Type(tmp) = "Boolean" or Type(tmp) = "roBoolean") and tmp then return ""
    server = HomeCache_str(s.serverUrl)
    token = HomeCache_str(s.accessToken)
    profile = HomeCache_str(s.profileId)
    if server = "" or token = "" or profile = "" then return ""
    userId = ""
    if s.user <> invalid and Type(s.user) = "roAssociativeArray" then userId = HomeCache_str(s.user.id)
    return FormatJson(["siku-home", server, HomeCache_str(s.serverId), userId, profile])
end function

' The file name for an owner hash (64 lower-case hex digits).
function HomeCache_fileName(ownerHash as string) as string
    return "siku-home-v1-" + ownerHash + ".json"
end function

' Whether a cachefs file name is one of ours (the cache or a write's temp file
' `<name>.<uuid>.part`, unique per write so two writes never share one), for purges.
function HomeCache_isOwnedName(name as string) as boolean
    re = CreateObject("roRegex", "^siku-home-v1-[0-9a-f]{64}\.json(\.[0-9a-f-]{1,36}\.part)?$", "")
    return re.IsMatch(name)
end function

' "fresh" | "stale" (older than the limit) | "future" (the clock moved back: not trusted).
function HomeCache_freshness(savedAt as dynamic, now as integer) as string
    t = Type(savedAt)
    if t <> "Integer" and t <> "roInt" and t <> "roInteger" and t <> "LongInteger" and t <> "roLongInteger" and t <> "Double" and t <> "roDouble" and t <> "Float" and t <> "roFloat" then return "stale"
    age = now - savedAt
    if age < -300 then return "future"
    if age > HomeCache_maxAgeSeconds() then return "stale"
    return "fresh"
end function

' ---------- Trimming ----------

function HomeCache_str(v as dynamic) as string
    if v = invalid then return ""
    t = Type(v)
    if t = "roString" or t = "String" then return v
    if t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" or t = "roLongInteger" then return v.ToStr()
    return ""
end function

function HomeCache_isScalar(v as dynamic) as boolean
    t = Type(v)
    return t = "Boolean" or t = "roBoolean" or t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" or t = "roString" or t = "String"
end function

' A key that may carry an address, a signature or a credential: never stored.
function HomeCache_isUnsafeKey(key as string) as boolean
    k = LCase(key)
    if Right(k, 4) = "_url" or Right(k, 5) = "_urls" or k = "url" or k = "urls" then return true
    if Instr(1, k, "token") > 0 or Instr(1, k, "thumbhash") > 0 or Instr(1, k, "signature") > 0 then return true
    return false
end function

' A string cut to `limit` characters.
function HomeCache_clip(v as dynamic, limit as integer) as dynamic
    if Type(v) <> "roString" and Type(v) <> "String" then return v
    if Len(v) <= limit then return v
    return Left(v, limit)
end function

' The scalar members of a nested object (user_state, user_data, overlay_summary, group), without
' URLs or credentials.
function HomeCache_scalars(o as dynamic) as dynamic
    if o = invalid or Type(o) <> "roAssociativeArray" then return invalid
    out = {}
    lim = HomeCache_limits()
    for each k in o
        v = o[k]
        if not HomeCache_isUnsafeKey(k) and HomeCache_isScalar(v) then out[k] = HomeCache_clip(v, lim.text)
    end for
    return out
end function

' The card fields Home reads (Content_fillCard, Content_metaLine, the marquee, Spoilers.brs,
' HomeCardActions.brs). Artwork URLs are left out on purpose (see the header).
function HomeCache_cardKeys() as object
    return ["id", "content_id", "type", "title", "series_title", "episode_title", "series_id", "season_number", "episode_number", "year", "runtime", "duration_seconds", "position_seconds", "progress_updated_at", "play_content_id", "play_season_number", "content_rating", "watched", "item_source", "library_id", "overview"]
end function

function HomeCache_trimCard(card as dynamic) as dynamic
    if card = invalid or Type(card) <> "roAssociativeArray" then return invalid
    lim = HomeCache_limits()
    out = {}
    for each k in HomeCache_cardKeys()
        v = card[k]
        if v <> invalid and HomeCache_isScalar(v) then
            if k = "overview" then out[k] = HomeCache_clip(v, lim.overview) else out[k] = HomeCache_clip(v, lim.text)
        end if
    end for
    genres = []
    for each g in Arr_or(card.genres)
        if genres.Count() < 2 and (Type(g) = "roString" or Type(g) = "String") then genres.Push(HomeCache_clip(g, 40))
    end for
    if genres.Count() > 0 then out.genres = genres
    for each k in ["user_state", "user_data", "overlay_summary", "group"]
        sc = HomeCache_scalars(card[k])
        if sc <> invalid and sc.Count() > 0 then out[k] = sc
    end for
    ' Spoiler protection flags (*_is_episode_still) say which artwork slot is a still.
    for each k in card
        if Right(LCase(k), 17) = "_is_episode_still" and HomeCache_isScalar(card[k]) then out[k] = card[k]
    end for
    return out
end function

' One Home section as stored: its metadata and its trimmed cards, unfiltered (hide-watched and
' this Roku's section order are applied again when the cache is drawn, so they follow the
' settings as they are then).
function HomeCache_trimSection(section as dynamic, items as dynamic) as dynamic
    if section = invalid or Type(section) <> "roAssociativeArray" then return invalid
    lim = HomeCache_limits()
    s = {}
    for each k in ["id", "title", "section_type", "featured", "customized", "is_custom", "item_limit", "total_count"]
        v = section[k]
        if v <> invalid and HomeCache_isScalar(v) then s[k] = HomeCache_clip(v, lim.text)
    end for
    cards = []
    for each c in Arr_or(items)
        if cards.Count() >= lim.items then exit for
        t = HomeCache_trimCard(c)
        if t <> invalid then cards.Push(t)
    end for
    s.items = cards
    return s
end function

' The body HomeCacheTask writes (it adds owner and savedAt): entries are HomePage's
' [{section, items}] before filtering.
function HomeCache_payload(entries as object) as object
    lim = HomeCache_limits()
    sections = []
    for each e in entries
        if sections.Count() >= lim.sections then exit for
        if e <> invalid and Type(e) = "roAssociativeArray" then
            items = e.rawItems
            if items = invalid then items = e.items
            s = HomeCache_trimSection(e.section, items)
            if s <> invalid then sections.Push(s)
        end if
    end for
    return { schema: HomeCache_schema(), sections: sections }
end function

' Checks a parsed file against the owner and the clock. Returns { status: "hit" | "stale" | "miss",
' reason, age, sections }. A file of another owner or schema, or of the wrong shape, is a miss.
function HomeCache_check(snapshot as dynamic, ownerHash as string, now as integer) as object
    out = { status: "miss", reason: "", age: 0, sections: [] }
    if snapshot = invalid or Type(snapshot) <> "roAssociativeArray" then
        out.reason = "corrupt"
        return out
    end if
    schema = snapshot.schema
    st = Type(schema)
    if (st <> "Integer" and st <> "roInt" and st <> "roInteger") or schema <> HomeCache_schema() then
        out.reason = "schema"
        return out
    end if
    if HomeCache_str(snapshot.owner) <> ownerHash or ownerHash = "" then
        out.reason = "owner"
        return out
    end if
    if Type(snapshot.sections) <> "roArray" then
        out.reason = "corrupt"
        return out
    end if
    fresh = HomeCache_freshness(snapshot.savedAt, now)
    if fresh <> "fresh" then
        out.status = "stale"
        out.reason = fresh
        return out
    end if
    out.age = now - snapshot.savedAt
    sections = []
    for each s in snapshot.sections
        if s <> invalid and Type(s) = "roAssociativeArray" then
            s.items = Arr_or(s.items)
            sections.Push(s)
        end if
    end for
    if sections.Count() = 0 then
        out.reason = "empty"
        return out
    end if
    out.status = "hit"
    out.sections = sections
    return out
end function
