' SPDX-License-Identifier: AGPL-3.0-or-later
' Signed artwork expires (docs/api-spec.md: "An expired signature returns 404, so refetch the data.
' URLs change at least daily, or every 15 minutes for non-revisioned ones"). A page that keeps its
' first answer for hours fills with default artwork as the viewer scrolls to cards whose images were
' never loaded. So pages re-read their data quietly:
'   - when shown again (back from a detail page or the player) with an answer older than
'     Fresh_maxAgeSeconds(), and
'   - when a card's image fails to load and the answer is old enough for its URLs to have expired
'     (at most once per Fresh_artRetrySeconds(), so a genuinely broken image cannot loop).
' MediaCardItem reports a failed server image by bumping the `artFailed` counter on the nearest
' ancestor content node that has one (Fresh_watchArt adds it to a page's content root). Signed URLs are never cached (HomeCache strips them).
' Adapted in idea from Silo-Server/silo-roku, AGPL-3.0 (components/views/BrowseRows.bs, failed
' poster re-read; docs/implementation-plan.md section 4.6 "Artwork").

' Epoch seconds as an integer. Not through Num_or: it returns a single-precision float, which
' rounds an epoch (1.8e9) to the nearest 128 s and broke these comparisons.
function Fresh_secs(v as dynamic) as integer
    t = Type(v)
    if t = "roInt" or t = "roInteger" or t = "Integer" then return v
    if t = "LongInteger" or t = "roLongInteger" or t = "Double" or t = "roDouble" then return Int(v)
    return 0
end function

function Fresh_maxAgeSeconds() as integer
    return 900
end function

' An answer younger than this is trusted even when an image fails (the image is broken, not expired).
function Fresh_artMinAgeSeconds() as integer
    return 300
end function

function Fresh_artRetrySeconds() as integer
    return 600
end function

' Whether an answer that arrived at loadedAt (0 = never) is old enough to read again on show.
function Fresh_isStale(loadedAt as dynamic, now as dynamic) as boolean
    at = Fresh_secs(loadedAt)
    if at <= 0 then return false
    return Fresh_secs(now) - at >= Fresh_maxAgeSeconds()
end function

' Whether a failed card image should make the page read its answer again: the answer is old enough
' for its signatures to have run out and the last such re-read (lastArtReload, 0 = none) is not recent.
function Fresh_artReloadDue(loadedAt as dynamic, lastArtReload as dynamic, now as dynamic) as boolean
    at = Fresh_secs(loadedAt)
    if at <= 0 then return false
    t = Fresh_secs(now)
    if t - at < Fresh_artMinAgeSeconds() then return false
    last = Fresh_secs(lastArtReload)
    if last > 0 and t - last < Fresh_artRetrySeconds() then return false
    return true
end function

' Whether a failed URI is server artwork worth reporting (not a package image, not empty).
function Fresh_isRemoteUri(uri as dynamic) as boolean
    u = LCase(Str_orEmpty(uri))
    return Left(u, 7) = "http://" or Left(u, 8) = "https://"
end function

' Gives a content root the counter item components bump, observed by `callback` in the caller.
sub Fresh_watchArt(root as dynamic, callback as string)
    if root = invalid then return
    if not root.hasField("artFailed") then root.addFields({ artFailed: 0 })
    root.observeField("artFailed", callback)
end sub

' The log line for a quiet re-read ("[siku-art] reload page=home reason=stale age=1200s").
sub Fresh_log(page as string, reason as string, loadedAt as dynamic)
    age = Time_nowSeconds() - Fresh_secs(loadedAt)
    print "[siku-art] reload page="; page; " reason="; reason; " age="; age.ToStr(); "s"
end sub
