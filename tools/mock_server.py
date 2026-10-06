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
STATE = {"devices": {}, "sessions": {}, "watchlist": set(), "favorites": set(), "watched": set(), "progress": {}}
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


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        LOG.append(fmt % args)

    def send(self, code, body=None, ctype="application/json"):
        data = b""
        if body is not None:
            data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
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
            return self.send(200, {"genres": GENRES, "studios": [], "networks": [], "countries": [], "original_languages": [], "content_ratings": ["PG", "PG-13", "R"], "technical": {}})
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
            elif key in ("title", "year", "runtime", "rating"):
                items.sort(key=lambda i: (i.get(key if key != "rating" else "rating_imdb") or 0), reverse=sort.startswith("-"))
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
            v = dict(d["versions"][0])
            v["marker_segments"] = [{"kind": "intro", "start_seconds": 30, "end_seconds": 90}]
            return self.send(200, {"content_id": d["content_id"], "type": d["type"], "title": d["title"], "versions": [v],
                                   "user_data": d["user_data"], "series_id": d.get("series_id"), "season_number": d.get("season_number"),
                                   "episode_number": d.get("episode_number"), "intro": {"start_seconds": 30, "end_seconds": 90}})
        if p == "/api/v2/playback/capabilities":
            return self.send(200, {"revision": "1", "state": "available", "allowed": True, "installation_id": "11111111-1111-4111-8111-111111111111",
                                   "protocol_versions": [3], "features": ["playback_plan_v3", "sequenced_progress_v1"], "deliveries": ["original_http", "server_transcode_hls"]})
        if p == "/api/v2/playback/start" and method == "POST":
            sid = uuid.uuid4().hex
            STATE["sessions"][sid] = b
            LOG.append("START " + json.dumps(b)[:400])
            return self.send(201, {"protocol_version": 3, "server_features": ["playback_plan_v3", "neutral_playback_v3_contract_v1", "sequenced_progress_v1"],
                                   "outcome": "playable", "session_id": sid,
                                   "playback_plan": {"protocol_version": 3, "plan_id": "plan:1", "plan_attempt_key": "v3:1", "session_id": sid,
                                                     "delivery": "original_http",
                                                     "stream": {"url": "/mock-media/%s.mp4?st=abc" % sid, "protocol": "http_progressive", "container": "mp4", "mime_type": "video/mp4", "headers": {}, "header_refresh": "none"},
                                                     "timeline": {"player_start_seconds": b.get("start_position") or 0, "timeline_offset_seconds": 0, "can_seek_anywhere": True},
                                                     "subtitle": {"mode": "off", "inventory": [{"track_id": "file:42:subtitle:0", "combined_index": 0, "codec": "srt", "language": "eng", "label": "English", "delivery": "sidecar", "url": "/api/v2/stream/%s/subtitles/0.vtt?file_id=42" % sid}]},
                                                     "source": {"duration_seconds": 3000}}})
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
        if p == "/api/v2/settings/values/effective":
            return self.send(200, {"items": [{"key": "playback.intro_skip_mode", "value": "ask"}], "revision": 1})
        return self.problem(404, "not_found", "Mock: no route for " + p)


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
