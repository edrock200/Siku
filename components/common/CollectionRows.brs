' Home and library rows of collections (silo-server #4410 / #4415; adapted from Silo-Server/silo-roku
' 8183af8 and d240f47, AGPL-3.0). A section of section_type `collection_posters` carries its cards
' in `collections`, not `items` (`items` is [] and total_count counts the cards). Each card is the
' library Collections grid's card (Content_collectionCard: title, count, poster or collage, the
' placeholder when it has none) and opens that collection's page (LibraryScreen section
' "collection"). The row shows every card the server sends (at most 30; the client stops at
' CollRows_max()), with no "Explore all" card: it has no row page (a section page of it answers no
' items). A card never offers a card menu, and takes the marquee hero only when the server sent a
' backdrop for it (#4415: backdrop_url, never on a personal collection); a card without one leaves
' the hero on the card it showed, as "Explore all" does.
'
' Pure functions, host-tested in tests/test_collection_rows.py. Needs Utils.brs and Content.brs.
' SPDX-License-Identifier: AGPL-3.0-or-later

' The most cards a row of collections shows (the rows' memory bound; the server sends at most 30).
function CollRows_max() as integer
    return 40
end function

' Whether a section (a Section body of the Home or library section reads) is a row of collections,
' whatever the case of its section_type.
function CollRows_isRow(section as dynamic) as boolean
    if section = invalid or Type(section) <> "roAssociativeArray" then return false
    return LCase(Str_orEmpty(section.section_type).Trim()) = "collection_posters"
end function

' A row's cards in the server's order, at most CollRows_max(): Content_collectionCard fields plus
' the kind (`library` for a server collection, `user` for a personal one), the library the server
' names for it and, on a server collection with one, its backdrop for the hero. Entries without an
' id are left out.
function CollRows_cards(section as dynamic) as object
    out = []
    if section = invalid or Type(section) <> "roAssociativeArray" then return out
    seen = {}
    for each c in Arr_or(section.collections)
        if out.Count() >= CollRows_max() then exit for
        if c <> invalid and Type(c) = "roAssociativeArray" then
            cid = Str_orEmpty(c.id)
            if cid <> "" and not seen.DoesExist(cid) then
                seen[cid] = true
                kind = "library"
                if LCase(Str_orEmpty(c.source)) = "user" then kind = "user"
                card = Content_collectionCard(c)
                card.collection_kind = kind
                lib = Str_orEmpty(c.library_id)
                if lib <> "" then card.library_id = lib
                backdrop = Str_orEmpty(c.backdrop_url)
                if kind = "library" and backdrop <> "" then
                    card.backdrop_url = backdrop
                    if not Str_isEmpty(c.backdrop_thumbhash) then card.backdrop_thumbhash = Str_orEmpty(c.backdrop_thumbhash)
                end if
                out.Push(card)
            end if
        end if
    end for
    return out
end function

' Whether a card (a card AA, the node's raw) is a collection's.
function CollRows_isCard(card as dynamic) as boolean
    if card = invalid or Type(card) <> "roAssociativeArray" then return false
    return LCase(Str_orEmpty(card["type"])) = "collection"
end function

' Whether the marquee hero shows a card while it is focused: every card but a collection's without
' a backdrop (Explore all is the feed's own node and handled there).
function CollRows_heroShows(card as dynamic) as boolean
    if card = invalid or Type(card) <> "roAssociativeArray" then return false
    if not CollRows_isCard(card) then return true
    return Str_orEmpty(card.backdrop_url) <> ""
end function

' The hero's meta line for a collection's card: its count ("12 items"), "" when it holds none.
function CollRows_metaLine(card as dynamic) as string
    if card = invalid or Type(card) <> "roAssociativeArray" then return ""
    return Content_collectionCount(card.item_count)
end function

' The LibraryScreen params that open a row card's collection page (LibraryPage section
' "collection"). From Home (pageLibraryId ""), the page lists every member the viewer sees, the titles
' the card counts: no library_id and no media type. On a library page, that library and the page's
' Movies / Series view of a mixed library (mediaType, "" for every other page), as the Collections
' grid narrows it. A personal collection reads source user_collection.
function CollRows_openParams(card as object, pageLibraryId as string, libraryName as string, mode as string, mediaType as string) as object
    p = { section: "collection", collectionId: Str_orEmpty(card.collection_id), collectionKind: Str_orEmpty(card.collection_kind), title: Str_orEmpty(card.title), collectionTitle: Str_orEmpty(card.title), fromRow: true, libraryId: "", libraryName: "", mode: "", mediaType: "" }
    ' Bracket keys keep their case (dot assignment lower-cases a key; pitfall 15).
    if p["collectionKind"] = "" then p["collectionKind"] = "library"
    if pageLibraryId <> "" then
        p["libraryId"] = pageLibraryId
        p["libraryName"] = libraryName
        p["mode"] = mode
        p["mediaType"] = mediaType
    end if
    return p
end function

' The catalog source of a collection page: user_collection for a personal collection, else
' library_collection.
function CollRows_catalogSource(kind as dynamic) as string
    if LCase(Str_orEmpty(kind)) = "user" then return "user_collection"
    return "library_collection"
end function

' The [siku-home] line for a row of collections: its id, the cards it shows, how many have a hero
' backdrop and how many are empty (no count).
function CollRows_rowLog(sectionId as string, cards as object) as string
    backdrops = 0
    empty = 0
    for each c in cards
        if Str_orEmpty(c.backdrop_url) <> "" then backdrops = backdrops + 1
        if Int(Content_num(c.item_count)) <= 0 then empty = empty + 1
    end for
    return "[siku-home] collection row=" + sectionId + " cards=" + cards.Count().ToStr() + " backdrops=" + backdrops.ToStr() + " empty=" + empty.ToStr() + " explore_all=no"
end function
