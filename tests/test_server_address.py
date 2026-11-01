# SPDX-License-Identifier: AGPL-3.0-or-later
"""ServerAddr_candidates (components/common/ServerAddress.brs): the typed address with Advanced
options' protocol and port (Silo Android TV #758/#771; silo-roku source/onboarding/address.bs).
Auto never adds port 8090 on its own."""
import unittest

from brs import check_cases

FILES = ["components/common/ServerAddress.brs", "components/common/Utils.brs"]
C = "ServerAddr_candidates"
INVALID = "Enter a valid server address."
PORT = "Port must be a number between 1 and 65535."


def ok(*urls):
    return {"error": "", "candidates": list(urls)}


def err(msg):
    return {"error": msg, "candidates": []}


class Candidates(unittest.TestCase):
    def test_cases(self):
        check_cases(self, FILES, [
            ("empty", C, ["  ", "auto", ""], err("Please enter a server host.")),
            ("auto tries https then http", C, ["Media.Example.com", "auto", ""],
             ok("https://media.example.com", "http://media.example.com")),
            ("no 8090 probe", C, ["silo.local", "auto", ""], lambda v: all(":8090" not in u for u in v["candidates"])),
            ("typed scheme kept in auto", C, ["http://silo.local:8090/", "auto", ""], ok("http://silo.local:8090")),
            ("chosen protocol replaces a typed one", C, ["http://silo.local", "https", ""], ok("https://silo.local")),
            ("http only", C, ["silo.local", "http", ""], ok("http://silo.local")),
            ("port field", C, ["silo.local", "auto", "8090"], ok("https://silo.local:8090", "http://silo.local:8090")),
            ("typed port wins", C, ["silo.local:9000", "auto", "8090"], ok("https://silo.local:9000", "http://silo.local:9000")),
            ("leading zeros", C, ["silo.local", "https", "0443"], ok("https://silo.local:443")),
            ("path prefix kept", C, ["https://example.com/silo/", "auto", ""], ok("https://example.com/silo")),
            ("ipv4", C, ["192.168.1.20:8090", "http", ""], ok("http://192.168.1.20:8090")),
            ("ipv6", C, ["[fd00::1]:8090", "http", ""], ok("http://[fd00::1]:8090")),
            ("bare ipv6", C, ["fd00::1", "auto", ""], err(INVALID)),
            ("other scheme", C, ["ftp://silo.local", "auto", ""], err("Use an address that starts with https:// or http://.")),
            ("credentials", C, ["https://me:pw@silo.local", "auto", ""], err("Remove the user name and password from the address.")),
            ("space in host", C, ["my server", "auto", ""], err(INVALID)),
            ("empty label", C, ["silo..local", "auto", ""], err(INVALID)),
            ("query", C, ["silo.local?x=1", "auto", ""], err(INVALID)),
            ("port zero typed", C, ["silo.local:0", "auto", ""], err(PORT)),
            ("port letters typed", C, ["silo.local:abc", "auto", ""], err(INVALID)),
            ("port field too big", C, ["silo.local", "auto", "70000"], err(PORT)),
            ("port field letters", C, ["silo.local", "auto", "80a"], err(PORT)),
            ("empty typed port", C, ["silo.local:", "auto", ""], err(INVALID)),
        ])

    def test_messages(self):
        check_cases(self, FILES, [
            ("server message kept", "ServerAddr_unreachableText", ["auto", "Server is starting"], "Could not reach server: Server is starting"),
            ("bare error", "ServerAddr_unreachableText", ["auto", ""], "Could not reach a Silo server at that address."),
            ("https only", "ServerAddr_unreachableText", ["https", ""], "Could not reach a Silo server at that address over HTTPS."),
            ("problem detail", "ServerAddr_serverMessage", [503, {"title": "Unavailable", "detail": "Server is starting"}], "Server is starting"),
            ("stand-in title is no message", "ServerAddr_serverMessage", [404, {"title": "Something went wrong (404)", "detail": ""}], ""),
            ("unreachable is no message", "ServerAddr_serverMessage", [0, {"title": "Can't reach the server", "detail": "timeout"}], ""),
        ])


if __name__ == "__main__":
    unittest.main()
