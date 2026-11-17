# SPDX-License-Identifier: AGPL-3.0-or-later
"""Home and library rows of collections (components/common/CollectionRows.brs; silo-server #4410 /
#4415, Silo Android TV db87f835f / #979, first adapted from silo-roku 8183af8 and d240f47): a
collection_posters section's cards come from `collections`, each read on its own, shown whole in the
server's order with the Collections grid's card and one caption ("by Name" or the count); Home holds
server collections back until it knows the libraries it shows; the hero shows the backdrop, else the
poster; a card opens as Android TV opens it."""
import json
import os
import unittest

from brs import check_cases

FILES = ["components/common/CollectionRows.brs", "components/common/Content.brs", "components/common/Utils.brs"]


def section(collections, section_type="collection_posters", featured=False):
    return {"id": "franchises", "section_type": section_type, "title": "Franchises", "featured": featured, "item_limit": 20,
            "total_count": len(collections), "items": [], "collections": collections}


MARVEL = {"id": "01J9Z8C3W4R5T6Y7U8I9O0P1Q2", "source": "library", "title": "Marvel", "poster_url": "https://s3.example.test/marvel.jpg",
          "poster_is_collage": False, "backdrop_url": "https://s3.example.test/marvel-backdrop.jpg",
          "backdrop_thumbhash": "3OcRJYB4d3h/iIeHeEh3eIhw+j2w", "item_count": 12, "library_id": "1"}
GHIBLI = {"id": "c-ghibli", "source": "user", "title": "Ghibli nights", "poster_url": "https://s3.example.test/collage.jpg",
          "poster_is_collage": True, "item_count": 5, "creator_profile_id": "p-owner"}

MARVEL_CARD = {"content_id": "collection:library:01J9Z8C3W4R5T6Y7U8I9O0P1Q2", "collection_id": "01J9Z8C3W4R5T6Y7U8I9O0P1Q2",
               "type": "collection", "title": "Marvel", "poster_url": "https://s3.example.test/marvel.jpg", "item_count": 12,
               "collection_kind": "library", "library_id": "1", "backdrop_url": "https://s3.example.test/marvel-backdrop.jpg",
               "backdrop_thumbhash": "3OcRJYB4d3h/iIeHeEh3eIhw+j2w"}
GHIBLI_CARD = {"content_id": "collection:user:c-ghibli", "collection_id": "c-ghibli", "type": "collection", "title": "Ghibli nights",
               "poster_url": "https://s3.example.test/collage.jpg", "item_count": 5, "collection_kind": "user",
               "creator_profile_id": "p-owner"}

SESSION = {"serverUrl": "http://silo.example:8097", "accountId": "a1", "profileId": "p-sam"}
NAMES = {"key": "http://silo.example:8097|a1", "names": {"p-owner": "Laura", "p-sam": "Sam"}}


def many(n):
    return [{"id": "c%d" % i, "source": "library", "title": "Collection %d" % i, "poster_url": "", "item_count": i, "library_id": "1"}
            for i in range(1, n + 1)]


class Rows(unittest.TestCase):
    def test_which_sections(self):
        f = "CollRows_isRow"
        check_cases(self, FILES, [
            ("a row of collections", f, [section([])], True),
            ("any case", f, [section([], "Collection_Posters")], True),
            ("a featured row of collections is still one", f, [section([], featured=True)], True),
            ("a title row", f, [section([], "trending_on_server")], False),
            ("the library collection index is not a row", f, [{"collections": [], "groups": []}], False),
            ("not a section", f, [None], False),
        ])

    def test_cards(self):
        f = "CollRows_cards"
        numeric_lib = dict(MARVEL, library_id=7)
        same_id_user = dict(GHIBLI, id=MARVEL["id"])
        backdrop_on_user = dict(GHIBLI, backdrop_url="https://s3.example.test/x.jpg")
        check_cases(self, FILES, [
            ("server and personal collections, in order", f, [section([MARVEL, GHIBLI])], [MARVEL_CARD, GHIBLI_CARD]),
            ("a numeric library_id reads as text", f, [section([numeric_lib])],
             [MARVEL_CARD | {"library_id": "7"}]),
            ("a server and a personal collection may share an id", f, [section([MARVEL, same_id_user])],
             [MARVEL_CARD, GHIBLI_CARD | {"collection_id": MARVEL["id"], "content_id": "collection:user:" + MARVEL["id"]}]),
            ("a backdrop is read whatever the kind (tvMarqueeItem)", f, [section([backdrop_on_user])],
             [GHIBLI_CARD | {"backdrop_url": "https://s3.example.test/x.jpg"}]),
            ("entries without an id and repeats are left out", f, [section([{"title": "x", "source": "user"}, None, MARVEL, MARVEL])], [MARVEL_CARD]),
            ("no collections", f, [dict(section([]), collections=None)], []),
            ("not a section", f, [None], []),
        ])

    def test_bad_cards_are_left_out_alone(self):
        """Each card decodes on its own (decodeSectionV2): the rest of the row stays."""
        f = "CollRows_cards"
        check_cases(self, FILES, [
            ("a count that is not a number", f, [section([dict(MARVEL, item_count="lots"), GHIBLI])], [GHIBLI_CARD]),
            ("a title that is an object", f, [section([dict(MARVEL, title={"en": "Marvel"}), GHIBLI])], [GHIBLI_CARD]),
            ("a poster that is a list", f, [section([MARVEL, dict(GHIBLI, poster_url=["a"])])], [MARVEL_CARD]),
            ("a collage flag that is not a yes/no", f, [section([dict(MARVEL, poster_is_collage="maybe"), GHIBLI])], [GHIBLI_CARD]),
            ("a fractional count", f, [section([dict(MARVEL, item_count=2.5), GHIBLI])], [GHIBLI_CARD]),
            ("a card that is not an object", f, [section(["Marvel", 7, GHIBLI])], [GHIBLI_CARD]),
            ("a server collection without a library", f, [section([dict(MARVEL, library_id=None), GHIBLI])], [GHIBLI_CARD]),
            ("a blank library", f, [section([dict(MARVEL, library_id="  "), GHIBLI])], [GHIBLI_CARD]),
            ("an unknown source", f, [section([dict(MARVEL, source="smart"), GHIBLI])], [GHIBLI_CARD]),
            ("no source", f, [section([{k: v for k, v in MARVEL.items() if k != "source"}, GHIBLI])], [GHIBLI_CARD]),
            # Read leniently, as SiloJson does.
            ("a count sent as digits reads as a number", f, [section([dict(MARVEL, item_count="12")])], [MARVEL_CARD]),
            ("null fields take their defaults", f, [section([dict(GHIBLI, poster_url=None, item_count=None, poster_is_collage=None)])],
             [GHIBLI_CARD | {"poster_url": "", "item_count": None}]),
            ("a collage flag as text", f, [section([dict(GHIBLI, poster_is_collage="true")])], [GHIBLI_CARD]),
        ])

    def test_whole_row(self):
        """Every card the server sends (it sends at most 30), above the 20-card cut, up to the rows' bound of 40."""
        cards = [{"content_id": "collection:library:c%d" % i, "collection_id": "c%d" % i, "type": "collection", "title": "Collection %d" % i,
                  "poster_url": "", "item_count": i, "collection_kind": "library", "library_id": "1"} for i in range(1, 41)]
        check_cases(self, FILES, [
            ("30 cards stay 30", "CollRows_cards", [section(many(30))], cards[:30]),
            ("the rows' bound", "CollRows_cards", [section(many(45))], cards),
            ("max", "CollRows_max", [], 40),
        ])


class HomeLibraries(unittest.TestCase):
    """TV Home shows a server collection only once it knows which libraries it shows the profile
    (withTvShownCollections): never an ebook library's."""

    LIBS = [{"id": "1", "name": "Movies", "type": "movies"}, {"id": 5, "name": "Everything", "type": "mixed"},
            {"id": "6", "name": "Books", "type": "ebook"}, {"id": "7", "name": "Comics", "type": "Comics"},
            {"id": "4", "name": "Audiobooks", "type": "audiobooks"}, {"name": "No id", "type": "movies"}]

    def test_library_map(self):
        check_cases(self, FILES, [
            ("reading libraries left out", "CollRows_libraryMap", [self.LIBS],
             {"1": {"name": "Movies", "type": "movies"}, "5": {"name": "Everything", "type": "mixed"},
              "4": {"name": "Audiobooks", "type": "audiobooks"}}),
            ("nothing", "CollRows_libraryMap", [None], {}),
            ("ebook", "CollRows_libraryTypeShown", ["ebook"], False),
            ("manga", "CollRows_libraryTypeShown", [" Manga "], False),
            ("audiobooks stay", "CollRows_libraryTypeShown", ["audiobooks"], True),
            ("video", "CollRows_libraryTypeShown", ["movies"], True),
        ])

    def test_shown_on_home(self):
        f = "CollRows_shownOnHome"
        books = MARVEL_CARD | {"library_id": "6", "collection_id": "c-books", "content_id": "collection:library:c-books"}
        known = {"known": True, "libs": {"1": {"name": "Movies", "type": "movies"}}}
        check_cases(self, FILES, [
            ("shown libraries only", f, [[MARVEL_CARD, books, GHIBLI_CARD], known], [MARVEL_CARD, GHIBLI_CARD]),
            ("not known yet: server collections wait, personal ones stay", f, [[MARVEL_CARD, GHIBLI_CARD], {"known": False, "libs": {}}],
             [GHIBLI_CARD]),
            ("no answer at all", f, [[MARVEL_CARD, GHIBLI_CARD], None], [GHIBLI_CARD]),
            ("a known empty list", f, [[MARVEL_CARD], {"known": True, "libs": {}}], []),
        ])


class Captions(unittest.TestCase):
    def test_owner(self):
        f = "CollRows_ownerName"
        names = NAMES["names"]
        check_cases(self, FILES, [
            ("another profile's shared collection", f, [GHIBLI_CARD, names, "p-sam"], "Laura"),
            ("the viewer's own", f, [GHIBLI_CARD, names, "p-owner"], ""),
            ("an unknown active profile", f, [GHIBLI_CARD, names, ""], ""),
            ("a maker this Roku has no name for", f, [dict(GHIBLI_CARD, creator_profile_id="p-gone"), names, "p-sam"], ""),
            ("no maker", f, [{k: v for k, v in GHIBLI_CARD.items() if k != "creator_profile_id"}, names, "p-sam"], ""),
            ("a server collection never has one", f, [dict(MARVEL_CARD, creator_profile_id="p-owner"), names, "p-sam"], ""),
            ("no names", f, [GHIBLI_CARD, None, "p-sam"], ""),
        ])

    def test_names(self):
        f = "CollRows_profileNames"
        check_cases(self, FILES, [
            ("this account's names", f, [SESSION, NAMES], NAMES["names"]),
            ("another account's", f, [dict(SESSION, accountId="a2"), NAMES], {}),
            ("nothing remembered", f, [SESSION, None], {}),
            ("a profile list's names", "CollRows_profileNameMap",
             [[{"id": "p-owner", "name": "Laura"}, {"id": "p-x", "name": " "}, {"name": "No id"}, None]], {"p-owner": "Laura"}),
        ])

    def test_caption(self):
        f = "CollRows_caption"
        check_cases(self, FILES, [
            ("by Name, not the count", f, [GHIBLI_CARD, "Laura", True], "by Laura"),
            ("by Name on a scoped page too", f, [GHIBLI_CARD, "Laura", False], "by Laura"),
            ("the count", f, [MARVEL_CARD, "", True], "12 items"),
            ("one", f, [dict(MARVEL_CARD, item_count=1), "", True], "1 item"),
            ("grouped digits", f, [dict(MARVEL_CARD, item_count=1284), "", True], "1,284 items"),
            ("empty: no line", f, [dict(MARVEL_CARD, item_count=0), "", True], ""),
            ("counts off (a Movies or Series scoped page)", f, [MARVEL_CARD, "", False], ""),
        ])

    def test_caption_by_catalog_key(self):
        """The maker line is read by its catalog key, not by "by {0}", which is also the audiobook author line."""
        here = os.path.dirname(os.path.abspath(__file__))
        with open(os.path.join(here, "..", "locale", "hr", "strings.json"), encoding="utf-8") as f:
            hr = json.load(f)
        g = {"global": {"appLocale": "hr", "strings": hr}}
        check_cases(self, FILES, [
            ("Croatian names the profile", "CollRows_caption", [GHIBLI_CARD, "Laura", True], "iz profila Laura", g),
            ("not the author wording", "TxF", ["by {0}", ["Laura"]], "autor: Laura", g),
        ])

    def test_with_captions(self):
        check_cases(self, FILES, [
            ("captions and the owner", "CollRows_withCaptions", [[MARVEL_CARD, GHIBLI_CARD], NAMES["names"], "p-sam", True],
             [MARVEL_CARD | {"caption": "12 items"}, GHIBLI_CARD | {"caption": "by Laura", "owner_name": "Laura"}]),
            ("the maker sees the count", "CollRows_withCaptions", [[GHIBLI_CARD], NAMES["names"], "p-owner", True],
             [GHIBLI_CARD | {"caption": "5 items"}]),
        ])


class Hero(unittest.TestCase):
    def test_hero(self):
        f = "CollRows_heroShows"
        check_cases(self, FILES, [
            ("a collection with a backdrop", f, [MARVEL_CARD], True),
            ("a collection without one shows its poster", f, [GHIBLI_CARD], True),
            ("a title", f, [{"content_id": "movie:a", "type": "movie"}], True),
            ("nothing", f, [None], False),
            ("a collection card", "CollRows_isCard", [MARVEL_CARD], True),
            ("a movie card", "CollRows_isCard", [{"type": "movie"}], False),
        ])

    def test_art(self):
        f = "CollRows_heroArt"
        check_cases(self, FILES, [
            ("backdrop", f, [MARVEL_CARD], "backdrop"),
            ("poster when it has no backdrop", f, [GHIBLI_CARD], "poster"),
            ("an empty backdrop", f, [dict(MARVEL_CARD, backdrop_url=" ")], "poster"),
            ("neither", f, [dict(GHIBLI_CARD, poster_url="")], "none"),
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
    HOME_LIBS = {"1": {"name": "Movies", "type": "movies"}}

    def test_params(self):
        f = "CollRows_openParams"
        base = {"section": "collection", "collectionId": "01J9Z8C3W4R5T6Y7U8I9O0P1Q2", "collectionKind": "library", "title": "Marvel",
                "collectionTitle": "Marvel", "fromRow": True}
        user = base | {"collectionId": "c-ghibli", "collectionKind": "user", "title": "Ghibli nights", "collectionTitle": "Ghibli nights"}
        none = {"libraryId": "", "libraryName": "", "mode": "", "mediaType": ""}
        check_cases(self, FILES, [
            ("from Home: a server collection in its own library", f, [MARVEL_CARD, "", "", "", "", self.HOME_LIBS],
             base | {"libraryId": "1", "libraryName": "Movies", "mode": "movies", "mediaType": ""}),
            ("from Home: a library not in the map still opens there", f, [MARVEL_CARD, "", "", "", ""],
             base | none | {"libraryId": "1"}),
            ("from Home: a personal collection without a library", f, [GHIBLI_CARD, "", "", "", "", self.HOME_LIBS], user | none),
            ("on a library page: that library", f, [MARVEL_CARD, "1", "Movies", "movies", ""],
             base | {"libraryId": "1", "libraryName": "Movies", "mode": "movies", "mediaType": ""}),
            ("a mixed library's Series view narrows it", f, [MARVEL_CARD, "5", "Everything", "mixed", "series"],
             base | {"libraryId": "5", "libraryName": "Everything", "mode": "mixed", "mediaType": "series"}),
            ("a personal collection on a scoped page: that library and scope", f, [GHIBLI_CARD, "5", "Everything", "mixed", "movie"],
             user | {"libraryId": "5", "libraryName": "Everything", "mode": "mixed", "mediaType": "movie"}),
            ("a personal collection on an unscoped page: no library", f, [GHIBLI_CARD, "1", "Movies", "movies", ""], user | none),
        ])

    def test_source(self):
        f = "CollRows_catalogSource"
        check_cases(self, FILES, [
            ("server collection", f, ["library"], "library_collection"),
            ("personal collection", f, ["user"], "user_collection"),
            ("unknown or missing reads as a server collection", f, [None], "library_collection"),
        ])

    def test_log(self):
        shared = GHIBLI_CARD | {"caption": "by Laura", "owner_name": "Laura"}
        check_cases(self, FILES, [
            ("row line", "CollRows_rowLog", ["franchises", [MARVEL_CARD, shared, dict(GHIBLI_CARD, item_count=0)], 2],
             "[siku-home] collection row=franchises cards=3 backdrops=1 empty=1 shared=1 held=2 explore_all=no"),
            ("nothing held", "CollRows_rowLog", ["franchises", [MARVEL_CARD]],
             "[siku-home] collection row=franchises cards=1 backdrops=1 empty=0 shared=0 held=0 explore_all=no"),
        ])


if __name__ == "__main__":
    unittest.main()
