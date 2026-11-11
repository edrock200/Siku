# SPDX-License-Identifier: AGPL-3.0-or-later
"""Change Account at launch and the profile menu's profile row (Silo Android #880 / #881; adapted
from Silo-Server/silo-roku 4a22785 and 431c1f1, AGPL-3.0): where a launch that asks starts
(ProfileLaunch_startScreen), the row the menu shows (Accounts_profileMenuRow, a port of Android's
ProfileMenuRowTest), the limit read from the profile list, the household's primary profile and the
New Profile form's rules and outcomes."""
import unittest

from brs import check_cases

FILES = ["components/common/Accounts.brs", "components/common/ProfileLaunch.brs",
         "components/common/Session.brs", "components/common/Utils.brs"]


class LaunchStart(unittest.TestCase):
    def test_start_screen(self):
        f = "ProfileLaunch_startScreen"
        check_cases(self, FILES, [
            ("two accounts and the launch asks: Change Account", f, [True, 2, False], "ChangeAccountScreen"),
            ("more accounts, other servers included", f, [True, 5, False], "ChangeAccountScreen"),
            ("one saved account behaves as before", f, [True, 1, False], "ProfileScreen"),
            ("no account counted: the picker", f, [True, 0, False], "ProfileScreen"),
            ("a launch that does not ask (Automatic)", f, [False, 3, False], "ProfileScreen"),
            ("a content link waiting for a profile keeps the picker route", f, [True, 3, True], "ProfileScreen"),
        ])


class MenuRow(unittest.TestCase):
    def test_row(self):
        f = "Accounts_profileMenuRow"
        check_cases(self, FILES, [
            ("several profiles: Switch Profile", f, [3, 6, False], "switch_profile"),
            ("several profiles at the limit still switch", f, [2, 2, False], "switch_profile"),
            ("no list read yet (-1): Switch Profile", f, [-1, -1, False], "switch_profile"),
            ("no entry at all: Switch Profile", f, [None, None, False], "switch_profile"),
            ("zero profiles counts as not read", f, [0, 6, False], "switch_profile"),
            ("one profile with room: Add Profile", f, [1, 3, False], "add_profile"),
            ("one profile, limit unknown (-1): Add Profile", f, [1, -1, False], "add_profile"),
            ("one profile, limit never stored: Add Profile", f, [1, None, False], "add_profile"),
            ("one profile, limit 1: no row", f, [1, 1, False], "none"),
            ("one profile, limit 0: no row", f, [1, 0, False], "none"),
            ("a handoff session shows no row", f, [3, 6, True], "none"),
            ("a handoff session with one profile shows no row", f, [1, -1, True], "none"),
            ("counts stored as strings read as numbers", f, ["1", "4", False], "add_profile"),
        ])

    def test_max_profiles_of(self):
        f = "Accounts_maxProfilesOf"
        check_cases(self, FILES, [
            ("the server's limit", f, [{"items": [], "max_profiles": 4}], 4),
            ("a limit of one", f, [{"items": [], "max_profiles": 1}], 1),
            ("a numeric string", f, [{"items": [], "max_profiles": "5"}], 5),
            ("an older server sends none", f, [{"items": []}], -1),
            ("null", f, [{"items": [], "max_profiles": None}], -1),
            ("garbage", f, [{"items": [], "max_profiles": "lots"}], -1),
            ("a negative number", f, [{"items": [], "max_profiles": -3}], -1),
            ("not an object", f, [None], -1),
        ])


class Primary(unittest.TestCase):
    def test_household_primary(self):
        f = "Accounts_householdPrimary"
        laura = {"id": "p-owner", "name": "Laura", "is_primary": True, "has_pin": True}
        sam = {"id": "p-sam", "name": "Sam", "is_primary": False}
        check_cases(self, FILES, [
            ("the one marked is_primary", f, [[sam, laura]], lambda v: v["id"] == "p-owner"),
            ("an only profile without the mark", f, [[{"id": "p-1", "name": "One"}]], lambda v: v["id"] == "p-1"),
            ("several and none marked: none", f, [[sam, {"id": "p-2", "name": "Two"}]], None),
            ("a string is_primary is not the mark", f, [[{"id": "p-3", "is_primary": "true"}, sam]], None),
            ("an empty list", f, [[]], None),
            ("no list", f, [None], None),
        ])


class NewProfileForm(unittest.TestCase):
    def test_problem(self):
        f = "Accounts_newProfileProblem"
        check_cases(self, FILES, [
            ("a name and no PIN", f, ["Ana", ""], ""),
            ("a name and four digits", f, ["Ana", "0420"], ""),
            ("an empty name", f, ["", ""], "name"),
            ("spaces only", f, ["   ", "1234"], "name"),
            ("three digits", f, ["Ana", "123"], "pin"),
            ("five digits", f, ["Ana", "12345"], "pin"),
            ("letters in the PIN", f, ["Ana", "12a4"], "pin"),
        ])

    def test_body(self):
        f = "Accounts_newProfileBody"
        check_cases(self, FILES, [
            ("the trimmed name only", f, ["  Ana ", "", False], {"name": "Ana"}),
            ("with a PIN", f, ["Ana", "1234", False], {"name": "Ana", "pin": "1234"}),
            ("a child profile gets the PG ceiling", f, ["Kid", "", True],
             {"name": "Kid", "is_child": True, "max_content_rating": "PG"}),
        ])

    def test_outcome(self):
        f = "Accounts_createOutcome"
        check_cases(self, FILES, [
            ("201", f, [201, ""], "created"),
            ("any 2xx", f, [200, ""], "created"),
            ("no answer: it may exist", f, [0, "network"], "unconfirmed"),
            ("the primary's proof refused", f, [403, "profile_verification_required"], "verify"),
            ("another 403", f, [403, "forbidden"], "refused"),
            ("the household is full", f, [409, "profile_limit_reached"], "refused"),
            ("a rejected member", f, [422, "validation_failed"], "refused"),
            ("a server error", f, [500, ""], "failed"),
        ])


if __name__ == "__main__":
    unittest.main()
