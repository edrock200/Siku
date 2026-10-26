#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Posts a Siku release to a Discord channel webhook.

  DISCORD_WEBHOOK_URL=<url> python3 tools/announce_discord.py <tag> [<repo>]

The message is the tag's CHANGELOG.md section (the same plain-language notes as the GitHub
release) plus links to the release page and the side-loadable zip. The webhook URL is a secret:
it comes from the environment (the release workflow passes the DISCORD_WEBHOOK_URL repository
secret) and is never committed or printed.
"""
import json
import os
import sys
import urllib.request


def section(tag: str) -> str:
    out, inside = [], False
    with open("CHANGELOG.md", encoding="utf-8") as f:
        for line in f:
            if line.startswith("## "):
                if inside:
                    break
                inside = line[3:].strip() == tag
                continue
            if inside:
                out.append(line.rstrip("\n"))
    return "\n".join(out).strip()


def main() -> int:
    url = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    if not url:
        print("DISCORD_WEBHOOK_URL is not set; nothing posted.")
        return 0
    tag = sys.argv[1]
    repo = sys.argv[2] if len(sys.argv) > 2 else "edrock200/Siku"
    notes = section(tag) or "See the release page for what changed."
    page = f"https://github.com/{repo}/releases/tag/{tag}"
    zip_url = f"https://github.com/{repo}/releases/download/{tag}/siku-{tag}.zip"
    links = (f"\n\n**Download:** [siku-{tag}.zip]({zip_url}) · [Release page]({page})\n"
             "Install: Roku developer mode › http://<roku-ip> › Upload › Replace.")
    room = 4000 - len(links)
    if len(notes) > room:
        notes = notes[: room - 40].rsplit("\n", 1)[0] + "\n… (full notes on the release page)"
    payload = {
        "username": "Siku",
        "embeds": [{"title": f"Siku {tag} is out", "url": page, "description": notes + links, "color": 0x3B82F6}],
        "allowed_mentions": {"parse": []},
    }
    req = urllib.request.Request(url + "?wait=true", data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json", "User-Agent": "Siku-release"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        print(f"Posted {tag} to Discord (HTTP {resp.status}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
