' SPDX-License-Identifier: AGPL-3.0-or-later
' The one place an episode's label is worded (Silo Android #1035, EpisodeLabel.kt): its season and
' episode code, or, for a series the server marks `episode_labels: "air_date"` (a sports league that
' Sportarr numbers S2026E296), the episode's air date ("Nov 20, 2026", Time_longDate in the interface
' language). The numbers still sort episodes and pick what plays next; only the label changes. An
' undated episode, or one whose air date is not a real YYYY-MM-DD day, keeps its code.
' Pure: no node access, so tests/test_episode_label.py runs it on the host.

' Whether a series with these episode_labels labels its episodes by air date (exact match, as Android).
function EpLabel_byAirDate(labels as dynamic) as boolean
    if Type(labels) <> "roString" and Type(labels) <> "String" then return false
    return labels = "air_date"
end function

' The calendar date of an ISO date or timestamp ("2026-11-20", "2026-11-20T19:30:00Z") as
' "YYYY-MM-DD"; "" when it is not one, including a day the month does not have (2026-02-30), which
' roDateTime would roll into the next month (Android's calendarDateOrNull rejects it too).
function EpLabel_calendarDate(raw as dynamic) as string
    if Type(raw) <> "roString" and Type(raw) <> "String" then return ""
    s = raw.Trim()
    cut = Instr(1, s, "T")
    if cut > 0 then s = Left(s, cut - 1)
    cut = Instr(1, s, " ")
    if cut > 0 then s = Left(s, cut - 1)
    if not Time_isDateOnly(s) then return ""
    y = Val(Left(s, 4))
    mo = Val(Mid(s, 6, 2))
    d = Val(Right(s, 2))
    if y < 1 or mo < 1 or mo > 12 or d < 1 then return ""
    if d > EpLabel_daysInMonth(Int(y), Int(mo)) then return ""
    return s
end function

function EpLabel_daysInMonth(y as integer, mo as integer) as integer
    if mo = 2 then
        if (y mod 4 = 0 and y mod 100 <> 0) or y mod 400 = 0 then return 29
        return 28
    end if
    if mo = 4 or mo = 6 or mo = 9 or mo = 11 then return 30
    return 31
end function

' The air date that labels an episode of a date-labeled series ("Nov 20, 2026"); "" when the series
' uses numbers or the date is missing or unreadable.
function EpLabel_airDate(labels as dynamic, airDate as dynamic) as string
    if not EpLabel_byAirDate(labels) then return ""
    d = EpLabel_calendarDate(airDate)
    if d = "" then return ""
    return Time_longDate(d)
end function

' The code in a surface's spelling (codes are technical: ASCII numbers in every language):
'   "tag"    S01E02    (cards; zero-padded so a row lines up)
'   "short"  S2 · E8   (detail hero line, episode menu)
'   "spaced" S2 E8     (Home marquee meta line)
'   "dotted" S2·E8     (player eyebrow, Info pane, Up Next)
' "" when both numbers are missing; one missing number leaves its half out.
function EpLabel_code(season as dynamic, episode as dynamic, style = "tag" as string) as string
    if style = "tag" then return Content_seasonEpisode(season, episode)
    s = Content_seShort(season, episode)
    if style = "spaced" then return s.Replace(" · ", " ")
    if style = "dotted" then return s.Replace(" · ", "·")
    return s
end function

' The episode's air date for a date-labeled series, else its code in `style`.
function EpLabel_text(season as dynamic, episode as dynamic, labels as dynamic, airDate as dynamic, style = "tag" as string) as string
    d = EpLabel_airDate(labels, airDate)
    if d <> "" then return d
    return EpLabel_code(season, episode, style)
end function

' The series' episode_labels for an item: its own (cards, item detail and /watch carry them), else
' `fallback` (the series page's detail for its episode list, the playing /watch for Up Next).
function EpLabel_labelsOf(item as dynamic, fallback = invalid as dynamic) as dynamic
    if item <> invalid and Type(item) = "roAssociativeArray" and not Str_isEmpty(item.episode_labels) then return item.episode_labels
    return fallback
end function

' EpLabel_text for an episode card or detail (season_number, episode_number, episode_labels, air_date).
function EpLabel_of(item as dynamic, style = "tag" as string, fallbackLabels = invalid as dynamic) as string
    if item = invalid or Type(item) <> "roAssociativeArray" then return ""
    return EpLabel_text(item.season_number, item.episode_number, EpLabel_labelsOf(item, fallbackLabels), item.air_date, style)
end function
