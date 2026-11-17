# SPDX-License-Identifier: AGPL-3.0-or-later
"""Home and library rows of collections (components/common/CollectionRows.brs; silo-server #4410 /
#4415, adapted from silo-roku 8183af8 and d240f47): a collection_posters section's cards come from
`collections`, shown whole in the server's order with the Collections grid's card, a backdrop only
on a server collection that has one (the hero), and a page that opens with that library's view."""
import unittest

from brs import check_cases

FILES = ["components/common/CollectionRows.brs", "components/common/Content.brs", "components/common/Utils.brs"]


def section(collections, section_type="collection_posters"):
    return {"id": "franchises", "section_type": section_type, "title": "Franchises", "featured": False, "item_limit": 20,
            "total_count": len(collections), "items": [], "collections": collections}


MARVEL = {"id": "01J9Z8C3W4R5T6Y7U8I9O0P1Q2", "source": "library", "title": "Marvel", "poster_url": "https://s3.example.test/marvel.jpg",
          "poster_is_collage": False, "backdrop_url": "https://s3.example.test/marvel-backdrop.jpg",
          "backdrop_thumbhash": "3OcRJYB4d3h/iIeHeEh3eIhw+j2w", "item_count": 12, "library_id": "1"}
GHIBLI = {"id": "c-ghibli", "source": "user", "title": "Ghibli nights", "poster_url": "https://s3.example.test/collage.jpg",
          "poster_is_collage": True, "item_count": 5, "creator_profile_id": "p-owner"}

MARVEL_CARD = {"content_id": "collection:01J9Z8C3W4R5T6Y7U8I9O0P1Q2", "collection_id": "01J9Z8C3W4R5T6Y7U8I9O0P1Q2", "type": "collection",
               "title": "Marvel", "poster_url": "https://s3.example.test/marvel.jpg", "item_count": 12, "collection_kind": "library",
               "library_id": "1", "backdrop_url": "https://s3.example.test/marvel-backdrop.jpg",
               "backdrop_thumbhash": "3OcRJYB4d3h/iIeHeEh3eIhw+j2w"}
GHIBLI_CARD = {"content_id": "collection:c-ghibli", "collection_id": "c-ghibli", "type": "collection", "title": "Ghibli nights",
               "poster_url": "https://s3.example.test/collage.jpg", "item_count": 5, "collection_kind": "user"}


def many(n):
    return [{"id": "c%d" % i, "source": "library", "title": "Collection %d" % i, "poster_url": "", "item_count": i, "library_id": "1"}
            for i in range(1, n + 1)]


class Rows(unittest.TestCase):
    def test_which_sections(self):
        f = "CollRows_isRow"
        check_cases(self, FILES, [
            ("a row of collections", f, [section([])], True),
            ("any case", f, [section([], "Collection_Posters")], True),
            ("a title row", f, [section([], "trending_on_server")], False),
            ("the library collection index is not a row", f, [{"collections": [], "groups": []}], False),
            ("not a section", f, [None], False),
        ])

    def test_cards(self):
        f = "CollRows_cards"
        backdrop_on_user = dict(GHIBLI, backdrop_url="https://s3.example.test/x.jpg")
        numeric_lib = dict(MARVEL, library_id=7)
        check_cases(self, FILES, [
            ("server and personal collections, in order", f, [section([MARVEL, GHIBLI])], [MARVEL_CARD, GHIBLI_CARD]),
            ("a personal collection never takes a backdrop", f, [section([backdrop_on_user])], [GHIBLI_CARD]),
            ("a numeric library_id reads as text", f, [section([numeric_lib])], [MARVEL_CARD | {"library_id": "7"}]),
            ("entries without an id and repeats are left out", f, [section([{"title": "x"}, None, MARVEL, MARVEL])], [MARVEL_CARD]),
            ("no collections", f, [dict(section([]), collections=None)], []),
            ("not a section", f, [None], []),
        ])

    def test_whole_row(self):
        """Every card the server sends (it sends at most 30), above the 20-card cut, up to the rows' bound of 40."""
        cards = [{"content_id": "collection:c%d" % i, "collection_id": "c%d" % i, "type": "collection", "title": "Collection %d" % i,
                  "poster_url": "", "item_count": i, "collection_kind": "library", "library_id": "1"} for i in range(1, 41)]
        check_cases(self, FILES, [
            ("30 cards stay 30", "CollRows_cards", [section(many(30))], cards[:30]),
            ("the rows' bound", "CollRows_cards", [section(many(45))], cards),
            ("max", "CollRows_max", [], 40),
        ])


class Hero(unittest.TestCase):
    def test_hero(self):
        f = "CollRows_heroShows"
        check_cases(self, FILES, [
            ("a collection with a backdrop", f, [MARVEL_CARD], True),
            ("a collection without one", f, [GHIBLI_CARD], False),
            ("an empty backdrop", f, [dict(MARVEL_CARD, backdrop_url="")], False),
            ("a title", f, [{"content_id": "movie:a", "type": "movie"}], True),
            ("nothing", f, [None], False),
            ("a collection card", "CollRows_isCard", [MARVEL_CARD], True),
            ("a movie card", "CollRows_isCard", [{"type": "movie"}], False),
        ])

    def test_meta_line(self):
        check_cases(self, FILES, [
            ("the count", "CollRows_metaLine", [MARVEL_CARD], "12 items"),
            ("one", "CollRows_metaLine", [dict(MARVEL_CARD, item_count=1)], "1 item"),
            ("grouped digits", "CollRows_metaLine", [dict(MARVEL_CARD, item_count=1284)], "1,284 items"),
            ("a count sent as text", "CollRows_metaLine", [dict(MARVEL_CARD, item_count="3")], "3 items"),
            ("empty: no line", "CollRows_metaLine", [dict(MARVEL_CARD, item_count=0)], ""),
            ("no count", "CollRows_metaLine", [dict(MARVEL_CARD, item_count=None)], ""),
        ])


class Card(unittest.TestCase):
    def test_grid_card(self):
        """The library Collections grid builds the same card (LibraryPage onCollections)."""
        check_cases(self, FILES, [
            ("grid entry", "Content_collectionCard", [{"id": "c1", "title": "Award Winners", "poster_url": "/p.jpg", "item_count": 4}],
             {"content_id": "collection:c1", "collection_id": "c1", "type": "collection", "title": "Award Winners", "poster_url": "/p.jpg", "item_count": 4}),
            ("no poster: the placeholder", "Content_collectionCard", [{"id": "c2", "title": "Empty"}],
             {"content_id": "collection:c2", "collection_id": "c2", "type": "collection", "title": "Empty", "poster_url": "", "item_count": None}),
            ("count", "Content_collectionCount", [4], "4 items"),
            ("zero has no caption", "Content_collectionCount", [0], ""),
        ])


class Open(unittest.TestCase):
    def test_params(self):
        f = "CollRows_openParams"
        base = {"section": "collection", "collectionId": "01J9Z8C3W4R5T6Y7U8I9O0P1Q2", "collectionKind": "library", "title": "Marvel",
                "collectionTitle": "Marvel", "fromRow": True}
        check_cases(self, FILES, [
            ("from Home: every member, no library", f, [MARVEL_CARD, "", "", "", ""],
             base | {"libraryId": "", "libraryName": "", "mode": "", "mediaType": ""}),
            ("on a library page: that library", f, [MARVEL_CARD, "1", "Movies", "movies", ""],
             base | {"libraryId": "1", "libraryName": "Movies", "mode": "movies", "mediaType": ""}),
            ("a mixed library's Series view narrows it", f, [MARVEL_CARD, "5", "Everything", "mixed", "series"],
             base | {"libraryId": "5", "libraryName": "Everything", "mode": "mixed", "mediaType": "series"}),
            ("a personal collection", f, [GHIBLI_CARD, "", "", "", ""],
             base | {"collectionId": "c-ghibli", "collectionKind": "user", "title": "Ghibli nights", "collectionTitle": "Ghibli nights",
                     "libraryId": "", "libraryName": "", "mode": "", "mediaType": ""}),
        ])

    def test_source(self):
        f = "CollRows_catalogSource"
        check_cases(self, FILES, [
            ("server collection", f, ["library"], "library_collection"),
            ("personal collection", f, ["user"], "user_collection"),
            ("unknown or missing reads as a server collection", f, [None], "library_collection"),
        ])

    def test_log(self):
        check_cases(self, FILES, [
            ("row line", "CollRows_rowLog", ["franchises", [MARVEL_CARD, GHIBLI_CARD, dict(GHIBLI_CARD, item_count=0)]],
             "[siku-home] collection row=franchises cards=3 backdrops=1 empty=1 explore_all=no"),
        ])


if __name__ == "__main__":
    unittest.main()
