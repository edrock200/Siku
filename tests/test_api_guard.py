# SPDX-License-Identifier: AGPL-3.0-or-later
"""ApiTask's v2-only guard (ApiTask_refusal): Siku never reaches /api/v1 or /health."""
import unittest

from brs import check_cases

FILES = ["components/tasks/ApiTask.brs", "components/common/Utils.brs"]
OK = ""


def refused(v):
    return isinstance(v, str) and v != ""


class ApiGuard(unittest.TestCase):
    def test_paths(self):
        cases = [
            ("v2 path", {"path": "/api/v2/home/sections"}, OK),
            ("v2 path with query", {"path": "/api/v2/search?q=a..b"}, OK),
            ("encoded content id", {"path": "/api/v2/catalog/items/movie%3Aheat-1995"}, OK),
            ("v1 path", {"path": "/api/v1/items"}, refused),
            ("health", {"path": "/health"}, refused),
            ("no path", {}, refused),
            ("prefix without slash", {"path": "/api/v2"}, refused),
            ("upper-case v2", {"path": "/API/V2/home"}, refused),
            ("dot-dot to v1", {"path": "/api/v2/../v1/items"}, refused),
            ("encoded dot-dot", {"path": "/api/v2/%2E%2E/v1/items"}, refused),
            ("encoded slash dot-dot", {"path": "/api/v2/x%2F..%2F..%2Fhealth"}, refused),
            ("single dot", {"path": "/api/v2/./home"}, refused),
            ("backslash", {"path": "/api/v2/..\\v1"}, refused),
            ("absolute v2 url", {"url": "https://silo.example/api/v2/home/sections"}, OK),
            ("absolute v1 url (used to bypass the guard)", {"url": "https://silo.example/api/v1/items"}, refused),
            ("absolute health url", {"url": "http://silo.example:8097/health"}, refused),
            ("absolute url, no path", {"url": "http://silo.example"}, refused),
            ("non-http url", {"url": "file:///tmp/x"}, refused),
            ("baseUrl origin", {"baseUrl": "http://192.168.1.5:8097", "path": "/api/v2/system/identity"}, OK),
            ("baseUrl with prefix", {"baseUrl": "https://example.com/silo", "path": "/api/v2/system/identity"}, OK),
            ("baseUrl query swallows the v2 path (phone-pushed URL)",
             {"baseUrl": "http://evil.example/health?x=", "path": "/api/v2/system/identity"}, refused),
            ("baseUrl fragment", {"baseUrl": "http://h/#", "path": "/api/v2/system/identity"}, refused),
            ("baseUrl dot segments", {"baseUrl": "http://h/api/v2/..", "path": "/api/v2/x"}, refused),
            ("baseUrl not http", {"baseUrl": "javascript:x", "path": "/api/v2/x"}, refused),
        ]
        check_cases(self, FILES, [(n, "ApiTask_refusal", [req], exp) for n, req, exp in cases])


if __name__ == "__main__":
    unittest.main()
