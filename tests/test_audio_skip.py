# SPDX-License-Identifier: AGPL-3.0-or-later
"""AudioSkip.brs: audiobook skip intervals come from the profile on a revision-9 server and from
this device's pref (Android's 10/15/30/60 s, 30 s by default) on an older one."""
import unittest

from brs import check_cases, glob

FILES = ["components/player/AudioSkip.brs", "components/common/Settings.brs", "components/common/Utils.brs"]


def g(items=None, prefs=None, rev=21, available=True):
    out = glob(items, prefs)
    out["settings"]["manifestRevision"] = rev
    out["settings"]["available"] = available
    return out


class AudioSkip(unittest.TestCase):
    def test_seconds(self):
        c = "AudioSkip_seconds"
        prof = {"player.audiobook_skip_back_seconds": 15, "player.audiobook_skip_forward_seconds": 45}
        check_cases(self, FILES, [
            ("profile value back", c, ["back"], 15, {"global": g(prof)}),
            ("profile value forward", c, ["forward"], 45, {"global": g(prof)}),
            ("profile value as a string", c, ["back"], 90, {"global": g({"player.audiobook_skip_back_seconds": "90"})}),
            ("revision 8: the device pref", c, ["back"], 60, {"global": g(prof, {"audiobookSkipBack": 60}, rev=8)}),
            ("no settings: the device pref", c, ["forward"], 15, {"global": g(prof, {"audiobookSkipForward": 15}, available=False)}),
            ("no pref: 30 s", c, ["back"], 30, {"global": g(None, None, rev=8)}),
            ("a pref outside Android's set: 30 s", c, ["back"], 30, {"global": g(None, {"audiobookSkipBack": 45}, rev=8)}),
            ("profile-wide but unset: the device pref", c, ["back"], 10, {"global": g({}, {"audiobookSkipBack": 10})}),
        ])

    def test_choices(self):
        c = "AudioSkip_choices"
        check_cases(self, FILES, [
            ("contract choices", c, [], [5, 10, 15, 30, 45, 60, 90], {"global": g()}),
            ("device choices", c, [], [10, 15, 30, 60], {"global": g(rev=8)}),
        ])


if __name__ == "__main__":
    unittest.main()
