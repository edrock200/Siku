# SPDX-License-Identifier: AGPL-3.0-or-later
"""Wire values from the LAN are untrusted: any device can send handoffOffer {serverURL: 1} or a
pushServer whose serverURL is an object. Lan_trimUrl (components/lan/LanBytes.brs) returns ""
for anything that is not a string, so RemoteControl.onOffer refuses the offer and
PhonePairing's Pair_onPush ignores the push instead of crashing on .Trim()."""
import unittest

from brs import check_cases

LAN = ["components/lan/LanBytes.brs", "components/common/Utils.brs"]
PAIR = ["components/remote/PhonePairing.brs"] + LAN
BAD = [("Integer", 1), ("Float", 1.5), ("AA", {"url": "http://x"}), ("Boolean", True), ("array", ["http://x"]), ("invalid", None)]


class TrimUrl(unittest.TestCase):
    def test_non_strings(self):
        cases = []
        for name, v in BAD:
            cases.append(("trim " + name, "Lan_trimUrl", [v], ""))
            cases.append(("server id of " + name, "Lan_serverIdFor", [v], ""))
            cases.append(("canonical " + name, "Lan_canonicalUrl", [v], ""))
        cases.append(("a string is trimmed", "Lan_trimUrl", ["  http://b.local:8090// "], "http://b.local:8090"))
        cases.append(("an empty string", "Lan_trimUrl", [""], ""))
        check_cases(self, LAN, cases)

    def test_pair_display_name(self):
        cases = [("display name with serverURL " + name, "Pair_displayName", [{"serverURL": v, "serverName": ""}], "") for name, v in BAD]
        cases.append(("its name wins", "Pair_displayName", [{"serverURL": 7, "serverName": " Home "}], "Home"))
        check_cases(self, PAIR, cases)


if __name__ == "__main__":
    unittest.main()
