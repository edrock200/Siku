# SPDX-License-Identifier: AGPL-3.0-or-later
"""Series playback return (Silo Android #802, SeriesReturn.brs): the episode a series page lands on
when the player it opened closes. The next episode only after the credits or the end, never a
shuffle pick, only under the identity that launched the player; the page loads the return's season
first when it shows another one."""
import unittest

from brs import check_cases

FILES = ["components/common/SeriesReturn.brs", "components/common/Utils.brs"]

SESSION = {"serverUrl": "http://silo.example:8097", "serverId": "srv", "profileId": "p1",
           "user": {"id": "u1"}, "accessToken": "acc"}
ID = "http://silo.example:8097|srv|u1|p1|own"
NEXT = {"content_id": "ep6", "season_number": 1, "episode_number": 6}
NEXT_SEASON = {"content_id": "s2e1", "season_number": "2", "episode_number": "1"}


def state(**kw):
    st = {"seriesId": "show", "itemId": "ep5", "seasonNumber": 1, "episodeNumber": 5,
          "nextEpisode": NEXT, "shuffle": False, "reached": False,
          "launchIdentity": ID, "identity": ID}
    st.update(kw)
    return st


def target(episode, season, number, reason):
    def check(v):
        return (isinstance(v, dict) and v["kind"] == "series_return" and v["seriesId"] == "show"
                and v["episodeId"] == episode and v["seasonNumber"] == season
                and v["episodeNumber"] == number and v["reason"] == reason and v["identity"] == ID)
    return check


class SeriesReturn(unittest.TestCase):
    def test_identity(self):
        f = "SeriesReturn_identity"
        borrowed = dict(SESSION, temporary=True)
        check_cases(self, FILES, [
            ("signed in", f, [SESSION], ID),
            ("a phone's borrowed profile is its own identity", f, [borrowed], ID.replace("|own", "|borrowed")),
            ("no profile", f, [dict(SESSION, profileId="")], ""),
            ("no session", f, [None], ""),
        ])

    def test_target(self):
        f = "SeriesReturn_target"
        check_cases(self, FILES, [
            ("finished: the next episode", f, [state(reached=True)], target("ep6", 1, 6, "finished")),
            ("next season, numbers as strings", f, [state(reached=True, nextEpisode=NEXT_SEASON)],
             target("s2e1", 2, 1, "finished")),
            ("Up Next opened mid-episode: stays", f, [state(reached=False)], target("ep5", 1, 5, "on_screen")),
            ("finished, nothing after it", f, [state(reached=True, nextEpisode=None)], target("ep5", 1, 5, "on_screen")),
            ("shuffle lands on the episode on screen", f, [state(reached=True, shuffle=True)],
             target("ep5", 1, 5, "shuffle")),
            ("missing flags read as false", f, [state(reached=None, shuffle=None)], target("ep5", 1, 5, "on_screen")),
            ("a next episode without an id", f, [state(reached=True, nextEpisode={"season_number": 1})],
             target("ep5", 1, 5, "on_screen")),
            ("missing numbers", f, [state(seasonNumber=None, episodeNumber=None)], target("ep5", -1, -1, "on_screen")),
            ("another identity now", f, [state(identity="other")], None),
            ("signed out", f, [state(identity="")], None),
            ("no series", f, [state(seriesId="")], None),
        ])

    def test_accept(self):
        f = "SeriesReturn_accept"
        t = {"kind": "series_return", "seriesId": "show", "episodeId": "ep6", "seasonNumber": 1,
             "episodeNumber": 6, "reason": "finished", "identity": ID}
        same = lambda v: isinstance(v, dict) and v["episodeId"] == "ep6"  # noqa: E731
        check_cases(self, FILES, [
            ("this series page", f, [t, "series", "show", ID], same),
            ("type is case-insensitive", f, [t, "Series", "show", ID], same),
            ("an episode page", f, [t, "episode", "show", ID], None),
            ("another series", f, [t, "series", "other", ID], None),
            ("another identity", f, [t, "series", "show", "x"], None),
            ("another result", f, [{"kind": "x", "seriesId": "show", "episodeId": "e", "identity": ID}, "series", "show", ID], None),
            ("no result", f, [None, "series", "show", ID], None),
        ])

    def test_season_and_index(self):
        seasons = [{"season_number": 0}, {"season_number": 1}, {"season_number": "2"}]
        eps = [{"content_id": "a"}, {"content_id": "ep6"}]
        check_cases(self, FILES, [
            ("another listed season loads", "SeriesReturn_seasonToLoad", [{"seasonNumber": 2}, 1, seasons], 2),
            ("the selected season stays", "SeriesReturn_seasonToLoad", [{"seasonNumber": 1}, 1, seasons], -1),
            ("an unlisted season stays", "SeriesReturn_seasonToLoad", [{"seasonNumber": 5}, 1, seasons], -1),
            ("before the seasons were selected", "SeriesReturn_seasonToLoad", [{"seasonNumber": 2}, None, seasons], 2),
            ("no season number", "SeriesReturn_seasonToLoad", [{"seasonNumber": -1}, 1, seasons], -1),
            ("no return", "SeriesReturn_seasonToLoad", [None, 1, seasons], -1),
            ("episode found", "SeriesReturn_indexIn", [{"episodeId": "ep6"}, eps], 1),
            ("episode missing", "SeriesReturn_indexIn", [{"episodeId": "zz"}, eps], -1),
            ("tag", "SeriesReturn_tag", [{"seasonNumber": 2, "episodeNumber": 1}], "2x1"),
            ("tag without numbers", "SeriesReturn_tag", [{"seasonNumber": -1, "episodeNumber": -1}], "?x?"),
        ])


if __name__ == "__main__":
    unittest.main()
