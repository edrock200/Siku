' SPDX-License-Identifier: AGPL-3.0-or-later
' On-device audiobook resume record (Android TV keeps one too: AudiobookPlayerViewModel
' loadResumePositionSnapshot). The server applies its video thresholds to POST /sync/progress:
' a position under 5 % of the book is dropped without touching the stored row, and one over 90 %
' is stored as finished at position 0. On a long book the first and the last stretch therefore
' never reach the server; this record covers them.
'
' One registry key holds the newest AudioResume_max() books across servers and profiles:
'   { items: [{ k: "<server>|<profile>|<contentId>", pos, total, base, at }] }   newest first
'   pos    whole-book seconds where listening stopped on this device
'   base   what we expect the server to hold for the book (the last position it accepted)
' The record applies only while the server still holds `base`. Any other server position means
' another device (or the web) moved the book since, and the server wins.

function AudioResume_max() as integer
    return 20
end function

function AudioResume_key(identity as string, contentId as string) as string
    return identity + "|" + contentId
end function

function AudioResume_all() as object
    v = Registry_read("audiobookResume", invalid)
    if Type(v) <> "roAssociativeArray" then return []
    return Arr_or(v.items)
end function

function AudioResume_get(identity as string, contentId as string) as dynamic
    k = AudioResume_key(identity, contentId)
    for each e in AudioResume_all()
        if Type(e) = "roAssociativeArray" and Str_orEmpty(e.k) = k then return e
    end for
    return invalid
end function

' rec: {pos, total, base}
sub AudioResume_put(identity as string, contentId as string, rec as object)
    k = AudioResume_key(identity, contentId)
    out = [{ k: k, pos: Num_or(rec.pos), total: Num_or(rec.total), base: Num_or(rec.base), at: Time_nowSeconds() }]
    for each e in AudioResume_all()
        if Type(e) = "roAssociativeArray" and Str_orEmpty(e.k) <> k and out.Count() < AudioResume_max() then out.Push(e)
    end for
    Registry_write("audiobookResume", { items: out })
end sub

sub AudioResume_clear(identity as string, contentId as string)
    k = AudioResume_key(identity, contentId)
    existing = AudioResume_all()
    out = []
    for each e in existing
        if Type(e) = "roAssociativeArray" and Str_orEmpty(e.k) <> k then out.Push(e)
    end for
    if out.Count() <> existing.Count() then Registry_write("audiobookResume", { items: out })
end sub

' The device's resume point for a book while the server still holds what this device last left
' it at; -1 when there is no record or the server has moved on.
function AudioResume_position(identity as string, contentId as string, serverPos as float) as float
    e = AudioResume_get(identity, contentId)
    if e = invalid then return -1.0
    if Abs(serverPos - Num_or(e.base)) > 2 then return -1.0
    return Num_or(e.pos)
end function

' What the server stores after accepting a sync of `p` seconds of `total` (default thresholds:
' under 5 % is ignored, over 90 % is finished at 0). `prev` is the value it held before.
function AudioResume_serverAfter(p as float, total as float, prev as float) as float
    if total <= 0 then return p
    if p / total < 0.05 then return prev
    if p / total > 0.9 then return 0.0
    return p
end function
