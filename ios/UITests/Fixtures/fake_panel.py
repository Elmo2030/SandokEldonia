#!/usr/bin/env python3
"""A tiny fake Xtream panel for the player checks: login, categories, channels, movies, a series with two episodes, a short EPG, and the
stream URLs (/live, /movie, /series) served from a media folder WITH HTTP Range support (mpv needs it to seek).
Usage: fake_panel.py <media dir> [port]   user/password: any.   Hebrew and English names, no real content."""
import base64, json, os, re, sys, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

MEDIA = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8765
LIVE = [("101", "ערוץ בדיקה 1"), ("102", "Test News"), ("103", "Test Sports"), ("104", "ערוץ בדיקה 4"), ("105", "Test Movies")]
FILES = {"movie": {"201": "vod.mkv", "202": "vod.mkv"}, "series": {"401": "ep1.mkv", "402": "ep2.mkv"}, "live": {k: "live.ts" for k, _ in LIVE}}

def api(q):
    a = q.get("action", [None])[0]
    if a is None:
        return {"user_info": {"auth": 1, "status": "Active"}, "server_info": {"timezone": "UTC"}}
    if a == "get_live_categories": return [{"category_id": "1", "category_name": "Test channels"}]
    if a == "get_live_streams":
        return [{"stream_id": int(i), "name": n, "category_id": "1", "stream_icon": "", "epg_channel_id": f"ch{i}", "tv_archive": 0} for i, n in LIVE]
    if a == "get_vod_categories": return [{"category_id": "2", "category_name": "Test movies"}]
    if a == "get_vod_streams":
        return [{"stream_id": 201, "name": "Test movie (testsrc)", "category_id": "2", "container_extension": "mkv", "rating": "7.5"},
                {"stream_id": 202, "name": "סרט בדיקה", "category_id": "2", "container_extension": "mkv", "rating": "6"}]
    if a == "get_series_categories": return [{"category_id": "3", "category_name": "Test series"}]
    if a == "get_series": return [{"series_id": 301, "name": "Test series", "category_id": "3", "cover": ""}]
    if a == "get_series_info":
        return {"info": {"name": "Test series"}, "episodes": {"1": [
            {"id": "401", "episode_num": 1, "title": "Pilot", "season": 1, "container_extension": "mkv"},
            {"id": "402", "episode_num": 2, "title": "Second", "season": 1, "container_extension": "mkv"}]}}
    if a == "get_short_epg":
        now = int(time.time())
        def e(t, s, d): return {"title": base64.b64encode(t.encode()).decode(), "start_timestamp": now + s, "stop_timestamp": now + s + d}
        return {"epg_listings": [e("Evening news", -1200, 3000), e("Weather and sport", 1800, 1800), e("Late film", 3600, 5400)][:int(q.get("limit", ["3"])[0])]}
    return []

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_HEAD(self): self.do_GET()
    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/player_api.php":
            body = json.dumps(api(parse_qs(u.query))).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers()
            self.wfile.write(body); return
        m = re.match(r"/(live|movie|series)/[^/]+/[^/]+/([^/.]+)\.\w+$", u.path)
        name = FILES.get(m.group(1), {}).get(m.group(2)) if m else None
        if not name and u.path.lstrip("/") in os.listdir(MEDIA): name = u.path.lstrip("/")
        if not name: self.send_error(404); return
        path = os.path.join(MEDIA, name); size = os.path.getsize(path)
        r = re.match(r"bytes=(\d*)-(\d*)", self.headers.get("Range") or "")
        a, b = 0, size - 1
        if r:
            a = int(r.group(1)) if r.group(1) else max(size - int(r.group(2)), 0)
            b = min(int(r.group(2)), size - 1) if r.group(1) and r.group(2) else size - 1
        self.send_response(206 if r else 200)
        if r: self.send_header("Content-Range", f"bytes {a}-{b}/{size}")
        self.send_header("Content-Length", str(b - a + 1)); self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Type", "video/mp2t" if name.endswith(".ts") else "video/x-matroska"); self.end_headers()
        if self.command == "HEAD": return
        try:
            with open(path, "rb") as f:
                f.seek(a); left = b - a + 1
                while left > 0:
                    buf = f.read(min(65536, left))
                    if not buf: break
                    self.wfile.write(buf); left -= len(buf)
        except (BrokenPipeError, ConnectionResetError): pass

ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
