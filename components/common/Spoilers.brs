' Spoiler protection for unwatched episodes (settings contract revision 17, Android TV #427).
' The profile settings catalog.hide_unwatched_episode_images and
' catalog.hide_unwatched_episode_overviews choose what to hide; the server never changes catalog
' responses, so every screen applies them with these helpers.
'
' Self-contained apart from Utils.brs (Str_orEmpty, Num_or): it reads the settings snapshot on
' m.global.settings directly, so any component (the player's Up Next panel too) can include it:
'   <script type="text/brightscript" uri="pkg:/components/common/Spoilers.brs" />
' Roku cannot blur a Poster, so a hidden still is not loaded at all: callers show the default
' artwork (MediaCardItem's brand glow) or another, non-episode image instead.
' SPDX-License-Identifier: AGPL-3.0-or-later

' { hideImages, hideOverviews } for the active server + profile. Both off until the server has
' answered with a manifest that knows the keys, so an older server shows episodes as before.
function Spoilers_prefs() as object
    out = { hideImages: false, hideOverviews: false }
    st = m.global.settings
    if st = invalid or Type(st) <> "roAssociativeArray" or st.available <> true or st.items = invalid then return out
    s = m.global.session
    if s <> invalid and Str_orEmpty(st.identity) <> Str_orEmpty(s.serverUrl) + "|" + Str_orEmpty(s.profileId) then return out
    if Int(Num_or(st.manifestRevision, 0)) < 17 then return out
    img = st.items["catalog.hide_unwatched_episode_images"]
    ovw = st.items["catalog.hide_unwatched_episode_overviews"]
    if img <> invalid and Type(img) = "roAssociativeArray" and img.value = true then out.hideImages = true
    if ovw <> invalid and Type(ovw) = "roAssociativeArray" and ovw.value = true then out.hideOverviews = true
    return out
end function

' An episode is unwatched while it is neither played nor in progress. Missing watch state counts as
' unwatched, so an episode is never revealed only because its payload left the state out.
function Spoilers_isUnwatched(item as dynamic) as boolean
    if item = invalid or Type(item) <> "roAssociativeArray" then return true
    if item.watched = true then return false
    seconds = Num_or(item.position_seconds, 0)
    for each k in ["user_data", "user_state"]
        ud = item[k]
        if ud <> invalid and Type(ud) = "roAssociativeArray" then
            if ud.played = true or ud.is_in_progress = true then return false
            p = Num_or(ud.position_seconds, 0)
            if p > seconds then seconds = p
        end if
    end for
    return seconds <= 0
end function

function Spoilers_isEpisode(item as dynamic) as boolean
    if item = invalid or Type(item) <> "roAssociativeArray" then return false
    return LCase(Str_orEmpty(item["type"])) = "episode"
end function

' The server's provenance flag for one artwork slot ("poster", "backdrop", "still"): true when
' that image is the episode's own still, false when it is series/season art, invalid when the
' server does not say (older servers; treated as a still, so protection errs on the safe side).
function Spoilers_slotIsStill(item as dynamic, slot as string) as dynamic
    if slot = "still" then return true
    if item = invalid or Type(item) <> "roAssociativeArray" then return invalid
    v = item[slot + "_is_episode_still"]
    if v = true or v = false then return v
    return invalid
end function

' Whether the image in `slot` must be hidden for `item`.
function Spoilers_hidesImage(item as dynamic, slot = "still" as string) as boolean
    if not Spoilers_isEpisode(item) then return false
    if not Spoilers_prefs().hideImages then return false
    if not Spoilers_isUnwatched(item) then return false
    return Spoilers_slotIsStill(item, slot) <> false
end function

function Spoilers_hidesOverview(item as dynamic) as boolean
    if not Spoilers_isEpisode(item) then return false
    if not Spoilers_prefs().hideOverviews then return false
    return Spoilers_isUnwatched(item)
end function

' The episode's overview, or "" when spoiler protection hides it. For the player's Up Next panel,
' episode rails and heroes: Spoilers_overview(episode).
function Spoilers_overview(item as dynamic) as string
    if item = invalid or Type(item) <> "roAssociativeArray" then return ""
    if Spoilers_hidesOverview(item) then return ""
    return Str_orEmpty(item.overview)
end function

' The URL of `slot` ("still", "backdrop", "poster") on `item`, or "" when protection hides it.
' Raw (unresolved) API URL; pass the result through Url_resolve as usual.
function Spoilers_imageUrl(item as dynamic, slot = "still" as string) as string
    if item = invalid or Type(item) <> "roAssociativeArray" then return ""
    if Spoilers_hidesImage(item, slot) then return ""
    return Str_orEmpty(item[slot + "_url"])
end function

' A 16:9 image for an episode card or the player's Up Next panel: its still, else a backdrop or
' poster that is not the episode's still when protection hides the still, else the series
' backdrop newer servers send (never a still), else "".
function Spoilers_wideImageUrl(item as dynamic) as string
    if item = invalid or Type(item) <> "roAssociativeArray" then return ""
    for each slot in ["still", "backdrop", "poster"]
        u = Spoilers_imageUrl(item, slot)
        if u <> "" then return u
    end for
    return Spoilers_seriesBackdropUrl(item)
end function

' ---------- Episode parent artwork (Silo Android #711, EpisodeParentArtwork.kt) ----------
' Servers with episode_parent_artwork send series_poster_url, series_backdrop_url and
' season_poster_url (+ *_thumbhash) on episode cards, catalog cards and item detail. Series and
' season art is never an episode still, so spoiler protection leaves it visible. Older servers omit
' the fields and every helper below falls back to the card's own artwork, as before. All return a
' raw API URL; resolve it with Url_resolve like any other artwork.

' An episode's series backdrop (series_backdrop_url), or "" for other types and older servers.
function Spoilers_seriesBackdropUrl(item as dynamic) as string
    if not Spoilers_isEpisode(item) then return ""
    return Str_orEmpty(item.series_backdrop_url).Trim()
end function

' An episode's season poster, else its series poster; "" for other types and older servers.
function Spoilers_parentPosterUrl(item as dynamic) as string
    if not Spoilers_isEpisode(item) then return ""
    u = Str_orEmpty(item.season_poster_url).Trim()
    if u = "" then u = Str_orEmpty(item.series_poster_url).Trim()
    return u
end function

' The backdrop for a hero or full-screen background (Home/library marquee, detail hero): an
' episode's series backdrop when the card carries one, else its own backdrop unless protection
' hides it (TvFocusMarqueeModel, resolveTvDetailHeroArtwork).
function Spoilers_heroBackdropUrl(item as dynamic) as string
    u = Spoilers_seriesBackdropUrl(item)
    if u <> "" then return u
    return Spoilers_imageUrl(item, "backdrop")
end function

' Poster-shaped art for a card: an episode's season or series poster when the server sends one,
' else its own poster unless protection hides it.
function Spoilers_posterUrl(item as dynamic) as string
    u = Spoilers_parentPosterUrl(item)
    if u <> "" then return u
    return Spoilers_imageUrl(item, "poster")
end function

' The Up Next background from On Deck cards (TvPlayerNextUpOverlay): the first card's series
' backdrop, else its backdrop unless protection hides it; cards with nothing visible are skipped.
function Spoilers_firstBackdropUrl(items as dynamic) as string
    if items = invalid or Type(items) <> "roArray" then return ""
    for each it in items
        u = Spoilers_heroBackdropUrl(it)
        if u <> "" then return u
    end for
    return ""
end function
