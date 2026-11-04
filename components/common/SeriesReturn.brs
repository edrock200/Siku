' Series playback return (Silo Android #802, tvOS SeriesPlaybackReturn): the episode a series page
' selects when the player it opened closes. The player hands it back as its screen result
' (Nav_close); DetailScreen applies it on a series page of the same series and identity.
' Pure functions, tested by tests/test_series_return.py.
' SPDX-License-Identifier: AGPL-3.0-or-later

' Who the return belongs to: server, account, profile, and whether the profile is a phone's
' borrowed one. "" when nobody is signed in.
function SeriesReturn_identity(s as dynamic) as string
    if s = invalid or Type(s) <> "roAssociativeArray" then return ""
    server = Str_orEmpty(s.serverUrl)
    profile = Str_orEmpty(s.profileId)
    if server = "" or profile = "" then return ""
    userId = ""
    if s.user <> invalid and Type(s.user) = "roAssociativeArray" then userId = Str_orEmpty(s.user.id)
    borrowed = "own"
    tmp = s.temporary
    if (Type(tmp) = "Boolean" or Type(tmp) = "roBoolean") and tmp then borrowed = "borrowed"
    return server + "|" + Str_orEmpty(s.serverId) + "|" + userId + "|" + profile + "|" + borrowed
end function

' A flag that may be missing (never `= true` on invalid: skill pitfall 16).
function SeriesReturn_isTrue(v as dynamic) as boolean
    if Type(v) = "Boolean" or Type(v) = "roBoolean" then return v
    return false
end function

' A season or episode number, -1 when missing or not a number.
function SeriesReturn_num(v as dynamic) as integer
    if v = invalid then return -1
    n = Num_or(v, -1)
    if n < 0 then return -1
    return Int(n)
end function

' The return the player records as it closes, or invalid. st:
'   seriesId, itemId, seasonNumber, episodeNumber  the episode on screen (its watch detail)
'   nextEpisode   what Up Next offers (a catalog episode), or invalid
'   shuffle       a shuffle is playing: its next pick is not the series' next episode
'   reached       the episode reached its credits or its end (opening Up Next by hand does not count)
'   launchIdentity / identity   SeriesReturn_identity when the player opened, and now
' The page lands on the next episode only once this one reached its credits or end, and never on
' a shuffle pick; otherwise on the episode on screen (auto-play may have moved past the first one).
function SeriesReturn_target(st as object) as dynamic
    identity = Str_orEmpty(st.identity)
    if identity = "" or Str_orEmpty(st.launchIdentity) <> identity then return invalid
    seriesId = Str_orEmpty(st.seriesId)
    itemId = Str_orEmpty(st.itemId)
    if seriesId = "" or itemId = "" then return invalid
    t = { "kind": "series_return", "seriesId": seriesId, "episodeId": itemId, "seasonNumber": SeriesReturn_num(st.seasonNumber), "episodeNumber": SeriesReturn_num(st.episodeNumber), "reason": "on_screen", "identity": identity }
    if SeriesReturn_isTrue(st.shuffle) then
        t["reason"] = "shuffle"
        return t
    end if
    nxt = st.nextEpisode
    if SeriesReturn_isTrue(st.reached) and nxt <> invalid and Type(nxt) = "roAssociativeArray" and not Str_isEmpty(nxt.content_id) then
        t["episodeId"] = Str_orEmpty(nxt.content_id)
        t["seasonNumber"] = SeriesReturn_num(nxt.season_number)
        t["episodeNumber"] = SeriesReturn_num(nxt.episode_number)
        t["reason"] = "finished"
    end if
    return t
end function

' The return a series page applies, or invalid: a player's series return for this series page,
' recorded under the identity signed in now.
function SeriesReturn_accept(result as dynamic, itemType as string, seriesId as string, identity as string) as dynamic
    if result = invalid or Type(result) <> "roAssociativeArray" then return invalid
    if Str_orEmpty(result.kind) <> "series_return" then return invalid
    if LCase(itemType) <> "series" or seriesId = "" or identity = "" then return invalid
    if Str_orEmpty(result.seriesId) <> seriesId or Str_orEmpty(result.identity) <> identity then return invalid
    if Str_isEmpty(result.episodeId) then return invalid
    return result
end function

' The season a return needs loaded first: its season when that differs from the one selected and
' the page lists it, else -1 (stay on the selected season).
function SeriesReturn_seasonToLoad(t as dynamic, selectedSeason as dynamic, seasons as object) as integer
    if t = invalid then return -1
    n = SeriesReturn_num(t.seasonNumber)
    if n < 0 then return -1
    if selectedSeason <> invalid and SeriesReturn_num(selectedSeason) = n then return -1
    for each s in seasons
        if s <> invalid and Type(s) = "roAssociativeArray" and SeriesReturn_num(s.season_number) = n then return n
    end for
    return -1
end function

' The index of the return's episode in a season's episodes, -1 when it is not there.
function SeriesReturn_indexIn(t as dynamic, episodes as object) as integer
    if t = invalid then return -1
    id = Str_orEmpty(t.episodeId)
    if id = "" then return -1
    for i = 0 to episodes.Count() - 1
        ep = episodes[i]
        if ep <> invalid and Type(ep) = "roAssociativeArray" and Str_orEmpty(ep.content_id) = id then return i
    end for
    return -1
end function

' "2x5" for the console line ("?" for a missing number).
function SeriesReturn_tag(t as dynamic) as string
    if t = invalid then return "?x?"
    sn = SeriesReturn_num(t.seasonNumber)
    en = SeriesReturn_num(t.episodeNumber)
    s = "?"
    e = "?"
    if sn >= 0 then s = sn.ToStr()
    if en >= 0 then e = en.ToStr()
    return s + "x" + e
end function
