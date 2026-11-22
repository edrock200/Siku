' The collections a movie or series is in, on its detail page (Silo Android #1007, which Siku ports;
' web ItemCollectionsRow). GET /api/v2/catalog/items/{id}/collections (listCatalogItemCollections,
' silo-server #4528) answers { items: [collection cards], preview_items: [titles] }: the cards are
' server collections first, then personal ones, already filtered by the server's viewer rules, and
' preview_items holds other titles of the collection only when exactly one collection holds the
' title. The page shows:
' - one collection with other titles: up to six of them under the collection's name, then an
'   Explore all card that opens the collection;
' - otherwise an "Also in" row with a card for every collection (no cap beyond CollRows_max()).
' The read exists only on servers whose search capabilities advertise `item_collections`, and only
' movies and series ask. Nothing shows while loading, when no collection holds the title, or after a
' failed first read; a failed refresh keeps the row on screen, as the box set row does.
'
' As on Home (CollectionRows.brs), a server collection shows only from a library this Roku shows the
' profile, so an ebook library's never appears, and reading titles (books, comics, manga) stay out of
' a preview; a preview left with none shows its collection's card under "Also in" (Android TV's
' withTvShownCollections and visibleOnTv).
'
' Pure functions, host-tested in tests/test_item_collections.py. Needs Utils.brs, Content.brs and
' CollectionRows.brs.
' SPDX-License-Identifier: AGPL-3.0-or-later

' The most titles a single collection's preview shows (ITEM_COLLECTION_PREVIEW_LIMIT, as the web).
function ItemColl_previewMax() as integer
    return 6
end function

' Whether this page type asks at all: movies and series only.
function ItemColl_asks(itemType as dynamic) as boolean
    t = LCase(Str_orEmpty(itemType).Trim())
    return t = "movie" or t = "series"
end function

' Whether a GET /api/v2/catalog/search/capabilities body advertises the read (item_collections:
' true). Anything else, a missing field included, means an older server that is never asked.
function ItemColl_supported(caps as dynamic) as boolean
    if caps = invalid or Type(caps) <> "roAssociativeArray" then return false
    v = caps.item_collections
    if not CollRows_isBool(v) then return false
    return v
end function

' A listCatalogItemCollections body read as { cards, preview }, or invalid when it is not one (both
' members are required on the wire; decodeItemCollectionsV2 fails the read then, so the page keeps
' what it shows). Each card is read on its own (CollRows_cards: a card this client cannot read or
' open is left out); preview titles need a content id.
function ItemColl_read(body as dynamic) as dynamic
    if body = invalid or Type(body) <> "roAssociativeArray" then return invalid
    if Type(body.items) <> "roArray" or Type(body.preview_items) <> "roArray" then return invalid
    cards = CollRows_cards({ collections: body.items })
    preview = []
    for each it in body.preview_items
        if it <> invalid and Type(it) = "roAssociativeArray" then
            if Str_orEmpty(it.content_id).Trim() <> "" then preview.Push(it)
        end if
    end for
    return { cards: cards, preview: preview }
end function

' The row a read gives (ItemCollectionsRow): { kind: "preview", collection, items } when one
' collection holds the title and the server sent other titles (at most ItemColl_previewMax()),
' { kind: "also_in", cards } otherwise, invalid when no collection holds it.
function ItemColl_row(read as dynamic) as dynamic
    if read = invalid or Type(read) <> "roAssociativeArray" then return invalid
    cards = Arr_or(read.cards)
    if cards.Count() = 0 then return invalid
    preview = Arr_or(read.preview)
    if cards.Count() = 1 and preview.Count() > 0 then
        items = []
        for i = 0 to preview.Count() - 1
            if items.Count() < ItemColl_previewMax() then items.Push(preview[i])
        end for
        return { kind: "preview", collection: cards[0], items: items }
    end if
    return { kind: "also_in", cards: cards }
end function

' Whether the row holds a server collection, whose library must be known to be shown.
function ItemColl_needsLibraries(row as dynamic) as boolean
    if row = invalid or Type(row) <> "roAssociativeArray" then return false
    cards = []
    if row.kind = "preview" then cards = [row.collection] else cards = Arr_or(row.cards)
    for each c in cards
        if Str_orEmpty(c.collection_kind) = "library" then return true
    end for
    return false
end function

' The row as this Roku shows it, given the libraries it shows the profile (`shown`: { known, libs }
' as CollRows_shownOnHome reads it): server collections only from those libraries, personal ones
' always; reading titles left out of a preview, and a preview left with none shows its collection's
' card under "Also in". invalid when nothing is left.
function ItemColl_forTv(row as dynamic, shown as dynamic) as dynamic
    if row = invalid or Type(row) <> "roAssociativeArray" then return invalid
    if row.kind = "preview" then
        if CollRows_shownOnHome([row.collection], shown).Count() = 0 then return invalid
        items = []
        for each it in Arr_or(row.items)
            if CollRows_libraryTypeShown(it["type"]) then items.Push(it)
        end for
        if items.Count() = 0 then return { kind: "also_in", cards: [row.collection] }
        return { kind: "preview", collection: row.collection, items: items }
    end if
    cards = CollRows_shownOnHome(Arr_or(row.cards), shown)
    if cards.Count() = 0 then return invalid
    return { kind: "also_in", cards: cards }
end function

' The section's heading: the collection's name over a preview, else "Also in".
function ItemColl_heading(row as dynamic) as string
    if row = invalid or Type(row) <> "roAssociativeArray" then return ""
    if row.kind = "preview" then return Str_orEmpty(row.collection.title)
    return Tx("Also in")
end function

' The [siku-detail] line for the row as drawn: its kind, the cards or titles it shows and how many
' server collections the read held that this Roku left out (held).
function ItemColl_rowLog(row as dynamic, held as integer) as string
    if row = invalid or Type(row) <> "roAssociativeArray" then return "[siku-detail] collections row=none held=" + held.ToStr()
    if row.kind = "preview" then return "[siku-detail] collections row=preview titles=" + Arr_or(row.items).Count().ToStr() + " explore_all=yes held=" + held.ToStr()
    return "[siku-detail] collections row=also_in cards=" + Arr_or(row.cards).Count().ToStr() + " held=" + held.ToStr()
end function

' Server collection cards the read had that the drawn row lacks.
function ItemColl_heldCount(raw as dynamic, drawn as dynamic) as integer
    a = ItemColl_cardCount(raw)
    b = ItemColl_cardCount(drawn)
    if a > b then return a - b
    return 0
end function

function ItemColl_cardCount(row as dynamic) as integer
    if row = invalid or Type(row) <> "roAssociativeArray" then return 0
    if row.kind = "preview" then return 1
    return Arr_or(row.cards).Count()
end function
