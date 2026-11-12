# SPDX-License-Identifier: AGPL-3.0-or-later
"""components/common/ProfileManage.brs: the picker's manage mode and Edit Profile (Silo Android TV's
TvProfileSelectionViewModel, TvEditProfileViewModel, HouseholdManagementSession and the server's
PATCH / DELETE /api/v2/profiles/{id} rules)."""
import unittest

from brs import check_cases

FILES = ["components/common/ProfileManage.brs", "components/common/Accounts.brs", "components/common/Utils.brs"]

LAURA = {"id": "p-owner", "name": "Laura", "has_pin": True, "is_primary": True}
SAM = {"id": "p-sam", "name": "Sam", "has_pin": False, "is_primary": False}
KIDS = {"id": "p-kids", "name": "Kids", "has_pin": True, "is_child": True, "max_content_rating": "PG"}
HOUSE = [LAURA, SAM, KIDS]


class Permissions(unittest.TestCase):
    def test_can_manage(self):
        f = "ProfileManage_canManage"
        check_cases(self, FILES, [
            ("a household with a primary", f, [HOUSE, False], True),
            ("no primary flagged, several profiles", f, [[SAM, KIDS], False], False),
            ("a single profile is the primary", f, [[SAM], False], True),
            ("a phone's borrowed profile", f, [HOUSE, True], False),
            ("no profiles", f, [[], False], False),
            ("not a list", f, [None, False], False),
            ("is_primary as text is not a primary", f, [[{"id": "a", "is_primary": "true"}, SAM], False], False),
        ])

    def test_can_delete(self):
        f = "ProfileManage_canDelete"
        check_cases(self, FILES, [
            ("the primary profile", f, [LAURA], False),
            ("another profile", f, [SAM], True),
            ("a child profile", f, [KIDS], True),
            ("no id", f, [{"name": "x"}], False),
            ("is_primary false", f, [{"id": "a", "is_primary": False}], True),
            ("not an object", f, [None], False),
        ])

    def test_can_add(self):
        f = "ProfileManage_canAdd"
        check_cases(self, FILES, [
            ("room", f, [3, 6], True),
            ("full", f, [6, 6], False),
            ("unknown limit", f, [9, -1], True),
        ])

    def test_headers(self):
        f = "ProfileManage_headers"
        check_cases(self, FILES, [
            ("with a token", f, [{"id": "p-owner", "token": "ptok-1"}], {"X-Profile-Id": "p-owner", "X-Profile-Token": "ptok-1"}),
            ("no PIN, no token", f, [{"id": "p-owner", "token": ""}], {"X-Profile-Id": "p-owner"}),
            ("no manager", f, [None], {}),
            ("no id", f, [{"token": "t"}], {}),
        ])

    def test_needs_verification(self):
        f = "ProfileManage_needsVerification"
        check_cases(self, FILES, [
            ("stale token", f, [403, "profile_verification_required"], True),
            ("unverified", f, [403, "profile_unverified"], True),
            ("other 403", f, [403, "forbidden"], False),
            ("401", f, [401, "profile_verification_required"], False),
        ])


class EditForm(unittest.TestCase):
    def test_name_taken(self):
        f = "ProfileManage_nameTaken"
        check_cases(self, FILES, [
            ("another profile's name, other case and spaces", f, [HOUSE, " sam ", "p-kids"], True),
            ("its own name", f, [HOUSE, "Sam", "p-sam"], False),
            ("a new name", f, [HOUSE, "Max", "p-sam"], False),
        ])

    def test_edit_problem(self):
        f = "ProfileManage_editProblem"
        check_cases(self, FILES, [
            ("fine", f, [HOUSE, "p-sam", "Samuel", ""], ""),
            ("unchanged name", f, [HOUSE, "p-sam", "Sam", ""], ""),
            ("blank", f, [HOUSE, "p-sam", "   ", ""], "name"),
            ("taken", f, [HOUSE, "p-sam", "laura", ""], "taken"),
            ("too long", f, [HOUSE, "p-sam", "x" * 65, ""], "long"),
            ("64 is fine", f, [HOUSE, "p-sam", "x" * 64, ""], ""),
            ("new PIN of four digits", f, [HOUSE, "p-sam", "Sam", "5678"], ""),
            ("new PIN too short", f, [HOUSE, "p-sam", "Sam", "56"], "pin"),
            ("new PIN not digits", f, [HOUSE, "p-sam", "Sam", "12a4"], "pin"),
        ])


def lower(d):
    return {k.lower(): v for k, v in d.items()}


class UpdateBody(unittest.TestCase):
    def test_body(self):
        f = "ProfileManage_updateBody"
        cases = [
            ("rename only", [SAM, " Samuel ", "keep", "", False], {"name": "Samuel", "is_child": False}),
            ("set a PIN", [SAM, "Sam", "set", "5678", False], {"name": "Sam", "pin": "5678", "is_child": False}),
            ("change a PIN", [LAURA, "Laura", "set", "4321", False], {"name": "Laura", "pin": "4321", "is_child": False}),
            ("remove a PIN sends null", [KIDS, "Kids", "remove", "", True], {"name": "Kids", "pin": None, "is_child": True}),
            ("remove on a profile without one sends nothing", [SAM, "Sam", "remove", "", False], {"name": "Sam", "is_child": False}),
            ("set without digits keeps it", [KIDS, "Kids", "set", "", True], {"name": "Kids", "is_child": True}),
            ("child on fills PG", [SAM, "Sam", "keep", "", True], {"name": "Sam", "is_child": True, "max_content_rating": "PG"}),
            ("child on keeps an existing ceiling", [dict(SAM, max_content_rating="PG-13"), "Sam", "keep", "", True],
             {"name": "Sam", "is_child": True}),
            ("child off clears the ceiling", [KIDS, "Kids", "keep", "", False], {"name": "Kids", "is_child": False, "max_content_rating": None}),
            ("child off clears a library restriction", [dict(KIDS, library_restrictions_enabled=True), "Kids", "keep", "", False],
             {"name": "Kids", "is_child": False, "max_content_rating": None, "library_restrictions_enabled": False}),
            ("an adult's ceiling stays", [dict(SAM, max_content_rating="R"), "Sam", "keep", "", False], {"name": "Sam", "is_child": False}),
        ]
        check_cases(self, FILES, [(n, f, a, (lambda e: lambda v: lower(v) == e)(e)) for n, a, e in cases])

    def test_describe(self):
        f = "ProfileManage_describe"
        check_cases(self, FILES, [
            ("rename", f, [{"name": "Secret Name", "is_child": False}], "name,child=off"),
            ("PIN set, never the digits", f, [{"name": "x", "pin": "5678", "is_child": True, "max_content_rating": "PG"}],
             "name,pin=set,child=on,rating"),
            ("PIN cleared", f, [{"name": "x", "pin": None, "is_child": False}], "name,pin=clear,child=off"),
        ])


class Outcomes(unittest.TestCase):
    def test_save(self):
        f = "ProfileManage_saveOutcome"
        check_cases(self, FILES, [
            ("saved", f, [200, ""], "saved"),
            ("stale token", f, [403, "profile_verification_required"], "verify"),
            ("no answer", f, [0, "timeout"], "network"),
            ("deleted meanwhile", f, [404, "not_found"], "gone"),
            ("name conflict", f, [409, "conflict"], "taken"),
            ("validation", f, [422, "validation_failed"], "refused"),
            ("forbidden", f, [403, "forbidden"], "refused"),
            ("server error", f, [500, ""], "failed"),
        ])

    def test_delete(self):
        f = "ProfileManage_deleteOutcome"
        check_cases(self, FILES, [
            ("deleted", f, [204, ""], "deleted"),
            ("already gone", f, [404, "not_found"], "gone"),
            ("the primary", f, [409, "primary_profile_protected"], "protected"),
            ("stale token", f, [403, "profile_unverified"], "verify"),
            ("no answer", f, [0, ""], "network"),
            ("server error", f, [500, ""], "failed"),
        ])


if __name__ == "__main__":
    unittest.main()
