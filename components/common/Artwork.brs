' Artwork at the size each screen draws it (Android TV #612, ArtworkWidths / TvArtworkLayout).
' Servers that list `slot_width_params` in GET /api/v2/images/capabilities take a width per
' artwork slot (poster_width, backdrop_width, logo_width, still_width, photo_width) on every v2
' read that returns artwork, and answer each slot with the narrowest cached size at least that
' wide. Older servers reject those parameters, so they are sent only to the server that
' advertised them; `image_size` stays on every request as the fallback.
'
' The probe is cached on m.global.imageCaps as { serverUrl, slots: { poster: "poster_width", ... } }.
' Needs Utils.brs and Api.brs (Artwork_fetchCaps).
' SPDX-License-Identifier: AGPL-3.0-or-later

' Pixel widths Siku draws each surface at on its 1920x1080 canvas (the UI is 1080p even on a 4K
' TV, so canvas pixels are the pixels on screen). Cards grow with the Poster Size preference.
function Artwork_layout(surface as string, cardScale = 1.0 as float) as object
    if surface = "home" or surface = "discover" then
        ' Shelf poster 176 px, Continue Watching cards 360 px, the 1229x756 hero (a 16:9 backdrop
        ' must be 1344 px wide to fill it when cropped) and the marquee title logo (880 px).
        return { poster: Int(176 * cardScale + 0.5), backdrop: 1344, still: Int(360 * cardScale + 0.5), logo: 880 }
    else if surface = "detail" then
        ' The same hero backdrop as Home, the 650 px title logo and 200 px cast photos.
        return { backdrop: 1344, logo: 650, photo: 200 }
    else if surface = "episodes" then
        return { still: 360 }
    else if surface = "similar" then
        return { poster: Int(176 * cardScale + 0.5) }
    else if surface = "browse" then
        ' The widest grid cell (Large posters, 5 columns) is about 300 px.
        return { poster: Int(276 * cardScale + 0.5), still: Int(360 * cardScale + 0.5) }
    else if surface = "people" then
        return { poster: Int(236 * cardScale + 0.5), photo: 400 }
    end if
    return {}
end function

' True once the capability probe answered (or failed) for the active server.
function Artwork_capsSettled() as boolean
    if not m.global.hasField("imageCaps") then return false
    c = m.global.imageCaps
    if c = invalid or Type(c) <> "roAssociativeArray" then return false
    return Str_orEmpty(c.serverUrl) = Str_orEmpty(m.global.session.serverUrl) and Str_orEmpty(c.serverUrl) <> ""
end function

' Probes the capability once per server; `callback` (a function in the calling component) gets
' the response event and must call Artwork_storeCaps(event). Waits at most 3 seconds, after which
' reads go out without widths, as they would to an older server.
sub Artwork_fetchCaps(callback as string)
    Api_call({ method: "GET", path: "/api/v2/images/capabilities", timeout: 3, context: { serverUrl: Str_orEmpty(m.global.session.serverUrl) } }, callback)
end sub

sub Artwork_storeCaps(event as object)
    resp = Api_result(event)
    serverUrl = ""
    if resp.context <> invalid then serverUrl = Str_orEmpty(resp.context.serverUrl)
    ' A probe of another server (a switch while it ran) is dropped.
    if serverUrl = "" or serverUrl <> Str_orEmpty(m.global.session.serverUrl) then return
    slots = {}
    if resp.ok and Type(resp.data) = "roAssociativeArray" and LCase(Str_orEmpty(resp.data.state)) = "available" then
        params = resp.data.slot_width_params
        if params <> invalid and Type(params) = "roAssociativeArray" then
            for each slot in params
                name = Str_orEmpty(params[slot])
                if name = "" then name = slot + "_width"
                slots[LCase(slot)] = name
            end for
        end if
    end if
    if not m.global.hasField("imageCaps") then m.global.addFields({ imageCaps: {} })
    m.global.imageCaps = { serverUrl: serverUrl, slots: slots }
end sub

' Adds the per-slot widths of `surface` to a query AA (in place) when the active server
' advertised them; returns the same AA. Any other server gets the query unchanged.
function Artwork_query(query as object, surface as string, cardScale = 1.0 as float) as object
    if not Artwork_capsSettled() then return query
    slots = m.global.imageCaps.slots
    if slots = invalid or Type(slots) <> "roAssociativeArray" or slots.Count() = 0 then return query
    widths = Artwork_layout(surface, cardScale)
    for each slot in widths
        name = slots[slot]
        if name <> invalid then
            px = Int(widths[slot])
            if px < 1 then px = 1
            if px > 7680 then px = 7680
            query[name] = px
        end if
    end for
    return query
end function
