"""A small fake Silo server for exercising Siku in the brs-engine simulator.

It speaks the /api/v2 shapes documented in docs/api-spec.md, with a synthetic
library (movies, series with seasons and episodes, people) and generated artwork.

Run:  python3 tools/mock_server.py [--port 8097]
Then connect Siku to http://127.0.0.1:8097

Device sign-in auto-approves on the second poll. Password login accepts any
username with password "silo". The "Kids" profile has PIN 1234.

Test switches (not part of the API) change behaviour for one scenario. Set them at start with
--switch name=value (repeatable) or at run time with POST /mock/switch {"name": value} (null
clears one); GET /mock/switch lists them.
  hidden_libraries=<JSON array>  the profile's ui.disabled_library_ids default, e.g. [2,"4"]
  mixed_library=1                add library 5 "Everything" (type "mixed": movies and series)
  progress_410=1                 POST /playback/{id}/progress answers 410 playback_session_ended
  replan_410=1                   POST /playback/{id}/replan answers 410 playback_session_ended
  user_code=<code>               the device sign-in code to show (default 4821-7730)
  stale_profile=<profile id>     every request on that profile answers 403
                                 profile_verification_required until GET /api/v2/profiles runs
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
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse, unquote

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # artwork is optional
    Image = None

FONT = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
STATE = {"devices": {}, "sessions": {}, "watchlist": set(), "favorites": set(), "watched": set(), "progress": {}, "shuffles": {}, "switches": {}}
LOCK = threading.Lock()
LOG = []
# Feature switches (main() sets them from the command line).
OPTS = {"active_quality": True, "ai_fail": False, "ai_transcribe_only": False, "buffering_quality": True, "probe_kbps": 40000}

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
        **({"machine_translated_fields": ["overview"]} if si == 0 and s == 1 and e % 2 == 0 else {}),
    }


# ---------- Trailers & More, theme music, AI translation markers ----------
# Item detail `extras[]` (ItemExtraInfo + still_url/still_thumbhash) and `videos[]` (ItemVideoInfo).
# Extras have no watch detail of their own here (GET /api/v2/watch/extra:… answers 404), which
# exercises the player's fallback that starts the extra by file id.
MOCK_TRAILERS = {
    "movie:glass-city": {
        "extras": [
            {"content_id": "extra:glass-city-trailer", "kind": "trailer", "title": "Official Trailer", "duration_seconds": 151,
             "file_id": 61, "still_url": img("still", "extra:glass-city-trailer"), "still_thumbhash": "mock"},
            {"content_id": "extra:glass-city-bts", "kind": "behind_the_scenes", "title": "", "duration_seconds": 754,
             "file_id": 62, "still_url": img("still", "extra:glass-city-bts")},
            {"content_id": "extra:glass-city-deleted", "kind": "deleted_scene", "title": "The Rooftop", "duration_seconds": 3725, "file_id": 63},
        ],
        "videos": [
            {"kind": "trailer", "site": "YouTube", "site_key": "dQw4w9WgXcQ", "name": "Glass City | Official Trailer", "is_official": True},
            {"kind": "teaser", "site": "Vimeo", "site_key": "123456", "name": "Vimeo teaser (dropped)", "is_official": False},
            {"kind": "featurette", "site": "youtube", "site_key": "9bZkp7q19f0", "name": "", "is_official": False},
            {"kind": "trailer", "site": "YouTube", "site_key": "dQw4w9WgXcQ", "name": "Duplicate (dropped)", "is_official": True},
        ],
    },
    "series:orbital": {
        "extras": [
            {"content_id": "extra:orbital-featurette", "kind": "featurette", "title": "Building the Station", "duration_seconds": 412,
             "file_id": 64, "still_url": img("still", "extra:orbital-featurette")},
        ],
        "videos": [
            {"kind": "trailer", "site": "YouTube", "site_key": "M7lc1UVf-VE", "name": "Orbital: Season 1 Trailer", "is_official": True},
        ],
    },
}
MOCK_TRANSLATED = {"movie:glass-city", "series:orbital"}


def mock_themes(cid):
    """Item detail `themes` (ThemeSongSet): Glass City and Orbital own one theme; Orbital's seasons
    and episodes inherit the series' set, as the server resolves it. Other items: an empty set."""
    owner = None
    if cid == "movie:glass-city":
        owner = cid
    elif cid == "series:orbital" or cid.startswith("season:series:orbital-") or cid.startswith("episode:orbital-"):
        owner = "series:orbital"
    if owner is None:
        return {"owner_id": cid, "items": []}
    return {"owner_id": owner, "items": [{"id": "7", "title": "Main Theme", "duration_seconds": 95, "container": "mp3"}]}


def silent_wav(seconds=2):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(8000)
        w.writeframes(b"\x00\x00" * 8000 * seconds)
    return buf.getvalue()


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
    trailers = MOCK_TRAILERS.get(cid)
    if trailers:
        # "Trailers & More": local extras (still_url on all but one, file ids the playback mock
        # accepts) and YouTube videos, plus one Vimeo video the client must drop and a duplicate.
        d["extras"] = [dict(x) for x in trailers["extras"]]
        d["videos"] = [dict(v) for v in trailers["videos"]]
    themes = mock_themes(cid)
    if themes is not None:
        d["themes"] = themes
    if cid in MOCK_TRANSLATED:
        d["machine_translated_fields"] = ["overview", "tagline"]
    if cid == "movie:glass-city":
        # Long track and version lists, to check that the pickers scroll instead of running off screen.
        langs = ["eng", "spa", "fra", "deu", "ita", "por", "jpn", "kor", "rus", "zho", "ara", "hin", "nld", "swe", "pol"]
        v0 = d["versions"][0]
        v0["audio_tracks"] = [{"index": i, "language": l, "codec": "eac3" if i % 2 == 0 else "aac", "channels": 6 if i % 2 == 0 else 2,
                               "default": i == 0, "title": "Audio %d (%s)" % (i + 1, l)} for i, l in enumerate(langs)]
        v0["subtitle_tracks"] = [{"index": i, "language": l, "codec": "srt", "forced": i % 5 == 4, "default": False,
                                  "external": i % 3 == 0, "title": "Subtitle %d (%s)" % (i + 1, l)} for i, l in enumerate(langs)]
        for n in range(8):
            v = dict(v0)
            v["file_id"] = str(50 + n)
            v["resolution"] = ["1080p", "720p", "2160p", "480p"][n % 4]
            d["versions"].append(v)
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


def mixed_sections(full=False):
    """Library 5 ("Everything", mixed). Inline items are capped at the shelf's item_limit, the way
    the real server bounds them; `full` gives the whole shelf for the section catalog source."""
    ms = all_movies()
    ss = all_series()
    recent = []
    for i in range(max(len(ms), len(ss))):
        if i < len(ms):
            recent.append(ms[i])
        if i < 2 and i < len(ss):
            recent.append(ss[i])
    recent += ss[2:]  # the older series sit beyond the inline window
    secs = [
        {"id": "mixed_recent", "section_type": "recently_added", "title": "Recently Added in Everything", "featured": False, "item_limit": 12, "items": recent},
        {"id": "mixed_gems", "section_type": "hidden_gems", "title": "Hidden Gems", "featured": False, "item_limit": 12,
         "customized": True, "items": ms[12:18] + ss[:3]},
    ]
    out = []
    for sct in secs:
        sct = dict(sct)
        if not full:
            sct["items"] = sct["items"][:sct["item_limit"]]
        sct["total_count"] = len(sct["items"])
        out.append(sct)
    return out


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


# Per-file marker ranges for the watch detail; files in ON_DEMAND_MARKER_FILES report them only to a
# read that names them (file_id), the way the server fills on-demand markers.
FILE_MARKERS = {
    "default": {"intro": {"start_seconds": 30, "end_seconds": 90}},
    "52": {"intro": {"start_seconds": 40, "end_seconds": 100}, "credits": {"start_seconds": 2800, "end_seconds": 2990}},
    "56": {"recap": {"start_seconds": 5, "end_seconds": 45}, "intro": {"start_seconds": 60, "end_seconds": 120}},
}
ON_DEMAND_MARKER_FILES = {"56"}


# Files the mock treats as a 4K Dolby Vision (profile 8.1) HEVC MKV with E-AC3 5.1: the 2160p
# variants of movie:glass-city. Everything else is the 1080p H.264/AAC MP4.
FOUR_K_FILES = {"52", "56"}


def playback_summary(b):
    """One line of what a start/replan body declared, for the mock log."""
    caps = b.get("client_capabilities") or {}
    hd = caps.get("hdr_details") or {}
    ctx = b.get("client_playback_context") or {}
    out = ctx.get("output") or {}
    disp = out.get("display") or {}
    pt = (caps.get("audio_passthrough") or {}).get("passthrough_codecs")
    return ("quality=%s cap=%s metered=%s max_res=%s video=%s audio=%s passthru=%s hdr=%s hdr10=%s hdr10+=%s hlg=%s dv=%s display_evidence=%s deliveries=%s"
            % (b.get("quality_preference"), b.get("bandwidth_cap_kbps"), b.get("metered"), caps.get("max_resolution"),
               ",".join(caps.get("codecs_video") or []), ",".join(caps.get("codecs_audio") or []), ",".join(pt or []),
               caps.get("hdr"), hd.get("hdr10"), hd.get("hdr10_plus"), hd.get("hlg"), hd.get("dolby_vision_profiles"),
               disp.get("hdr_evidence"), ",".join(sorted((ctx.get("deliveries") or {}).keys()))))


def playback_route(fid, b):
    """Mimics the server planner for the two mock sources: delivery, decision_reason, recipe, claims, source."""
    caps = (b or {}).get("client_capabilities") or {}
    hd = caps.get("hdr_details") or {}
    quality = str((b or {}).get("quality_preference") or "auto").lower()
    cap = (b or {}).get("bandwidth_cap_kbps") or 0
    warnings = []
    if fid not in FOUR_K_FILES:
        source = {"media_file_id": fid, "duration_seconds": 3000, "container": "mp4", "video_codec": "h264", "width": 1920, "height": 1080,
                  "frame_rate": 23.976, "bitrate_kbps": 8000, "dynamic_range": "sdr", "audio_codec": "aac", "audio_channels": 2, "audio_layout": "stereo"}
        qualities = [{"label": "original", "height": 1080, "bitrate_kbps": 8000, "preserves_source": True},
                     {"label": "720p-high", "display_name": "720p High", "height": 720, "bitrate_kbps": 4000, "preserves_source": False}]
        if quality in ("720p", "480p", "720p-high") or (cap and cap < 8000):
            height = 720 if quality != "480p" else 480
            reason = "quality_bandwidth_cap" if (cap and cap < 8000 and quality not in ("720p", "480p", "720p-high")) else "quality_fixed_rung"
            if reason == "quality_bandwidth_cap":
                warnings.append({"code": "bandwidth_cap_applied", "message": "Delivery quality is limited by the configured bandwidth cap."})
            recipe = {"video_codec": "h264", "audio_codec": "aac", "width": height * 16 // 9, "height": height, "frame_rate": 23.976,
                      "bitrate_kbps": min(cap or 4000, 4000), "dynamic_range": "sdr", "audio_channels": 2, "audio_layout": "stereo"}
            return "server_transcode_hls", reason, recipe, {"video": {}, "audio": {"codec": "aac", "passthrough": False, "reason": "server_audio_adaptation"}}, source, qualities, warnings
        recipe = dict(source)
        recipe.pop("media_file_id"), recipe.pop("duration_seconds"), recipe.pop("container")
        return "original_http", "validated_original_playback", recipe, {"video": {}, "audio": {"codec": "aac", "passthrough": False, "reason": "client_decode_supported"}}, source, qualities, warnings
    source = {"media_file_id": fid, "duration_seconds": 3000, "container": "mkv", "video_codec": "hevc", "video_profile": "main 10", "bit_depth": 10,
              "width": 3840, "height": 2160, "frame_rate": 23.976, "bitrate_kbps": 24000, "dynamic_range": "dolby_vision", "dolby_vision_profile": 8,
              "dv_bl_compat_id": 1, "audio_codec": "eac3", "audio_channels": 6, "audio_layout": "5.1"}
    qualities = [{"label": "original", "height": 2160, "bitrate_kbps": 24000, "preserves_source": True},
                 {"label": "1080p-high", "display_name": "1080p High", "height": 1080, "bitrate_kbps": 10000, "preserves_source": False},
                 {"label": "1080p-medium", "display_name": "1080p Medium", "height": 1080, "bitrate_kbps": 6000, "preserves_source": False},
                 {"label": "720p-high", "display_name": "720p High", "height": 720, "bitrate_kbps": 4000, "preserves_source": False}]
    dv = hd.get("dolby_vision_profiles") or []
    hdr10 = bool(hd.get("hdr10"))
    audio_ok = "eac3" in [c.lower() for c in caps.get("codecs_audio") or []]
    ladder = [(2160, 20000), (1080, 5000), (720, 2000), (480, 0)]
    if fid == "56":
        # File 56 always comes back as the fMP4 HLS remux, to exercise the client's silent-remux
        # recovery (Roku plays no audio from muxed CMAF; PlayerScreen.maybeRecoverSilentRemux).
        recipe = {"video_codec": "hevc", "audio_codec": "aac", "width": 3840, "height": 2160, "frame_rate": 23.976, "bitrate_kbps": 24000,
                  "dynamic_range": "hdr10", "audio_channels": 6, "audio_layout": "5.1"}
        warnings.append({"code": "dolby_vision_removed", "message": "Dolby Vision metadata is removed and the validated HDR10 base layer is preserved."})
        warnings.append({"code": "audio_converted", "message": "The selected audio track is converted to AAC for HLS delivery."})
        claims = {"video": {"hdr10": True}, "audio": {"codec": "aac", "passthrough": False, "reason": "hls_audio_adaptation"}}
        return "server_remux_hls", "hls_audio_adaptation", recipe, claims, source, qualities, warnings

    def transcode(height, reason, bitrate):
        recipe = {"video_codec": "h264", "audio_codec": "aac", "width": height * 16 // 9, "height": height, "frame_rate": 23.976,
                  "bitrate_kbps": bitrate, "dynamic_range": "sdr", "audio_channels": 6, "audio_layout": "5.1"}
        warnings.append({"code": "hdr_tone_mapped", "message": "HDR video is tone-mapped to SDR for this playback route."})
        return "server_transcode_hls", reason, recipe, {"video": {}, "audio": {"codec": "aac", "passthrough": False, "reason": "server_audio_adaptation"}}, source, qualities, warnings

    if cap and cap < 24000:
        # The cap is a hard ceiling that outranks "original" (ResolveQualityPolicyV3): 80 % of it buys a ladder class.
        budget = cap * 0.8
        height = next(h for h, floor in ladder if budget >= floor)
        warnings.append({"code": "bandwidth_cap_applied", "message": "Delivery quality is limited by the configured bandwidth cap."})
        return transcode(height, "quality_bandwidth_cap", min(cap, 8000))
    if quality in ("1080p", "720p", "480p") or quality.startswith(("1080p-", "720p-", "480p-")):
        height = int(quality.split("p")[0])
        rung_kbps = {"1080p-high": 10000, "1080p-medium": 6000, "720p-high": 4000}.get(quality)
        return transcode(height, "quality_fixed_rung", rung_kbps or {1080: 6000, 720: 4000, 480: 1500}.get(height, 4000))
    if caps.get("max_resolution") in ("1080p", "720p") and quality == "auto":
        return transcode(1080, "quality_device_limit", 8000)
    if 8 in dv and audio_ok:
        recipe = {"video_codec": "hevc", "audio_codec": "eac3", "width": 3840, "height": 2160, "frame_rate": 23.976, "bitrate_kbps": 24000,
                  "dynamic_range": "dolby_vision", "audio_channels": 6, "audio_layout": "5.1"}
        claims = {"video": {"dolby_vision": True, "dolby_vision_reason": "native_profile_supported"},
                  "audio": {"codec": "eac3", "passthrough": False, "reason": "client_decode_supported"}}
        return "original_http", "validated_original_playback", recipe, claims, source, qualities, warnings
    if hdr10:
        # Dolby Vision off (or profile 8 not declared): the validated HDR10 base layer by remux.
        audio = "eac3" if audio_ok else "aac"
        recipe = {"video_codec": "hevc", "audio_codec": audio, "width": 3840, "height": 2160, "frame_rate": 23.976, "bitrate_kbps": 24000,
                  "dynamic_range": "hdr10", "audio_channels": 6, "audio_layout": "5.1"}
        warnings.append({"code": "dolby_vision_removed", "message": "Dolby Vision metadata is removed and the validated HDR10 base layer is preserved."})
        claims = {"video": {"hdr10": True}, "audio": {"codec": audio, "passthrough": False, "reason": "client_decode_supported" if audio_ok else "server_audio_adaptation"}}
        return "server_remux_hls", "hls_packaging_required", recipe, claims, source, qualities, warnings
    return transcode(2160, "quality_auto_source", 20000)


def active_quality_for(delivery, recipe, qualities, quality):
    """plan_active_quality_v1: the available_qualities label the plan delivers, or None (the source
    plays unchanged, or the encode falls between entries). A picked rung names itself; otherwise
    the entry of the delivered height whose bitrate is closest to the recipe's."""
    if delivery != "server_transcode_hls":
        return None
    entries = [q for q in qualities if not q.get("preserves_source")]
    if quality in [q["label"] for q in entries]:
        return quality
    same = [q for q in entries if q.get("height") == recipe.get("height")]
    if not same:
        return None
    return min(same, key=lambda q: abs(q.get("bitrate_kbps", 0) - (recipe.get("bitrate_kbps") or 0)))["label"]


def learned_limit_apply(body):
    """buffering_quality_v1 (Silo Android #636): a lowering replan (bandwidth_estimate_source
    observed_rebuffer) teaches this device a learned limit, learned_limit "clear" forgets it, and
    Auto then plans under min(estimate, learned limit) unless the request says "ignore". Returns the
    body the planner sees (the budget as a cap) and the plan's bandwidth_limit, if one applied."""
    b = dict(body or {})
    bq = STATE.setdefault("bq", {"learned_limit": None, "probe": None})
    features = b.get("client_features") or []
    supported = OPTS["buffering_quality"] and "buffering_quality_v1" in features
    est = b.get("bandwidth_estimate_kbps")
    if supported and b.get("learned_limit") == "clear":
        bq["learned_limit"] = None
        print("LEARNED LIMIT cleared", flush=True)
    if supported and est and b.get("bandwidth_estimate_source") == "observed_rebuffer":
        observed = b.get("observed_throughput_kbps")
        kbps = min(est, observed) if observed else est
        bq["learned_limit"] = {"kbps": kbps, "observed_at": "2026-10-17T20:15:00Z", "expires_at": "2026-10-24T20:15:00Z"}
        print("LEARNED LIMIT set %d kbps" % kbps, flush=True)
    quality = str(b.get("quality_preference") or "auto").lower()
    limit = None
    budget = est
    if supported and quality == "auto" and b.get("learned_limit") != "ignore" and bq["learned_limit"]:
        limit = bq["learned_limit"]["kbps"]
        budget = min(budget, limit) if budget else limit
    if budget and quality == "auto":
        cap = b.get("bandwidth_cap_kbps")
        b["bandwidth_cap_kbps"] = min(cap, budget) if cap else budget
    bandwidth_limit = {"kbps": limit, "source": "observed_rebuffer", "expires_at": bq["learned_limit"]["expires_at"]} if limit else None
    return b, bandwidth_limit


def playback_decision(sid, position, fid, body=None):
    """The start / replan decision: inventory = the file's sidecar plus every stored subtitle."""
    planned_body, bandwidth_limit = learned_limit_apply(body)
    print("BUFFERING request est=%s source=%s observed=%s learned_limit=%s features=%s" % (
        (body or {}).get("bandwidth_estimate_kbps"), (body or {}).get("bandwidth_estimate_source"), (body or {}).get("observed_throughput_kbps"),
        (body or {}).get("learned_limit"), ",".join((body or {}).get("client_features") or [])), flush=True)
    delivery, reason, recipe, claims, source, qualities, warnings = playback_route(fid, planned_body)
    quality = str((body or {}).get("quality_preference") or "auto").lower()
    features = ["playback_plan_v3", "neutral_playback_v3_contract_v1", "sequenced_progress_v1"]
    active = active_quality_for(delivery, recipe, qualities, quality)
    if OPTS["active_quality"]:
        features.append("plan_active_quality_v1")
    LOG.append("DECISION delivery=%s reason=%s quality=%s active_quality=%s" % (delivery, reason, quality, active))
    print("DECISION delivery=%s reason=%s quality=%s cap=%s active_quality=%s" % (delivery, reason, quality, (body or {}).get("bandwidth_cap_kbps"), active), flush=True)
    if delivery == "original_http":
        stream = {"url": "/mock-media/%s.mp4?st=abc" % sid, "protocol": "http_progressive", "container": source["container"], "mime_type": "video/mp4", "headers": {}, "header_refresh": "none"}
    else:
        stream = {"url": "/api/v2/playback/transcode/%s/master.m3u8?st=abc" % sid, "protocol": "hls", "container": "hls", "mime_type": "application/vnd.apple.mpegurl", "headers": {}, "header_refresh": "none"}
    inventory = [{"track_id": "file:%s:subtitle:0" % fid, "combined_index": 0, "source": "external", "codec": "srt", "language": "eng",
                  "label": "English", "forced": False, "default": False, "hearing_impaired": False, "delivery": "sidecar",
                  "url": "/api/v2/stream/%s/subtitles/0.vtt?file_id=%s&external_subtitle_key=f903" % (sid, fid), "sync_key": EXTERNAL_SYNC_KEY}]
    if fid in FOUR_K_FILES:
        # The 4K MKV also carries embedded tracks: an English SubRip (served as a WebVTT sidecar, so a
        # Roku can show it; auto-selection prefers it over the external file, Silo Android #529) and
        # an English PGS (image-based: Roku lists it as unavailable). Inventory order: externals first.
        inventory.append({"track_id": "file:%s:subtitle:1" % fid, "combined_index": 1, "source": "embedded", "codec": "subrip", "language": "eng",
                          "label": "English", "forced": False, "default": True, "hearing_impaired": False, "delivery": "sidecar",
                          "url": "/api/v2/stream/%s/subtitles/1.vtt?file_id=%s&embedded_stream_index=0" % (sid, fid)})
        inventory.append({"track_id": "file:%s:subtitle:2" % fid, "combined_index": 2, "source": "embedded", "codec": "hdmv_pgs_subtitle", "language": "eng",
                          "label": "English (PGS)", "forced": False, "default": False, "hearing_impaired": False, "delivery": "sidecar",
                          "url": "/api/v2/stream/%s/subtitles/2.sup?file_id=%s&embedded_stream_index=1" % (sid, fid)})
    for rec in SUBS["stored"]:
        if rec["media_file_id"] != fid:
            continue
        idx = len(inventory)
        inventory.append({"track_id": "file:%s:subtitle:%d" % (fid, idx), "combined_index": idx, "source": "downloaded", "codec": rec["format"],
                          "language": rec["language"], "label": ("%s (%s)" % (rec["release_name"], rec["provider"]) if rec["provider"] in ("translated", "transcribed") else (rec["release_name"] or rec["provider"])), "forced": False, "default": False,
                          "hearing_impaired": rec["hearing_impaired"], "delivery": "sidecar",
                          "url": "/api/v2/stream/%s/subtitles/%d.vtt?file_id=%s&downloaded_subtitle_id=%s" % (sid, idx, fid, rec["id"]),
                          "sync_key": "stored-" + rec["id"]})
    plan_extra = {}
    if OPTS["active_quality"] and active is not None:
        plan_extra["active_quality"] = active
    if bandwidth_limit:
        plan_extra["bandwidth_limit"] = bandwidth_limit
    if OPTS["buffering_quality"]:
        features.append("buffering_quality_v1")
    # The selected subtitle (a start's subtitle_track_id, a replan's selected_tracks.subtitle). An
    # embedded text track on a transcode comes back as a WebVTT rendition of the HLS stream when the
    # client lists hls_subtitle_renditions_v1 (Silo Android #611); a failure_recovery classified
    # subtitle_hls_rendition_failed gets the sidecar plan instead.
    b = body or {}
    wanted = b.get("subtitle_track_id") or ((b.get("selected_tracks") or {}).get("subtitle") or {}).get("id")
    subtitle = {"mode": "off", "inventory": inventory}
    selected_sub = None
    row = next((r for r in inventory if r["track_id"] == wanted), None) if wanted else None
    if row is not None:
        selected_sub = {"id": row["track_id"], "index": row["combined_index"]}
        failed_rendition = b.get("operation") == "failure_recovery" and (b.get("failure") or {}).get("classification") == "subtitle_hls_rendition_failed"
        if (delivery == "server_transcode_hls" and row["source"] == "embedded" and row["codec"] in ("subrip", "srt", "webvtt")
                and "hls_subtitle_renditions_v1" in (b.get("client_features") or []) and not failed_rendition):
            subtitle = {"mode": "render", "track_id": row["track_id"], "inventory": inventory,
                        "hls_rendition": {"group_id": "subs", "name": "Subtitles", "format": "vtt", "mime_type": "text/vtt"}}
            features.append("hls_subtitle_renditions_v1")
        else:
            subtitle = {"mode": "convert" if row["delivery"] == "sidecar" else "burn_in", "track_id": row["track_id"], "inventory": inventory}
        print("SUBTITLE decision track=%s mode=%s rendition=%s" % (row["track_id"], subtitle["mode"], "hls_rendition" in subtitle), flush=True)
    selected = {"audio": {"id": "file:%s:audio:0" % fid, "index": 0}}
    if selected_sub:
        selected["subtitle"] = selected_sub
    return {"protocol_version": 3, "server_features": features,
            "outcome": "playable", "session_id": sid,
            "playback_plan": {"protocol_version": 3, "plan_id": "plan:%d" % (len(SUBS["stored"]) + 1), "plan_attempt_key": "v3:%d" % (len(SUBS["stored"]) + 1), "session_id": sid,
                              "delivery": delivery, "decision_reason": reason,
                              "stream": stream,
                              "timeline": {"player_start_seconds": position, "timeline_offset_seconds": 0, "can_seek_anywhere": True},
                              "selected_tracks": selected,
                              "effective_recipe": recipe, "claims": claims, "available_qualities": qualities,
                              "degradation_warnings": warnings, "transformations": [], "applied_quirks": [], "runtime_corrections": [],
                              "requested_media_file_id": fid, "effective_media_file_id": fid,
                              "subtitle": subtitle,
                              "source": source, **plan_extra}}


def subtitle_route(handler, method, p, q, b):
    if not p.startswith("/api/v2/subtitles"):
        return False
    if p == "/api/v2/subtitles/ai/status":
        # --ai-transcribe-only: transcription without translation (Silo Android #547).
        handler.send(200, {"revision": "mock-ai-1", "state": "available", "allowed": True, "enabled": not OPTS["ai_transcribe_only"], "transcribe_enabled": True})
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
        print("AI TRANSLATE", json.dumps({k: b.get(k) for k in ("kind", "source_index", "source_language", "target_language")}), flush=True)
        for k in ("media_file_id", "kind", "source_index", "source_language", "target_language", "start_position"):
            if k not in b:
                handler.problem(422, "validation_failed", "%s is required" % k)
                return True
        if b["kind"] not in ("translate", "transcribe", "transcribe_translate"):
            handler.problem(422, "validation_failed", "unknown kind")
            return True
        if OPTS["ai_transcribe_only"] and b["kind"] != "transcribe":
            # The real server's answer when translation is not configured.
            handler.problem(422, "ai_not_configured", "AI subtitle processing is not configured")
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
                if OPTS["ai_fail"]:
                    # --ai-fail: every job fails on its second read, with the reason the client must show.
                    job.update(status="failed", progress=0.34, progress_message="", error_message="The transcription model ran out of memory on this server.")
                    LOG.append("AI FAILED " + job["id"])
                else:
                    job.update(status="running", progress=0.72, progress_message="Translating")
            else:
                # Stored AI tracks as the real server labels them: a "(translated)" / "(transcribed)"
                # provider and a release name "English → German (AI)" / "English (AI transcribed)".
                src = (job["source_language"] or "en")
                if job["kind"] == "transcribe":
                    provider, release, lang = "transcribed", "%s (AI transcribed)" % src, (job["target_language"] or src)
                else:
                    provider, release, lang = "translated", "%s → %s (AI)" % (src, job["target_language"]), job["target_language"]
                rec = sub_store(job["media_file_id"], provider, lang, release, auto_sync=False)
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

    def send_probe(self, q):
        """The bandwidth probe: `size` bytes of filler, throttled to --probe-kbps. A second probe
        within 10 s gets 429 with Retry-After, as the real server rate-limits them."""
        now = time.time()
        last = STATE.get("probe_at", 0)
        if now - last < 10:
            return self.send(429, {"type": "about:blank", "title": "Too many probes", "status": 429}, extra={"Retry-After": "30"})
        STATE["probe_at"] = now
        size = min(int((q.get("size") or ["8000000"])[0]), 64 * 1024 * 1024)
        print("PROBE GET size=%d at %d kbps" % (size, OPTS["probe_kbps"]), flush=True)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        chunk = b"\0" * 65536
        bytes_per_s = OPTS["probe_kbps"] * 1000 / 8
        sent = 0
        start = time.time()
        try:
            while sent < size:
                n = min(len(chunk), size - sent)
                self.wfile.write(chunk[:n])
                sent += n
                ahead = sent / bytes_per_s - (time.time() - start)
                if ahead > 0:
                    time.sleep(ahead)
        except (BrokenPipeError, ConnectionResetError):
            pass

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
        if p == "/mock/switch":
            if method == "POST":
                for k, v in (b or {}).items():
                    if v is None:
                        STATE["switches"].pop(k, None)
                    else:
                        STATE["switches"][k] = v
                print("SWITCHES", json.dumps(STATE["switches"]), flush=True)
            return self.send(200, STATE["switches"])
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
            return self.send(201, {"device_code": code, "user_code": STATE["switches"].get("user_code", "4821-7730"), "match_code": "warm pony",
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

        if re.match(r"^/api/v2/catalog/items/.+/themes/[^/]+/audio$", p) and "token=mock-theme-grant" in self.path:
            # A theme grant URL authorises itself (no bearer token), like the real one.
            return self.send(200, silent_wav(), "audio/wav")
        if not self.authed():
            return self.problem(401, "invalid_token", "Authentication required")
        stale = STATE["switches"].get("stale_profile")
        if stale and p == "/api/v2/profiles" and method == "GET":
            # The viewer is back on the picker: the next profile pick is a fresh, valid proof.
            STATE["switches"].pop("stale_profile", None)
            print("STALE_PROFILE cleared by the profile list", flush=True)
        elif stale and self.headers.get("X-Profile-Id") == str(stale):
            print("STALE_PROFILE 403", method, p, flush=True)
            return self.problem(403, "profile_verification_required", "Profile verification required")
        if requests_route(self, method, p, q, b):
            return
        if subtitle_route(self, method, p, q, b):
            return
        if notifications_route(self, method, p, q, b):
            return
        if settings_route(self, method, p, q, b):
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
            libs = [
                {"id": "1", "name": "Movies", "type": "movies", "sort_order": 0},
                {"id": "2", "name": "Shows", "type": "series", "sort_order": 1},
                {"id": "3", "name": "Music", "type": "music", "sort_order": 2},
                {"id": "4", "name": "Audiobooks", "type": "audiobooks", "sort_order": 3},
            ]
            if STATE["switches"].get("mixed_library"):
                # A real server sends numeric ids; this one does, to exercise id normalisation.
                libs.append({"id": 5, "name": "Everything", "type": "mixed", "sort_order": 4})
            return self.send(200, {"items": libs})
        if p == "/api/v2/home/sections":
            return self.send(200, home_sections())
        m = re.match(r"^/api/v2/library/([^/]+)/sections$", p)
        if m:
            secs = home_sections()["sections"]
            if m.group(1) == "5":
                return self.send(200, {"sections": mixed_sections()})
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
        if p == "/api/v2/catalog" and q.get("source", [""])[0] == "section" and q.get("library_id", [""])[0] == "5":
            # A mixed library's shelf, paged in its stored order (TvLibraryMediaScope refills from it).
            sec = next((x for x in mixed_sections(full=True) if x["id"] == q.get("section_id", [""])[0]), None)
            if sec is None:
                return self.problem(404, "not_found", "Unknown section")
            LOG.append("SECTION CATALOG %s cursor=%s" % (sec["id"], q.get("cursor", [""])[0]))
            print("SECTION CATALOG", sec["id"], "cursor=" + q.get("cursor", [""])[0], flush=True)
            return self.send(200, page(sec["items"], q))
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
        if p == "/api/v2/catalog/themes/capabilities":
            return self.send(200, {"revision": "mock-1", "state": "available", "allowed": True, "delivery": "routed",
                                   "transcode": True, "cluster_routing": False, "grant_lifetime_seconds": 300})
        m = re.match(r"^/api/v2/catalog/items/(.+)/themes/([^/]+)/playback$", p)
        if m and method == "POST":
            fmts = (b or {}).get("accepted_formats") or []
            LOG.append("THEME GRANT %s %s accepted=%s" % (m.group(1), m.group(2), json.dumps(fmts)))
            print("THEME GRANT", m.group(1), m.group(2), json.dumps(fmts), flush=True)
            mp3 = any(f.get("container") == "mp3" for f in fmts) or not fmts
            return self.send(200, {"url": "/api/v2/catalog/items/%s/themes/%s/audio?token=mock-theme-grant" % (m.group(1), m.group(2)),
                                   "expires_at": "2030-01-01T00:05:00Z", "delivery": "original" if mp3 else "converted",
                                   "content_type": "audio/wav" if mp3 else "audio/mp4"})
        m = re.match(r"^/api/v2/catalog/items/(.+)/themes/([^/]+)/audio$", p)
        if m:
            LOG.append("THEME AUDIO %s %s" % (m.group(1), m.group(2)))
            return self.send(200, silent_wav(), "audio/wav")
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
            # File-specific markers (Silo Android #527): each version carries its own ranges, and a
            # version whose markers the server fills on demand (file 56 here) has them only when the
            # read names it with file_id.
            asked = (q.get("file_id") or [""])[0]
            print("WATCH %s file_id=%s" % (m.group(1), asked or "-"), flush=True)
            vs = []
            for v in d["versions"]:
                v = dict(v)
                fid = str(v.get("file_id"))
                ranges = FILE_MARKERS.get(fid, FILE_MARKERS["default"])
                if fid in ON_DEMAND_MARKER_FILES and asked != fid:
                    ranges = {}
                for kind in ("intro", "recap", "credits", "preview"):
                    v[kind] = ranges.get(kind)
                v["marker_segments"] = [{"kind": k, "start_seconds": r["start_seconds"], "end_seconds": r["end_seconds"]} for k, r in ranges.items()]
                vs.append(v)
            return self.send(200, {"content_id": d["content_id"], "type": d["type"], "title": d["title"], "versions": vs,
                                   "series_title": d.get("series_title"),
                                   "user_data": d["user_data"], "series_id": d.get("series_id"), "season_number": d.get("season_number"),
                                   "episode_number": d.get("episode_number"), "intro": {"start_seconds": 30, "end_seconds": 90},
                                   # The profile's subtitle preferences as the server resolves them for this title.
                                   "effective_subtitle_language": settings_effective(self, "playback.subtitle_language", q)["value"],
                                   "effective_subtitle_mode": settings_effective(self, "playback.subtitle_mode", q)["value"],
                                   "effective_show_forced_subtitles": settings_effective(self, "playback.show_forced_subtitles", q)["value"]})
        if p == "/api/v2/playback/capabilities":
            caps = {"revision": "1", "state": "available", "allowed": True, "installation_id": "11111111-1111-4111-8111-111111111111",
                    "protocol_versions": [3], "features": ["playback_plan_v3", "sequenced_progress_v1"], "deliveries": ["original_http", "server_transcode_hls"]}
            if OPTS["buffering_quality"]:
                # Buffering quality and the connection speed test (Silo Android #636).
                caps["features"] += ["buffering_quality_v1", "connection_speed_v1"]
                caps.update({"bandwidth_probe_url": "/api/v2/playback/bandwidth-probe", "bandwidth_probe_target_kbps": 30000,
                             "bandwidth_probe_automatic": True, "bandwidth_probe_max_age_seconds": 604800})
            return self.send(200, caps)
        if p == "/api/v2/playback/connection" and method == "GET" and OPTS["buffering_quality"]:
            bq = STATE.setdefault("bq", {"learned_limit": None, "probe": None})
            out = {"connection": "local"}
            if bq["learned_limit"]:
                out["learned_limit"] = bq["learned_limit"]
            if bq["probe"]:
                out["probe"] = bq["probe"]
            # The server's Auto budget: 80 % of the lower of the reading and the learned limit.
            reading = bq["probe"]["kbps"] if bq["probe"] else None
            limit = bq["learned_limit"]["kbps"] if bq["learned_limit"] else None
            base = min(x for x in (reading, limit) if x) if (reading or limit) else None
            if base:
                out["auto_budget_kbps"] = base * 8 // 10
            return self.send(200, out)
        if p == "/api/v2/playback/connection/learned-limit" and method == "DELETE" and OPTS["buffering_quality"]:
            STATE.setdefault("bq", {"learned_limit": None, "probe": None})["learned_limit"] = None
            print("LEARNED LIMIT reset from Settings", flush=True)
            return self.send(204)
        if p == "/api/v2/playback/bandwidth-probe" and method == "GET" and OPTS["buffering_quality"]:
            return self.send_probe(q)
        if p == "/api/v2/playback/bandwidth-probe/results" and method == "POST" and OPTS["buffering_quality"]:
            print("PROBE RESULT " + json.dumps(b), flush=True)
            STATE.setdefault("bq", {"learned_limit": None, "probe": None})["probe"] = {
                "kbps": b.get("kbps"), "measured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "transport": b.get("transport"), "lower_bound": bool(b.get("lower_bound"))}
            if b.get("manual") and STATE["bq"]["learned_limit"] and (b.get("kbps") or 0) > STATE["bq"]["learned_limit"]["kbps"]:
                STATE["bq"]["learned_limit"] = None
            return self.send(204)
        if p == "/api/v2/playback/start" and method == "POST":
            sid = uuid.uuid4().hex
            STATE["sessions"][sid] = b
            LOG.append("START " + json.dumps(b)[:400])
            print("START", json.dumps({k: b.get(k) for k in ("file_id", "audio_track_id", "subtitle_track_id", "start_position")}), flush=True)
            print("START CAPS", playback_summary(b), flush=True)
            LOG.append("START CAPS " + playback_summary(b))
            return self.send(201, playback_decision(sid, b.get("start_position") or 0, b.get("file_id") or "42", b))
        m = re.match(r"^/api/v2/playback/([^/]+)/(replan|progress)$", p)
        if m and method == "POST" and STATE["switches"].get(m.group(2) + "_410"):
            print("SESSION_ENDED 410", m.group(2), flush=True)
            LOG.append("SESSION_ENDED 410 " + m.group(2))
            return self.problem(410, "playback_session_ended", "An administrator ended this playback session")
        m = re.match(r"^/api/v2/playback/([^/]+)/replan$", p)
        if m and method == "POST":
            # Same decision shape as start; the inventory lists subtitles stored since (track_change).
            LOG.append("REPLAN " + json.dumps({k: b.get(k) for k in ("operation", "position_seconds", "selected_tracks")}))
            print("REPLAN", b.get("operation"), b.get("position_seconds"), playback_summary(b), flush=True)
            if m.group(1) not in STATE["sessions"]:
                return self.problem(410, "playback_session_ended", "Session ended")
            start = STATE["sessions"][m.group(1)]
            decision = playback_decision(m.group(1), b.get("position_seconds") or 0, start.get("file_id") or "42", b)
            plan = decision.get("playback_plan") or {}
            if b.get("operation") == "failure_recovery" and plan.get("delivery") == "server_remux_hls":
                # The real planner skips the attempted remux and falls through to an H.264 MPEG-TS
                # transcode for a client whose HEVC decoder is level-bound (Roku).
                plan["delivery"] = "server_transcode_hls"
                plan["decision_reason"] = "client_failure_recovery"
                plan["effective_recipe"] = {"video_codec": "h264", "audio_codec": "aac", "width": 1920, "height": 1080,
                                            "dynamic_range": "sdr", "audio_channels": 2, "audio_layout": "stereo", "bitrate_kbps": 8000}
                plan["degradation_warnings"] = [{"code": "client_failure_recovery", "message": "Re-planned after a client failure."}]
            if b.get("operation") == "track_change" and (b.get("selected_tracks") or {}).get("audio"):
                plan.setdefault("selected_tracks", {})["audio"] = b["selected_tracks"]["audio"]
            return self.send(200, decision)
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



# ---------------------------------------------------------------------------
# Settings (the canonical "effective settings cascade", contracts/settings/v1).
# GET  /api/v2/settings/contract/capabilities
# GET  /api/v2/settings/values/effective?keys=a&keys=b   -> {items:[{key,value,source,scope,...}], revision}
# PUT  /api/v2/settings/values/{key}?scope=...  {"value": ...} -> the stored row
# DELETE /api/v2/settings/values/{key}?scope=... -> 204 (404 when nothing is stored there)
# profile_device rows key on the X-Silo-Device-Id header, profile_client on X-Silo-Client-Family.
# ---------------------------------------------------------------------------
SETTINGS_REVISION = 21
SETTINGS_DEFS = {
    # key: (introduced_in, default, allowed scopes, resolution order)
    "playback.preferred_quality": (1, "auto", ["profile", "profile_device"], ["profile_device", "profile"]),
    "playback.max_bitrate_kbps": (1, None, ["profile", "profile_device"], ["profile_device", "profile"]),
    "playback.audio_language": (1, None, ["profile", "profile_device", "profile_library", "profile_series"], ["profile_device", "profile"]),
    "playback.subtitle_language": (1, None, ["profile", "profile_device", "profile_library", "profile_series"], ["profile_device", "profile"]),
    "playback.subtitle_mode": (1, "auto", ["profile", "profile_device", "profile_library", "profile_series"], ["profile_device", "profile"]),
    "playback.show_forced_subtitles": (1, True, ["profile", "profile_device", "profile_library", "profile_series"], ["profile_device", "profile"]),
    "playback.intro_skip_mode": (7, "ask", ["profile", "profile_device"], ["profile_device", "profile"]),
    "playback.buffering_quality_mode": (21, "always", ["profile", "profile_device"], ["profile_device", "profile"]),
    "playback.auto_skip_credits": (1, False, ["profile", "profile_device"], ["profile_device", "profile"]),
    "playback.auto_skip_recap": (1, False, ["profile", "profile_device"], ["profile_device", "profile"]),
    "playback.auto_play_next": (1, True, ["profile", "profile_device"], ["profile_device", "profile"]),
    "playback.auto_play_next_preview": (1, False, ["profile", "profile_device"], ["profile_device", "profile"]),
    "playback.next_up_prompt_seconds": (1, 30, ["profile", "profile_device"], ["profile_device", "profile"]),
    "playback.subtitle_appearance": (1, {"fontSize": "large", "fontFamily": "sans-serif", "fontColor": "#ffffff", "backgroundColor": "#000000",
                                         "backgroundStyle": "box", "backgroundOpacity": 75, "textOpacity": 100, "textOutline": False,
                                         "textOutlineColor": "#000000", "position": "bottom"},
                                     ["profile", "profile_device"], ["profile_device", "profile"]),
    "player.hdr_enabled": (1, True, ["profile_device"], ["profile_device"]),
    "player.dolby_vision_enabled": (1, True, ["profile_device"], ["profile_device"]),
    "player.dv_profile7_hdr10_fallback": (1, False, ["profile_device"], ["profile_device"]),
    "player.match_frame_rate": (1, False, ["profile_device"], ["profile_device"]),
    "player.video_skip_back_seconds": (9, 10, ["profile"], ["profile"]),
    "player.video_skip_forward_seconds": (9, 30, ["profile"], ["profile"]),
    "player.audiobook_skip_back_seconds": (9, 10, ["profile"], ["profile"]),
    "player.audiobook_skip_forward_seconds": (9, 30, ["profile"], ["profile"]),
    "catalog.metadata_language": (1, None, ["profile"], ["profile"]),
    "home.hide_watched_items": (12, False, ["profile"], ["profile"]),
    "ui.card_presentation": (5, {"poster_size": "standard", "caption": "title_metadata"}, ["profile", "profile_client", "profile_device"],
                             ["profile_device", "profile_client", "profile"]),
    "ui.title_art": (16, True, ["profile", "profile_device"], ["profile", "profile_device"]),
    "ui.disabled_library_ids": (1, None, ["profile"], ["profile"]),
    "ui.theme_music_enabled": (11, False, ["profile", "profile_device"], ["profile_device", "profile"]),
    "ui.theme_music_loop": (11, False, ["profile", "profile_device"], ["profile_device", "profile"]),
    "ui.theme": (1, "cinema-dark", ["account", "profile"], ["profile", "account"]),
}
SETTINGS_SCOPES = ["account", "profile", "profile_client", "profile_device", "profile_library", "profile_series"]
SETTINGS_LANGUAGE_KEYS = {"playback.audio_language", "playback.subtitle_language", "catalog.metadata_language"}
SETTINGS_SUGGESTED = ["en", "es", "fr", "de", "ja"]


def settings_store():
    return STATE.setdefault("settings", {"rows": {}, "revision": 0})


def settings_identity(handler, scope, q):
    """The (scope, profile, device/family) a stored row is keyed by; None when the request lacks it."""
    profile = handler.headers.get("X-Profile-Id") or ""
    if scope == "account":
        return ("account", "", "")
    if scope == "profile":
        return ("profile", profile, "")
    if scope == "profile_device":
        device = (q.get("device_id") or [handler.headers.get("X-Silo-Device-Id") or ""])[0]
        if not device:
            return None
        return ("profile_device", profile, device)
    if scope == "profile_client":
        family = handler.headers.get("X-Silo-Client-Family") or ""
        if not family:
            return None
        return ("profile_client", profile, family)
    if scope == "profile_library":
        return ("profile_library", profile, (q.get("library_id") or [""])[0])
    if scope == "profile_series":
        return ("profile_series", profile, (q.get("series_id") or [""])[0])
    return None


def settings_row_view(key, ident, row):
    out = {"key": key, "scope": ident[0], "value": row["value"], "revision": row["revision"], "updated_at": row["updated_at"]}
    if ident[0] != "account":
        out["profile_id"] = ident[1]
    if ident[0] == "profile_device":
        out["device_id"] = ident[2]
    elif ident[0] == "profile_client":
        out["client_family"] = ident[2]
    elif ident[0] == "profile_library":
        out["library_id"] = ident[2]
    elif ident[0] == "profile_series":
        out["series_id"] = ident[2]
    return out


def settings_effective(handler, key, q):
    introduced, default, _allowed, order = SETTINGS_DEFS[key]
    if key == "ui.disabled_library_ids" and STATE["switches"].get("hidden_libraries"):
        hid = STATE["switches"]["hidden_libraries"]
        default = json.loads(hid) if isinstance(hid, str) else hid
    store = settings_store()
    for scope in order:
        ident = settings_identity(handler, scope, q)
        if ident is None:
            continue
        row = store["rows"].get((key,) + ident)
        if row is not None:
            out = {"key": key, "value": row["value"], "source": scope, "definition_revision": introduced,
                   "updated_at": row["updated_at"], "scope": scope}
            if scope != "account":
                out["profile_id"] = ident[1]
            if scope == "profile_device":
                out["device_id"] = ident[2]
            if scope == "profile_client":
                out["client_family"] = ident[2]
            if key in SETTINGS_LANGUAGE_KEYS:
                out["suggested_values"] = SETTINGS_SUGGESTED
            return out
    out = {"key": key, "value": default, "source": "default", "definition_revision": introduced}
    if key in SETTINGS_LANGUAGE_KEYS:
        out["suggested_values"] = SETTINGS_SUGGESTED
    return out


def settings_validation(handler, location, detail):
    return handler.send(422, {"type": "https://siloserver.org/docs/api/v2/problems/validation_failed", "title": "Validation failed", "status": 422,
                              "detail": "The request did not pass validation; see errors.",
                              "errors": [{"location": location, "code": "invalid", "detail": detail}]}, "application/problem+json")


def settings_route(handler, method, p, q, b):
    if p == "/api/v2/settings/contract/capabilities" and method == "GET":
        return handler.send(200, {"revision": "mock-settings", "state": "available", "allowed": True, "api_version": 1,
                                  "manifest_revision": SETTINGS_REVISION, "contract_etag": '"etag-%d"' % SETTINGS_REVISION,
                                  "definition_count": len(SETTINGS_DEFS), "scopes": SETTINGS_SCOPES, "client_families": ["tv", "mobile", "tablet", "desktop", "web"],
                                  "supports_batched_effective": True, "supports_idempotent_writes": True, "supports_atomic_shortcuts": True}) or True
    if p == "/api/v2/settings/values/effective" and method == "GET":
        if not handler.headers.get("X-Profile-Id"):
            return handler.problem(400, "profile_required", "X-Profile-Id is required") or True
        keys = q.get("keys") or sorted(SETTINGS_DEFS)
        for k in keys:
            if k not in SETTINGS_DEFS:
                return settings_validation(handler, "query.keys", "No setting named %s exists in this server's contract" % k) or True
        LOG.append("SETTINGS effective %s" % ",".join(keys))
        return handler.send(200, {"items": [settings_effective(handler, k, q) for k in keys], "revision": SETTINGS_REVISION}) or True
    m = re.match(r"^/api/v2/settings/values/([^/]+)$", p)
    if m and method in ("GET", "PUT", "DELETE"):
        key = m.group(1)
        if key not in SETTINGS_DEFS:
            return settings_validation(handler, "path.key", "No setting named %s exists in this server's contract" % key) or True
        scope = (q.get("scope") or [""])[0]
        if scope not in SETTINGS_SCOPES:
            return settings_validation(handler, "query.scope", "scope is required") or True
        if scope not in SETTINGS_DEFS[key][2]:
            return settings_validation(handler, "query.scope", "%s does not allow scope %s" % (key, scope)) or True
        if scope != "account" and not handler.headers.get("X-Profile-Id"):
            return handler.problem(400, "profile_required", "X-Profile-Id is required") or True
        ident = settings_identity(handler, scope, q)
        if ident is None:
            return handler.problem(400, "device_header_required", "X-Silo-Device-Id is required for device-scoped settings") or True
        store = settings_store()
        with LOCK:
            row = store["rows"].get((key,) + ident)
            if method == "GET":
                if row is None:
                    return handler.problem(404, "not_found", "Nothing is stored at that scope") or True
                return handler.send(200, settings_row_view(key, ident, row)) or True
            if method == "DELETE":
                LOG.append("SETTINGS delete %s scope=%s" % (key, scope))
                print("SETTINGS delete %s scope=%s" % (key, scope), flush=True)
                if row is None:
                    return handler.problem(404, "not_found", "Nothing is stored at that scope") or True
                del store["rows"][(key,) + ident]
                store["revision"] += 1
                return handler.send(204) or True
            if "value" not in (b or {}):
                return settings_validation(handler, "body.value", "value is required") or True
            value = b["value"]
            if key in SETTINGS_LANGUAGE_KEYS and (value is None or value == ""):
                return settings_validation(handler, "body.value", "language_tag must not be empty") or True
            if key == "playback.max_bitrate_kbps" and value is not None and not (100 <= int(value) <= 200000):
                return settings_validation(handler, "body.value", "max_bitrate_kbps must be within 100..200000") or True
            revision = (row["revision"] if row else 0) + 1
            row = {"value": value, "revision": revision, "updated_at": "2026-10-06T00:00:00.000Z"}
            store["rows"][(key,) + ident] = row
            store["revision"] += 1
            LOG.append("SETTINGS put %s scope=%s value=%s" % (key, scope, json.dumps(value)))
            print("SETTINGS put %s scope=%s value=%s" % (key, scope, json.dumps(value)), flush=True)
            return handler.send(200, settings_row_view(key, ident, row)) or True
    return False

def tokens(username="laura"):
    return {"access_token": "acc-" + uuid.uuid4().hex[:12], "refresh_token": "ref-" + uuid.uuid4().hex[:12], "expires_in": 3600,
            "user": {"id": "1", "username": username, "role": "admin", "permissions": []}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8097)
    ap.add_argument("--switch", action="append", default=[], metavar="NAME=VALUE",
                    help="set a test switch at start (see the module docstring)")
    ap.add_argument("--theme-music", action="store_true", help="turn ui.theme_music_enabled on by default (profile scope)")
    ap.add_argument("--no-active-quality", action="store_true",
                    help="act as a server before plan_active_quality_v1 (the client infers the lit Quality row)")
    ap.add_argument("--ai-fail", action="store_true", help="every AI subtitle job fails on its second read")
    ap.add_argument("--ai-transcribe-only", action="store_true", help="AI transcription on, AI translation off")
    ap.add_argument("--no-buffering-quality", action="store_true", help="act as a server before buffering_quality_v1 / connection_speed_v1")
    ap.add_argument("--probe-kbps", type=int, default=40000, help="rate the bandwidth probe download is throttled to")
    args = ap.parse_args()
    for sw in args.switch:
        k, _, v = sw.partition("=")
        STATE["switches"][k.strip()] = v.strip() or "1"
    if args.theme_music:
        d = SETTINGS_DEFS["ui.theme_music_enabled"]
        SETTINGS_DEFS["ui.theme_music_enabled"] = (d[0], True) + tuple(d[2:])
    OPTS["active_quality"] = not args.no_active_quality
    OPTS["ai_fail"] = args.ai_fail
    OPTS["ai_transcribe_only"] = args.ai_transcribe_only
    OPTS["buffering_quality"] = not args.no_buffering_quality
    OPTS["probe_kbps"] = args.probe_kbps
    srv = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print("Mock Silo on http://127.0.0.1:%d" % args.port, flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
