# SPDX-License-Identifier: AGPL-3.0-or-later
"""Episode parent artwork (Silo Android #711): an episode's hero and full-screen backgrounds prefer
its series backdrop, poster-shaped episode cards its season or series poster, spoiler protection
keeps that art (it is never a still), older servers keep the card's own art, and the Home cache
never stores the new URLs. Also the refused Mark as Watched toast (Silo Android #706)."""
import json
import unittest

from brs import check_cases, glob

FILES = ["components/common/Spoilers.brs", "components/common/Utils.brs"]
CACHE = ["components/common/HomeCache.brs", "components/common/Utils.brs"]
ACTIONS = ["components/widgets/HomeCardActions.brs", "components/common/Api.brs", "components/common/Content.brs",
           "components/common/Utils.brs"]

HIDE = {"global": glob({"catalog.hide_unwatched_episode_images": True})}
SHOW = {"global": glob({})}

EPISODE = {
    "content_id": "episode:orbital-s01e02", "type": "episode", "title": "Chapter 2",
    "still_url": "/img/still.jpg", "backdrop_url": "/img/still-as-backdrop.jpg", "poster_url": "/img/still-as-poster.jpg",
    "backdrop_is_episode_still": True, "poster_is_episode_still": True,
    "user_state": {"played": False},
}
PARENT = dict(EPISODE, series_backdrop_url="/img/series-backdrop.jpg?exp=1&sig=2", series_backdrop_thumbhash="SB",
              series_poster_url="/img/series-poster.jpg", series_poster_thumbhash="SP",
              season_poster_url="/img/season-poster.jpg", season_poster_thumbhash="SN")
MOVIE = {"content_id": "movie:x", "type": "movie", "backdrop_url": "/img/movie-backdrop.jpg", "poster_url": "/img/movie-poster.jpg",
         "series_backdrop_url": "/img/ignored.jpg", "season_poster_url": "/img/ignored.jpg"}


class HeroBackdrop(unittest.TestCase):
    def test_hero(self):
        check_cases(self, FILES, [
            ("series backdrop wins", "Spoilers_heroBackdropUrl", [PARENT], PARENT["series_backdrop_url"], SHOW),
            ("kept under spoiler protection", "Spoilers_heroBackdropUrl", [PARENT], PARENT["series_backdrop_url"], HIDE),
            ("older server: own backdrop", "Spoilers_heroBackdropUrl", [EPISODE], EPISODE["backdrop_url"], SHOW),
            ("older server under protection: nothing", "Spoilers_heroBackdropUrl", [EPISODE], "", HIDE),
            ("blank series backdrop falls back", "Spoilers_heroBackdropUrl", [dict(PARENT, series_backdrop_url="  ")],
             EPISODE["backdrop_url"], SHOW),
            ("only episodes use it", "Spoilers_heroBackdropUrl", [MOVIE], MOVIE["backdrop_url"], HIDE),
            ("type case-insensitive", "Spoilers_heroBackdropUrl", [dict(PARENT, type="Episode")],
             PARENT["series_backdrop_url"], HIDE),
            ("not a card", "Spoilers_heroBackdropUrl", [None], "", SHOW),
        ])

    def test_poster(self):
        check_cases(self, FILES, [
            ("season poster first", "Spoilers_posterUrl", [PARENT], PARENT["season_poster_url"], HIDE),
            ("then series poster", "Spoilers_posterUrl", [dict(PARENT, season_poster_url=None)],
             PARENT["series_poster_url"], HIDE),
            ("older server: own poster", "Spoilers_posterUrl", [EPISODE], EPISODE["poster_url"], SHOW),
            ("older server under protection: nothing", "Spoilers_posterUrl", [EPISODE], "", HIDE),
            ("movie keeps its poster", "Spoilers_posterUrl", [MOVIE], MOVIE["poster_url"], SHOW),
        ])

    def test_wide_card_falls_back_to_series_backdrop(self):
        check_cases(self, FILES, [
            ("still when shown", "Spoilers_wideImageUrl", [PARENT], PARENT["still_url"], SHOW),
            ("series backdrop when every slot is a hidden still", "Spoilers_wideImageUrl", [PARENT],
             PARENT["series_backdrop_url"], HIDE),
            ("older server: default artwork", "Spoilers_wideImageUrl", [EPISODE], "", HIDE),
        ])

    def test_up_next_background(self):
        plain = dict(EPISODE, content_id="episode:b")
        check_cases(self, FILES, [
            ("first card's series backdrop", "Spoilers_firstBackdropUrl", [[PARENT, MOVIE]], PARENT["series_backdrop_url"], HIDE),
            ("hidden backdrop skipped", "Spoilers_firstBackdropUrl", [[plain, MOVIE]], MOVIE["backdrop_url"], HIDE),
            ("unprotected: first card's backdrop", "Spoilers_firstBackdropUrl", [[plain, MOVIE]], plain["backdrop_url"], SHOW),
            ("nothing visible", "Spoilers_firstBackdropUrl", [[plain]], "", HIDE),
            ("no cards", "Spoilers_firstBackdropUrl", [[]], "", HIDE),
        ])


class HomeCacheLeavesParentArtworkOut(unittest.TestCase):
    def test_trim(self):
        check_cases(self, CACHE, [
            ("no series/season URLs or thumbhashes", "HomeCache_trimCard", [PARENT],
             lambda v: not any(k.startswith(("series_poster", "series_backdrop", "season_poster")) for k in v)
             and "sig=" not in json.dumps(v)),
        ])


class WatchedFailureToast(unittest.TestCase):
    def test_text(self):
        detail = {"ok": False, "status": 409, "error": {"code": "conflict", "title": "Conflict", "detail": "Managed by your admin."}}
        title_only = {"ok": False, "status": 403, "error": {"code": "forbidden", "title": "Not allowed", "detail": ""}}
        bare = {"ok": False, "status": 500, "error": {"code": "", "title": "Something went wrong (500)", "detail": ""}}
        offline = {"ok": False, "status": 0, "error": {"code": "network", "title": "Can't reach the server", "detail": "timeout"}}
        check_cases(self, ACTIONS, [
            ("problem detail", "CardActions_watchedFailureText", [True, detail], "Couldn't mark as watched. Managed by your admin."),
            ("title when no detail", "CardActions_watchedFailureText", [False, title_only], "Couldn't mark as unwatched. Not allowed"),
            ("generic for a bare 500", "CardActions_watchedFailureText", [True, bare], "Couldn't mark as watched. Try again."),
            ("offline", "CardActions_watchedFailureText", [True, offline],
             "Couldn't mark as watched. Can't reach the server. Check your connection."),
            ("no response", "CardActions_watchedFailureText", [False, None], "Couldn't mark as unwatched. Try again."),
            ("string status", "CardActions_watchedFailureText", [True, dict(detail, status="409")],
             "Couldn't mark as watched. Managed by your admin."),
        ])

    def test_rollback_patch(self):
        card = {"content_id": "episode:x", "type": "episode", "position_seconds": 900, "duration_seconds": 1800,
                "user_state": {"played": False}}
        check_cases(self, ACTIONS, [
            ("restores mark and progress", "CardActions_rollbackPatch", [card],
             lambda v: v["watched"] is False and abs(v["progress"] - 0.5) < 1e-6 and v["contentId"] == "episode:x"),
            ("watched card", "CardActions_rollbackPatch", [dict(card, user_state={"played": True})],
             lambda v: v["watched"] is True),
        ])


if __name__ == "__main__":
    unittest.main()
