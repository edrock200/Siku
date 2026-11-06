# SPDX-License-Identifier: AGPL-3.0-or-later
"""Removing a failed request (Silo Android #792): which cards offer Remove (MediaRequest.isRemovableFailure,
MyRequestsUiState.canRemove), what each DELETE /api/v2/requests/{id} answer means
(MyRequestsViewModel.removeFailed), and the title becoming requestable again (applyingRemoval)."""
import unittest

from brs import check_cases

FILES = ["components/common/Requests.brs", "components/common/Utils.brs"]


def rec(outcome="failed", targets=(), rid="r-1"):
    return {"id": rid, "media_type": "movie", "tmdb_id": 1, "title": "Gone", "status": "failed", "outcome": outcome,
            "targets": [{"id": "t%d" % i, "status": s} for i, s in enumerate(targets)]}


def resp(status, code=None, ok=None):
    r = {"ok": 200 <= status < 300 if ok is None else ok, "status": status}
    if code is not None:
        r["error"] = {"code": code, "title": "T", "detail": "Server says no"}
    return r


class RemovalRule(unittest.TestCase):
    def test_cases(self):
        f = "Req_isRemovableFailure"
        check_cases(self, FILES, [
            ("failed, nothing delivered", f, [rec(targets=["failed"])], True),
            ("failed without targets", f, [rec()], True),
            ("delivered one quality before failing", f, [rec(targets=["completed", "failed"])], False),
            ("active", f, [rec("active")], False),
            ("declined", f, [rec("declined")], False),
            ("cancelled", f, [rec("cancelled")], False),
            ("not a record", f, [None], False),
        ])

    def test_can_remove(self):
        f = "Req_canRemove"
        check_cases(self, FILES, [
            ("server takes removals", f, [rec(), True, False], True),
            ("older server", f, [rec(), False, False], False),
            ("an action in flight", f, [rec(), True, True], False),
            ("partly delivered", f, [rec(targets=["completed"]), True, False], False),
        ])

    def test_gate_flag(self):
        check_cases(self, FILES, [
            ("flag on", "Req_removeFailedSupported", [], True, {"global": {"requests": {"enabled": True, "removeFailedSupported": True}}}),
            ("flag absent", "Req_removeFailedSupported", [], False, {"global": {"requests": {"enabled": True}}}),
            ("flag not a boolean", "Req_removeFailedSupported", [], False, {"global": {"requests": {"removeFailedSupported": "true"}}}),
            ("no gate yet", "Req_removeFailedSupported", [], False, {"global": {}}),
        ])


class RemoveOutcome(unittest.TestCase):
    def test_cases(self):
        f = "Req_removeOutcome"
        conflict = "This request changed since the list loaded, so it wasn't removed."
        unconfirmed = "We couldn't confirm the removal. Refresh your requests to check it."
        check_cases(self, FILES, [
            ("204", f, [resp(204)], {"kind": "removed", "toast": "Request removed"}),
            ("404: removed elsewhere, no notice", f, [resp(404, "not_found")], {"kind": "gone", "toast": ""}),
            ("409 conflict", f, [resp(409, "conflict")], {"kind": "conflict", "toast": conflict}),
            ("409 requests turned off", f, [resp(409, "capability_disabled")], {"kind": "failed", "toast": "Requests are turned off"}),
            ("no answer", f, [resp(0, "timeout")], {"kind": "uncertain", "toast": unconfirmed}),
            ("502", f, [resp(502, "bad_gateway")], {"kind": "uncertain", "toast": unconfirmed}),
            ("403 with a detail", f, [resp(403, "forbidden")], {"kind": "failed", "toast": "Server says no"}),
            ("invalid", f, [None], {"kind": "uncertain", "toast": unconfirmed}),
        ])

    def test_copy(self):
        check_cases(self, FILES, [
            ("title", "Req_removeConfirmTitle", [], "Remove this request?"),
            ("message names the title", "Req_removeConfirmMessage", ["Gone"],
             'Your failed request for "Gone" will be deleted. You can request the title again later.'),
        ])


class RequestableAgain(unittest.TestCase):
    def test_results_without(self):
        mine = {"media_type": "movie", "tmdb_id": 1, "request": {"request_id": "r-1", "state": "failed", "requestable": True}}
        other_request = {"media_type": "movie", "tmdb_id": 1, "request": {"request_id": "r-9", "state": "pending"}}
        other_title = {"media_type": "movie", "tmdb_id": 2, "request": {"request_id": "r-1"}}
        series_same_id = {"media_type": "series", "tmdb_id": 1, "request": {"request_id": "r-1"}}
        check_cases(self, FILES, [
            ("the removed request's title", "Req_resultsWithout", [[mine], rec()],
             lambda v: v[0]["request"] == {"requestable": True} and v[0]["tmdb_id"] == 1),
            ("a title showing another request", "Req_resultsWithout", [[other_request], rec()], [other_request]),
            ("another title", "Req_resultsWithout", [[other_title, series_same_id], rec()], [other_title, series_same_id]),
            ("records without", "Req_recordsWithout", [[rec(rid="r-1"), rec(rid="r-2")], "r-1"], lambda v: [r["id"] for r in v] == ["r-2"]),
        ])


if __name__ == "__main__":
    unittest.main()
