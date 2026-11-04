' SPDX-License-Identifier: AGPL-3.0-or-later
' Pure helpers for the Calendar page (no SceneGraph, so tests/test_calendar_format.py runs them):
' the IANA time zone sent to GET /api/v2/calendar, the cards' badges and their air time.

' The IANA zone the server groups days by, from Roku's own time-zone name (roDeviceInfo.GetTimeZone
' gives "US/Eastern", "Europe/United Kingdom", "Canada/Central Standard"), else a whole-hour
' "Etc/GMT±N" from the TV's offset (minutes east of UTC; Etc names count west as positive), else ""
' (send no zone: the server uses UTC). Adapted from Silo-Server/silo-roku, AGPL-3.0
' (source/calendar/page.bs, timeZone/ianaLike).
function CalFmt_ianaZone(rokuName as dynamic, offsetMinutes as dynamic) as string
    known = {
        "US/Puerto Rico": "America/Puerto_Rico", "US/Guam": "Pacific/Guam", "US/Samoa": "Pacific/Pago_Pago",
        "US/Hawaii": "Pacific/Honolulu", "US/Aleutian": "America/Adak", "US/Alaska": "America/Anchorage",
        "US/Pacific": "America/Los_Angeles", "US/Arizona": "America/Phoenix", "US/Mountain": "America/Denver",
        "US/Central": "America/Chicago", "US/Eastern": "America/New_York",
        "Canada/Pacific": "America/Vancouver", "Canada/Mountain": "America/Edmonton",
        "Canada/Central Standard": "America/Regina", "Canada/Central": "America/Winnipeg",
        "Canada/Eastern": "America/Toronto", "Canada/Atlantic": "America/Halifax",
        "Canada/Newfoundland": "America/St_Johns",
        "Europe/Iceland": "Atlantic/Reykjavik", "Europe/Ireland": "Europe/Dublin",
        "Europe/United Kingdom": "Europe/London", "Europe/Portugal": "Europe/Lisbon",
        "Europe/Central European Time": "Europe/Paris", "Europe/Greece/Finland": "Europe/Athens"
    }
    name = Str_orEmpty(rokuName).Trim()
    ' AA keys are case-insensitive, so look the name up by its exact spelling first.
    if name <> "" and known.DoesExist(name) then return known[name]
    if CalFmt_ianaLike(name) then return name
    if name = "UTC" or name = "GMT" or name = "Etc/UTC" then return "Etc/UTC"
    offset = Int(Num_or(offsetMinutes, 0))
    if offset mod 60 <> 0 then return ""
    hours = offset \ 60
    if hours = 0 then return "Etc/UTC"
    if hours > 0 then return "Etc/GMT-" + hours.ToStr()
    return "Etc/GMT+" + (-hours).ToStr()
end function

' Whether a name outside Roku's list reads as an IANA zone ("Asia/Tokyo"), as newer firmware may
' give: a known IANA area, a slash, and no spaces.
function CalFmt_ianaLike(name as string) as boolean
    slash = Instr(1, name, "/")
    if slash < 2 or slash = Len(name) or Instr(1, name, " ") > 0 then return false
    areas = { Africa: true, America: true, Antarctica: true, Asia: true, Atlantic: true, Australia: true, Europe: true, Indian: true, Pacific: true, Etc: true }
    return areas.DoesExist(Left(name, slash - 1))
end function

' The TV's offset east of UTC in minutes (roDateTime.ToLocalTime moves the clock by it).
function CalFmt_offsetMinutes() as integer
    dt = CreateObject("roDateTime")
    utc = dt.AsSeconds()
    dt.ToLocalTime()
    return Int((dt.AsSeconds() - utc) / 60)
end function

' Every badge the server sends that the card can name, in the server's order (Silo Android
' calendarBadgeLabel, #722: PREMIERE, NEW SEASON, FINALE, and DIGITAL / PHYSICAL for a movie listed
' on its first home release; unknown ones are skipped).
function CalFmt_badgeLabels(badges as dynamic) as object
    out = []
    seen = {}
    for each b in Arr_or(badges)
        s = LCase(Str_orEmpty(b))
        label = ""
        if s = "series_premiere" then
            label = "PREMIERE"
        else if s = "season_premiere" then
            label = "NEW SEASON"
        else if s = "finale" or s = "season_finale" or s = "series_finale" then
            label = "FINALE"
        else if s = "digital" then
            label = "DIGITAL"
        else if s = "physical" then
            label = "PHYSICAL"
        end if
        if label <> "" and not seen.DoesExist(label) then
            seen[label] = true
            out.Push(label)
        end if
    end for
    return out
end function

function CalFmt_digits(s as string) as boolean
    if s = "" then return false
    for i = 1 to Len(s)
        c = Asc(Mid(s, i, 1))
        if c < 48 or c > 57 then return false
    end for
    return true
end function

' Seconds since 1970 of an RFC 3339 instant with "Z" or a numeric offset
' ("2026-06-09T21:00:00-04:00"), or -1. Parsed by hand: roDateTime.FromISO8601String does not
' apply numeric offsets on every Roku OS. Adapted from Silo-Server/silo-roku, AGPL-3.0
' (source/calendar/page.bs, instantSeconds).
function CalFmt_instantSeconds(value as dynamic) as integer
    text = Str_orEmpty(value)
    if Len(text) < 20 then return -1
    sep = Mid(text, 11, 1)
    if sep <> "T" and sep <> "t" then return -1
    datePart = Left(text, 10)
    if not Time_isDateOnly(datePart) then return -1
    clock = Mid(text, 12, 8)
    if Mid(clock, 3, 1) <> ":" or Mid(clock, 6, 1) <> ":" then return -1
    if not CalFmt_digits(Left(clock, 2)) or not CalFmt_digits(Mid(clock, 4, 2)) or not CalFmt_digits(Mid(clock, 7, 2)) then return -1
    dt = CreateObject("roDateTime")
    dt.FromISO8601String(datePart + "T00:00:00Z")
    secs = dt.AsSeconds() + Int(Val(Left(clock, 2))) * 3600 + Int(Val(Mid(clock, 4, 2))) * 60 + Int(Val(Mid(clock, 7, 2)))
    rest = Mid(text, 20)
    if Left(rest, 1) = "." then
        i = 2
        while i <= Len(rest) and CalFmt_digits(Mid(rest, i, 1))
            i = i + 1
        end while
        rest = Mid(rest, i)
    end if
    if rest = "Z" or rest = "z" then return secs
    if Len(rest) <> 6 or Mid(rest, 4, 1) <> ":" or not CalFmt_digits(Mid(rest, 2, 2)) or not CalFmt_digits(Mid(rest, 5, 2)) then return -1
    off = Int(Val(Mid(rest, 2, 2))) * 3600 + Int(Val(Mid(rest, 5, 2))) * 60
    if Left(rest, 1) = "+" then return secs - off
    if Left(rest, 1) = "-" then return secs + off
    return -1
end function

' "9:05 PM", or "21:05" on a 24-hour clock.
function CalFmt_clockText(hour as integer, minute as integer, clock24 as boolean) as string
    if clock24 then return Str_padLeft(hour.ToStr(), 2) + ":" + Str_padLeft(minute.ToStr(), 2)
    period = "AM"
    if hour >= 12 then period = "PM"
    shown = hour mod 12
    if shown = 0 then shown = 12
    return shown.ToStr() + ":" + Str_padLeft(minute.ToStr(), 2) + " " + period
end function

' When the event airs on the TV's clock (Silo Android CalendarTimeFormatter.localDisplayAirTime):
' air_at moved to local time (offsetSeconds east of UTC for that instant; pass invalid to use the
' TV's own rules for that date), else the network's wall-clock air_time as it is, except "00:00"
' (date-only entries report midnight), else "".
function CalFmt_airTime(ev as dynamic, clock24 as boolean, offsetSeconds = invalid as dynamic) as string
    if Type(ev) <> "roAssociativeArray" then return ""
    instant = CalFmt_instantSeconds(ev.air_at)
    if instant >= 0 then
        if offsetSeconds = invalid then
            dt = CreateObject("roDateTime")
            dt.FromSeconds(instant)
            dt.ToLocalTime()
            offsetSeconds = dt.AsSeconds() - instant
        end if
        localSecs = instant + Int(Num_or(offsetSeconds, 0))
        minuteOfDay = (((localSecs mod 86400) + 86400) mod 86400) \ 60
        return CalFmt_clockText(minuteOfDay \ 60, minuteOfDay mod 60, clock24)
    end if
    text = Str_orEmpty(ev.air_time)
    if Len(text) >= 5 and Mid(text, 3, 1) = ":" and CalFmt_digits(Left(text, 2)) and CalFmt_digits(Mid(text, 4, 2)) then
        if Left(text, 5) = "00:00" then return ""
        hour = Int(Val(Left(text, 2)))
        minute = Int(Val(Mid(text, 4, 2)))
        if hour < 24 and minute < 60 then return CalFmt_clockText(hour, minute, clock24)
    end if
    return ""
end function
