# SPDX-License-Identifier: AGPL-3.0-or-later
"""Settings_superseded: an older settings load must not overwrite a newer published snapshot."""
import unittest

from brs import SESSION, check_cases, settings

FILES = ["components/common/Settings.brs", "components/common/Utils.brs", "components/common/Content.brs"]
IDENT = SESSION["serverUrl"] + "|" + SESSION["profileId"]


def g(published_seq, latest=None):
    st = settings()
    st["loadSeq"] = published_seq
    out = {"session": dict(SESSION), "settings": st, "prefs": {}}
    if latest is not None:
        out["settingsLoadSeq"] = latest
    return {"global": out}


class LoadSeq(unittest.TestCase):
    def test_superseded(self):
        check_cases(self, FILES, [
            ("the newest load publishes", "Settings_superseded", [{"seq": 3}, IDENT], False, g(2, 3)),
            ("an older load arriving after a newer published one is dropped", "Settings_superseded",
             [{"seq": 2}, IDENT], True, g(3, 3)),
            ("an older load may publish before the newer one lands", "Settings_superseded",
             [{"seq": 2}, IDENT], False, g(1, 3)),
            ("the same load's retry publishes", "Settings_superseded", [{"seq": 3}, IDENT], False, g(3, 3)),
            ("another profile's answer", "Settings_superseded", [{"seq": 9}, "http://other|p2"], True, g(1, 9)),
            ("a snapshot from before load numbers", "Settings_superseded", [{"seq": 1}, IDENT], False,
             {"global": {"session": dict(SESSION), "settings": settings(), "prefs": {}}}),
            ("a seq sent back as a string", "Settings_superseded", [{"seq": "4"}, IDENT], False, g(4, 4)),
            ("no context", "Settings_superseded", [None, IDENT], True, g(1, 1)),
        ])


if __name__ == "__main__":
    unittest.main()
