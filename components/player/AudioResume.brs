' SPDX-License-Identifier: AGPL-3.0-or-later
' On-device audiobook resume record. The server applies its playback thresholds to
' POST /api/v2/sync/progress (userstore.ResolveProgressState): a position under
' playback.min_resume_threshold (5 % by default) of the book is dropped without touching the stored
' row, and one over playback.watched_threshold (90 %) is stored as finished at position 0. On a
' 10-hour book the first half hour and the last hour therefore never reach the server, and Start
' Over followed by a short listen leaves the old resume point. Android keeps an on-device position
' too (AudiobookPlayerViewModel.loadResumePositionSnapshot); this record covers those stretches.
'
' One registry key holds the newest AudioResume_max() books across servers and profiles:
'   { items: [{ k: "<server>|<profile>|<contentId>", position, total, base, at }] }   newest first
'   position  whole-book seconds where listening stopped on this device
'   base      what the server is expected to hold for the book (the last position it accepted)
' The record applies only while the server still holds `base`. Any other server position means
' another device (or the web) moved the book since, and the server wins. Pure apart from the
' registry: tests/test_audio_resume.py runs it in brs-cli.

function AudioResume_max() as integer
    return 12
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

' rec: { position, total, base } in whole-book seconds. The newest record goes first; the oldest
' beyond AudioResume_max() is dropped.
sub AudioResume_put(identity as string, contentId as string, rec as object)
    if identity = "" or contentId = "" then return
    k = AudioResume_key(identity, contentId)
    out = [{ k: k, position: Num_or(rec.position), total: Num_or(rec.total), base: Num_or(rec.base), at: Time_nowSeconds() }]
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

' This device's resume point for a book while the server still holds what this device last left
' it at; -1 when there is no record or the server has moved on.
function AudioResume_position(identity as string, contentId as string, serverPos as float) as float
    e = AudioResume_get(identity, contentId)
    if e = invalid then return -1.0
    if Abs(serverPos - Num_or(e.base)) > 2 then return -1.0
    p = Num_or(e.position)
    if p <= 0 then return -1.0
    return p
end function

' What the server holds after accepting a sync of `p` seconds of `total` with the default
' thresholds (under 5 % is ignored, over 90 % is finished at 0). `prev` is what it held before.
' A server with other thresholds makes `base` disagree, and the record then simply stops applying.
function AudioResume_serverAfter(p as float, total as float, prev as float) as float
    if total <= 0 then return p
    if p > 0 and p / total < 0.05 then return prev
    if p / total > 0.9 then return 0.0
    return p
end function
