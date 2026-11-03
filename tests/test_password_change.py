# SPDX-License-Identifier: AGPL-3.0-or-later
"""Temporary passwords (Silo Android #790): the 403 password_change_required refusal is recognised
(PasswordChange_isRequired) and Http_problem replaces the server's protocol detail with text a
person can act on."""
import unittest

from brs import check_cases

FILES = ["components/common/PasswordChange.brs", "components/tasks/Http.brs", "components/common/Utils.brs"]
TYPE = "https://siloserver.org/docs/api/v2/problems/password_change_required"
PICKER = "Your password needs to be reset. Use the Silo mobile app or website to set a new one, then come back."
OTHER = ("An admin set a temporary password for this account. Set a new one in the Silo mobile app "
         "or on the website, then sign in again.")


def refusal(status=403, code="password_change_required"):
    return {"ok": False, "status": status, "error": {"code": code, "title": "t", "detail": "d"}}


class PasswordChange(unittest.TestCase):
    def test_detection(self):
        cases = [
            ("403 password_change_required", refusal(), True),
            ("status as a string", refusal(status="403"), True),
            ("another 403", refusal(code="profile_verification_required"), False),
            ("401 with the code", refusal(status=401), False),
            ("network failure", {"ok": False, "status": 0, "error": {"code": "network"}}, False),
            ("no error object", {"ok": False, "status": 403}, False),
            ("error not an object", {"ok": False, "status": 403, "error": "password_change_required"}, False),
            ("success", {"ok": True, "status": 200, "data": {}}, False),
        ]
        specs = [(n, "PasswordChange_isRequired", [r], exp) for n, r, exp in cases]
        specs.append(("invalid", "PasswordChange_isRequired", [None], False))
        check_cases(self, FILES, specs)

    def test_messages(self):
        check_cases(self, FILES, [
            ("picker", "PasswordChange_pickerMessage", [], PICKER),
            ("other screens", "PasswordChange_message", [], OTHER),
        ])

    def test_problem_text(self):
        body = {"type": TYPE, "title": "Password change required", "status": 403,
                "detail": "Change the temporary password with POST /api/v2/account/password, then refresh the session."}
        plain = {"type": "https://siloserver.org/docs/api/v2/problems/forbidden", "title": "Forbidden", "detail": "No."}
        by_code = {"code": "password_change_required", "detail": "protocol"}
        check_cases(self, FILES, [
            ("type ending in the code", "Http_problem", [403, body, None],
             {"code": "password_change_required", "title": OTHER, "detail": OTHER}),
            ("code field only", "Http_problem", [403, by_code, None],
             {"code": "password_change_required", "title": OTHER, "detail": OTHER}),
            ("another problem keeps its text", "Http_problem", [403, plain, None],
             {"code": "forbidden", "title": "Forbidden", "detail": "No."}),
        ])


if __name__ == "__main__":
    unittest.main()
