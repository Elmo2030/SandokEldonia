#!/usr/bin/env python3
"""A neutral, invented IPTV provider for screenshots and UI tests of the iPhone/iPad app (nothing real: invented titles,
generated artwork, a generated test video). An Xtream Codes API on http://127.0.0.1:8099 (user demo, password demo):
live / movie / series lists, details, episodes, a short program guide, posters and logos as PNG, and one MP4 for every stream.
    python3 ios/Demo/demo-server.py [port]            then launch the app with:  -demoServer http://127.0.0.1:8099 -demoImages 1
The simulator reaches this Mac's 127.0.0.1. Artwork is cached in $TMPDIR/iptv-demo-art on first start (about 10 seconds)."""
import base64, hashlib, http.server, json, math, os, pathlib, struct, subprocess, sys, tempfile, time, urllib.parse, zlib

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
BASE = f"http://127.0.0.1:{PORT}"
ART = pathlib.Path(tempfile.gettempdir()) / "iptv-demo-art"
ART.mkdir(exist_ok=True)

LIVE = {  # category -> channels (a few without a logo on purpose: the app draws a monogram)
    "News": ["Harbor News 24", "World Report", "City Desk", "Morning Wire", "Evening Brief"],
    "Sports": ["Aurora Sports 1", "Aurora Sports 2", "Kickoff HD", "Court Side", "Marathon TV", "Pitch Report"],
    "Kids": ["Toon Time", "Little Cloud Kids", "Puzzle Pals", "Story Island"],
    "Documentary": ["Planet Docs", "Ocean Life", "Deep Time", "Nature One", "Old Roads"],
    "Music": ["Retro Radio TV", "Jazz Lounge", "Music Hits", "Night Vinyl"],
    "עברית": ["חדשות הנמל 24", "טבע וחיים", "ילדים בענן", "מוזיקה בערב"],
}
MOVIES = {
    "Drama": ["The Last Lighthouse", "Quiet Harbor", "Winter Letters", "Salt and Iron", "A House by the Sea", "Paper Moons", "The Long Table"],
    "Sci-Fi": ["Orbit Zero", "Signal from Kepler", "The Mirror Planet", "Nebula Run", "Low Gravity", "Station Nine", "Afterlight"],
    "Animation": ["Little Cloud", "Dragon Valley", "Fox and Ember", "The Paper Fleet", "Moon Garden", "Captain Button"],
    "Comedy": ["Wrong Wedding", "Office Chaos", "The Sea Cook", "Lucky Streak", "Desert Wind", "Second Honeymoon"],
    "Documentary": ["Under the Ice", "The Salt Road", "Hands of the Potter", "Night Trains", "Tidal"],
}
SERIES = {
    "Drama": ["North Pier", "The Archive", "Glass Hours", "Harvest Moon"],
    "Sci-Fi": ["Deep Signal", "Colony Seven", "The Long Orbit"],
    "Comedy": ["Flat Share", "Corner Shop", "Night Shift Café"],
    "Documentary": ["Wild Coast", "How It Was Built"],
}
PLOTS = ["A quiet town keeps a secret that the sea is about to give back. Two strangers have one night to decide what to do with it.",
         "When a signal arrives from a place that should be empty, a small crew has to choose between going home and finding out why.",
         "An old craftsman, a stubborn apprentice and one last commission that changes both of them.",
         "Everything goes wrong on the day it matters most, and somehow it ends up being the best day of the year.",
         "Told through the people who live and work along one river, over four seasons."]
CAST = ["Mara Elden, Tomas Vey, Ines Okafor, Jonah Reyes", "Lucia Marek, Daniel Aubrey, Priya Nair", "Hana Kovac, Oskar Lind, Femi Adeyemi, Rosa Quill"]
DIRECTORS = ["Ilse Brandt", "Kenji Arai", "Nora Whitlock", "Mateo Salas"]

def hue_of(s): return int(hashlib.md5(s.encode()).hexdigest()[:6], 16) % 1000 / 1000
def hsv(h, s, v):
    i = int(h * 6) % 6; f = h * 6 - int(h * 6); p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    r, g, b = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
    return r * 255, g * 255, b * 255

def png(path, w, h, pixel):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w): raw += bytes(int(max(0, min(255, c))) for c in pixel(x, y))
    def chunk(t, d): c = struct.pack(">I", len(d)) + t + d; return c + struct.pack(">I", zlib.crc32(t + d))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))

def art(kind, name, w, h):
    p = ART / f"{kind}-{hashlib.md5(name.encode()).hexdigest()[:10]}.png"
    if p.exists(): return p
    h1 = hue_of(name); h2 = (h1 + 0.12 + hue_of(name + "x") * 0.15) % 1
    cx, cy, r = w * (0.3 + 0.4 * hue_of(name + "c")), h * (0.28 + 0.2 * hue_of(name + "d")), w * 0.28
    def px(x, y):
        t = y / h
        c = [a + (b - a) * t for a, b in zip(hsv(h1, 0.62, 0.86), hsv(h2, 0.75, 0.42))]
        d = math.hypot(x - cx, y - cy)
        if d < r: k = 0.55 * (1 - d / r) ** 0.6 + 0.12; c = [v + (255 - v) * k for v in c]       # a soft sun or moon
        if kind == "poster" and y > h * 0.62: k = ((y - h * 0.62) / (h * 0.38)) ** 1.5 * 0.5; c = [v * (1 - k) for v in c]
        if kind == "poster" and abs(y - h * 0.70) < 1.2: c = [v * 0.8 for v in c]                 # a horizon line
        return c
    png(p, w, h, px); return p

def logo(name):
    p = ART / f"logo-{hashlib.md5(name.encode()).hexdigest()[:10]}.png"
    if p.exists(): return p
    h1 = hue_of(name); a, b = hsv(h1, 0.7, 0.9), hsv((h1 + 0.1) % 1, 0.8, 0.55)
    def px(x, y):
        if (x - 64) ** 2 + (y - 64) ** 2 > 62 ** 2: return (0, 0, 0)  # PNG without alpha: the corners stay dark
        t = (x + y) / 256; c = [u + (v - u) * t for u, v in zip(a, b)]
        if abs((x - 64) - (y - 64) * 0.9) < 9 and abs(y - 64) < 34: c = [255, 255, 255]          # a bold stroke as the mark
        return c
    png(p, 128, 128, px); return p

def build():
    items = {"live": [], "movie": [], "series": []}; cats = {"live": [], "movie": [], "series": []}
    n = 100
    for ci, (cat, names) in enumerate(LIVE.items(), 1):
        cats["live"].append({"category_id": str(ci), "category_name": cat})
        for nm in names:
            n += 1; items["live"].append({"num": n, "name": nm, "stream_id": n, "stream_icon": f"{BASE}/art/logo/{urllib.parse.quote(nm)}.png" if n % 3 else "",
                                         "category_id": str(ci), "tv_archive": 1 if n % 4 == 0 else 0, "tv_archive_duration": 3, "epg_channel_id": f"c{n}", "added": "1"})
    for kind, src, key, iconkey in (("movie", MOVIES, "stream_id", "stream_icon"), ("series", SERIES, "series_id", "cover")):
        for ci, (cat, names) in enumerate(src.items(), 1):
            cats[kind].append({"category_id": str(ci), "category_name": cat})
            for nm in names:
                n += 1; year = 2018 + n % 8
                items[kind].append({"num": n, "name": f"{nm} ({year})" if kind == "movie" else nm, key: n, iconkey: f"{BASE}/art/poster/{urllib.parse.quote(nm)}.png",
                                    "category_id": str(ci), "rating": f"{5 + n % 40 / 10:.1f}", "container_extension": "mp4", "added": "1", "_base": nm, "_year": year})
    return items, cats

ITEMS, CATS = build()
BY_ID = {(k, str(i.get("stream_id", i.get("series_id")))): i for k, l in ITEMS.items() for i in l}
SHOWS = ["Morning Edition", "The Daily Brief", "Harbor Hour", "Match of the Evening", "Story Time", "Wild Places", "Late Session", "Weekend Roundup"]

def clean(l): return [{k: v for k, v in d.items() if not k.startswith("_")} for d in l]

def info(kind, item):
    n = item["num"]; base = item["_base"]
    d = {"name": base, "o_name": base, "plot": PLOTS[n % len(PLOTS)], "cast": CAST[n % len(CAST)], "director": DIRECTORS[n % len(DIRECTORS)],
         "genre": [c["category_name"] for c in CATS[kind] if c["category_id"] == item["category_id"]][0], "releasedate": f"{item['_year']}-05-12", "rating": item["rating"],
         "country": ["Denmark", "Japan", "Canada", "Portugal"][n % 4], "youtube_trailer": "aqz-KE-bpKQ",
         "cover_big": item.get("stream_icon") or item.get("cover"), "movie_image": item.get("stream_icon") or item.get("cover"),
         "backdrop_path": [f"{BASE}/art/backdrop/{urllib.parse.quote(base)}.png"]}
    if kind == "movie": d["duration_secs"] = (84 + n % 50) * 60
    return d

def series_info(item):
    seasons = 2 + item["num"] % 3; eps = {}; eid = item["num"] * 1000
    for s in range(1, seasons + 1):
        eps[str(s)] = []
        for e in range(1, 7 + item["num"] % 4):
            eid += 1; eps[str(s)].append({"id": str(eid), "episode_num": e, "season": s, "title": f"S{s} E{e} · " + ["The Arrival", "Low Tide", "A Letter", "Crossing", "Quiet Rooms", "What the River Knows", "Open Doors", "Home Again", "Long Light"][(e + s) % 9],
                                          "container_extension": "mp4", "info": {"duration_secs": 2700}})
    return {"info": info("series", item), "episodes": eps}

def epg(sid):
    now = int(time.time()); slot = now // 1800 * 1800; out = []
    for i in range(2):
        t = SHOWS[(int(sid) + slot // 1800 + i) % len(SHOWS)]
        out.append({"id": str(i), "title": base64.b64encode(t.encode()).decode(), "start_timestamp": str(slot + i * 1800), "stop_timestamp": str(slot + (i + 1) * 1800)})
    return {"epg_listings": out}

VIDEO = ART / "test.mp4"
def ensure_video():
    if VIDEO.exists(): return
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=25:duration=30", "-f", "lavfi", "-i", "sine=frequency=440:duration=30",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", "-movflags", "+faststart", str(VIDEO)], check=False)

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, body, ctype="application/json", code=200, extra=None):
        self.send_response(code); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body))); self.send_header("Cache-Control", "max-age=3600")
        for k, v in (extra or {}).items(): self.send_header(k, v)
        self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}; parts = [urllib.parse.unquote(x) for x in u.path.split("/") if x]
        if u.path == "/player_api.php":
            if q.get("username") != "demo" or q.get("password") != "demo": return self.send(json.dumps({"user_info": {"auth": 0}}).encode())
            a = q.get("action")
            if a is None: return self.send(json.dumps({"user_info": {"auth": 1, "status": "Active", "username": "demo"}, "server_info": {"timezone": "UTC"}}).encode())
            kind = {"live": "live", "vod": "movie", "series": "series"}.get(a.split("_")[1] if a.startswith("get_") and a.split("_")[1] in ("live", "vod", "series") else "", None)
            if a.endswith("_categories") and kind: return self.send(json.dumps(CATS[kind]).encode())
            if a in ("get_live_streams", "get_vod_streams", "get_series") and kind: return self.send(json.dumps(clean(ITEMS[kind])).encode())
            if a == "get_vod_info" and ("movie", q["vod_id"]) in BY_ID: it = BY_ID[("movie", q["vod_id"])]; return self.send(json.dumps({"info": info("movie", it), "movie_data": {"stream_id": it["num"]}}).encode())
            if a == "get_series_info" and ("series", q["series_id"]) in BY_ID: return self.send(json.dumps(series_info(BY_ID[("series", q["series_id"])])).encode())
            if a == "get_short_epg": return self.send(json.dumps(epg(q.get("stream_id", "0"))).encode())
            return self.send(b"[]")
        if len(parts) == 3 and parts[0] == "art":
            name = parts[2].rsplit(".", 1)[0]
            p = {"poster": lambda: art("poster", name, 240, 360), "backdrop": lambda: art("backdrop", name, 640, 360), "logo": lambda: logo(name)}.get(parts[1])
            return self.send(p().read_bytes(), "image/png") if p else self.send(b"", code=404)
        if parts and parts[0] in ("live", "movie", "series") and VIDEO.exists():
            data = VIDEO.read_bytes(); rng = self.headers.get("Range")
            if rng and rng.startswith("bytes="):
                a, _, b = rng[6:].partition("-"); s = int(a or 0); e = int(b) if b else len(data) - 1
                return self.send(data[s:e + 1], "video/mp4", 206, {"Content-Range": f"bytes {s}-{e}/{len(data)}", "Accept-Ranges": "bytes"})
            return self.send(data, "video/mp4", extra={"Accept-Ranges": "bytes"})
        self.send(b"not found", "text/plain", 404)

if __name__ == "__main__":
    for kind, l in ITEMS.items():                           # artwork first, so the first screenshot is not waiting for it
        for i in l:
            nm = i.get("_base") or i["name"]
            if kind == "live": logo(nm)
            else: art("poster", nm, 240, 360); art("backdrop", nm, 640, 360)
    ensure_video()
    print(f"demo provider on http://127.0.0.1:{PORT}  (user demo / password demo), {sum(len(v) for v in ITEMS.values())} items", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
