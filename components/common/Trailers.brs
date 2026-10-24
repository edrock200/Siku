' "Trailers & More" rail entries for detail pages, a port of Android's
' shared/.../model/catalog/TrailerRail.kt (trailerRailEntries, extraKindLabel,
' trailerRailDurationLabel, youtubeThumbnailUrl).
' Local extras (item detail `extras[]`) come first in server order, because they play in Siku;
' YouTube videos (`videos[]` with site "youtube") follow in server order and hand off to the
' YouTube channel. Other sites are dropped. Entries are de-duplicated by a namespaced key.
' SPDX-License-Identifier: AGPL-3.0-or-later

' [{ key, isLocal, title, kindLabel, subtitle, thumbUrl, raw }] for an item detail document.
function Trailer_entries(item as dynamic) as object
    out = []
    if item = invalid or Type(item) <> "roAssociativeArray" then return out
    seen = {}
    for each ex in Arr_or(item.extras)
        if Type(ex) = "roAssociativeArray" then
            cid = Str_orEmpty(ex.content_id)
            key = "local:" + cid
            if cid <> "" and not seen.DoesExist(key) then
                seen[key] = true
                kind = Trailer_kindLabel(ex.kind)
                title = Str_orEmpty(ex.title).Trim()
                if title = "" then title = kind
                ' Upstream shows only the runtime under a local extra; the kind is added here so a
                ' titled featurette still says what it is.
                subtitle = Str_joinDots([kind, Trailer_durationLabel(ex.duration_seconds)])
                if title = kind then subtitle = Trailer_durationLabel(ex.duration_seconds)
                out.Push({ key: key, isLocal: true, title: title, kindLabel: kind, subtitle: subtitle, thumbUrl: Url_resolve(ex.still_url), raw: ex })
            end if
        end if
    end for
    for each v in Arr_or(item.videos)
        if Type(v) = "roAssociativeArray" then
            siteKey = Str_orEmpty(v.site_key).Trim()
            if LCase(Str_orEmpty(v.site)) = "youtube" and siteKey <> "" then
                key = "remote:youtube:" + siteKey
                if not seen.DoesExist(key) then
                    seen[key] = true
                    kind = Trailer_kindLabel(v.kind)
                    title = Str_orEmpty(v.name).Trim()
                    if title = "" then title = kind
                    out.Push({ key: key, isLocal: false, title: title, kindLabel: kind, subtitle: "YouTube", thumbUrl: Trailer_youtubeThumb(siteKey), videoId: siteKey, raw: v })
                end if
            end if
        end if
    end for
    return out
end function

' YouTube's still for a video; hqdefault exists for every upload.
function Trailer_youtubeThumb(siteKey as string) as string
    return "https://i.ytimg.com/vi/" + siteKey + "/hqdefault.jpg"
end function

function Trailer_watchUrl(videoId as string) as string
    return "https://www.youtube.com/watch?v=" + videoId
end function

function Trailer_kindLabel(kind as dynamic) as string
    k = LCase(Str_orEmpty(kind).Trim())
    if k = "trailer" then return "Trailer"
    if k = "teaser" then return "Teaser"
    if k = "featurette" then return "Featurette"
    if k = "behind_the_scenes" or k = "behind-the-scenes" then return "Behind the Scenes"
    if k = "deleted_scene" or k = "deleted-scene" then return "Deleted Scene"
    if k = "interview" then return "Interview"
    words = k.Replace("_", " ").Replace("-", " ").Tokenize(" ")
    out = ""
    for each w in words
        if w <> "" then
            if out <> "" then out = out + " "
            out = out + UCase(Left(w, 1)) + Mid(w, 2)
        end if
    end for
    if out = "" then return "Extra"
    return out
end function

' "2:31" / "1:02:03" for a local extra's runtime; "" when unknown.
function Trailer_durationLabel(seconds as dynamic) as string
    total = Int(Num_or(seconds, 0))
    if total <= 0 then return ""
    hours = total \ 3600
    minutes = (total mod 3600) \ 60
    secs = total mod 60
    if hours > 0 then return hours.ToStr() + ":" + Str_padLeft(minutes.ToStr(), 2) + ":" + Str_padLeft(secs.ToStr(), 2)
    return minutes.ToStr() + ":" + Str_padLeft(secs.ToStr(), 2)
end function
