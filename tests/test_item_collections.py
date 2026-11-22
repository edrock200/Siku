# SPDX-License-Identifier: AGPL-3.0-or-later
"""The collections a movie or series is in, on its detail page (components/common/ItemCollections.brs;
Silo Android #1007, silo-server #4528 listCatalogItemCollections): only movies and series ask, only a
server whose search capabilities advertise item_collections is asked; one collection with other titles
previews up to six of them, otherwise an "Also in" row shows every card; a body without both members is
a failed read; server collections show only from libraries this Roku shows, reading titles stay out of a
preview, and a preview left with none shows its collection's card. The bodies follow Silo Android's
vendored API v2 fixtures list_catalog_item_collections_ok.json / _single_preview.json."""
import unittest

from brs import check_cases

FILES = ["components/common/ItemCollections.brs", "components/common/CollectionRows.brs",
         "components/common/Content.brs", "components/common/Utils.brs"]

CRIME = {"id": "01J9Z8C3W4R5T6Y7U8I9O0P1Q2", "source": "library", "title": "Crime classics",
         "poster_url": "/api/v2/images/collections/01J9Z8C3W4R5T6Y7U8I9O0P1Q2/poster", "poster_is_collage": False,
         "item_count": 24, "library_id": "1"}
FAVORITES = {"id": "c1", "source": "user", "title": "Favorites", "poster_url": "/api/v2/images/user-collections/c1/collage",
             "poster_is_collage": True, "item_count": 7, "creator_profile_id": "p-owner"}
BOOKS = {"id": "c-books", "source": "library", "title": "Book Club", "poster_url": "", "item_count": 7, "library_id": "6"}
HARBOR = {"content_id": "movie:harbor-lights-2019", "type": "movie", "title": "Harbor Lights", "year": 2019, "genres": [],
          "keywords": [], "status": "", "poster_url": "/api/v2/images/items/movie:harbor-lights-2019/poster"}

SHOWN = {"known": True, "libs": {"1": {"name": "Movies", "type": "movies"}}}
UNKNOWN = {"known": False, "libs": {}}


def title(i, kind="movie"):
    return {"content_id": "%s:t%d" % (kind, i), "type": kind, "title": "Title %d" % i}


def ids(row):
    return [c["content_id"] for c in row["items"]] if row["kind"] == "preview" else [c["collection_id"] for c in row["cards"]]


class Capability(unittest.TestCase):
    def test_cases(self):
        c = "ItemColl_supported"
        check_cases(self, FILES, [
            ("advertised", c, [{"revision": "r", "state": "available", "item_collections": True}], True),
            ("false", c, [{"item_collections": False}], False),
            ("absent: an older server is never asked", c, [{"revision": "r", "people_media_scope": True}], False),
            ("not a boolean", c, [{"item_collections": "yes"}], False),
            ("no body", c, [None], False),
            ("movies ask", "ItemColl_asks", ["movie"], True),
            ("series ask", "ItemColl_asks", ["Series"], True),
            ("episodes do not", "ItemColl_asks", ["episode"], False),
            ("seasons do not", "ItemColl_asks", ["season"], False),
            ("audiobooks do not", "ItemColl_asks", ["audiobook"], False),
        ])


class Rows(unittest.TestCase):
    def test_reads(self):
        reads = check_cases(self, FILES, [
            ("ok fixture reads both cards", "ItemColl_read", [{"items": [CRIME, FAVORITES], "preview_items": []}],
             lambda v: [c["content_id"] for c in v["cards"]] == ["collection:library:01J9Z8C3W4R5T6Y7U8I9O0P1Q2", "collection:user:c1"]
             and v["preview"] == []),
            ("single preview fixture", "ItemColl_read", [{"items": [CRIME], "preview_items": [HARBOR]}],
             lambda v: len(v["cards"]) == 1 and [p["content_id"] for p in v["preview"]] == ["movie:harbor-lights-2019"]),
            ("missing preview_items is a failed read", "ItemColl_read", [{"items": [CRIME]}], None),
            ("missing items is a failed read", "ItemColl_read", [{"preview_items": []}], None),
            ("items not a list", "ItemColl_read", [{"items": {}, "preview_items": []}], None),
            ("a card that does not open is left out, not the row", "ItemColl_read",
             [{"items": [CRIME, {"id": "x", "source": "library", "title": "No Library"}, {"id": "y", "source": "smart", "title": "?"}],
               "preview_items": []}],
             lambda v: len(v["cards"]) == 1),
            ("a preview title without a content id is left out", "ItemColl_read",
             [{"items": [CRIME], "preview_items": [{"content_id": "", "title": "x"}, HARBOR, "junk"]}],
             lambda v: len(v["preview"]) == 1),
        ])
        self.assertTrue(all(r["ok"] for r in reads))

    def test_shapes(self):
        c = "ItemColl_row"
        def read(cards, preview):
            return {"cards": cards, "preview": preview}

        card_crime = {"content_id": "collection:library:" + CRIME["id"], "collection_id": CRIME["id"], "collection_kind": "library",
                      "library_id": "1", "title": "Crime classics"}
        card_fav = {"content_id": "collection:user:c1", "collection_id": "c1", "collection_kind": "user", "title": "Favorites"}
        check_cases(self, FILES, [
            ("no collection: no row", c, [read([], [])], None),
            ("a failed read: no row", c, [None], None),
            ("several collections: Also in with every card (no cap)", c,
             [read([dict(card_crime, collection_id="c%d" % i) for i in range(15)], [])],
             lambda v: v["kind"] == "also_in" and len(v["cards"]) == 15),
            ("one collection with other titles: preview of up to six", c,
             [read([card_crime], [title(i) for i in range(1, 9)])],
             lambda v: v["kind"] == "preview" and v["collection"]["title"] == "Crime classics"
             and ids(v) == ["movie:t%d" % i for i in range(1, 7)]),
            ("one collection holding only this title: its card under Also in", c,
             [read([card_crime], [])], lambda v: v["kind"] == "also_in" and len(v["cards"]) == 1),
            ("two collections with a preview anyway: Also in", c,
             [read([card_crime, card_fav], [title(1)])], lambda v: v["kind"] == "also_in" and len(v["cards"]) == 2),
        ])


class ShownOnTv(unittest.TestCase):
    def test_cases(self):
        c = "ItemColl_forTv"
        crime = {"collection_id": CRIME["id"], "collection_kind": "library", "library_id": "1", "title": "Crime classics"}
        books = {"collection_id": "c-books", "collection_kind": "library", "library_id": "6", "title": "Book Club"}
        mine = {"collection_id": "c1", "collection_kind": "user", "title": "Favorites"}
        check_cases(self, FILES, [
            ("server collections only from shown libraries; personal ones stay", c,
             [{"kind": "also_in", "cards": [crime, books, mine]}, SHOWN],
             lambda v: v["kind"] == "also_in" and ids(v) == [CRIME["id"], "c1"]),
            ("nothing left: no row", c, [{"kind": "also_in", "cards": [books]}, SHOWN], None),
            ("libraries not known: server collections wait", c,
             [{"kind": "also_in", "cards": [crime, mine]}, UNKNOWN], lambda v: ids(v) == ["c1"]),
            ("a preview of a hidden library's collection: no row", c,
             [{"kind": "preview", "collection": books, "items": [title(1)]}, SHOWN], None),
            ("reading titles leave the preview", c,
             [{"kind": "preview", "collection": crime, "items": [title(1), title(2, "ebook"), title(3, "series"), title(4, "manga")]}, SHOWN],
             lambda v: v["kind"] == "preview" and ids(v) == ["movie:t1", "series:t3"]),
            ("a preview left with none shows its collection's card under Also in", c,
             [{"kind": "preview", "collection": mine, "items": [title(1, "ebook"), title(2, "comic")]}, SHOWN],
             lambda v: v["kind"] == "also_in" and ids(v) == ["c1"]),
            ("no row in, no row out", c, [None, SHOWN], None),
            ("needs libraries with a server card", "ItemColl_needsLibraries", [{"kind": "also_in", "cards": [mine, crime]}], True),
            ("personal ones only need none", "ItemColl_needsLibraries", [{"kind": "preview", "collection": mine, "items": []}], False),
            ("held count", "ItemColl_heldCount", [{"kind": "also_in", "cards": [crime, books, mine]}, {"kind": "also_in", "cards": [crime, mine]}], 1),
            ("heading over a preview is the collection's name", "ItemColl_heading",
             [{"kind": "preview", "collection": crime, "items": [title(1)]}], "Crime classics"),
            ("heading over Also in", "ItemColl_heading", [{"kind": "also_in", "cards": [mine]}], "Also in"),
            ("row log", "ItemColl_rowLog", [{"kind": "also_in", "cards": [mine, crime]}, 1],
             "[siku-detail] collections row=also_in cards=2 held=1"),
            ("row log none", "ItemColl_rowLog", [None, 0], "[siku-detail] collections row=none held=0"),
        ])


if __name__ == "__main__":
    unittest.main()
