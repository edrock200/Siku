' SPDX-License-Identifier: AGPL-3.0-or-later
' A series' seasons in display order and the season its page opens on (Silo Android #929 / #931;
' adapted from silo-roku a41d106): Specials are season zero and come first, then numbered seasons by
' number, as the server, the web app and every Silo client list them. A fresh series still opens on a
' numbered season. Pure: no node access, so tests/test_seasons.py runs it on the host.

' Whether a season is Specials: season_number 0, or flagged is_specials (whatever its number).
function Seasons_isSpecials(s as dynamic) as boolean
    if s = invalid or Type(s) <> "roAssociativeArray" then return false
    f = s.is_specials
    if (Type(f) = "roBoolean" or Type(f) = "Boolean") and f then return true
    if s.season_number = invalid then return false
    return Int(Num_or(s.season_number, -1)) = 0
end function

' The seasons in display order: Specials first (in the order listed), then numbered seasons by
' number (stable, so a number listed twice keeps its order), then seasons without a number.
function Seasons_ordered(seasons as dynamic) as object
    specials = []
    numbered = []
    rest = []
    for each s in Arr_or(seasons)
        if s <> invalid and Type(s) = "roAssociativeArray" then
            if Seasons_isSpecials(s) then
                specials.Push(s)
            else if s.season_number = invalid then
                rest.Push(s)
            else
                n = Num_or(s.season_number, 0)
                at = numbered.Count()
                for i = 0 to numbered.Count() - 1
                    if n < Num_or(numbered[i].season_number, 0) then
                        at = i
                        exit for
                    end if
                end for
                if at = numbered.Count() then
                    numbered.Push(s)
                else
                    rebuilt = []
                    for i = 0 to numbered.Count() - 1
                        if i = at then rebuilt.Push(s)
                        rebuilt.Push(numbered[i])
                    end for
                    numbered = rebuilt
                end if
            end if
        end if
    end for
    out = specials
    out.Append(numbered)
    out.Append(rest)
    return out
end function

' The season number a series page opens on (shared initialSeasonForDisplay): `preferred` (the
' server's play_season_number) when a listed season has it; otherwise, trying numbered seasons
' before Specials at each step, the first with an episode in progress, then the first partly
' watched, then the first not watched, then the first. invalid when nothing has a number.
function Seasons_initial(seasons as dynamic, preferred as dynamic) as dynamic
    ordered = Seasons_ordered(seasons)
    if preferred <> invalid then
        p = Int(Num_or(preferred, -1))
        for each s in ordered
            if s.season_number <> invalid and Int(Num_or(s.season_number, -2)) = p then return p
        end for
    end if
    candidates = []
    specials = []
    for each s in ordered
        if s.season_number <> invalid then
            if Seasons_isSpecials(s) then specials.Push(s) else candidates.Push(s)
        end if
    end for
    candidates.Append(specials)
    if candidates.Count() = 0 then return invalid
    for each s in candidates
        if Seasons_userNum(s, "in_progress_count") > 0 then return Int(Num_or(s.season_number, 0))
    end for
    for each s in candidates
        watched = Seasons_userNum(s, "watched_count")
        if watched > 0 and watched < Num_or(s.episode_count, 0) then return Int(Num_or(s.season_number, 0))
    end for
    for each s in candidates
        if not Seasons_played(s) then return Int(Num_or(s.season_number, 0))
    end for
    return Int(Num_or(candidates[0].season_number, 0))
end function

' A number from a season's user_data (0 when missing or not a number).
function Seasons_userNum(s as object, key as string) as float
    ud = s.user_data
    if ud = invalid or Type(ud) <> "roAssociativeArray" then return 0
    return Num_or(ud[key], 0)
end function

' Whether a season's user_data says it is watched (a missing flag is not).
function Seasons_played(s as object) as boolean
    ud = s.user_data
    if ud = invalid or Type(ud) <> "roAssociativeArray" then return false
    f = ud.played
    return (Type(f) = "roBoolean" or Type(f) = "Boolean") and f
end function
