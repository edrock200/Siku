' Home and library rows of collections (silo-server #4410 / #4415; Silo Android TV db87f835f, #979,
' which Siku ports; first adapted from Silo-Server/silo-roku 8183af8 and d240f47, AGPL-3.0). A
' section of section_type `collection_posters` carries its cards in `collections`, not `items`
' (`items` is [] and total_count counts the cards). Each card is the library Collections grid's card
' (Content_collectionCard: title, poster or collage, the placeholder when it has none) with one
' caption line: "by Name" for a personal collection another profile shared, else its count
' (TvCollectionRow). It opens that collection's page (LibraryScreen section "collection"). The row
' shows every card the server sends (at most 30; the client stops at CollRows_max()), with no
' "Explore all" card, never a card menu, and is never a featured hero. A focused card drives the
' marquee hero with its title and its backdrop (#4415: backdrop_url), the poster when it has none
' (tvMarqueeItem); no meta line, badges or synopsis.
'
' Each card is read on its own (decodeSectionV2): one with a wrongly typed field, an unknown source
' or (a server collection) no library is left out, never the row. Home shows a server collection
' only once the libraries this Roku shows the profile are known and hold its library, so an ebook
' library's collection never appears (withTvShownCollections).
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

' ---------- Reading one card (SectionCollectionCard, read leniently like Silo's SiloJson) ----------

function CollRows_isText(v as dynamic) as boolean
    t = Type(v)
    return t = "roString" or t = "String"
end function

function CollRows_isNumber(v as dynamic) as boolean
    t = Type(v)
    return t = "roInt" or t = "roInteger" or t = "Integer" or t = "roLongInteger" or t = "LongInteger" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double"
end function

function CollRows_isBool(v as dynamic) as boolean
    t = Type(v)
    return t = "roBoolean" or t = "Boolean"
end function

' A text field: absent, null, or any JSON scalar (a lenient reader takes 7 as "7"); never an object
' or a list.
function CollRows_textOk(v as dynamic) as boolean
    if v = invalid then return true
    return CollRows_isText(v) or CollRows_isNumber(v) or CollRows_isBool(v)
end function

' A whole-number field: absent, null, a whole number, or digits sent as text ("12").
function CollRows_intOk(v as dynamic) as boolean
    if v = invalid then return true
    if CollRows_isNumber(v) then return v = Int(v)
    if not CollRows_isText(v) then return false
    s = v.Trim()
    if Left(s, 1) = "-" then s = Mid(s, 2)
    if s = "" then return false
    for i = 1 to Len(s)
        ch = Mid(s, i, 1)
        if ch < "0" or ch > "9" then return false
    end for
    return true
end function

' A yes/no field: absent, null, a boolean, or "true" / "false" as text.
function CollRows_boolOk(v as dynamic) as boolean
    if v = invalid then return true
    if CollRows_isBool(v) then return true
    if not CollRows_isText(v) then return false
    s = LCase(v.Trim())
    return s = "true" or s = "false"
end function

' Whether a card entry reads at all: an object whose fields have their types. A card that fails is
' left out on its own (Android TV catches the card's decoding error), never the row.
function CollRows_cardReadable(c as dynamic) as boolean
    if c = invalid or Type(c) <> "roAssociativeArray" then return false
    for each k in ["id", "source", "title", "poster_url", "poster_thumbhash", "backdrop_url", "backdrop_thumbhash", "library_id", "creator_profile_id"]
        if not CollRows_textOk(c[k]) then return false
    end for
    if not CollRows_intOk(c["item_count"]) then return false
    return CollRows_boolOk(c["poster_is_collage"])
end function

' The kind of a readable card: "library" (a server collection with a library to open it in), "user"
' (a personal collection), or "" when this client cannot open it (no id, an unknown source, a server
' collection without a library; SectionCollectionCard.isOpenable).
function CollRows_cardKind(c as dynamic) as string
    if not CollRows_cardReadable(c) then return ""
    if Str_orEmpty(c.id).Trim() = "" then return ""
    src = LCase(Str_orEmpty(c.source).Trim())
    if src = "user" then return "user"
    if src = "library" and Str_orEmpty(c.library_id).Trim() <> "" then return "library"
    return ""
end function

' A row's cards in the server's order, at most CollRows_max(): Content_collectionCard fields plus the
' kind (`library` | `user`), a content_id unique in the row ("collection:<kind>:<id>": a server and
' a personal collection may share an id; rowKey), the server collection's library, the personal
' collection's maker (creator_profile_id) and the backdrop (+ thumbhash) when the server sent one.
' Cards that do not read or open are left out, and so are repeats.
function CollRows_cards(section as dynamic) as object
    out = []
    if section = invalid or Type(section) <> "roAssociativeArray" then return out
    seen = {}
    for each c in Arr_or(section.collections)
        if out.Count() >= CollRows_max() then exit for
        kind = CollRows_cardKind(c)
        if kind <> "" then
            cid = Str_orEmpty(c.id)
            key = "collection:" + kind + ":" + cid
            if not seen.DoesExist(key) then
                seen[key] = true
                card = Content_collectionCard(c)
                card["content_id"] = key
                card["collection_kind"] = kind
                if CollRows_isText(card.item_count) then card["item_count"] = Int(Content_num(card.item_count))
                if kind = "library" then
                    card["library_id"] = Str_orEmpty(c.library_id).Trim()
                else if not Str_isEmpty(Str_orEmpty(c.creator_profile_id)) then
                    card["creator_profile_id"] = Str_orEmpty(c.creator_profile_id)
                end if
                backdrop = Str_orEmpty(c.backdrop_url)
                if backdrop.Trim() <> "" then
                    card["backdrop_url"] = backdrop
                    thumb = Str_orEmpty(c.backdrop_thumbhash)
                    if thumb.Trim() <> "" then card["backdrop_thumbhash"] = thumb
                end if
                out.Push(card)
            end if
        end if
    end for
    return out
end function

' ---------- Which cards Home shows (TvHomeSections.withTvShownCollections) ----------

' Whether this Roku shows a library of this type: never a reading library (ebooks, comics, manga;
' there is no reader on a TV; Android TV's isTvHiddenMediaType).
function CollRows_libraryTypeShown(libType as dynamic) as boolean
    t = LCase(Str_orEmpty(libType).Trim())
    hidden = { ebook: true, ebooks: true, book: true, books: true, comic: true, comics: true, manga: true, reading: true }
    return not hidden.DoesExist(t)
end function

' The libraries whose server collections Home may show, from the library list this Roku shows the
' profile (already without the libraries the profile hid): { id: { name, type } }, reading libraries
' left out.
function CollRows_libraryMap(libraries as dynamic) as object
    out = {}
    for each lib in Arr_or(libraries)
        if lib <> invalid and Type(lib) = "roAssociativeArray" then
            lid = Str_orEmpty(lib.id).Trim()
            if lid <> "" and CollRows_libraryTypeShown(lib["type"]) then out[lid] = { name: Str_orEmpty(lib.name), "type": Str_orEmpty(lib["type"]) }
        end if
    end for
    return out
end function

' Home's cards of a row: every personal collection, and a server collection only when `shown` (the
' { known, libs } ShellScreen publishes as m.global.collectionLibraries) is known and holds its
' library. Until the libraries are known, server collections wait: an unverified one could be an
' ebook library's.
function CollRows_shownOnHome(cards as object, shown as dynamic) as object
    known = false
    libs = {}
    if shown <> invalid and Type(shown) = "roAssociativeArray" then
        known = CollRows_isBool(shown.known) and shown.known
        if shown.libs <> invalid and Type(shown.libs) = "roAssociativeArray" then libs = shown.libs
    end if
    out = []
    for each c in cards
        if Str_orEmpty(c.collection_kind) = "user" then
            out.Push(c)
        else if known and libs.DoesExist(Str_orEmpty(c.library_id)) then
            out.Push(c)
        end if
    end for
    return out
end function

' ---------- The caption line (TvCollectionRow, TvCollectionOwners) ----------

' The "by Name" maker of a card: a personal collection made by another profile than the active one
' whose name this Roku knows (`names`: { profileId: name } from the account's profile list). "" for
' server collections, the viewer's own, an unknown active profile and makers with no known name.
function CollRows_ownerName(card as dynamic, names as dynamic, activeProfileId as dynamic) as string
    if card = invalid or Type(card) <> "roAssociativeArray" then return ""
    if Str_orEmpty(card.collection_kind) <> "user" then return ""
    creator = Str_orEmpty(card.creator_profile_id).Trim()
    active = Str_orEmpty(activeProfileId).Trim()
    if creator = "" or active = "" or creator = active then return ""
    if names = invalid or Type(names) <> "roAssociativeArray" then return ""
    return Str_orEmpty(names[creator]).Trim()
end function

' The account a profile list belongs to, as the names' key: server and account.
function CollRows_namesKey(session as dynamic) as string
    if session = invalid or Type(session) <> "roAssociativeArray" then return ""
    return Str_orEmpty(session.serverUrl) + "|" + Str_orEmpty(session.accountId)
end function

' { profileId: name } from a GET /api/v2/profiles answer's items.
function CollRows_profileNameMap(items as dynamic) as object
    out = {}
    for each p in Arr_or(items)
        if p <> invalid and Type(p) = "roAssociativeArray" then
            pid = Str_orEmpty(p.id).Trim()
            nm = Str_orEmpty(p.name).Trim()
            if pid <> "" and nm <> "" then out[pid] = nm
        end if
    end for
    return out
end function

' Keeps the account's profile names from a profile list just read (the picker, ShellScreen's refresh
' when a profile opens), as Android TV reads the account's cached profiles; no request of its own.
sub CollRows_rememberProfiles(session as dynamic, items as dynamic)
    if m.global = invalid or not m.global.hasField("profileNames") then return
    m.global.profileNames = { key: CollRows_namesKey(session), names: CollRows_profileNameMap(items) }
end sub

' The remembered names when they belong to this session's account, else {}.
function CollRows_profileNames(session as dynamic, remembered as dynamic) as object
    if remembered = invalid or Type(remembered) <> "roAssociativeArray" then return {}
    if Str_orEmpty(remembered.key) <> CollRows_namesKey(session) or CollRows_namesKey(session) = "|" then return {}
    names = remembered.names
    if names = invalid or Type(names) <> "roAssociativeArray" then return {}
    return names
end function

' A card's one caption line: "by Name" for another profile's shared collection, else its count
' ("12 items"; "" when it holds none, or when counts are off: a Movies- or Series-scoped library
' page, where the whole collection's count would be wrong).
function CollRows_caption(card as dynamic, owner as string, showCounts as boolean) as string
    ' Read by its catalog key: "by {0}" is also the audiobook author line, which several languages
    ' word differently ("autor: {0}" against hr "iz profila {0}").
    if owner <> "" then return TxKey("android.collections_posterCard_byOwner", { "0": owner }, "by " + owner)
    if not showCounts or card = invalid or Type(card) <> "roAssociativeArray" then return ""
    return Content_collectionCount(card.item_count)
end function

' Copies of a row's cards with their caption (the card's `caption`, which Content_cardNode shows and
' reads aloud in place of the count) and, on a shared one, `owner_name`.
function CollRows_withCaptions(cards as object, names as dynamic, activeProfileId as dynamic, showCounts as boolean) as object
    out = []
    for each c in cards
        card = AA_copy(c)
        owner = CollRows_ownerName(c, names, activeProfileId)
        card["caption"] = CollRows_caption(c, owner, showCounts)
        if owner <> "" then card["owner_name"] = owner
        out.Push(card)
    end for
    return out
end function

' ---------- Hero ----------

' Whether a card (a card AA, the node's raw) is a collection's.
function CollRows_isCard(card as dynamic) as boolean
    if card = invalid or Type(card) <> "roAssociativeArray" then return false
    return LCase(Str_orEmpty(card["type"])) = "collection"
end function

' Whether the marquee hero shows a card while it is focused: every card, a collection's too (its
' backdrop, else its poster). "Explore all" is the feed's own node and handled there.
function CollRows_heroShows(card as dynamic) as boolean
    return card <> invalid and Type(card) = "roAssociativeArray"
end function

' What a collection card's hero shows: "backdrop", "poster" (it has none; tvMarqueeItem's
' fallback) or "none" (no picture at all: the hero goes dark).
function CollRows_heroArt(card as dynamic) as string
    if card = invalid or Type(card) <> "roAssociativeArray" then return "none"
    if Str_orEmpty(card.backdrop_url).Trim() <> "" then return "backdrop"
    if Str_orEmpty(card.poster_url).Trim() <> "" then return "poster"
    return "none"
end function

' ---------- Opening a card ----------

' The LibraryScreen params that open a row card's collection page (LibraryPage section
' "collection"), as Android TV opens it (TvMainShell openHomeCollection and the library page's
' onCollectionClick):
' - From Home (pageLibraryId ""): a server collection in its own library (`homeLibraries`, the map
'   CollRows_libraryMap built, names it and gives its mode); a personal collection without one.
' - On a Movies- or Series-scoped page of a mixed library (mediaType set): that library and scope,
'   whatever the kind.
' - On any other library page: a server collection in that library, a personal one without one.
function CollRows_openParams(card as object, pageLibraryId as string, libraryName as string, mode as string, mediaType as string, homeLibraries = invalid as dynamic) as object
    p = { section: "collection", collectionId: Str_orEmpty(card.collection_id), collectionKind: Str_orEmpty(card.collection_kind), title: Str_orEmpty(card.title), collectionTitle: Str_orEmpty(card.title), fromRow: true, libraryId: "", libraryName: "", mode: "", mediaType: "" }
    ' Bracket keys keep their case (dot assignment lower-cases a key; pitfall 15).
    if p["collectionKind"] = "" then p["collectionKind"] = "library"
    user = p["collectionKind"] = "user"
    if pageLibraryId = "" then
        if user then return p
        lid = Str_orEmpty(card.library_id)
        p["libraryId"] = lid
        if homeLibraries <> invalid and Type(homeLibraries) = "roAssociativeArray" then
            lib = homeLibraries[lid]
            if lib <> invalid and Type(lib) = "roAssociativeArray" then
                p["libraryName"] = Str_orEmpty(lib.name)
                p["mode"] = Library_mode(lib["type"])
            end if
        end if
        return p
    end if
    if user and mediaType = "" then return p
    p["libraryId"] = pageLibraryId
    p["libraryName"] = libraryName
    p["mode"] = mode
    p["mediaType"] = mediaType
    return p
end function

' The catalog source of a collection page: user_collection for a personal collection, else
' library_collection.
function CollRows_catalogSource(kind as dynamic) as string
    if LCase(Str_orEmpty(kind)) = "user" then return "user_collection"
    return "library_collection"
end function

' ---------- Diagnostics ----------

' The [siku-home] line for a row of collections: its id, the cards it shows, how many have a hero
' backdrop, how many are empty (no count), how many are shared by another profile ("by Name") and
' how many server collections Home holds back (held: libraries not known yet, or not shown).
function CollRows_rowLog(sectionId as string, cards as object, held = 0 as integer) as string
    backdrops = 0
    empty = 0
    shared = 0
    for each c in cards
        if Str_orEmpty(c.backdrop_url) <> "" then backdrops = backdrops + 1
        if Int(Content_num(c.item_count)) <= 0 then empty = empty + 1
        if Str_orEmpty(c.owner_name) <> "" then shared = shared + 1
    end for
    return "[siku-home] collection row=" + sectionId + " cards=" + cards.Count().ToStr() + " backdrops=" + backdrops.ToStr() + " empty=" + empty.ToStr() + " shared=" + shared.ToStr() + " held=" + held.ToStr() + " explore_all=no"
end function
