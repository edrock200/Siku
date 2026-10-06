"""A small fake Silo server for exercising Siku in the brs-engine simulator.

It speaks the /api/v2 shapes documented in docs/api-spec.md, with a synthetic
library (movies, series with seasons and episodes, people) and generated artwork.

Run:  python3 tools/mock_server.py [--port 8097]
Then connect Siku to http://127.0.0.1:8097

Device sign-in auto-approves on the second poll. Password login accepts any
username with password "silo". The "Kids" profile has PIN 1234.
"""
import argparse
import hashlib
import io
import json
import random
import re
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse, unquote

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # artwork is optional
    Image = None

FONT = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
STATE = {"devices": {}, "sessions": {}, "watchlist": set(), "favorites": set(), "watched": set(), "progress": {}, "shuffles": {}}
LOCK = threading.Lock()
LOG = []

GENRES = ["Science Fiction", "Drama", "Crime", "Comedy", "Thriller", "Adventure", "Animation", "Documentary"]
MOVIE_TITLES = [
    "Northern Lights", "The Quiet Harbor", "Glass City", "Paper Moons", "Iron Orchard", "The Last Ferry",
    "Signal Fire", "Blue Hour", "Kingdom of Salt", "After the Rain", "Velvet Static", "The Long Way Home",
    "Copper Sky", "Small Hours", "Wildflower", "The Cartographer", "Midnight Garden", "Echo Park",
    "Silver Lining", "Paper Tigers", "The Lighthouse Keeper", "Night Train", "Golden State", "Undertow",
]
SERIES = [
    ("Orbital", 3, 8), ("The Night Desk", 2, 10), ("Harbor Lane", 4, 6), ("Wild Coast", 1, 8), ("Frontier", 2, 6),
]
PEOPLE = ["Ava Thornton", "Marcus Reed", "Lena Ortiz", "Samuel Park", "Priya Nair", "Jonah Weller", "Clara Holm", "Diego Santos"]
COLORS = [(52, 92, 196), (196, 64, 92), (230, 140, 40), (40, 150, 120), (120, 70, 190), (200, 170, 50), (60, 130, 200), (170, 60, 60)]


def h(s):
    return int(hashlib.md5(s.encode()).hexdigest()[:8], 16)


def img(kind, key):
    return "/mock-img/%s/%s.jpg" % (kind, key.replace(":", "_"))


def person(i):
    name = PEOPLE[i % len(PEOPLE)]
    return {"person_id": str(100 + i), "name": name, "photo_url": img("person", str(100 + i))}


def movie(i):
    title = MOVIE_TITLES[i]
    cid = "movie:%s" % re.sub(r"[^a-z]+", "-", title.lower()).strip("-")
    year = 1990 + (h(title) % 35)
    runtime = 88 + h(title) % 70
    return {
        "content_id": cid, "type": "movie", "title": title, "year": year, "runtime": runtime,
        "duration_seconds": runtime * 60, "genres": [GENRES[h(title) % len(GENRES)], GENRES[(h(title) // 7) % len(GENRES)]],
        "keywords": [], "status": "matched", "content_rating": ["PG", "PG-13", "R", "TV-MA"][h(title) % 4],
        "overview": "A %s story about %s, told across one unforgettable season. Old friends, new secrets, and a city that never quite sleeps." % (GENRES[h(title) % 8].lower(), title.lower()),
        "tagline": "Every light has a shadow.",
        "rating_imdb": round(5.5 + (h(title) % 40) / 10, 1),
        "poster_url": img("poster", cid), "backdrop_url": img("backdrop", cid), "logo_url": img("logo", cid),
        "release_date": "%d-0%d-1%d" % (year, 1 + h(title) % 9, h(title) % 9),
        "overlay_summary": {"resolution": ["4K", "1080p", "1080p"][h(title) % 3], "hdr": ["HDR10", "", "Dolby Vision"][h(title) % 3], "audio": "EAC3"},
        "user_state": {"played": cid in STATE["watched"], "is_favorite": cid in STATE["favorites"], "in_watchlist": cid in STATE["watchlist"]},
    }


def series(i):
    title, seasons, eps = SERIES[i]
    cid = "series:%s" % title.lower().replace(" ", "-")
    year = 2015 + h(title) % 10
    return {
        "content_id": cid, "type": "series", "title": title, "year": year, "genres": [GENRES[h(title) % 8]],
        "keywords": [], "status": "matched", "content_rating": "TV-14", "season_count": seasons,
        "episode_count": seasons * eps, "overview": "%s follows a small crew through %d seasons of trouble, loyalty and very long nights." % (title, seasons),
        "poster_url": img("poster", cid), "backdrop_url": img("backdrop", cid), "logo_url": img("logo", cid),
        "play_content_id": episode_id(cid, 1, 1), "play_season_number": 1, "first_air_date": "%d-03-04" % year,
        "networks": ["Mock Network"],
        "user_state": {"played": False, "is_favorite": cid in STATE["favorites"], "in_watchlist": cid in STATE["watchlist"]},
    }


def episode_id(series_cid, s, e):
    return "episode:%s-s%02de%02d" % (series_cid.split(":", 1)[1], s, e)


def episode(si, s, e):
    sr = series(si)
    cid = episode_id(sr["content_id"], s, e)
    pos = STATE["progress"].get(cid, 0)
    return {
        "content_id": cid, "type": "episode", "title": "Chapter %d" % e, "series_id": sr["content_id"],
        "series_title": sr["title"], "season_number": s, "episode_number": e, "runtime": 48, "duration_seconds": 2880,
        "overview": "The crew faces a new problem in episode %d of season %d." % (e, s), "air_date": "2024-0%d-%02d" % (1 + s % 9, e),
        "still_url": img("still", cid), "backdrop_url": sr["backdrop_url"], "poster_url": sr["poster_url"],
        "files": [{"file_id": str(1000 + si * 100 + s * 10 + e), "resolution": "1080p", "codec_video": "h264", "container": "mp4"}],
        "user_data": {"position_seconds": pos, "duration_seconds": 2880, "played": cid in STATE["watched"]},
        "user_state": {"played": cid in STATE["watched"], "is_favorite": False, "in_watchlist": False},
    }


def all_movies():
    return [movie(i) for i in range(len(MOVIE_TITLES))]


def all_series():
    return [series(i) for i in range(len(SERIES))]


def find(cid):
    for m in all_movies():
        if m["content_id"] == cid:
            return m
    for i, s in enumerate(all_series()):
        if s["content_id"] == cid:
            return s
        _, seasons, eps = SERIES[i]
        for sn in range(1, seasons + 1):
            if cid == "season:%s-%d" % (s["content_id"], sn):
                return {"content_id": cid, "type": "season", "title": "Season %d" % sn, "series_id": s["content_id"],
                        "series_title": s["title"], "season_number": sn, "poster_url": s["poster_url"], "backdrop_url": s["backdrop_url"]}
            for en in range(1, eps + 1):
                if cid == episode_id(s["content_id"], sn, en):
                    return episode(i, sn, en)
    return None


def detail(cid):
    item = find(cid)
    if item is None:
        return None
    d = dict(item)
    d["cast"] = [dict(person(h(cid) + k), character="Character %d" % (k + 1), order=k) for k in range(6)]
    d["crew"] = [dict(person(h(cid) + 7), job="Director"), dict(person(h(cid) + 3), job="Writer")]
    d["studios"] = ["Mock Pictures"]
    d["countries"] = ["United States"]
    pos = STATE["progress"].get(cid, 0)
    d["user_data"] = {"position_seconds": pos, "duration_seconds": d.get("duration_seconds", 0), "played": cid in STATE["watched"],
                      "is_in_progress": pos > 0, "last_file_id": "42"}
    d["intro"] = {"start": 30, "end": 90}
    d["credits"] = {"start": max(0, d.get("duration_seconds", 3000) - 240), "end": d.get("duration_seconds", 3000)}
    d["versions"] = [{"file_id": "42", "resolution": "1080p", "codec_video": "h264", "codec_audio": "aac", "container": "mp4", "hdr": False,
                      "duration": d.get("duration_seconds", 3000), "bitrate": 8000, "file_size": 1, "added_at": "2026-01-01T00:00:00Z",
                      "audio_tracks": [{"index": 0, "language": "eng", "codec": "aac", "channels": 2, "default": True, "title": "English"}],
                      "subtitle_tracks": [{"index": 0, "language": "eng", "codec": "srt", "forced": False, "default": False, "external": True, "title": "English"}]}]
    if d["type"] == "movie" and h(cid) % 3 == 0:
        # A second, richer version so the detail page's Version / Audio / Subtitles selectors appear.
        d["versions"].insert(0, {"file_id": "43", "resolution": "2160p", "codec_video": "hevc", "codec_audio": "eac3", "container": "mkv", "hdr": True,
                                 "duration": d.get("duration_seconds", 3000), "bitrate": 24000, "file_size": 9000000000, "added_at": "2026-02-01T00:00:00Z",
                                 "audio_tracks": [{"index": 0, "language": "eng", "codec": "eac3", "channels": 6, "layout": "5.1", "default": True, "title": "English"},
                                                  {"index": 1, "language": "spa", "codec": "aac", "channels": 2, "default": False, "title": "Español"},
                                                  {"index": 2, "language": "eng", "codec": "aac", "channels": 2, "default": False, "title": "Commentary"}],
                                 "subtitle_tracks": [{"index": 0, "language": "eng", "codec": "srt", "forced": False, "default": False, "external": True, "title": "English"},
                                                     {"index": 1, "language": "eng", "codec": "srt", "forced": False, "default": False, "external": False, "hearing_impaired": True, "title": "English SDH"},
                                                     {"index": 2, "language": "spa", "codec": "srt", "forced": True, "default": False, "external": False, "title": "Español (Forced)"}]})
    return d


def page(items, q):
    limit = int(q.get("limit", ["50"])[0])
    start = int(q.get("cursor", ["0"])[0] or 0)
    chunk = items[start:start + limit]
    nxt = start + limit
    return {"items": chunk, "page": {"has_more": nxt < len(items), "next_cursor": str(nxt) if nxt < len(items) else ""},
            "total": len(items), "total_exact": True}


def home_sections():
    ms = all_movies()
    ss = all_series()
    cw = []
    m0 = dict(ms[3]); m0.update(position_seconds=1800, item_source="in_progress"); cw.append(m0)
    e = episode(0, 1, 3); e.update(position_seconds=900, item_source="in_progress"); cw.append(e)
    e2 = episode(1, 2, 1); e2.update(item_source="next_up"); cw.append(e2)
    m1 = dict(ms[8]); m1.update(position_seconds=3000, item_source="in_progress"); cw.append(m1)
    return {"sections": [
        {"id": "continue_watching", "section_type": "continue_watching", "title": "Continue Watching", "featured": False, "total_count": len(cw), "items": cw},
        {"id": "recent_movies", "section_type": "recently_added", "title": "Recently Added in Movies", "featured": False, "total_count": 12, "items": ms[:12]},
        {"id": "recent_series", "section_type": "recently_added", "title": "Recently Added in Shows", "featured": False, "total_count": len(ss), "items": ss},
        {"id": "hidden_gems", "section_type": "hidden_gems", "title": "Hidden Gems", "featured": False, "total_count": 10, "items": ms[12:22]},
        {"id": "trending", "section_type": "trending_on_server", "title": "Trending on Server", "featured": False, "total_count": 8, "items": ms[6:14]},
    ]}


def make_image(kind, key):
    if Image is None:
        return b""
    seed = h(key)
    c1 = COLORS[seed % len(COLORS)]
    c2 = tuple(int(v * 0.25) for v in COLORS[(seed // 3) % len(COLORS)])
    sizes = {"poster": (300, 450), "backdrop": (1280, 720), "still": (480, 270), "logo": (800, 200), "person": (300, 300), "avatar": (256, 256)}
    w, hgt = sizes.get(kind, (300, 450))
    if kind == "logo":
        im = Image.new("RGBA", (w, hgt), (0, 0, 0, 0))
    else:
        im = Image.new("RGB", (w, hgt), c2)
        d = ImageDraw.Draw(im)
        for y in range(hgt):
            t = y / hgt
            d.line([(0, y), (w, y)], fill=tuple(int(c1[i] * (1 - t) + c2[i] * t) for i in range(3)))
        for k in range(6):
            r = (seed >> k) % 120 + 40
            x = (seed * (k + 3)) % w
            yy = (seed * (k + 7)) % hgt
            d.ellipse([x - r, yy - r, x + r, yy + r], outline=tuple(min(255, v + 40) for v in c1), width=3)
    d = ImageDraw.Draw(im)
    title = key.split("_", 1)[-1].replace("-", " ").title()
    if kind in ("poster", "logo"):
        font = ImageFont.truetype(FONT, 34 if kind == "poster" else 92)
        words = title.split()
        lines, cur = [], ""
        for wd in words:
            if len(cur + " " + wd) > (14 if kind == "poster" else 22):
                lines.append(cur.strip()); cur = wd
            else:
                cur += " " + wd
        lines.append(cur.strip())
        y0 = hgt - 40 * len(lines) - 30 if kind == "poster" else 10
        for i, ln in enumerate(lines):
            d.text((20, y0 + i * (40 if kind == "poster" else 96)), ln, font=font, fill=(255, 255, 255, 255))
    if kind == "person":
        font = ImageFont.truetype(FONT, 120)
        initials = "".join(p[0] for p in title.split()[:2])
        d.text((w / 2, hgt / 2), initials or "?", font=font, fill=(255, 255, 255), anchor="mm")
    buf = io.BytesIO()
    if kind == "logo":
        im.save(buf, "PNG")
    else:
        im.save(buf, "JPEG", quality=80)
    return buf.getvalue()


# ---------------------------------------------------------------- audio (music + audiobooks)
# The real v2 server has no native album/artist/track types yet (see AudioDetailScreen); these
# shapes are the provisional ones Siku reads: catalog cards of type album/artist/track, album
# detail with inline `tracks`, artist detail with inline `albums`. Audiobooks follow the real
# contract: CatalogItemDetail.audiobook + FileVersion parts (presentation_kind "audiobook_part").
ARTISTS = [("The Tidelines", "Indie Rock"), ("Mara Quell", "Electronic"), ("Low Country Choir", "Folk"), ("Ostinato", "Jazz")]
ALBUMS = [(0, "Harbor Songs", 2019, 9), (0, "Weather Systems", 2022, 7), (1, "Neon Fields", 2021, 10),
          (2, "Hollow Pines", 2018, 8), (3, "Late Set", 2020, 6), (1, "Afterglow", 2024, 8)]
TRACK_WORDS = ["Lanterns", "Saltwater", "Northbound", "Quiet Engines", "Paper Boats", "Undertow", "Firelight", "Low Tide",
               "Glass Hours", "Satellites", "Driftwood", "Static Bloom", "Morning Train", "Cinder"]
AUDIOBOOKS = [
    {"slug": "the-long-orbit", "title": "The Long Orbit", "year": 2023, "authors": [0], "narrators": [1], "series": "Orbit Cycle", "parts": [[1500, 1800, 2100, 1800], [1600, 2000, 1900], [2400, 1700, 2200]]},
    {"slug": "small-kingdoms", "title": "Small Kingdoms", "year": 2021, "authors": [2], "narrators": [3, 4], "parts": [[1200, 1500, 1320, 1800, 1500, 1680, 1440, 1560]]},
    {"slug": "a-wider-orbit", "title": "A Wider Orbit", "year": 2024, "authors": [0], "narrators": [1], "series": "Orbit Cycle", "parts": [[1700, 1900, 2000], [1800, 2100]]},
    {"slug": "glass-harbor", "title": "Glass Harbor", "year": 2019, "authors": [5], "narrators": [6], "series": "Harbor Chronicles", "parts": [[2200, 2400, 1900, 2100]]},
    {"slug": "harbor-of-salt", "title": "Harbor of Salt", "year": 2020, "authors": [5], "narrators": [6], "series": "Harbor Chronicles", "parts": [[2000, 2300, 2100]]},
    {"slug": "1984-revisited", "title": "1984 Revisited", "year": 2018, "authors": [7], "narrators": [2], "parts": [[1500, 1500, 1500, 1500]]},
    {"slug": "midnight-ledger", "title": "Midnight Ledger", "year": 2022, "authors": [7], "narrators": [4], "parts": [[1800, 1600, 1700, 1900, 1500]]},
    {"slug": "the-quiet-shore", "title": "The Quiet Shore", "year": 2017, "authors": [2], "narrators": [3], "series": "Harbor Chronicles", "parts": [[1300, 1400, 1600]]},
]
# Groups that have cover stacks (the others exercise the initials placeholder).
GROUP_COVERS = {"Ava Thornton", "Orbit Cycle", "Harbor Chronicles"}
AUDIO_FILES = {}


def slug(t):
    return re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")


def artist_card(i):
    name, genre = ARTISTS[i]
    cid = "artist:" + slug(name)
    return {"content_id": cid, "type": "artist", "title": name, "genres": [genre], "keywords": [], "status": "matched",
            "poster_url": img("poster", "artist-" + slug(name))}


def album_tracks(ai):
    art, title, year, n = ALBUMS[ai]
    out = []
    for k in range(n):
        tid = "track:%s-%d" % (slug(title), k + 1)
        dur = 150 + (h(tid) % 200)
        fid = "a%d%02d" % (ai + 1, k + 1)
        AUDIO_FILES[fid] = {"duration": dur, "container": "mp3", "content_id": tid}
        out.append({"content_id": tid, "type": "track", "title": TRACK_WORDS[(ai * 3 + k) % len(TRACK_WORDS)] + ("" if k < 5 else " (Reprise)"),
                    "track_number": k + 1, "disc_number": 1, "duration_seconds": dur, "file_id": fid,
                    "artist": ARTISTS[art][0], "album": title, "album_id": "album:" + slug(title),
                    "poster_url": img("poster", "album-" + slug(title))})
    return out


def album_card(ai):
    art, title, year, n = ALBUMS[ai]
    return {"content_id": "album:" + slug(title), "type": "album", "title": title, "year": year, "artist": ARTISTS[art][0],
            "artist_id": artist_card(art)["content_id"], "genres": [ARTISTS[art][1]], "keywords": [], "status": "matched",
            "duration_seconds": sum(t["duration_seconds"] for t in album_tracks(ai)), "track_count": n,
            "poster_url": img("poster", "album-" + slug(title))}


def audiobook_card(bi):
    b = AUDIOBOOKS[bi]
    cid = "audiobook:" + b["slug"]
    total = sum(sum(p) for p in b["parts"])
    pos = STATE["progress"].get(cid, 0)
    return {"content_id": cid, "type": "audiobook", "title": b["title"], "year": b["year"], "genres": ["Fiction"], "keywords": [],
            "status": "matched", "duration_seconds": total, "position_seconds": pos or None,
            "authors": [PEOPLE[i] for i in b["authors"]], "narrators": [PEOPLE[i] for i in b["narrators"]],
            "series_name": b.get("series"), "poster_url": img("poster", "book-" + b["slug"])}


def sort_title(t):
    """The server sorts on a sort title without the leading article."""
    for art in ("The ", "A ", "An "):
        if t.startswith(art):
            return t[len(art):]
    return t


def catalog_filter(items, q):
    """Shared GET /api/v2/catalog + POST /api/v2/catalog/query filters: name_prefix and rule groups
    (the client sends author / series "is" rules and genre "contains" rules), then sort."""
    prefix = q.get("name_prefix", [""])[0]
    if prefix:
        if prefix == "#":
            items = [i for i in items if not sort_title(i["title"])[:1].isalpha()]
        else:
            items = [i for i in items if sort_title(i["title"]).lower().startswith(prefix.lower())]
    for group in q.get("_groups", []):
        match_any = group.get("match") == "any"
        rules = group.get("rules") or []

        def rule_ok(item, rule):
            field, value = rule.get("field"), rule.get("value")
            if field == "author":
                return value in item.get("authors", [])
            if field == "narrator":
                return value in item.get("narrators", [])
            if field == "series":
                return value == item.get("series_name")
            if field == "genre":
                return value in item.get("genres", [])
            if field == "watched":
                return (item["content_id"] in STATE["watched"]) == (str(value).lower() == "true")
            if field == "in_progress":
                return bool(STATE["progress"].get(item["content_id"])) == (str(value).lower() == "true")
            if field == "favorited":
                return (item["content_id"] in STATE["favorites"]) == (str(value).lower() == "true")
            if field == "in_watchlist":
                return (item["content_id"] in STATE["watchlist"]) == (str(value).lower() == "true")
            return True

        if rules:
            items = [i for i in items if (any if match_any else all)(rule_ok(i, r) for r in rules)]
    sort = q.get("sort", ["title"])[0]
    key = sort.lstrip("-")
    if key == "title":
        items = sorted(items, key=lambda i: sort_title(i["title"]).lower(), reverse=sort.startswith("-"))
    elif key in ("year", "runtime", "rating", "rating_imdb", "duration_seconds"):
        items = sorted(items, key=lambda i: (i.get("rating_imdb" if key == "rating" else key) or 0), reverse=sort.startswith("-"))
    return items


def audiobook_groups(q):
    """GET /api/v2/catalog/audiobook-groups: AudiobookGroupCollection built from the books."""
    group_by = q.get("group_by", [""])[0]
    groups = {}
    for bi, b in enumerate(AUDIOBOOKS):
        card = audiobook_card(bi)
        if group_by == "author":
            names = card["authors"]
        elif group_by == "narrator":
            names = card["narrators"]
        else:
            names = [b["series"]] if b.get("series") else []
        for name in names:
            g = groups.setdefault(name, {"name": name, "item_count": 0, "total_duration_seconds": 0, "in_progress_count": 0,
                                         "finished_count": 0, "poster_urls": []})
            g["item_count"] += 1
            g["total_duration_seconds"] += card["duration_seconds"]
            if STATE["progress"].get(card["content_id"]):
                g["in_progress_count"] += 1
            if card["content_id"] in STATE["watched"]:
                g["finished_count"] += 1
            if name in GROUP_COVERS and len(g["poster_urls"]) < 4:
                g["poster_urls"].append(card["poster_url"])
    out = list(groups.values())
    text = q.get("q", [""])[0].lower()
    if text:
        out = [g for g in out if g["name"].lower().startswith(text)]
    sort = q.get("sort", ["name"])[0]
    if sort == "count":
        out.sort(key=lambda g: -g["item_count"])
    elif sort == "duration":
        out.sort(key=lambda g: -g["total_duration_seconds"])
    else:
        out.sort(key=lambda g: g["name"].lower())
    return out


def audiobook_detail(bi):
    b = AUDIOBOOKS[bi]
    d = audiobook_card(bi)
    total = d["duration_seconds"]
    versions, chno = [], 0
    for pi, chapters in enumerate(b["parts"]):
        fid = "b%d%d" % (bi + 1, pi + 1)
        dur = sum(chapters)
        AUDIO_FILES[fid] = {"duration": dur, "container": "m4b", "content_id": d["content_id"]}
        chs, t = [], 0
        for ci, c in enumerate(chapters):
            chno += 1
            chs.append({"index": ci, "title": "Chapter %d: %s" % (chno, TRACK_WORDS[(chno + bi) % len(TRACK_WORDS)]),
                        "start_seconds": t, "end_seconds": t + c, "source": "embedded"})
            t += c
        versions.append({"file_id": fid, "resolution": "", "codec_video": "", "codec_audio": "aac", "container": "m4b", "hdr": False,
                         "file_size": dur * 16000, "duration": dur, "bitrate": 128, "added_at": "2026-01-01T00:00:00Z", "chapters": chs,
                         "presentation_kind": "audiobook_part", "presentation_group_key": "default",
                         "presentation_part_index": pi + 1, "presentation_part_total": len(b["parts"])})
    pos = STATE["progress"].get(d["content_id"], 0)
    d.update({
        "overview": "A slow-burning story about distance, signal and the people who wait on the ground. " * 3,
        "versions": versions, "playback_variants": [],
        "user_state": {"played": False, "is_favorite": d["content_id"] in STATE["favorites"], "in_watchlist": False},
        "user_data": {"position_seconds": pos, "duration_seconds": total, "played": False, "is_in_progress": pos > 0,
                      "last_file_id": versions[0]["file_id"]},
        "audiobook": {"authors": [{"name": PEOPLE[i], "person_id": str(100 + i)} for i in b["authors"]],
                      "narrators": [{"name": PEOPLE[i], "person_id": str(100 + i)} for i in b["narrators"]],
                      "total_duration_seconds": total, "publisher": "Mock House Audio", "other_narrations": [],
                      "related": {"also_by_author": [{"content_id": audiobook_card(j)["content_id"], "title": AUDIOBOOKS[j]["title"],
                                                      "poster_url": audiobook_card(j)["poster_url"], "year": AUDIOBOOKS[j]["year"]}
                                                     for j in range(len(AUDIOBOOKS)) if j != bi],
                                  "similar": []}},
    })
    return d


def audio_detail(cid):
    for ai in range(len(ALBUMS)):
        c = album_card(ai)
        if c["content_id"] == cid:
            c.update(tracks=album_tracks(ai), overview="The %s record from %s." % (c["title"], c["artist"]),
                     user_state={"played": False, "is_favorite": cid in STATE["favorites"], "in_watchlist": False})
            return c
        for t in album_tracks(ai):
            if t["content_id"] == cid:
                d = dict(t)
                d["versions"] = [{"file_id": t["file_id"], "resolution": "", "codec_video": "", "codec_audio": "mp3", "container": "mp3", "hdr": False,
                                  "file_size": 1, "duration": t["duration_seconds"], "bitrate": 320, "added_at": "2026-01-01T00:00:00Z"}]
                return d
    for i in range(len(ARTISTS)):
        a = artist_card(i)
        if a["content_id"] == cid:
            a.update(albums=[album_card(ai) for ai in range(len(ALBUMS)) if ALBUMS[ai][0] == i],
                     overview="%s make %s records." % (a["title"], ARTISTS[i][1].lower()),
                     user_state={"played": False, "is_favorite": cid in STATE["favorites"], "in_watchlist": False})
            return a
    for bi in range(len(AUDIOBOOKS)):
        if audiobook_card(bi)["content_id"] == cid:
            return audiobook_detail(bi)
    return None


def audio_route(handler, method, p, q, b):
    """Returns True when it answered the request; other routes fall through untouched."""
    if p == "/api/v2/catalog/audiobook-groups" and method == "GET":
        if q.get("group_by", [""])[0] not in ("author", "narrator", "series"):
            handler.problem(422, "validation_failed", "group_by must be author, narrator or series")
            return True
        groups = audiobook_groups(q) if q.get("library_id", [""])[0] == "4" else []
        handler.send(200, page(groups, q))
        return True
    if p == "/api/v2/catalog" and method == "GET":
        lib = q.get("library_id", [""])[0]
        typ = q.get("type", [""])[0]
        if lib not in ("3", "4") and typ not in ("album", "artist", "track", "audiobook"):
            return False
        if lib == "4" or typ == "audiobook":
            items = [audiobook_card(i) for i in range(len(AUDIOBOOKS))]
        elif typ == "artist":
            items = [artist_card(i) for i in range(len(ARTISTS))]
        elif typ == "track":
            items = [t for ai in range(len(ALBUMS)) for t in album_tracks(ai)]
        else:
            items = [album_card(i) for i in range(len(ALBUMS))]
        text = q.get("q", [""])[0].lower()
        if text:
            items = [i for i in items if text in i["title"].lower()]
        handler.send(200, page(catalog_filter(items, q), q))
        return True
    m = re.match(r"^/api/v2/catalog/items/([^/]+)$", p)
    if m:
        d = audio_detail(m.group(1))
        if d is None:
            return False
        handler.send(200, d)
        return True
    m = re.match(r"^/api/v2/library/([34])/sections$", p)
    if m:
        if m.group(1) == "3":
            secs = [{"id": "music_albums", "section_type": "recently_added", "title": "Recently Added in Music", "featured": False,
                     "total_count": len(ALBUMS), "items": [album_card(i) for i in range(len(ALBUMS))]},
                    {"id": "music_artists", "section_type": "custom_filter", "title": "Artists", "featured": False,
                     "total_count": len(ARTISTS), "items": [artist_card(i) for i in range(len(ARTISTS))]}]
        else:
            secs = [{"id": "books_recent", "section_type": "recently_added", "title": "Recently Added in Audiobooks", "featured": False,
                     "total_count": len(AUDIOBOOKS), "items": [audiobook_card(i) for i in range(len(AUDIOBOOKS))]}]
        handler.send(200, {"sections": secs})
        return True
    if p == "/api/v2/playback/start" and method == "POST" and b.get("file_id") in AUDIO_FILES:
        f = AUDIO_FILES[b["file_id"]]
        sid = uuid.uuid4().hex
        STATE["sessions"][sid] = b
        LOG.append("START " + json.dumps(b)[:400])
        mime = "audio/mpeg" if f["container"] == "mp3" else "audio/mp4"
        handler.send(201, {"protocol_version": 3, "server_features": ["playback_plan_v3", "neutral_playback_v3_contract_v1", "sequenced_progress_v1"],
                           "outcome": "playable", "session_id": sid,
                           "playback_plan": {"protocol_version": 3, "plan_id": "plan:a", "plan_attempt_key": "v3:a", "session_id": sid,
                                             "delivery": "original_http",
                                             "stream": {"url": "/mock-media/%s.%s?st=abc" % (sid, f["container"]), "protocol": "http_progressive",
                                                        "container": f["container"], "mime_type": mime, "headers": {}, "header_refresh": "none"},
                                             "timeline": {"source_start_seconds": b.get("start_position") or 0, "player_start_seconds": b.get("start_position") or 0,
                                                          "timeline_offset_seconds": 0, "can_seek_anywhere": True},
                                             "subtitle": {"mode": "off", "inventory": []},
                                             "source": {"media_file_id": b["file_id"], "duration_seconds": f["duration"], "audio_codec": "aac"}}})
        return True
    if p == "/api/v2/sync/progress" and method == "POST":
        items = b.get("items") or []
        res = []
        for i, it in enumerate(items):
            STATE["progress"][it.get("media_item_id")] = (it.get("position_ms") or 0) / 1000.0
            res.append({"index": i, "media_item_id": it.get("media_item_id"), "status": "success"})
        LOG.append("SYNC " + json.dumps(b)[:200])
        handler.send(200, {"items": res, "summary": {"total": len(res), "succeeded": len(res), "failed": 0}})
        return True
    return False


for _ai in range(len(ALBUMS)):
    album_tracks(_ai)
for _bi in range(len(AUDIOBOOKS)):
    audiobook_detail(_bi)


# ---------------------------------------------------------------- media requests (/api/v2/requests)
# Shapes follow contracts/api/v2/openapi.json + fixtures (request_status_ok, list_my_requests_ok,
# create_request_ok, cancel_request_ok, admin_requests_ok). TMDB titles are synthetic; their
# poster_path/backdrop_path are absolute mock-img URLs (the client passes absolute URLs through).
# User "1" (laura, admin) owns r-1..r-3 and r-6; user "2" asked for r-4 (pending) and r-5 (failed).
REQ_TITLES = [
    # (media_type, tmdb_id, title, year, genre, library_content_id or None)
    ("movie", 9001, "Starfall", 2025, "Science Fiction", None),
    ("movie", 9002, "The Glass Archive", 2024, "Thriller", None),
    ("movie", 9003, "Harbor of Ghosts", 2023, "Drama", None),
    ("movie", 9004, "Red Meridian", 2022, "Western", None),
    ("movie", 9005, "Paper Lanterns", 2026, "Animation", None),
    ("movie", 9006, "Cold Engines", 2021, "Action", None),
    ("movie", 9007, "Northern Lights", 2003, "Drama", "movie:northern-lights"),
    ("movie", 9008, "A Field in Winter", 2026, "Romance", None),
    ("series", 9101, "Lowland", 2024, "Crime", None),
    ("series", 9102, "The Understudy", 2025, "Comedy", None),
    ("series", 9103, "Deep Water", 2023, "Documentary", None),
    ("series", 9104, "Orbital", 2016, "Science Fiction", "series:orbital"),
    ("series", 9105, "Signal & Noise", 2026, "Drama", None),
]
REQ_STATE = {"requests": [], "seq": 10}


def req_ts(days_ago):
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - days_ago * 86400))


def req_title(mt, tid):
    for t in REQ_TITLES:
        if t[0] == mt and t[1] == tid:
            return t
    return None


def req_record(rid, mt, tid, user, status, outcome, state, days_ago, targets=(), **extra):
    t = req_title(mt, tid)
    rec = {
        "id": rid, "provider": "tmdb", "media_type": mt, "tmdb_id": tid, "title": t[2], "year": t[3],
        "overview": req_overview(t), "poster_path": None, "backdrop_path": None,
        "status": status, "outcome": outcome, "state": state, "seasons": [], "season_progress": [], "source": "direct",
        "requested_by_user_id": user, "requested_by_profile_id": "p-owner" if user == "1" else "p-other",
        "is_anime": False, "targets": [], "created_at": req_ts(days_ago), "updated_at": req_ts(days_ago / 2.0),
    }
    for i, (quality, tstatus) in enumerate(targets):
        rec["targets"].append({"id": "%s-t%d" % (rid, i), "request_id": rid, "quality": quality, "is_anime": False,
                               "status": tstatus, "created_at": rec["created_at"], "updated_at": rec["updated_at"]})
    if status in ("approved", "queued", "downloading", "completed"):
        rec["approved_at"] = rec["updated_at"]
    rec.update(extra)
    return rec


def req_seed():
    REQ_STATE["requests"] = [
        req_record("r-1", "movie", 9001, "1", "pending", "active", "pending", 2, [("1080p", "pending")]),
        req_record("r-2", "movie", 9002, "1", "downloading", "active", "processing", 6, [("1080p", "downloading"), ("4K", "queued")]),
        req_record("r-3", "series", 9104, "1", "completed", "active", "available", 30, [("1080p", "completed")],
                   library_content_id="series:orbital", completed_at=req_ts(20)),
        req_record("r-4", "series", 9102, "2", "pending", "active", "pending", 1),
        req_record("r-5", "movie", 9003, "2", "failed", "failed", "failed", 4, [("1080p", "failed")],
                   last_error="one or more fulfillment targets failed"),
        req_record("r-6", "movie", 9004, "1", "pending", "declined", "declined", 9, outcome_reason="Not available in your region"),
    ]


def req_overview(t):
    return "%s is a %s %s from %d. Mock TMDB entry #%d, available to request on this server." % (
        t[2], t[4].lower(), "film" if t[0] == "movie" else "series", t[3], t[1])


req_seed()


def req_images(handler, rec):
    host = handler.headers.get("Host", "127.0.0.1:8097")
    key = "tmdb-%s-%s_%s" % (rec["media_type"], rec["tmdb_id"], slug(rec["title"]))
    rec["poster_path"] = "http://%s%s" % (host, img("poster", key))
    rec["backdrop_path"] = "http://%s%s" % (host, img("backdrop", key))
    return rec


def req_for_title(mt, tid):
    recs = [r for r in REQ_STATE["requests"] if r["media_type"] == mt and r["tmdb_id"] == tid]
    recs.sort(key=lambda r: r["created_at"], reverse=True)
    active = [r for r in recs if r["outcome"] == "active"]
    return (active[0] if active else (recs[0] if recs else None))


def req_annotation(t):
    mt, tid, lib = t[0], t[1], t[5]
    r = req_for_title(mt, tid)
    state = {"requestable": True, "following": False, "requested_by_viewer": False}
    if r is not None and r["outcome"] != "cancelled":
        state.update({"status": r["status"], "state": r["state"], "request_id": r["id"],
                      "requested_by_viewer": r["requested_by_user_id"] == "1"})
        state["requestable"] = r["outcome"] in ("declined", "failed")
    if lib and (r is None or r["outcome"] != "active" or r["state"] == "available"):
        state["requestable"] = False
        state["reason"] = "already_available"
    return state


def req_result(handler, t):
    res = {"media_type": t[0], "tmdb_id": t[1], "title": t[2], "year": t[3], "overview": req_overview(t),
           "release_date": "%d-05-01" % t[3], "popularity": 50.0 + t[1] % 50, "vote_average": round(6.0 + (t[1] % 30) / 10.0, 1),
           "availability": "available" if t[5] else "missing", "request": req_annotation(t), "in_watchlist": False}
    if t[5]:
        res["library_content_id"] = t[5]
    return req_images(handler, res)


def req_page(handler, titles):
    return {"page": 1, "total_pages": 1, "total_results": len(titles), "results": [req_result(handler, t) for t in titles]}


def req_collection(handler, recs, q):
    recs = [req_images(handler, dict(r)) for r in recs]
    limit = int((q.get("limit") or ["50"])[0])
    cursor = (q.get("cursor") or ["o0"])[0]
    offset = int(cursor[1:]) if cursor.startswith("o") and cursor[1:].isdigit() else 0
    chunk = recs[offset:offset + limit]
    page = {"has_more": offset + limit < len(recs)}
    if page["has_more"]:
        page["next_cursor"] = "o%d" % (offset + limit)
    return {"items": chunk, "page": page}


def req_filter(recs, q):
    st = (q.get("status") or [None])[0]
    oc = (q.get("outcome") or [None])[0]
    mt = (q.get("media_type") or [None])[0]
    text = (q.get("q") or [None])[0]
    view = (q.get("view") or [None])[0]
    out = []
    for r in recs:
        if st and r["status"] != st:
            continue
        if oc and r["outcome"] != oc:
            continue
        if mt and r["media_type"] != mt:
            continue
        if text and not (text.lower() in r["title"].lower() or text == str(r["tmdb_id"])):
            continue
        if view == "needs_approval" and not (r["status"] == "pending" and r["outcome"] == "active"):
            continue
        if view == "failed" and r["outcome"] != "failed":
            continue
        out.append(r)
    return sorted(out, key=lambda r: r["created_at"], reverse=True)


def req_find(rid):
    for r in REQ_STATE["requests"]:
        if r["id"] == rid:
            return r
    return None


def requests_route(handler, method, p, q, b):
    if not p.startswith("/api/v2/requests") and not p.startswith("/api/v2/admin/requests"):
        return False
    if p == "/api/v2/requests/status":
        handler.send(200, {"revision": "mock-requests-1", "state": "available", "allowed": True, "requests_enabled": True,
                           "rating_restrictions_enforced": False, "follow_supported": True, "season_requests_supported": True,
                           "missing_seasons_requestable": False, "download_progress_supported": True,
                           "watchlist_titles_supported": False, "watchlist_requests": False})
        return True
    if p == "/api/v2/admin/requests/capabilities":
        handler.send(200, {"available": True, "guarded_configuration": False, "routing": False,
                           "revision": "mock-cap-1", "state": "available", "allowed": True})
        return True
    if p == "/api/v2/requests/discover":
        movies = [t for t in REQ_TITLES if t[0] == "movie"]
        series_ = [t for t in REQ_TITLES if t[0] == "series"]
        sections = [("trending_movies", "Trending Movies", movies[:6]), ("trending_series", "Trending Series", series_[:4]),
                    ("popular_movies", "Popular Movies", movies[3:]), ("popular_series", "Popular Series", series_[1:]),
                    ("upcoming_movies", "Upcoming Movies", [t for t in movies if t[3] >= 2026])]
        items = []
        for key, title, ts in sections:
            sec = req_page(handler, ts)
            sec.update({"key": key, "title": title})
            items.append(sec)
        handler.send(200, {"items": items})
        return True
    m = re.match(r"^/api/v2/requests/discover/([a-z_]+)$", p)
    if m:
        mt = "movie" if m.group(1).endswith("movies") else "series"
        sec = req_page(handler, [t for t in REQ_TITLES if t[0] == mt])
        sec.update({"key": m.group(1), "title": m.group(1).replace("_", " ").title()})
        handler.send(200, sec)
        return True
    if p == "/api/v2/requests/search":
        text = ((q.get("q") or [""])[0]).strip().lower()
        mt = (q.get("media_type") or ["all"])[0]
        if not text:
            handler.problem(422, "validation_failed", "q is required")
            return True
        if mt not in ("movie", "series", "all"):
            handler.problem(422, "validation_failed", "media_type must be movie, series or all")
            return True
        # Any query matches something, so the simulator (which cannot type) still shows the row.
        hits = [t for t in REQ_TITLES if text in t[2].lower()] or list(REQ_TITLES[:6])
        hits = [t for t in hits if mt == "all" or t[0] == mt]
        handler.send(200, req_page(handler, hits))
        return True
    m = re.match(r"^/api/v2/requests/detail/(movie|series)/(\d+)$", p)
    if m:
        t = req_title(m.group(1), int(m.group(2)))
        if t is None:
            handler.problem(404, "not_found", "Title not found")
            return True
        d = req_result(handler, t)
        d.update({"imdb_id": "tt%07d" % t[1], "original_title": t[2], "tagline": "Some stories are worth the wait.",
                  "genres": [t[4], "Drama" if t[4] != "Drama" else "Mystery"], "vote_count": 1200 + t[1] % 900,
                  "status": "Released", "homepage": "", "content_rating": "PG-13" if t[0] == "movie" else "TV-14",
                  "production_companies": ["Mock Pictures"], "networks": [] if t[0] == "movie" else ["Mock Network"],
                  "cast": [{"name": PEOPLE[i % len(PEOPLE)], "character": "Role %d" % (i + 1), "order": i} for i in range(4)],
                  "creators": [] if t[0] == "movie" else [PEOPLE[t[1] % len(PEOPLE)]],
                  "director": PEOPLE[(t[1] + 3) % len(PEOPLE)] if t[0] == "movie" else "",
                  "recommendations": [req_result(handler, o) for o in REQ_TITLES if o[1] != t[1]][:6], "seasons": []})
        if t[0] == "movie":
            d["runtime"] = 95 + t[1] % 50
        else:
            d.update({"number_of_seasons": 1 + t[1] % 3, "number_of_episodes": 8 * (1 + t[1] % 3), "first_air_date": "%d-01-10" % t[3]})
        handler.send(200, d)
        return True
    if p == "/api/v2/requests" and method == "POST":
        mt, tid = b.get("media_type"), b.get("tmdb_id")
        t = req_title(mt, tid) if isinstance(tid, int) else None
        if t is None or not b.get("title"):
            handler.problem(422, "validation_failed", "media_type, tmdb_id and title are required")
            return True
        cur = req_for_title(mt, tid)
        if cur is not None and cur["outcome"] == "active":
            handler.problem(409, "conflict", "This title has already been requested")
            return True
        REQ_STATE["seq"] += 1
        rec = req_record("r-%d" % REQ_STATE["seq"], mt, tid, "1", "pending", "active", "pending", 0)
        REQ_STATE["requests"].append(rec)
        handler.send(201, req_images(handler, dict(rec)))
        return True
    if p == "/api/v2/requests/mine":
        mine = req_filter([r for r in REQ_STATE["requests"] if r["requested_by_user_id"] == "1"], q)
        handler.send(200, req_collection(handler, mine, q))
        return True
    if p == "/api/v2/admin/requests":
        handler.send(200, req_collection(handler, req_filter(REQ_STATE["requests"], q), q))
        return True
    m = re.match(r"^/api/v2/requests/([^/]+)(/cancel)?$", p)
    if m:
        r = req_find(m.group(1))
        if r is None or r["requested_by_user_id"] != "1":
            handler.problem(404, "not_found", "Request not found")
            return True
        if m.group(2):
            if method != "POST":
                return False
            if not (r["status"] == "pending" and r["outcome"] == "active"):
                handler.problem(409, "invalid_state", "This request can no longer be changed")
                return True
            r.update({"outcome": "cancelled", "state": "cancelled", "updated_at": req_ts(0)})
        handler.send(200, req_images(handler, dict(r)))
        return True
    m = re.match(r"^/api/v2/admin/requests/([^/]+)/(approve|decline|retry)$", p)
    if m and method == "POST":
        r = req_find(m.group(1))
        if r is None:
            handler.problem(404, "not_found", "Request not found")
            return True
        action = m.group(2)
        if action in ("approve", "decline") and not (r["status"] == "pending" and r["outcome"] == "active"):
            handler.problem(409, "invalid_state", "This request can no longer be changed")
            return True
        if action == "retry" and r["outcome"] != "failed":
            handler.problem(409, "invalid_state", "This request can no longer be changed")
            return True
        now = req_ts(0)
        if action == "approve":
            r.update({"status": "approved", "state": "approved", "approved_at": now, "updated_at": now})
        elif action == "decline":
            r.update({"outcome": "declined", "state": "declined", "updated_at": now})
            if b.get("reason"):
                r["outcome_reason"] = b["reason"]
        else:
            r.update({"status": "queued", "outcome": "active", "state": "approved", "last_error": "", "updated_at": now})
            for tg in r["targets"]:
                tg["status"] = "queued"
        handler.send(200, req_images(handler, dict(r)))
        return True
    return False


# ---------------------------------------------------------------- subtitles (search, download, AI, sync)
# Shapes follow contracts/api/v2/openapi.json (SubtitleSearchResults, StoredSubtitle, SubtitleAIJob,
# SubtitleSyncState …) and the fixtures subtitles_search_partial / subtitle_download /
# subtitle_ai_create / subtitle_ai_quota. Jobs advance a step on every read so the client's polling
# can be exercised: an AI job completes on its third read, a sync job on its third read.
SUBS = {"stored": [], "ai_jobs": {}, "sync": {}, "seq": 100, "rev": {}}
EXTERNAL_SYNC_KEY = "external-" + "f903" * 16


def sub_file_id(b, q=None):
    return str((b or {}).get("media_file_id") or "42")


def sub_sync_job(status, phase=None, progress=None, result=None, trigger="auto", failure=None, jid=None):
    job = {"id": jid or str(SUBS["seq"]), "status": status, "trigger": trigger, "confidence": None,
           "created_at": "2026-10-06T00:00:00.000Z", "finished_at": None}
    if phase:
        job["phase"] = phase
    if progress is not None:
        job["progress"] = progress
    if result is not None:
        job["result"] = result
        job["confidence"] = 0.93
        job["finished_at"] = "2026-10-06T00:01:00.000Z"
    if failure:
        job["failure"] = failure
    return job


def sub_sync_state(key, fid):
    """The SubtitleSyncState for a key, creating the sidecar's entry on first use."""
    st = SUBS["sync"].get(key)
    if st is None and key == EXTERNAL_SYNC_KEY:
        st = {"key": key, "media_file_id": fid, "source": "external", "language": "eng", "format": "srt",
              "label": "Glass.City.2019.1080p.srt", "timing": {"offset_ms": 0, "scale": 1}, "sync": None, "_reads": 0}
        SUBS["sync"][key] = st
    return st


def sub_sync_advance(st):
    """A running job moves one step per read: queued → analyzing → matching → synced (+2.3 s)."""
    job = st.get("sync")
    if not job or job["status"] not in ("pending", "running"):
        return
    st["_reads"] = st.get("_reads", 0) + 1
    n = st["_reads"]
    if n == 1:
        job.update(status="running", phase="analyzing", progress=0.35)
    elif n == 2:
        job.update(status="running", phase="matching", progress=0.7)
    else:
        job.pop("phase", None)
        job.pop("progress", None)
        job.update(status="synced", result={"offset_ms": 2300, "scale": 1}, confidence=0.93, finished_at="2026-10-06T00:01:00.000Z")
        st["timing"] = {"offset_ms": 2300, "scale": 1}
        SUBS["rev"][st["key"]] = SUBS["rev"].get(st["key"], 1) + 1


def sub_public(st):
    out = {k: v for k, v in st.items() if not k.startswith("_")}
    if out.get("sync") is None:
        out.pop("sync", None)
    return out


def sub_stored_public(rec):
    out = {k: v for k, v in rec.items() if not k.startswith("_")}
    st = SUBS["sync"].get("stored-" + rec["id"])
    if st is not None:
        out["timing"] = st["timing"]
        if st.get("sync"):
            out["sync"] = dict(st["sync"], subtitle_id=rec["id"])
    return out


def sub_store(fid, provider, language, release, fmt="srt", score=0.0, hi=False, auto_sync=True):
    SUBS["seq"] += 1
    rec = {"id": str(SUBS["seq"]), "media_file_id": fid, "provider": provider, "language": language, "format": fmt,
           "release_name": release, "score": score, "hearing_impaired": hi, "created_at": "2026-10-06T00:00:00.000Z",
           "timing": {"offset_ms": 0, "scale": 1}}
    SUBS["stored"].append(rec)
    key = "stored-" + rec["id"]
    SUBS["seq"] += 1
    SUBS["sync"][key] = {"key": key, "media_file_id": fid, "source": "downloaded", "stored_subtitle_id": rec["id"],
                         "language": language, "format": fmt, "label": release or provider, "timing": {"offset_ms": 0, "scale": 1},
                         "sync": sub_sync_job("pending", phase="queued", progress=0.0) if auto_sync else None, "_reads": 0}
    return rec


def playback_decision(sid, position, fid):
    """The start / replan decision: inventory = the file's sidecar plus every stored subtitle."""
    inventory = [{"track_id": "file:%s:subtitle:0" % fid, "combined_index": 0, "source": "external", "codec": "srt", "language": "eng",
                  "label": "English", "forced": False, "default": False, "hearing_impaired": False, "delivery": "sidecar",
                  "url": "/api/v2/stream/%s/subtitles/0.vtt?file_id=%s&external_subtitle_key=f903" % (sid, fid), "sync_key": EXTERNAL_SYNC_KEY}]
    for rec in SUBS["stored"]:
        if rec["media_file_id"] != fid:
            continue
        idx = len(inventory)
        inventory.append({"track_id": "file:%s:subtitle:%d" % (fid, idx), "combined_index": idx, "source": "downloaded", "codec": rec["format"],
                          "language": rec["language"], "label": rec["release_name"] or rec["provider"], "forced": False, "default": False,
                          "hearing_impaired": rec["hearing_impaired"], "delivery": "sidecar",
                          "url": "/api/v2/stream/%s/subtitles/%d.vtt?file_id=%s&downloaded_subtitle_id=%s" % (sid, idx, fid, rec["id"]),
                          "sync_key": "stored-" + rec["id"]})
    return {"protocol_version": 3, "server_features": ["playback_plan_v3", "neutral_playback_v3_contract_v1", "sequenced_progress_v1"],
            "outcome": "playable", "session_id": sid,
            "playback_plan": {"protocol_version": 3, "plan_id": "plan:%d" % (len(SUBS["stored"]) + 1), "plan_attempt_key": "v3:%d" % (len(SUBS["stored"]) + 1), "session_id": sid,
                              "delivery": "original_http",
                              "stream": {"url": "/mock-media/%s.mp4?st=abc" % sid, "protocol": "http_progressive", "container": "mp4", "mime_type": "video/mp4", "headers": {}, "header_refresh": "none"},
                              "timeline": {"player_start_seconds": position, "timeline_offset_seconds": 0, "can_seek_anywhere": True},
                              "selected_tracks": {"audio": {"id": "file:%s:audio:0" % fid, "index": 0}},
                              "subtitle": {"mode": "off", "inventory": inventory},
                              "source": {"media_file_id": fid, "duration_seconds": 3000}}}


def subtitle_route(handler, method, p, q, b):
    if not p.startswith("/api/v2/subtitles"):
        return False
    if p == "/api/v2/subtitles/ai/status":
        handler.send(200, {"revision": "mock-ai-1", "state": "available", "allowed": True, "enabled": True, "transcribe_enabled": True})
        return True
    if p == "/api/v2/subtitles/ai/quota":
        handler.send(200, {"limited": True, "limit": 5, "used": 2, "remaining": 3, "period": "day"})
        return True
    if p == "/api/v2/subtitles/providers/status":
        handler.send(200, {"revision": "mock-prov-1", "state": "available", "allowed": True, "schema_version": 1, "enabled": True,
                           "providers": ["opensubtitles", "subdl"]})
        return True
    if p == "/api/v2/subtitles/sync/status":
        handler.send(200, {"revision": "mock-sync-1", "state": "available", "allowed": True, "auto_sync": True, "external": True})
        return True
    if p == "/api/v2/subtitles/ai/translate" and method == "POST":
        LOG.append("AI TRANSLATE " + json.dumps(b))
        for k in ("media_file_id", "kind", "source_index", "source_language", "target_language", "start_position"):
            if k not in b:
                handler.problem(422, "validation_failed", "%s is required" % k)
                return True
        if b["kind"] not in ("translate", "transcribe", "transcribe_translate"):
            handler.problem(422, "validation_failed", "unknown kind")
            return True
        SUBS["seq"] += 1
        job = {"id": str(SUBS["seq"]), "media_file_id": sub_file_id(b), "kind": b["kind"], "source_index": b["source_index"],
               "source_language": b["source_language"], "target_language": b["target_language"], "engine": "mock", "model": "mock-1",
               "status": "pending", "progress": 0.0, "progress_message": "", "result_subtitle_id": None,
               "created_at": "2026-10-06T00:00:00.000Z", "updated_at": "2026-10-06T00:00:00.000Z", "_reads": 0}
        SUBS["ai_jobs"][job["id"]] = job
        handler.send(202, {"job": {k: v for k, v in job.items() if not k.startswith("_")}, "live_delivery_attached": False})
        return True
    m = re.match(r"^/api/v2/subtitles/ai/jobs/([^/]+)(/cancel)?$", p)
    if m:
        job = SUBS["ai_jobs"].get(m.group(1))
        if job is None:
            handler.problem(404, "not_found", "Unknown job")
            return True
        if m.group(2):
            job.update(status="cancelled")
            LOG.append("AI CANCEL " + job["id"])
            handler.send(204)
            return True
        if job["status"] in ("pending", "running"):
            job["_reads"] += 1
            if job["_reads"] == 1:
                job.update(status="running", progress=0.34, progress_message="Transcribing" if job["kind"] != "translate" else "Translating")
            elif job["_reads"] == 2:
                job.update(status="running", progress=0.72, progress_message="Translating")
            else:
                rec = sub_store(job["media_file_id"], "ai", job["target_language"], "AI %s" % job["kind"].replace("_", " "), auto_sync=False)
                job.update(status="completed", progress=1.0, progress_message="", result_subtitle_id=rec["id"])
        handler.send(200, {"job": {k: v for k, v in job.items() if not k.startswith("_")}})
        return True
    if p == "/api/v2/subtitles/search" and method == "POST":
        LOG.append("SUB SEARCH " + json.dumps(b))
        langs = b.get("languages") or ["en"]
        lang = langs[0]
        results = [
            {"id": "os-%s-1" % lang, "provider": "opensubtitles", "language": lang, "release_name": "Glass.City.2019.1080p.BluRay.x264-SPARKS", "format": "srt",
             "score": 92.5, "downloads": 18234, "hearing_impaired": False, "upload_date": "2024-02-01T00:00:00.000Z"},
            {"id": "sdl-%s-7" % lang, "provider": "subdl", "language": lang, "release_name": "Glass City (2019) WEB-DL 1080p HI", "format": "srt",
             "score": 61.0, "downloads": 2310, "hearing_impaired": True},
            {"id": "os-%s-9" % lang, "provider": "opensubtitles", "language": lang, "release_name": "glass.city.dvdrip.xvid", "format": "srt",
             "score": 24.0, "downloads": 410, "hearing_impaired": False},
        ]
        handler.send(200, {"results": results, "warnings": ["One or more subtitle providers could not complete the search."] if lang == "en" else []})
        return True
    if p == "/api/v2/subtitles/download" and method == "POST":
        LOG.append("SUB DOWNLOAD " + json.dumps(b))
        for k in ("media_file_id", "provider", "subtitle_id", "language", "release_name", "score", "hearing_impaired"):
            if k not in b:
                handler.problem(422, "validation_failed", "%s is required" % k)
                return True
        rec = sub_store(sub_file_id(b), b["provider"], b["language"], b["release_name"], score=b["score"], hi=b["hearing_impaired"])
        handler.send(200, {"subtitle": sub_stored_public(rec)})
        return True
    m = re.match(r"^/api/v2/subtitles/([^/]+)/sync/([^/]+)(/timing)?$", p)
    if m:
        fid, key = m.group(1), m.group(2)
        st = sub_sync_state(key, fid)
        if st is None or st["media_file_id"] != fid:
            handler.problem(404, "not_found", "Unknown subtitle")
            return True
        rev = SUBS["rev"].get(key, 1)
        if m.group(3):
            if method != "PUT":
                return False
            if "If-Match" not in handler.headers:
                handler.problem(428, "precondition_required", "If-Match is required")
                return True
            if handler.headers["If-Match"] != 'W/"%d"' % rev:
                handler.problem(412, "precondition_failed", "The subtitle changed")
                return True
            st["timing"] = {"offset_ms": int(b.get("offset_ms", 0)), "scale": b.get("scale", 1)}
            SUBS["rev"][key] = rev + 1
            LOG.append("SUB TIMING %s %s" % (key, json.dumps(st["timing"])))
            handler.send(200, {"subtitle": sub_public(st)})
            return True
        if method == "POST":
            SUBS["seq"] += 1
            st["sync"] = sub_sync_job("pending", phase="queued", progress=0.0, trigger="manual")
            st["_reads"] = 0
            LOG.append("SUB SYNC START " + key)
            handler.send(202, {"subtitle": sub_public(st)})
            return True
        sub_sync_advance(st)
        handler.send(200, {"subtitle": sub_public(st)}, extra={"ETag": 'W/"%d"' % SUBS["rev"].get(key, 1)})
        return True
    m = re.match(r"^/api/v2/subtitles/([^/]+)/sync$", p)
    if m:
        fid = m.group(1)
        sub_sync_state(EXTERNAL_SYNC_KEY, fid)
        states = [sub_public(st) for st in SUBS["sync"].values() if st["media_file_id"] == fid]
        handler.send(200, {"subtitles": states})
        return True
    m = re.match(r"^/api/v2/subtitles/([^/]+)$", p)
    if m and method == "GET":
        handler.send(200, {"subtitles": [sub_stored_public(r) for r in SUBS["stored"] if r["media_file_id"] == m.group(1)]})
        return True
    return False


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        LOG.append(fmt % args)

    def send(self, code, body=None, ctype="application/json", extra=None):
        data = b""
        if body is not None:
            data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        if data:
            self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if data:
            self.wfile.write(data)

    def problem(self, code, name, title):
        self.send(code, {"type": "https://siloserver.org/docs/api/v2/problems/" + name, "title": title, "status": code}, "application/problem+json")

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n == 0:
            return {}
        try:
            return json.loads(self.rfile.read(n))
        except ValueError:
            return {}

    def authed(self):
        auth = self.headers.get("Authorization", "")
        return auth.startswith("Bearer acc-")

    def do_GET(self):
        self.route("GET")

    def do_POST(self):
        self.route("POST")

    def do_PUT(self):
        self.route("PUT")

    def do_DELETE(self):
        self.route("DELETE")

    def do_PATCH(self):
        self.route("PATCH")

    def route(self, method):
        u = urlparse(self.path)
        p = unquote(u.path)
        q = parse_qs(u.query)
        b = self.body() if method in ("POST", "PUT", "PATCH", "DELETE") else {}
        print(method, self.path, flush=True)

        if p.startswith("/mock-img/"):
            _, _, kind, name = p.split("/", 3)
            return self.send(200, make_image(kind, name.rsplit(".", 1)[0]), "image/png" if kind == "logo" else "image/jpeg")
        if p.startswith("/mock-media/"):
            return self.send(404)
        # Test control (not part of the API): empty or reseed the notifications inbox.
        if p == "/mock/notifications/clear" and method == "POST":
            STATE["notifs"] = []
            return self.send(204)
        if p == "/mock/notifications/reset" and method == "POST":
            STATE.pop("notifs", None)
            return self.send(204)
        if re.match(r"^/api/v2/stream/[^/]+/subtitles/\d+\.vtt$", p):
            LOG.append("VTT " + self.path)
            return self.send(200, b"WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nMock subtitle line\n", "text/vtt")

        # POST /api/v2/catalog/query: the same query as GET /api/v2/catalog, as a JSON body plus
        # rule `groups` (CatalogQuery). Fold it into the GET handlers.
        if p == "/api/v2/catalog/query" and method == "POST":
            for k, v in (b or {}).items():
                if k == "groups":
                    q["_groups"] = v or []
                elif v is not None:
                    q[k] = [str(v)]
            p, method = "/api/v2/catalog", "GET"

        if audio_route(self, method, p, q, b):
            return

        # ---- public
        if p == "/api/v2/system/info":
            return self.send(200, {"api_major": 2, "server_version": "mock", "contract_digest": "x", "links": {}})
        if p == "/api/v2/system/identity":
            return self.send(200, {"server_id": "mock-server-1"})
        if p == "/api/v2/system/setup":
            return self.send(200, {"needs_setup": False, "wizard_completed": True})
        if p == "/api/v2/theme/branding":
            return self.send(200, {"server_name": "Mock Silo", "name": "Mock Silo"})
        if p == "/api/v2/auth/signup":
            return self.send(200, {"enabled": False})
        if p == "/api/v2/auth/providers":
            return self.send(200, {"password_login": True, "providers": []})
        if p == "/api/v2/auth/device/capability":
            return self.send(200, {"revision": "1", "state": "available", "cancel": True, "opened_signal": True, "protocol_versions": [2]})
        if p == "/api/v2/auth/device/start" and method == "POST":
            code = "dev-" + uuid.uuid4().hex[:8]
            STATE["devices"][code] = 0
            host = self.headers.get("Host", "127.0.0.1")
            return self.send(201, {"device_code": code, "user_code": "4821-7730", "match_code": "warm pony",
                                   "verification_uri": "http://%s/activate" % host,
                                   "verification_uri_complete": "http://%s/activate?code=48217730" % host,
                                   "expires_at": "2030-01-01T00:00:00Z", "expires_in": 900, "interval": 3})
        if p == "/api/v2/auth/device/poll" and method == "POST":
            code = b.get("device_code")
            if code not in STATE["devices"]:
                return self.problem(404, "not_found", "Unknown device code")
            STATE["devices"][code] += 1
            if STATE["devices"][code] < 3:
                return self.send(200, {"status": "pending", "poll_after": 3, "opened": STATE["devices"][code] > 1})
            del STATE["devices"][code]
            return self.send(200, {"status": "approved", "tokens": tokens(), "profile_id": "", "profile_token": ""})
        if p == "/api/v2/auth/device/cancel":
            return self.send(200, {"status": "canceled"})
        if p == "/api/v2/auth/login" and method == "POST":
            if b.get("password") != "silo":
                return self.problem(401, "invalid_token", "Invalid username or password")
            return self.send(200, tokens(b.get("username", "laura")))
        if p == "/api/v2/auth/refresh":
            return self.send(200, tokens())
        if p == "/api/v2/auth/logout":
            return self.send(204)

        if not self.authed():
            return self.problem(401, "invalid_token", "Authentication required")
        if requests_route(self, method, p, q, b):
            return
        if subtitle_route(self, method, p, q, b):
            return
        if notifications_route(self, method, p, q, b):
            return

        if p == "/api/v2/account/me":
            return self.send(200, tokens()["user"])
        if p == "/api/v2/profiles":
            return self.send(200, {"items": [
                {"id": "p-owner", "name": "Laura", "avatar_url": img("avatar", "laura"), "has_pin": False, "is_primary": True},
                {"id": "p-sam", "name": "Sam", "avatar_url": "", "has_pin": False, "is_primary": False},
                {"id": "p-kids", "name": "Kids", "avatar_url": img("avatar", "kids"), "has_pin": True, "is_child": True},
            ]})
        m = re.match(r"^/api/v2/profiles/([^/]+)/verify-pin$", p)
        if m:
            if b.get("pin") == "1234":
                return self.send(200, {"valid": True, "profile_token": "ptok-1", "expires_at": None})
            return self.send(200, {"valid": False})
        if p == "/api/v2/user/libraries":
            return self.send(200, {"items": [
                {"id": "1", "name": "Movies", "type": "movies", "sort_order": 0},
                {"id": "2", "name": "Shows", "type": "series", "sort_order": 1},
                {"id": "3", "name": "Music", "type": "music", "sort_order": 2},
                {"id": "4", "name": "Audiobooks", "type": "audiobooks", "sort_order": 3},
            ]})
        if p == "/api/v2/home/sections":
            return self.send(200, home_sections())
        m = re.match(r"^/api/v2/library/([^/]+)/sections$", p)
        if m:
            secs = home_sections()["sections"]
            return self.send(200, {"sections": secs[1:] if m.group(1) == "1" else secs[2:3]})
        m = re.match(r"^/api/v2/library/([^/]+)/collections$", p)
        if m:
            cols = [{"id": "c%d" % i, "title": t, "poster_url": img("poster", "collection-" + t), "item_count": 4} for i, t in enumerate(["Award Winners", "Night Owls", "Comfort Picks"])]
            return self.send(200, {"library_id": m.group(1), "collections": cols, "groups": [], "ungrouped": {"collections": cols}})
        if p == "/api/v2/catalog/filters":
            lib = q.get("library_id", [""])[0]
            genres = GENRES
            authors, narrators, series = [], [], []
            if lib == "3":
                genres = sorted({g for _, g in ARTISTS})
            elif lib == "4":
                genres = ["Fiction"]
                authors = [g["name"] for g in audiobook_groups({"group_by": ["author"]})]
                narrators = [g["name"] for g in audiobook_groups({"group_by": ["narrator"]})]
                series = [g["name"] for g in audiobook_groups({"group_by": ["series"]})]
            return self.send(200, {"genres": genres, "studios": [], "networks": [], "countries": [], "original_languages": [], "content_ratings": ["PG", "PG-13", "R"],
                                   "authors": authors, "narrators": narrators, "series": series, "technical": {}})
        if p == "/api/v2/catalog":
            src = q.get("source", ["query"])[0]
            lib = q.get("library_id", [""])[0]
            typ = q.get("type", [""])[0]
            text = q.get("q", [""])[0].lower()
            items = all_movies() + all_series()
            if lib == "1":
                items = all_movies()
            elif lib == "2":
                items = all_series()
            if typ:
                items = [i for i in items if i["type"] == typ]
            if src == "favorites":
                items = [i for i in all_movies() + all_series() if i["content_id"] in STATE["favorites"]]
            elif src == "watchlist":
                items = [i for i in all_movies() + all_series() if i["content_id"] in STATE["watchlist"]]
            elif src in ("person", "library_collection", "section"):
                items = items[h(str(q)) % 6:][:10]
            if text:
                items = [i for i in items if text in i["title"].lower()]
            sort = q.get("sort", ["title"])[0]
            key = sort.lstrip("-")
            if key == "random":
                items = items[h(str(time.time())) % len(items):][:1] or items[:1]
            else:
                items = catalog_filter(items, q)
            return self.send(200, page(items, q))
        m = re.match(r"^/api/v2/catalog/items/(.+)$", p)
        if m:
            d = detail(m.group(1))
            return self.send(200, d) if d else self.problem(404, "not_found", "Not found")
        m = re.match(r"^/api/v2/catalog/series/([^/]+)/seasons$", p)
        if m:
            for i, s in enumerate(all_series()):
                if s["content_id"] == m.group(1):
                    _, seasons, eps = SERIES[i]
                    return self.send(200, {"items": [{"content_id": "season:%s-%d" % (s["content_id"], n), "season_number": n,
                                                       "title": "Season %d" % n, "episode_count": eps, "is_specials": False,
                                                       "poster_url": s["poster_url"]} for n in range(1, seasons + 1)]})
            return self.problem(404, "not_found", "Not found")
        m = re.match(r"^/api/v2/catalog/series/([^/]+)/seasons/(\d+)/episodes$", p)
        if m:
            for i, s in enumerate(all_series()):
                if s["content_id"] == m.group(1):
                    _, seasons, eps = SERIES[i]
                    sn = int(m.group(2))
                    return self.send(200, {"items": [episode(i, sn, e) for e in range(1, eps + 1)] if 1 <= sn <= seasons else []})
            return self.problem(404, "not_found", "Not found")
        if p == "/api/v2/catalog/people":
            text = q.get("q", [""])[0].lower()
            ppl = [{"id": str(100 + i), "name": n, "photo_url": img("person", str(100 + i))} for i, n in enumerate(PEOPLE) if text in n.lower()]
            return self.send(200, {"items": ppl})
        m = re.match(r"^/api/v2/catalog/people/([^/]+)$", p)
        if m:
            i = int(m.group(1)) - 100
            return self.send(200, {"id": m.group(1), "name": PEOPLE[i % len(PEOPLE)], "photo_url": img("person", m.group(1)),
                                   "bio": "An actor known for quiet, careful performances. " * 6, "birth_date": "1980-05-02", "birthplace": "Portland, Oregon"})
        m = re.match(r"^/api/v2/recommendations/similar/(.+)$", p)
        if m:
            return self.send(200, {"items": all_movies()[h(m.group(1)) % 10:][:12]})
        if p == "/api/v2/recommendations/discover":
            ms = all_movies()
            return self.send(200, {"items": [
                {"type": "cluster", "key": "a", "title": "Because you watched Heat", "items": ms[0:10]},
                {"type": "popular", "key": "b", "title": "Popular on Mock Silo", "items": ms[10:20]},
                {"type": "top_rated", "key": "c", "title": "Top Rated", "items": all_series()},
            ]})
        if p == "/api/v2/history":
            return self.send(200, page(all_movies()[:6], q))
        if p == "/api/v2/calendar":
            start = q.get("start", ["2026-10-05"])[0]
            y, mo, d = (int(x) for x in start.split("-"))
            events = []
            for k in range(0, 7, 2):
                day = "%04d-%02d-%02d" % (y, mo, min(28, d + k))
                e = episode(k % len(SERIES), 1, k + 1)
                events.append({"date": day, "items": [dict(e, title=e["series_title"], episode_title=e["title"], air_date=day,
                                                            local_air_date=day, watched=False, badges=["season_premiere"] if k == 0 else [])]})
            return self.send(200, {"events": events})
        m = re.match(r"^/api/v2/watch/(.+)$", p)
        if m:
            d = detail(m.group(1))
            if not d:
                return self.problem(404, "not_found", "Not found")
            vs = []
            for v in d["versions"]:
                v = dict(v)
                v["marker_segments"] = [{"kind": "intro", "start_seconds": 30, "end_seconds": 90}]
                vs.append(v)
            return self.send(200, {"content_id": d["content_id"], "type": d["type"], "title": d["title"], "versions": vs,
                                   "series_title": d.get("series_title"),
                                   "user_data": d["user_data"], "series_id": d.get("series_id"), "season_number": d.get("season_number"),
                                   "episode_number": d.get("episode_number"), "intro": {"start_seconds": 30, "end_seconds": 90}})
        if p == "/api/v2/playback/capabilities":
            return self.send(200, {"revision": "1", "state": "available", "allowed": True, "installation_id": "11111111-1111-4111-8111-111111111111",
                                   "protocol_versions": [3], "features": ["playback_plan_v3", "sequenced_progress_v1"], "deliveries": ["original_http", "server_transcode_hls"]})
        if p == "/api/v2/playback/start" and method == "POST":
            sid = uuid.uuid4().hex
            STATE["sessions"][sid] = b
            LOG.append("START " + json.dumps(b)[:400])
            print("START", json.dumps({k: b.get(k) for k in ("file_id", "audio_track_id", "subtitle_track_id", "start_position")}), flush=True)
            return self.send(201, playback_decision(sid, b.get("start_position") or 0, b.get("file_id") or "42"))
        m = re.match(r"^/api/v2/playback/([^/]+)/replan$", p)
        if m and method == "POST":
            # Same decision shape as start; the inventory lists subtitles stored since (track_change).
            LOG.append("REPLAN " + json.dumps({k: b.get(k) for k in ("operation", "position_seconds", "selected_tracks")}))
            print("REPLAN", b.get("operation"), b.get("position_seconds"), flush=True)
            if m.group(1) not in STATE["sessions"]:
                return self.problem(410, "playback_session_ended", "Session ended")
            start = STATE["sessions"][m.group(1)]
            return self.send(200, playback_decision(m.group(1), b.get("position_seconds") or 0, start.get("file_id") or "42"))
        m = re.match(r"^/api/v2/playback/([^/]+)/progress$", p)
        if m:
            return self.send(200, {"outcome": "applied", "accepted": b})
        m = re.match(r"^/api/v2/playback/([^/]+)$", p)
        if m and method == "DELETE":
            return self.send(200, {"outcome": "stopped", "stop_id": b.get("stop_id")})
        m = re.match(r"^/api/v2/(watchlist|favorites|watched)/(.+)$", p)
        if m:
            key = {"watchlist": "watchlist", "favorites": "favorites", "watched": "watched"}[m.group(1)]
            if method in ("PUT", "POST"):
                STATE[key].add(m.group(2))
            elif method == "DELETE":
                STATE[key].discard(m.group(2))
            return self.send(204)
        if p.startswith("/api/v2/home/dismissals/"):
            return self.send(204)
        if p == "/api/v2/shuffles/capabilities":
            return self.send(200, {"state": "available", "allowed": True, "revision": "1",
                                   "scope_kinds": ["library", "series", "season", "library_collection", "user_collection"]})
        if p == "/api/v2/shuffles" and method == "POST":
            scope = b.get("scope") or {}
            pool = shuffle_pool(scope.get("kind", ""), str(scope.get("id", "")))
            if pool is None:
                return self.problem(404, "not_found", "Unknown shuffle scope")
            if not pool:
                return self.problem(409, "conflict", "Nothing in this scope can play")
            sid = str(len(STATE["shuffles"]) + 1)
            order = [c["content_id"] for c in pool]
            random.shuffle(order)
            STATE["shuffles"][sid] = {"id": sid, "scope": shuffle_scope(scope.get("kind", ""), str(scope.get("id", ""))), "order": order, "pos": 0,
                                      "created_at": "2026-10-06T00:00:00.000Z"}
            LOG.append("SHUFFLE CREATE " + json.dumps(b))
            return self.send(201, shuffle_view(STATE["shuffles"][sid]))
        m = re.match(r"^/api/v2/shuffles/([^/]+)(/advance|/skip)?$", p)
        if m:
            sh = STATE["shuffles"].get(m.group(1))
            if sh is None:
                if method == "DELETE":
                    return self.send(204)
                return self.problem(404, "not_found", "Unknown shuffle")
            if method == "DELETE":
                del STATE["shuffles"][m.group(1)]
                LOG.append("SHUFFLE DELETE " + m.group(1))
                return self.send(204)
            if m.group(2) == "/advance" and method == "POST":
                cur = sh["order"][sh["pos"] % len(sh["order"])]
                if b.get("from_content_id") == cur:
                    sh["pos"] += 1
                LOG.append("SHUFFLE ADVANCE " + json.dumps(b))
            elif m.group(2) == "/skip" and method == "POST":
                nxt_i = (sh["pos"] + 1) % len(sh["order"])
                if b.get("next_content_id") == sh["order"][nxt_i] and len(sh["order"]) > 2:
                    swap = (sh["pos"] + 2) % len(sh["order"])
                    sh["order"][nxt_i], sh["order"][swap] = sh["order"][swap], sh["order"][nxt_i]
                LOG.append("SHUFFLE SKIP " + json.dumps(b))
            return self.send(200, shuffle_view(sh))
        if p == "/api/v2/settings/values/effective":
            return self.send(200, {"items": [{"key": "playback.intro_skip_mode", "value": "ask"}], "revision": 1})
        return self.problem(404, "not_found", "Mock: no route for " + p)


# ---------- Notifications inbox (GET /api/v2/notifications, unread-count, {id}/read, read-all) ----------
# Shapes follow silo-server contracts/api/v2/openapi.json (listNotifications, getNotificationUnreadCount,
# markNotificationRead, markNotificationsRead). Cursors are "o<offset>"; read_cutoff is "rc-<epoch seconds>".
# Test control: POST /mock/notifications/clear empties the inbox, POST /mock/notifications/reset reseeds it.

def notif_seed():
    if "notifs" in STATE:
        return STATE["notifs"]
    now = int(time.time())
    rows = []
    ages = [90, 40 * 60, 3 * 3600, 20 * 3600, 2 * 86400, 5 * 86400, 9 * 86400, 30 * 86400]
    for i in range(32):
        age = ages[i] if i < len(ages) else 40 * 86400 + i * 86400
        kind = i % 5
        row = {"id": "ntf-%03d" % (i + 1), "profile_id": "p1", "reason_flags": {}, "read_at": None,
               "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - age))}
        if kind in (0, 1, 3):
            si = i % len(SERIES)
            sr = series(si)
            sn, en = 1 + i % SERIES[si][1], 1 + i % SERIES[si][2]
            row.update({"type": "episode.available", "series_id": sr["content_id"], "series_title": sr["title"],
                        "episode_id": episode_id(sr["content_id"], sn, en), "episode_title": "Chapter %d" % en,
                        "season_number": sn, "episode_number": en, "poster_url": sr["poster_url"],
                        "poster_path": "", "poster_thumbhash": "", "library_id": "2",
                        "reason_flags": {"favorite": i % 2 == 0, "watchlist": i % 3 == 0}})
        elif kind == 2:
            row.update({"type": "request.fulfilled", "series_title": MOVIE_TITLES[i % len(MOVIE_TITLES)], "library_id": "1"})
        else:
            row.update({"type": "webhook.auto_disabled" if i % 2 else "library.scan_completed", "library_id": "1"})
        if i >= 6 and i % 4 == 0:
            row["read_at"] = row["created_at"]
        rows.append(row)
    STATE["notifs"] = rows
    return rows


def notif_now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def notifications_route(handler, method, p, q, b):
    if not p.startswith("/api/v2/notifications"):
        return False
    rows = notif_seed()
    if p == "/api/v2/notifications" and method == "GET":
        items = rows
        if (q.get("status") or ["all"])[0] == "unread":
            items = [r for r in rows if not r["read_at"]]
        limit = min(200, max(1, int((q.get("limit") or ["50"])[0])))
        cursor = (q.get("cursor") or [""])[0]
        offset = int(cursor[1:]) if cursor.startswith("o") and cursor[1:].isdigit() else 0
        chunk = items[offset:offset + limit]
        more = offset + limit < len(items)
        pg = {"has_more": more}
        if more:
            pg["next_cursor"] = "o%d" % (offset + limit)
        handler.send(200, {"items": chunk, "page": pg, "read_cutoff": "rc-%d" % int(time.time())})
        return True
    if p == "/api/v2/notifications/unread-count" and method == "GET":
        handler.send(200, {"count": len([r for r in rows if not r["read_at"]])})
        return True
    if p == "/api/v2/notifications/read-all" and method == "POST":
        through = str((b or {}).get("through") or "")
        if not through.startswith("rc-") or not through[3:].isdigit():
            handler.problem(422, "validation_failed", "through must be a read_cutoff from the inbox list")
            return True
        cutoff = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(int(through[3:])))
        for r in rows:
            if not r["read_at"] and r["created_at"] <= cutoff:
                r["read_at"] = notif_now()
        LOG.append("NOTIF READ-ALL " + through)
        handler.send(204)
        return True
    m = re.match(r"^/api/v2/notifications/([^/]+)(/read)?$", p)
    if m:
        row = next((r for r in rows if r["id"] == m.group(1)), None)
        if row is None:
            handler.problem(404, "not_found", "Unknown notification")
            return True
        if m.group(2) and method == "POST":
            if not row["read_at"]:
                row["read_at"] = notif_now()
            LOG.append("NOTIF READ " + row["id"])
            handler.send(204)
            return True
        if not m.group(2) and method == "GET":
            handler.send(200, row)
            return True
    handler.problem(404, "not_found", "Mock: no route for " + p)
    return True


def shuffle_pool(kind, sid):
    """Movies and episodes a shuffle scope draws from; None for an unknown scope."""
    if kind == "library":
        if sid == "1":
            return all_movies()
        if sid == "2":
            return [episode(i, s, e) for i in range(len(SERIES)) for s in range(1, SERIES[i][1] + 1) for e in range(1, SERIES[i][2] + 1)]
        return None
    if kind == "series":
        for i, s in enumerate(all_series()):
            if s["content_id"] == sid:
                return [episode(i, sn, e) for sn in range(1, SERIES[i][1] + 1) for e in range(1, SERIES[i][2] + 1)]
        return None
    if kind == "season":
        for i, s in enumerate(all_series()):
            for sn in range(1, SERIES[i][1] + 1):
                if sid == "season:%s-%d" % (s["content_id"], sn):
                    return [episode(i, sn, e) for e in range(1, SERIES[i][2] + 1)]
        return None
    if kind in ("library_collection", "user_collection"):
        return all_movies()[h(sid) % 6:][:10]
    return None


def shuffle_scope(kind, sid):
    title = {"1": "Movies", "2": "Shows"}.get(sid, sid)
    parent = None
    item = find(sid)
    if item is not None:
        title = item["title"]
        if kind == "season":
            parent = item.get("series_title")
    elif kind in ("library_collection", "user_collection"):
        title = {"c0": "Award Winners", "c1": "Night Owls", "c2": "Comfort Picks"}.get(sid, "Collection")
    out = {"kind": kind, "id": sid, "title": title}
    if parent:
        out["parent_title"] = parent
    return out


def shuffle_view(sh):
    n = len(sh["order"])
    cur = find(sh["order"][sh["pos"] % n])
    nxt = find(sh["order"][(sh["pos"] + 1) % n]) if n > 1 else cur
    return {"id": sh["id"], "scope": sh["scope"], "current": cur, "next": nxt,
            "created_at": sh["created_at"], "updated_at": "2026-10-06T00:00:00.000Z"}


def tokens(username="laura"):
    return {"access_token": "acc-" + uuid.uuid4().hex[:12], "refresh_token": "ref-" + uuid.uuid4().hex[:12], "expires_in": 3600,
            "user": {"id": "1", "username": username, "role": "admin", "permissions": []}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8097)
    args = ap.parse_args()
    srv = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print("Mock Silo on http://127.0.0.1:%d" % args.port, flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
