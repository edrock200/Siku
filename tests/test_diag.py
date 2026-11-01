# SPDX-License-Identifier: AGPL-3.0-or-later
"""components/common/Diag.brs: log redaction, Roku exit codes and the log viewer's lines."""
import unittest

from brs import check_cases

FILES = ["components/common/Diag.brs"]


def lacks(*parts):
    return lambda v: all(p not in v for p in parts)


class Diag(unittest.TestCase):
    def test_scrub(self):
        s = "Diag_scrub"
        check_cases(self, FILES, [
            ("plain line kept", s, ["[siku-memory] pressure 82 level=trim was=normal"], "[siku-memory] pressure 82 level=trim was=normal"),
            ("url", s, ["[siku-theme] audio error 3 http://10.0.0.5:8097/api/v2/x?sig=abc"], "[siku-theme] audio error 3 <url>"),
            ("ip and port", s, ["[siku-lan] address changed to 192.168.1.20:8181"], "[siku-lan] address changed to <ip>"),
            ("email", s, ["[siku-auth] user ed@example.com"], lacks("ed@example.com")),
            ("id keys", s, ["[siku-playback] markers file=42 count=3"], "[siku-playback] markers file=<id> count=3"),
            ("trailer video", s, ["[siku-trailer] open YouTube video=dQw4w9WgXcQ"], "[siku-trailer] open YouTube video=<id>"),
            ("content_id", s, ["x content_id=abc-123 y"], "x content_id=<id> y"),
            ("uuid", s, ["pick 3f2a1c4e-1b2c-4d5e-8f90-123456789abc ok"], "pick <id> ok"),
            ("hex id", s, ["sheet 0123456789abcdef0123 failed"], "sheet <id> failed"),
            ("token", s, ["bearer eyJhbGciOiJIUzI1NiJ9xyzABC123"], lacks("eyJhbGciOiJIUzI1NiJ9")),
            ("capability names stay", s, ["claims client_selected_audio_track_v1 hls_copy_mpegts_v1"], "claims client_selected_audio_track_v1 hls_copy_mpegts_v1"),
            ("long line capped", s, ["x" * 900], lambda v: len(v) == 401),
            ("not a string", s, [None], ""),
        ])

    def test_exit(self):
        k = "Diag_exitKind"
        e = "Diag_exitOf"
        check_cases(self, FILES, [
            ("crash", k, ["EXIT_BRIGHTSCRIPT_CRASH"], "crash"),
            ("memory", k, ["exit_channel_mem_limit_fg"], "memory"),
            ("hang", k, ["EXIT_SIGNAL_TIMEOUT"], "hang"),
            ("killed", k, ["EXIT_SYSTEM_KILL"], "killed"),
            ("user left", k, ["EXIT_USER_NAV"], ""),
            ("nothing", k, [None], ""),
            ("from exit info", e, [{"exit_code": "EXIT_OUT_OF_MEMORY", "timestamp": "2026-11-01T02:11:03Z", "app_state": "FOREGROUND", "mem_limit": 300, "console_log": "secret"}, ""],
             lambda v: {k.lower(): x for k, x in v.items()} == {"code": "EXIT_OUT_OF_MEMORY", "kind": "memory", "when": "2026-11-01T02:11:03Z", "appstate": "foreground", "mediastate": "", "memlimitmb": 300, "key": "EXIT_OUT_OF_MEMORY@2026-11-01T02:11:03Z"}),
            ("launch reason when info has none", e, [{"exit_code": "EXIT_UNKNOWN"}, "EXIT_BRIGHTSCRIPT_CRASH"], lambda v: v["kind"] == "crash" and v["key"] == "EXIT_BRIGHTSCRIPT_CRASH@"),
            ("no info at all", e, [None, None], lambda v: v["code"] == "" and v["key"] == ""),
            ("label normal", "Diag_exitLabel", [{"code": "EXIT_USER_NAV", "kind": ""}], "Normal"),
            ("label crash", "Diag_exitLabel", [{"code": "EXIT_OUT_OF_MEMORY", "kind": "memory", "when": "2026-11-01T02:11:03Z"}], "It ran out of memory (2026-11-01 02:11 UTC)"),
            ("label unknown", "Diag_exitLabel", [{}], "Not reported"),
        ])

    def test_view_lines(self):
        v = "Diag_viewLines"
        check_cases(self, FILES, [
            ("newest lines", v, ["a\nb\nc\n", 10, 2], ["b", "c"]),
            ("long line cut", v, ["abcdefghij", 4, 5], ["abcd", "efgh", "ij"]),
            ("continuations indented", v, ["x" * 30, 24, 5], ["x" * 24, "    " + "x" * 6]),
            ("empty", v, ["", 10, 5], []),
        ])


class DiagLogConverted(unittest.TestCase):
    def test_no_print_left(self):
        """Every logged [siku-*] category goes through Diag_log (run tools/diag_log_convert.py)."""
        import subprocess
        import sys
        import os
        root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        r = subprocess.run([sys.executable, os.path.join(root, "tools", "diag_log_convert.py"), "--check"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_join(self):
        check_cases(self, ["components/common/Utils.brs"], [
            ("print-like join", "Diag_join", [["a=", 3, " b=", True, " c=", None]], "a=3 b=true c=invalid"),
        ])


if __name__ == "__main__":
    unittest.main()
