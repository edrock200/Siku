' Pure title, credit and listening-state rules for the audiobook detail page and player (Silo Android
' #975, a port of Apple's AudiobookDetailFormatting / Silo's shared AudiobookDetailFormatting.kt).
' Every rule is conservative: it rewrites only patterns it recognises and otherwise returns the
' input, so an unfamiliar title never comes out worse. The Kotlin regexes are hand-scanned here:
' Roku's PCRE and brs-engine's JavaScript regexes disagree on non-ASCII character classes (dashes).
'
' No SceneGraph and no other file needed: host-tested in tests/test_audiobook_format.py.
' SPDX-License-Identifier: AGPL-3.0-or-later

' The title without the series name and volume the server baked into it
' ("Stormlight Archive 5 - Wind and Truth (5 of 5)" in "The Stormlight Archive" -> "Wind and Truth").
' The series name is lifted out only before a volume number or a separator, so "Dune Messiah" stays
' whole in the "Dune" series.
function AudiobookFormat_cleanTitle(rawTitle as dynamic, seriesName as dynamic) as string
    original = AudiobookFormat_trim(AudiobookFormat_str(rawTitle), "")
    title = original
    series = AudiobookFormat_str(seriesName)
    if AudiobookFormat_trim(series, "") <> "" then title = AudiobookFormat_stripSeriesPrefix(title, series)
    title = AudiobookFormat_stripVolume(title, "of")
    title = AudiobookFormat_stripVolume(title, "book")
    title = AudiobookFormat_stripVolume(title, "vol")
    title = AudiobookFormat_trim(title, " -" + Chr(8211) + Chr(8212) + ":" + Chr(183) + ",")
    if title = "" then return original
    return title
end function

' A trailing "(N of M)": { index, total } (integers), both invalid when the title has none.
function AudiobookFormat_volume(rawTitle as dynamic) as object
    t = AudiobookFormat_trimEnd(AudiobookFormat_str(rawTitle))
    none = { index: invalid, total: invalid }
    if Right(t, 1) <> ")" then return none
    paren = AudiobookFormat_lastIndex(t, "(")
    if paren = 0 then return none
    nums = AudiobookFormat_volumeInner(Mid(t, paren + 1, Len(t) - paren - 1), "of")
    if nums = invalid then return none
    return { index: nums[0], total: nums[1] }
end function

' This book's place in its series: the series entry for contentId when it has a whole-number index
' above zero, else the title's "(N of M)" index; invalid when neither says.
function AudiobookFormat_seriesIndex(contentId as dynamic, rawTitle as dynamic, entries as dynamic) as dynamic
    cid = AudiobookFormat_str(contentId)
    if Type(entries) = "roArray" then
        for each e in entries
            if Type(e) = "roAssociativeArray" and AudiobookFormat_str(e.content_id) = cid then
                v = AudiobookFormat_number(e.series_index)
                if v <> invalid and v > 0 and v = Int(v) then return Int(v)
                exit for
            end if
        end for
    end if
    return AudiobookFormat_volume(rawTitle).index
end function

' The names to show on one line: { shown: [...], remaining: n }, invalid when there are none.
' Comma-joined names are split (servers sometimes send a whole cast as one string); a list one longer
' than `visible` is kept whole, so a line never ends in "& 1 more". Items are strings or { name }.
function AudiobookFormat_peopleSummary(names as dynamic, visible = 2 as integer) as dynamic
    cleaned = []
    if Type(names) = "roArray" then
        for each n in names
            s = n
            if Type(n) = "roAssociativeArray" then s = n.name
            for each piece in AudiobookFormat_str(s).Split(",")
                p = AudiobookFormat_trim(piece, "")
                if p <> "" then cleaned.Push(p)
            end for
        end for
    end if
    if cleaned.Count() = 0 then return invalid
    if cleaned.Count() <= visible + 1 then return { shown: cleaned, remaining: 0 }
    shown = []
    for i = 0 to visible - 1
        shown.Push(cleaned[i])
    end for
    return { shown: shown, remaining: cleaned.Count() - visible }
end function

' "A", "A & B", "A, B & C".
function AudiobookFormat_naturalJoin(names as dynamic) as string
    if Type(names) <> "roArray" or names.Count() = 0 then return ""
    n = names.Count()
    if n = 1 then return AudiobookFormat_str(names[0])
    out = ""
    for i = 0 to n - 2
        if i > 0 then out = out + ", "
        out = out + AudiobookFormat_str(names[i])
    end for
    return out + " & " + AudiobookFormat_str(names[n - 1])
end function

' The listening state behind the hero (TvAudiobookDetailHero): finished is the saved played flag or
' a position within 5 s of a known end; resume is the position past the 30 s grace while not
' finished (a book of unknown length still resumes), else -1. The Finished toggle shows `played`
' alone; a position near the end only turns Play into Play Again.
function AudiobookFormat_state(position as dynamic, total as dynamic, played as dynamic) as object
    at = AudiobookFormat_number(position)
    if at = invalid or at < 0 then at = 0.0
    tot = AudiobookFormat_number(total)
    if tot = invalid or tot < 0 then tot = 0.0
    isPlayed = Type(played) = "roBoolean" or Type(played) = "Boolean"
    if isPlayed then isPlayed = played
    finished = isPlayed or (tot > 0 and at > 0 and at >= tot - 5)
    resume = -1.0
    if at > 30 and not finished then resume = at
    return { finished: finished, resume: resume, played: isPlayed }
end function

' The audiobook hero's action row scroll (tvOS's horizontalScroll): `xs` and `widths` are the
' controls' offsets and widths, `avail` the hero's width. Returns { scroll, shown: [bool per control] }:
' 0 while the row fits; otherwise the least change from `current` that keeps the focused control whole,
' never past either end. A control the scroll pushes past an edge is not shown (Roku has no clip
' every device honours).
function AudiobookFormat_rowScroll(xs as object, widths as object, focused as integer, avail as integer, current as integer) as object
    n = xs.Count()
    shown = []
    if n = 0 or widths.Count() <> n then return { scroll: 0, shown: shown }
    rowW = xs[n - 1] + widths[n - 1]
    sc = current
    if rowW <= avail then
        sc = 0
    else
        i = focused
        if i < 0 or i >= n then i = 0
        lo = xs[i]
        hi = lo + widths[i]
        if hi - sc > avail then sc = hi - avail
        if lo - sc < 0 then sc = lo
        if sc > rowW - avail then sc = rowW - avail
        if sc < 0 then sc = 0
    end if
    for j = 0 to n - 1
        bx = xs[j] - sc
        shown.Push(bx >= -1 and bx + widths[j] <= avail + 1)
    end for
    return { scroll: sc, shown: shown }
end function

' ---------- helpers ----------

function AudiobookFormat_str(v as dynamic) as string
    if v = invalid then return ""
    if Type(v) = "roString" or Type(v) = "String" then return v
    return ""
end function

' A number from a number or a numeric string; invalid otherwise.
function AudiobookFormat_number(v as dynamic) as dynamic
    t = Type(v)
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" or t = "roLongInteger" or t = "LongInteger" then return v
    if t = "roString" or t = "String" then
        s = AudiobookFormat_trim(v, "")
        if s = "" then return invalid
        ok = false
        for i = 1 to Len(s)
            c = Mid(s, i, 1)
            if AudiobookFormat_isDigit(c) then
                ok = true
            else if c <> "." and not (i = 1 and c = "-") then
                return invalid
            end if
        end for
        if ok then return Val(s)
    end if
    return invalid
end function

' Kotlin's `\s`: ASCII whitespace.
function AudiobookFormat_isSpace(c as string) as boolean
    return c = " " or c = Chr(9) or c = Chr(10) or c = Chr(11) or c = Chr(12) or c = Chr(13)
end function

function AudiobookFormat_isDigit(c as string) as boolean
    return Len(c) = 1 and c >= "0" and c <= "9"
end function

function AudiobookFormat_isSeparator(c as string) as boolean
    return c = "-" or c = Chr(8211) or c = Chr(8212) or c = ":"
end function

' Trims whitespace and any character of `edges` from both ends.
function AudiobookFormat_trim(s as string, edges as string) as string
    a = 1
    b = Len(s)
    while a <= b
        c = Mid(s, a, 1)
        if not AudiobookFormat_isSpace(c) and Instr(1, edges, c) = 0 then exit while
        a = a + 1
    end while
    while b >= a
        c = Mid(s, b, 1)
        if not AudiobookFormat_isSpace(c) and Instr(1, edges, c) = 0 then exit while
        b = b - 1
    end while
    if b < a then return ""
    return Mid(s, a, b - a + 1)
end function

function AudiobookFormat_trimEnd(s as string) as string
    b = Len(s)
    while b >= 1 and AudiobookFormat_isSpace(Mid(s, b, 1))
        b = b - 1
    end while
    return Left(s, b)
end function

function AudiobookFormat_skipSpaces(s as string, i as integer) as integer
    while i <= Len(s) and AudiobookFormat_isSpace(Mid(s, i, 1))
        i = i + 1
    end while
    return i
end function

' 1-based position of the last `ch` in s, 0 when absent.
function AudiobookFormat_lastIndex(s as string, ch as string) as integer
    found = 0
    i = Instr(1, s, ch)
    while i > 0
        found = i
        i = Instr(i + 1, s, ch)
    end while
    return found
end function

function AudiobookFormat_dropArticle(s as string) as string
    lower = LCase(s)
    for each article in ["the ", "a ", "an "]
        if Left(lower, Len(article)) = article then return Mid(s, Len(article) + 1)
    end for
    return s
end function

' Drops a leading "<Series>[ N][ -:–] " when the title opens with the series name (articles ignored)
' and a volume number or a separator follows it: `^\s*(?:#?\d+(?:\.\d+)?\s*[-–—:]?|[-–—:])\s*(.*)$`.
function AudiobookFormat_stripSeriesPrefix(title as string, seriesName as string) as string
    core = AudiobookFormat_trim(AudiobookFormat_dropArticle(seriesName), "")
    if core = "" then return title
    hay = AudiobookFormat_dropArticle(title)
    n = Len(core)
    if Len(hay) < n or LCase(Left(hay, n)) <> LCase(core) then return title
    rest = Mid(hay, n + 1)
    i = AudiobookFormat_skipSpaces(rest, 1)
    j = i
    if Mid(rest, j, 1) = "#" then j = j + 1
    d = j
    while AudiobookFormat_isDigit(Mid(rest, j, 1))
        j = j + 1
    end while
    if j > d then
        if Mid(rest, j, 1) = "." and AudiobookFormat_isDigit(Mid(rest, j + 1, 1)) then
            j = j + 1
            while AudiobookFormat_isDigit(Mid(rest, j, 1))
                j = j + 1
            end while
        end if
        j = AudiobookFormat_skipSpaces(rest, j)
        if AudiobookFormat_isSeparator(Mid(rest, j, 1)) then j = j + 1
    else if AudiobookFormat_isSeparator(Mid(rest, i, 1)) then
        j = i + 1
    else
        return title
    end if
    j = AudiobookFormat_skipSpaces(rest, j)
    candidate = AudiobookFormat_trim(Mid(rest, j), "")
    ' Consuming everything means the "prefix" was the title itself.
    if candidate = "" then return title
    return candidate
end function

' Drops one trailing "(N of M)" (kind "of"), "(Book N)" ("book") or "(Vol. N)" / "(Volume N)"
' ("vol"), with the whitespace before it.
function AudiobookFormat_stripVolume(title as string, kind as string) as string
    if Right(title, 1) <> ")" then return title
    paren = AudiobookFormat_lastIndex(title, "(")
    if paren = 0 then return title
    if AudiobookFormat_volumeInner(Mid(title, paren + 1, Len(title) - paren - 1), kind) = invalid then return title
    return AudiobookFormat_trimEnd(Left(title, paren - 1))
end function

' The numbers inside a volume locator's parentheses, or invalid when it is not one of `kind`.
function AudiobookFormat_volumeInner(inner as string, kind as string) as dynamic
    s = LCase(AudiobookFormat_trim(inner, ""))
    i = 1
    if kind = "of" then
        a = AudiobookFormat_digitsAt(s, i)
        if a = invalid then return invalid
        i = a["next"]
        k = AudiobookFormat_skipSpaces(s, i)
        if k = i or Mid(s, k, 2) <> "of" then return invalid
        i = AudiobookFormat_skipSpaces(s, k + 2)
        if i = k + 2 then return invalid
        b = AudiobookFormat_digitsAt(s, i)
        if b = invalid or b["next"] <= Len(s) then return invalid
        return [a.value, b.value]
    else if kind = "book" then
        if Left(s, 4) <> "book" then return invalid
        i = AudiobookFormat_skipSpaces(s, 5)
        if i = 5 then return invalid
    else
        if Left(s, 3) <> "vol" then return invalid
        i = 4
        if Mid(s, i, 3) = "ume" then i = i + 3
        if Mid(s, i, 1) = "." then i = i + 1
        i = AudiobookFormat_skipSpaces(s, i)
    end if
    n = AudiobookFormat_digitsAt(s, i)
    if n = invalid or n["next"] <= Len(s) then return invalid
    return [n.value]
end function

' { value, next } for the digits starting at i (next: the position after them), invalid when none.
function AudiobookFormat_digitsAt(s as string, i as integer) as dynamic
    j = i
    while AudiobookFormat_isDigit(Mid(s, j, 1))
        j = j + 1
    end while
    if j = i then return invalid
    return { value: Int(Val(Mid(s, i, j - i))), "next": j }
end function
