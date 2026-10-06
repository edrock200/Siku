"""Renders UI icons from Material Icons Round (Apache-2.0) to white PNGs.

Usage: python3 scripts/make_icons.py <MaterialIconsRound-Regular.otf> <codepoints file>
Get both from https://github.com/google/material-design-icons/tree/master/font
Icons are white so components can tint them with blendColor.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(__file__), "..", "images", "icons")
SIZE = 96

ICONS = {
    "search": "search", "play": "play_arrow", "pause": "pause", "replay": "replay",
    "forward": "forward_30", "rewind": "replay_10", "skip_next": "skip_next",
    "skip_previous": "skip_previous", "subtitles": "closed_caption", "tune": "tune",
    "close": "close", "check": "check", "check_circle": "check_circle", "chevron_right": "chevron_right",
    "chevron_left": "chevron_left", "expand_more": "expand_more", "add": "add", "more": "more_horiz",
    "heart": "favorite_border", "heart_filled": "favorite", "bookmark": "bookmark_border",
    "bookmark_filled": "bookmark", "sparkle": "auto_awesome", "calendar": "calendar_today",
    "settings": "settings", "person": "person", "people": "people", "logout": "logout",
    "dns": "dns", "history": "history", "movie": "movie", "tv": "tv", "music": "music_note",
    "audiobook": "headphones", "home": "home", "start_over": "restart_alt", "audio": "graphic_eq",
    "info": "info", "error": "error_outline", "visibility": "visibility", "visibility_off": "visibility_off",
    "backspace": "backspace", "shuffle": "shuffle", "lock": "lock", "edit": "edit", "phone": "smartphone",
    "qr": "qr_code_2", "star": "star", "video": "videocam", "speed": "speed", "list": "list",
    "trailer": "smart_display", "collections": "collections_bookmark", "watched": "done_all",
    "play_circle": "play_circle", "fast_forward": "fast_forward", "fast_rewind": "fast_rewind",
    "volume": "volume_up", "sort": "sort", "filter": "filter_list", "refresh": "refresh",
    "language": "language", "key": "key",
}


def main():
    font_path, cp_path = sys.argv[1], sys.argv[2]
    cps = {}
    for line in open(cp_path):
        name, cp = line.split()
        cps[name] = int(cp, 16)
    os.makedirs(OUT, exist_ok=True)
    font = ImageFont.truetype(font_path, int(SIZE * 0.92))
    for out_name, glyph in ICONS.items():
        ch = chr(cps[glyph])
        img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
        d = ImageDraw.Draw(img)
        bbox = d.textbbox((0, 0), ch, font=font)
        w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
        d.text(((SIZE - w) / 2 - bbox[0], (SIZE - h) / 2 - bbox[1]), ch, font=font, fill=(255, 255, 255, 255))
        img.save(os.path.join(OUT, out_name + ".png"), optimize=True)
    print("rendered", len(ICONS), "icons")


if __name__ == "__main__":
    main()
