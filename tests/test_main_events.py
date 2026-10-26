# SPDX-License-Identifier: AGPL-3.0-or-later
"""source/MainEvents.brs: memory warnings and app focus as main.brs forwards them to MainScene."""
import unittest

from brs import check_cases

FILES = ["source/MainEvents.brs"]
APP = "roAppMemoryNotificationEvent"
DEV = "roDeviceInfoEvent"


class MainEvents(unittest.TestCase):
    def test_memory(self):
        p = "MainEvents_memoryPressure"
        check_cases(self, FILES, [
            ("channel usage", p, [APP, {"memoryUsagePercent": 83}], 83),
            ("channel usage, capitalised key", p, [APP, {"MemoryUsagePercent": 91}], 91),
            ("over 100 is capped", p, [APP, {"memoryUsagePercent": 140}], 100),
            ("negative ignored", p, [APP, {"memoryUsagePercent": -1}], -1),
            ("string ignored", p, [APP, {"memoryUsagePercent": "80"}], -1),
            ("missing ignored", p, [APP, {}], -1),
            ("not an object", p, [APP, None], -1),
            ("device low", p, [DEV, {"generalMemoryLevel": "low"}], 80),
            ("device critical", p, [DEV, {"generalMemoryLevel": "CRITICAL"}], 95),
            ("device normal", p, [DEV, {"generalMemoryLevel": "normal"}], 0),
            ("device focus event is not memory", p, [DEV, {"appFocused": False}], -1),
            ("other event", p, ["roInputEvent", {"memoryUsagePercent": 90}], -1),
        ])

    def test_focus(self):
        f = "MainEvents_appFocus"
        check_cases(self, FILES, [
            ("focus lost", f, [{"appFocused": False}], False),
            ("focus back", f, [{"appFocused": True}], True),
            ("screensaver exit", f, [{"exitedScreensaver": True}], True),
            ("memory event", f, [{"generalMemoryLevel": "low"}], None),
            ("not an object", f, ["x"], None),
        ])


if __name__ == "__main__":
    unittest.main()
