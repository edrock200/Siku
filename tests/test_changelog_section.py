# SPDX-License-Identifier: AGPL-3.0-or-later
"""tools/announce_discord.py section(): the one rule that finds a version's CHANGELOG.md section
for both the GitHub release notes (release.yml runs it with --notes) and the Discord post."""
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import announce_discord  # noqa: E402

CHANGELOG = """# Changelog

## v0.3.0 (2026-11-13)

- Dated heading.

## v0.2.0

- Bare heading.
- Second line.

## v0.2.0-beta

- Not v0.2.0.

## v0.1.47
- Last.
"""


class Section(unittest.TestCase):
    def setUp(self):
        fd, self.path = tempfile.mkstemp(suffix=".md")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(CHANGELOG)

    def tearDown(self):
        os.unlink(self.path)

    def test_heading_tag(self):
        self.assertEqual(announce_discord.heading_tag("## v0.2.0\n"), "v0.2.0")
        self.assertEqual(announce_discord.heading_tag("## v0.2.0 (2026-11-12)\n"), "v0.2.0")
        self.assertEqual(announce_discord.heading_tag("##   v0.2.0  \n"), "v0.2.0")
        self.assertEqual(announce_discord.heading_tag("## \n"), "")
        self.assertEqual(announce_discord.heading_tag("### v0.2.0\n"), "")
        self.assertEqual(announce_discord.heading_tag("- v0.2.0\n"), "")

    def test_sections(self):
        s = announce_discord.section
        self.assertEqual(s("v0.3.0", self.path), "- Dated heading.")
        self.assertEqual(s("v0.2.0", self.path), "- Bare heading.\n- Second line.")
        self.assertEqual(s("v0.2.0-beta", self.path), "- Not v0.2.0.")
        self.assertEqual(s("v0.1.47", self.path), "- Last.")
        self.assertEqual(s("v9.9.9", self.path), "")

    def test_notes_mode_reads_the_repository_changelog(self):
        # The release workflow's call: prints the section and needs no webhook.
        env = {k: v for k, v in os.environ.items() if k != "DISCORD_WEBHOOK_URL"}
        out = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "announce_discord.py"), "--notes", "v0.2.0"],
                             cwd=ROOT, env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.strip(), announce_discord.section("v0.2.0", os.path.join(ROOT, "CHANGELOG.md")))
        self.assertTrue(out.stdout.strip(), "CHANGELOG.md has a v0.2.0 section")


if __name__ == "__main__":
    unittest.main()
