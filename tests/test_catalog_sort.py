# SPDX-License-Identifier: AGPL-3.0-or-later
"""Library sort options that match Silo's web client (Silo Android #843, a port of CatalogSortTest;
silo-roku d4303e5 does the same): names, order and default directions, which fields a library, a
mixed library side, a personal list or a collection lists, the Rotten Tomatoes sorts only while the
server shows them, and a restored sort that stays listed."""
import unittest

from brs import check_cases

FILES = ["components/common/CatalogSort.brs", "tests/catalog_sort_io.brs", "components/common/Utils.brs"]

MOVIE = ["title", "added_at", "release_date", "year", "content_rating", "runtime", "rating_imdb", "rating_tmdb",
         "resolution", "bitrate", "progress", "date_viewed", "plays"]
SERIES = ["title", "added_at", "release_date", "last_air_date", "latest_episode_added", "year", "content_rating",
          "runtime", "rating_imdb", "rating_tmdb", "resolution", "bitrate", "progress", "date_viewed", "plays"]
AUDIOBOOK = ["title", "added_at", "release_date", "year", "runtime", "bitrate", "progress", "date_viewed", "plays",
             "author", "narrator", "series"]
RT = ["rt_critic", "rt_audience"]


def ids(name, want, relevance, personalized=True, shown=None, keep=""):
    return (name, "CatalogSortT_ids", [relevance, personalized, shown or [], keep], want)


class Options(unittest.TestCase):
    def test_lists(self):
        series_rt = SERIES[:10] + ["rating_rt_critic", "rating_rt_audience"] + SERIES[10:]
        check_cases(self, FILES, [
            ids("a movie library lists the web's movie sorts in its order", MOVIE, "movie"),
            ids("a series library gains the latest-episode sorts", SERIES, "series"),
            ids("the RT sorts appear only while the server shows them", series_rt, "series", shown=RT),
            ids("one shown RT source lists only its own sort", MOVIE[:8] + ["rating_rt_audience"] + MOVIE[8:],
                "movie", shown=["rt_audience"]),
            ids("a mixed library with no side lists what orders movies and series alike",
                ["title", "added_at", "release_date", "year", "content_rating", "runtime", "rating_imdb",
                 "rating_tmdb", "resolution", "bitrate", "progress", "date_viewed", "plays"], "video"),
            ids("an audiobook library lists its own sorts", AUDIOBOOK, "audiobook"),
            ids("personal lists and collections leave out the per-viewer sorts",
                [i for i in MOVIE if i not in ("progress", "date_viewed", "plays")], "movie", personalized=False),
            ids("favorites list every field but the per-viewer ones",
                ["title", "added_at", "release_date", "last_air_date", "latest_episode_added", "year",
                 "content_rating", "runtime", "rating_imdb", "rating_tmdb", "resolution", "bitrate", "author",
                 "narrator", "series"], "any", personalized=False),
            ids("a restored sort the library would not offer stays listed",
                MOVIE[:3] + ["latest_episode_added"] + MOVIE[3:], "movie", keep="latest_episode_added"),
            ids("a restored per-viewer sort stays listed on a collection", ["title", "added_at", "release_date",
                "year", "content_rating", "runtime", "rating_imdb", "rating_tmdb", "resolution", "bitrate", "plays"],
                "movie", personalized=False, keep="plays"),
            ("labels follow the web's names", "CatalogSortT_labels", ["series", True, RT, ""],
             ["Title", "Date Added", "Release Date", "Latest Episode Air Date", "Latest Episode Added", "Year",
              "Content Rating", "Duration", "IMDb Rating", "TMDB Rating", "RT Critic Rating", "RT Audience Rating",
              "Resolution", "Bitrate", "Progress", "Date Viewed", "Plays"]),
            ("reading lists say Date Read and Reads", "CatalogSortT_labels", ["ebook", True, [], ""],
             ["Title", "Date Added", "Release Date", "Year", "Duration", "Bitrate", "Progress", "Date Read", "Reads",
              "Author", "Series"]),
        ])

    def test_directions_and_aliases(self):
        check_cases(self, FILES, [
            ("title starts A-Z", "CatalogSortT_defaultDesc", ["title"], False),
            ("content rating starts ascending", "CatalogSortT_defaultDesc", ["content_rating"], False),
            ("latest episode added starts newest", "CatalogSortT_defaultDesc", ["latest_episode_added"], True),
            ("plays start with the most", "CatalogSortT_defaultDesc", ["plays"], True),
            ("title Z-A", "CatalogSort_directionLabel", ["title", True], "Z–A"),
            ("content rating reads A-Z", "CatalogSort_directionLabel", ["content_rating", False], "A–Z"),
            ("duration Longest", "CatalogSort_directionLabel", ["runtime", True], "Longest"),
            ("tmdb Lowest", "CatalogSort_directionLabel", ["rating_tmdb", False], "Lowest"),
            ("plays Most", "CatalogSort_directionLabel", ["plays", True], "Most"),
            ("plays Fewest", "CatalogSort_directionLabel", ["plays", False], "Fewest"),
            ("last air date Oldest", "CatalogSort_directionLabel", ["last_air_date", False], "Oldest"),
            ("an unknown field has none", "CatalogSort_directionLabel", ["popularity", True], ""),
            ("rating is IMDb rating", "CatalogSort_canonical", ["rating"], "rating_imdb"),
            ("a descending wire value", "CatalogSort_canonical", ["-recently_added"], "added_at"),
            ("sort_title is title", "CatalogSort_canonical", ["sort_title"], "title"),
            ("unknown sorts are dropped", "CatalogSort_canonical", ["popularity"], ""),
            ("a movie library", "CatalogSort_relevance", ["movies", ""], "movie"),
            ("a mixed library's Series side", "CatalogSort_relevance", ["mixed", "series"], "series"),
            ("a mixed library with no side", "CatalogSort_relevance", ["mixed", ""], "video"),
            ("a reading library", "CatalogSort_relevance", ["reading", ""], "ebook"),
            ("a music library reads as video", "CatalogSort_relevance", ["music", ""], "video"),
        ])

    def test_ratings_capability(self):
        check_cases(self, FILES, [
            ("available sources", "CatalogSort_parseRatings",
             [{"state": "available", "sources": [{"source": "imdb", "name": "IMDb"}, {"source": "RT_Critic"}]}],
             ["imdb", "rt_critic"]),
            ("another state shows none", "CatalogSort_parseRatings",
             [{"state": "not_configured", "sources": [{"source": "rt_critic"}]}], []),
            ("loose data shows none", "CatalogSort_parseRatings", [{"state": "available", "sources": "rt"}], []),
            ("no body shows none", "CatalogSort_parseRatings", [None], []),
        ])


if __name__ == "__main__":
    unittest.main()
