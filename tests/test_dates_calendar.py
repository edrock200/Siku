# SPDX-License-Identifier: AGPL-3.0-or-later
"""Dates and the Calendar's time zone, badges and air time.

Roku OS 15.3.4 reads a date-only ISO string ("2024-05-01") as 1970, so Time_isoForParse appends
midnight UTC and dates are formatted in UTC (no day shift in any zone). brs-engine parses date-only
strings itself, so the normalised string is tested directly as well as the formatted result."""
import unittest

from brs import check_cases

UTILS = ["components/common/Utils.brs"]
CAL = ["components/common/CalendarFormat.brs", "components/common/Utils.brs"]


class Dates(unittest.TestCase):
    def test_cases(self):
        check_cases(self, UTILS, [
            ("date only gets midnight UTC", "Time_isoForParse", ["2024-05-01"], "2024-05-01T00:00:00Z"),
            ("timestamp unchanged", "Time_isoForParse", ["2024-05-01T20:00:00Z"], "2024-05-01T20:00:00Z"),
            ("invalid is empty", "Time_isoForParse", [None], ""),
            ("date only detected", "Time_isDateOnly", ["1980-12-31"], True),
            ("timestamp is not date only", "Time_isDateOnly", ["1980-12-31T00:00:00Z"], False),
            ("letters are not a date", "Time_isDateOnly", ["1980-ab-31"], False),
            ("a number is not a date", "Time_isDateOnly", [19801231], False),
            ("long date", "Time_longDate", ["2024-05-01"], "May 1, 2024"),
            ("long date, year end", "Time_longDate", ["1999-12-31"], "Dec 31, 1999"),
            ("long date from a timestamp (UTC day)", "Time_longDate", ["2024-05-01T23:30:00Z"], "May 1, 2024"),
            ("unreadable date", "Time_longDate", ["soon"], ""),
            ("empty date", "Time_longDate", [""], ""),
        ])


class CalendarZone(unittest.TestCase):
    def test_cases(self):
        z = "CalFmt_ianaZone"
        check_cases(self, CAL, [
            ("US Eastern", z, ["US/Eastern", -300], "America/New_York"),
            ("UK", z, ["Europe/United Kingdom", 0], "Europe/London"),
            ("Saskatchewan", z, ["Canada/Central Standard", -360], "America/Regina"),
            ("Central European Time", z, ["Europe/Central European Time", 60], "Europe/Paris"),
            ("Greece/Finland", z, ["Europe/Greece/Finland", 120], "Europe/Athens"),
            ("an IANA name passes", z, ["Asia/Tokyo", 540], "Asia/Tokyo"),
            ("unknown name, whole hours east", z, ["Other/Somewhere Nice", 120], "Etc/GMT-2"),
            ("unknown name, whole hours west", z, ["Mystery", -300], "Etc/GMT+5"),
            ("unknown name at UTC", z, ["", 0], "Etc/UTC"),
            ("half-hour offset sends none", z, ["Asia/Kolkata time", 330], ""),
            ("Newfoundland by name", z, ["Canada/Newfoundland", -210], "America/St_Johns"),
        ])


class CalendarCards(unittest.TestCase):
    def test_cases(self):
        a = "CalFmt_airTime"
        check_cases(self, CAL, [
            ("all known badges in order", "CalFmt_badgeLabels", [["season_premiere", "finale"]], ["NEW SEASON", "FINALE"]),
            ("unknown badges skipped, duplicates once", "CalFmt_badgeLabels", [["x", "series_finale", "finale", "series_premiere"]], ["FINALE", "PREMIERE"]),
            ("no badges", "CalFmt_badgeLabels", [None], []),
            ("movie home releases (Silo Android #722)", "CalFmt_badgeLabels", [["digital"]], ["DIGITAL"]),
            ("physical release", "CalFmt_badgeLabels", [["PHYSICAL"]], ["PHYSICAL"]),
            ("every label the server sends", "CalFmt_badgeLabels",
             [["series_premiere", "season_premiere", "finale", "digital", "physical", "theatrical", "digital"]],
             ["PREMIERE", "NEW SEASON", "FINALE", "DIGITAL", "PHYSICAL"]),
            ("air_at in New York (EDT)", a, [{"air_at": "2026-06-10T01:00:00Z"}, False, -4 * 3600], "9:00 PM"),
            ("air_at with an offset", a, [{"air_at": "2026-06-09T21:05:00-04:00"}, True, 0], "01:05"),
            ("air_at with fractions", a, [{"air_at": "2026-06-09T12:30:00.000Z"}, False, 0], "12:30 PM"),
            ("midnight 12 h", a, [{"air_at": "2026-06-09T00:10:00Z"}, False, 0], "12:10 AM"),
            ("wall clock air_time", a, [{"air_time": "20:15"}, False, 0], "8:15 PM"),
            ("wall clock 24 h", a, [{"air_time": "08:05:00"}, True, 0], "08:05"),
            ("midnight air_time means no time", a, [{"air_time": "00:00"}, False, 0], ""),
            ("nothing", a, [{}, False, 0], ""),
            ("bad air_at falls back to air_time", a, [{"air_at": "tonight", "air_time": "21:00"}, False, 0], "9:00 PM"),
            ("instant parse", "CalFmt_instantSeconds", ["1970-01-02T00:00:00+01:00"], 82800),
            ("instant parse rejects junk", "CalFmt_instantSeconds", ["2026-06-09 21:00"], -1),
        ])


if __name__ == "__main__":
    unittest.main()
