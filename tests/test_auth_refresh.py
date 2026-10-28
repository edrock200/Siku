# SPDX-License-Identifier: AGPL-3.0-or-later
"""Token refresh (AuthTask): only a definite "refresh token invalid" answer signs the user out, and
a request waits for AuthTask longer than one refresh can take (docs/api-spec.md §2.4)."""
import unittest

from brs import call, check_cases

AUTH = ["components/tasks/AuthTask.brs", "components/common/Utils.brs"]
HTTP = ["components/tasks/Http.brs", "components/common/Utils.brs"]
PROBE = ["components/tasks/ProbeTask.brs", "components/tasks/Http.brs", "components/common/Utils.brs"]


class RefreshOutcome(unittest.TestCase):
    def test_outcomes(self):
        tok = {"access_token": "acc-1", "refresh_token": "ref-1", "expires_in": 3600}
        check_cases(self, AUTH, [
            ("token response", "AuthTask_outcome", [200, tok], "ok"),
            ("400 invalid_grant", "AuthTask_outcome", [400, {"type": "https://silo/problems/invalid_grant"}], "rejected"),
            ("401 session_expired", "AuthTask_outcome", [401, {"type": "https://silo/problems/session_expired"}], "rejected"),
            ("401 without a body", "AuthTask_outcome", [401, None], "rejected"),
            ("502 from a proxy keeps the session", "AuthTask_outcome", [502, None], "retry"),
            ("500 keeps the session", "AuthTask_outcome", [500, None], "retry"),
            ("504 keeps the session", "AuthTask_outcome", [504, None], "retry"),
            ("503 provider_unavailable", "AuthTask_outcome", [503, {"type": "x/provider_unavailable"}], "retry"),
            ("429", "AuthTask_outcome", [429, None], "retry"),
            ("403 (a proxy or firewall) keeps the session", "AuthTask_outcome", [403, None], "retry"),
            ("no answer", "AuthTask_outcome", [0, None], "retry"),
            ("200 with an HTML page (captive portal)", "AuthTask_outcome", [200, None], "retry"),
            ("200 JSON without a token", "AuthTask_outcome", [200, {"status": "ok"}], "retry"),
            ("200 with an empty token", "AuthTask_outcome", [200, {"access_token": ""}], "retry"),
            ("200 with a numeric token", "AuthTask_outcome", [200, {"access_token": 5}], "retry"),
            ("status as a string", "AuthTask_outcome", ["401", None], "rejected"),
        ])

    def test_wait_covers_the_worst_case(self):
        worst = call(AUTH, "AuthTask_worstCaseSeconds", [])
        wait = call(HTTP, "Auth_waitSeconds", [])
        self.assertEqual(worst, 41)
        # One refresh already running ahead of this one, plus its own.
        self.assertGreater(wait, 2 * worst)


class ProbeHeaders(unittest.TestCase):
    """The speed test sends the PIN proof of a protected profile (it runs outside ApiTask)."""

    def test_headers(self):
        base = {"deviceId": "dev", "accessToken": "acc-1", "serverUrl": "http://s"}
        pin = dict(base, profileId="p-kids", profileToken="ptok-1")
        plain = dict(base, profileId="p-owner", profileToken="")
        none = dict(base, profileId="")
        check_cases(self, PROBE, [
            ("PIN profile sends its token", "Probe_headers", [pin],
             lambda h: h["Authorization"] == "Bearer acc-1" and h["X-Profile-Id"] == "p-kids" and h["X-Profile-Token"] == "ptok-1"),
            ("profile without a PIN sends no token header", "Probe_headers", [plain],
             lambda h: h["X-Profile-Id"] == "p-owner" and "X-Profile-Token" not in h),
            ("no profile", "Probe_headers", [none], lambda h: "X-Profile-Id" not in h and "X-Profile-Token" not in h),
        ])


if __name__ == "__main__":
    unittest.main()
