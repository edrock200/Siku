# SPDX-License-Identifier: AGPL-3.0-or-later
"""Req_withoutLibraryTitles: Search's "Available to request" row leaves out titles the server
marks availability "available" (Silo Android #773)."""
import unittest

from brs import check_cases

FILES = ["components/common/Requests.brs", "components/common/Utils.brs"]


class WithoutLibraryTitles(unittest.TestCase):
    def test_cases(self):
        a = {"tmdb_id": 1, "availability": "available"}
        p = {"tmdb_id": 2, "availability": "partially_available"}
        m = {"tmdb_id": 3, "availability": "missing"}
        n = {"tmdb_id": 4}
        f = "Req_withoutLibraryTitles"
        check_cases(self, FILES, [
            ("in-library titles leave", f, [[a, p, m, n]], lambda v: [x["tmdb_id"] for x in v] == [2, 3, 4]),
            ("all in the library", f, [[a]], []),
            ("nothing", f, [[]], []),
        ])


if __name__ == "__main__":
    unittest.main()
