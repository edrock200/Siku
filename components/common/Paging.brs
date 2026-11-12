' Small pure helpers for lists that read their answers in pages or may see answers out of order
' (Search, a person's filmography, a series' episodes). Host-tested in tests/test_paging.py.
' SPDX-License-Identifier: AGPL-3.0-or-later

' Whether an answer is still wanted: its request context carries the read's number (seq) and what
' it was read for (ctx[field], a season number or a filter); it counts only when it is the newest
' read (seq) and that value is still the one selected (current).
function Paging_isCurrent(ctx as dynamic, field as string, current as dynamic, seq as dynamic) as boolean
    if Type(ctx) <> "roAssociativeArray" then return false
    if not Paging_isNum(ctx.seq) or not Paging_isNum(seq) then return false
    if Int(ctx.seq) <> Int(seq) then return false
    v = ctx[field]
    if Paging_isNum(v) and Paging_isNum(current) then return Int(v) = Int(current)
    if Paging_isStr(v) and Paging_isStr(current) then return v = current
    return false
end function

' The cursor of the page after this answer's (its page.next_cursor while page.has_more), else "".
function Paging_nextCursor(data as dynamic) as string
    if Type(data) <> "roAssociativeArray" then return ""
    pg = data.page
    if Type(pg) <> "roAssociativeArray" then return ""
    more = pg.has_more
    if Type(more) <> "Boolean" and Type(more) <> "roBoolean" then return ""
    if not more then return ""
    c = pg.next_cursor
    if not Paging_isStr(c) then return ""
    return c
end function

' Whether focus at index (of count cards, columns per row) is within `rows` rows of the end, so the
' next page should be read now.
function Paging_nearEnd(index as integer, count as integer, columns as integer, rows as integer) as boolean
    if count <= 0 or index < 0 then return false
    if columns < 1 then columns = 1
    return index >= count - columns * rows
end function

' Seconds to wait before reading a page again after `failures` failed tries in a row: 5, 10, 20,
' 40, then 60 (the Library's back-off).
function Paging_retryDelay(failures as integer) as integer
    if failures <= 0 then return 0
    d = 5
    for i = 2 to failures
        d = d * 2
        if d >= 60 then return 60
    end for
    return d
end function

' A count of titles the way Android TV's person page shows it: the server's total when it knows
' one ("72 titles"), else the titles loaded, with a "+" while more pages remain ("60+ titles");
' "" before anything is loaded.
function Paging_titleCount(total as dynamic, loaded as integer, hasMore as boolean) as string
    n = 0
    if Paging_isNum(total) then n = Int(total)
    if n > 0 then return TxP("{0} title", "{0} titles", n)
    if loaded <= 0 then return ""
    if hasMore then return TxP("{0}+ titles", "{0}+ titles", loaded)
    return TxP("{0} title", "{0} titles", loaded)
end function

function Paging_isNum(v as dynamic) as boolean
    t = Type(v)
    return t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble"
end function

function Paging_isStr(v as dynamic) as boolean
    return Type(v) = "String" or Type(v) = "roString"
end function
