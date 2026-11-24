# SPDX-License-Identifier: AGPL-3.0-or-later
"""Episode labels (Silo Android #1035, EpisodeLabel.kt; components/common/EpisodeLabel.brs).

Sportarr numbers a league's events S<year>E<n>; the server marks such a series
`episode_labels: "air_date"` and sends `air_date` on its episodes, and every surface then shows
the air date where the code went. An undated episode (or one whose date is not a real day) keeps
its code; other series keep their codes in each surface's spelling."""
import unittest

from brs import check_cases

FILES = ["components/common/EpisodeLabel.brs", "components/common/Content.brs", "components/common/Utils.brs"]
DE = {"appLocale": "de", "strings": {"Nov": "Nov.", "Feb": "Feb."}}


def ep(season=1, episode=2, title="Pilot", labels=None, air=None):
    d = {"type": "episode", "season_number": season, "episode_number": episode, "title": title}
    if labels is not None:
        d["episode_labels"] = labels
    if air is not None:
        d["air_date"] = air
    return d


GAME = ep(2026, 296, "Lakers at Celtics", "air_date", "2026-11-20")


class Flags(unittest.TestCase):
    def test_cases(self):
        check_cases(self, FILES, [
            ("air_date labels by date", "EpLabel_byAirDate", ["air_date"], True),
            ("absent labels use numbers", "EpLabel_byAirDate", [None], False),
            ("another value uses numbers", "EpLabel_byAirDate", ["numbers"], False),
            ("a different spelling is not air_date (exact, as Android)", "EpLabel_byAirDate", ["AIR_DATE"], False),
            ("a non-string is not air_date", "EpLabel_byAirDate", [True], False),
        ])


class CalendarDate(unittest.TestCase):
    def test_cases(self):
        f = "EpLabel_calendarDate"
        check_cases(self, FILES, [
            ("a date", f, ["2026-11-20"], "2026-11-20"),
            ("a timestamp's date part", f, ["2026-11-20T19:30:00Z"], "2026-11-20"),
            ("a spaced timestamp's date part", f, ["2026-11-20 19:30:00"], "2026-11-20"),
            ("surrounding spaces", f, [" 2026-11-20 "], "2026-11-20"),
            ("Feb 30 is not a day", f, ["2026-02-30"], ""),
            ("Feb 29 in a leap year", f, ["2024-02-29"], "2024-02-29"),
            ("Feb 29 in a common year", f, ["2026-02-29"], ""),
            ("1900 is not a leap year", f, ["1900-02-29"], ""),
            ("2000 is a leap year", f, ["2000-02-29"], "2000-02-29"),
            ("April 31", f, ["2026-04-31"], ""),
            ("month 13", f, ["2026-13-01"], ""),
            ("day 0", f, ["2026-11-00"], ""),
            ("year 0", f, ["0000-11-20"], ""),
            ("not a date", f, ["soon"], ""),
            ("empty", f, [""], ""),
            ("missing", f, [None], ""),
            ("a number", f, [20261120], ""),
        ])


class Text(unittest.TestCase):
    def test_cases(self):
        t = "EpLabel_text"
        check_cases(self, FILES, [
            ("a game shows its date", t, [2026, 296, "air_date", "2026-11-20", "tag"], "Nov 20, 2026"),
            ("the date in every style", t, [2026, 296, "air_date", "2026-11-20", "dotted"], "Nov 20, 2026"),
            ("a timestamp shows its UTC date", t, [2026, 296, "air_date", "2026-11-20T23:30:00Z", "short"], "Nov 20, 2026"),
            ("the date in the interface language", t, [2026, 296, "air_date", "2026-11-20", "tag"], "Nov. 20, 2026", {"global": DE}),
            ("an undated game keeps its code", t, [2026, 296, "air_date", None, "tag"], "S2026E296"),
            ("an unreadable date keeps the code", t, [2026, 296, "air_date", "2026-02-30", "short"], "S2026 · E296"),
            ("a numbered series ignores its air date", t, [1, 2, None, "2026-11-20", "tag"], "S01E02"),
            ("tag", t, [1, 2, None, None, "tag"], "S01E02"),
            ("short", t, [1, 2, None, None, "short"], "S1 · E2"),
            ("spaced", t, [1, 2, None, None, "spaced"], "S1 E2"),
            ("dotted", t, [1, 2, None, None, "dotted"], "S1·E2"),
            ("default style is the tag", t, [3, 10, None, None], "S03E10"),
            ("no numbers, no code", t, [None, None, None, None, "short"], ""),
        ])


class Items(unittest.TestCase):
    def test_cases(self):
        o = "EpLabel_of"
        check_cases(self, FILES, [
            ("a game card", o, [GAME, "tag"], "Nov 20, 2026"),
            ("a numbered card", o, [ep(), "dotted"], "S1·E2"),
            ("the series' labels when the episode has none", o, [ep(air="2026-11-20"), "short", "air_date"], "Nov 20, 2026"),
            ("the episode's own labels win", o, [ep(labels="numbers", air="2026-11-20"), "short", "air_date"], "S1 · E2"),
            ("no fallback, no date", o, [ep(air="2026-11-20"), "short"], "S1 · E2"),
            ("not an item", o, [None, "tag"], ""),
            ("labels of an item", "EpLabel_labelsOf", [GAME, None], "air_date"),
            ("labels fall back", "EpLabel_labelsOf", [ep(), "air_date"], "air_date"),
            ("labels of nothing", "EpLabel_labelsOf", [None, None], None),
        ])


class Surfaces(unittest.TestCase):
    """The surfaces that route through the helper: the episode rail's caption, the card and the
    Home marquee meta line."""

    def test_cases(self):
        c = "Content_episodeCaptionTitle"
        check_cases(self, FILES, [
            ("rail: a numbered episode", c, [ep()], "S01E02 · Pilot"),
            ("rail: a game's title leads alone", c, [GAME], "Lakers at Celtics"),
            ("rail: the series' labels apply", c, [ep(2026, 296, "Lakers at Celtics", air="2026-11-20"), "air_date"], "Lakers at Celtics"),
            ("rail: an untitled game shows its date", c, [ep(2026, 296, "", "air_date", "2026-11-20")], "Nov 20, 2026"),
            ("rail: an untitled, undated game keeps its code", c, [ep(2026, 296, " ", "air_date")], "S2026E296"),
            ("rail: an untitled numbered episode", c, [ep(title="")], "S01E02"),
            ("marquee: a game", "Content_metaLine", [dict(GAME, episode_title="Lakers at Celtics")], "Nov 20, 2026 · Lakers at Celtics"),
            ("marquee: a numbered episode", "Content_metaLine", [dict(ep(), episode_title="Pilot")], "S1 E2 · Pilot"),
        ])


if __name__ == "__main__":
    unittest.main()
