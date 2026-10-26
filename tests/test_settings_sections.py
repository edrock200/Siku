# SPDX-License-Identifier: AGPL-3.0-or-later
"""Settings_arrangeSections: the Home Sections editor's saved order and hidden rows."""
import unittest

from brs import check_cases

FILES = ["components/common/Settings.brs", "components/common/Utils.brs", "components/common/Content.brs"]
SECTIONS = [{"id": "continue"}, {"id": "next_up"}, {"id": "recent"}, {"id": "genre:action"}, {"id": 7}]


def ids(v):
    return [s["id"] for s in v]


def g(prefs):
    return {"global": {"prefs": prefs}}


class Sections(unittest.TestCase):
    def test_arrange(self):
        check_cases(self, FILES, [
            ("no prefs keeps the server order", "Settings_arrangeSections", [SECTIONS],
             lambda v: ids(v) == ["continue", "next_up", "recent", "genre:action", 7], g({})),
            ("saved order first, unknown rows after in server order", "Settings_arrangeSections", [SECTIONS],
             lambda v: ids(v) == ["recent", "continue", "next_up", "genre:action", 7],
             g({"sectionOrder": ["recent", "gone", "continue"]})),
            ("hidden rows dropped", "Settings_arrangeSections", [SECTIONS],
             lambda v: ids(v) == ["continue", "recent", 7], g({"hiddenSections": ["next_up", "genre:action"]})),
            ("hidden rows kept for the editor", "Settings_arrangeSections", [SECTIONS, True],
             lambda v: ids(v) == ["next_up", "continue", "recent", "genre:action", 7],
             g({"hiddenSections": ["next_up"], "sectionOrder": ["next_up"]})),
            ("numeric ids match their string form", "Settings_arrangeSections", [SECTIONS],
             lambda v: ids(v)[0] == 7, g({"sectionOrder": ["7"]})),
            ("a full reorder", "Settings_arrangeSections", [SECTIONS],
             lambda v: ids(v) == [7, "genre:action", "recent", "next_up", "continue"],
             g({"sectionOrder": ["7", "genre:action", "recent", "next_up", "continue"]})),
            ("prefs lists of the wrong type", "Settings_arrangeSections", [SECTIONS],
             lambda v: len(v) == 5, g({"sectionOrder": "recent", "hiddenSections": {"a": 1}})),
            ("sections not a list", "Settings_arrangeSections", [None], [], g({})),
            ("no prefs at all", "Settings_arrangeSections", [SECTIONS], lambda v: len(v) == 5, {"global": {}}),
        ])


if __name__ == "__main__":
    unittest.main()
