# SPDX-License-Identifier: AGPL-3.0-or-later
"""ProfileLaunch_heartbeatGap: how often the "last in use" time is rewritten (flash wear)."""
import unittest

from brs import check_cases

FILES = ["components/common/ProfileLaunch.brs", "components/common/Utils.brs", "components/common/Session.brs"]


def g(choice):
    return {"global": {"prefs": {"profileLaunch": choice}, "session": {"profileId": "p1"}}}


class Heartbeat(unittest.TestCase):
    def test_gap(self):
        check_cases(self, FILES, [
            ("Automatic writes nothing", "ProfileLaunch_heartbeatGap", [], 0, g("automatic")),
            ("Every Time writes nothing", "ProfileLaunch_heartbeatGap", [], 0, g("askEveryLaunch")),
            ("After 1 Hour: every 5 minutes", "ProfileLaunch_heartbeatGap", [], 300, g("afterOneHour")),
            ("After 12 Hours: every 10 minutes", "ProfileLaunch_heartbeatGap", [], 600, g("afterTwelveHours")),
            ("the timer ticks no slower than the shortest gap", "ProfileLaunch_heartbeatSeconds", [], 300, g("automatic")),
        ])


if __name__ == "__main__":
    unittest.main()
