#!/usr/bin/env python3
"""Checks docs/review/ReviewPlaylist.m3u the way IPTVMac reads it.
Offline (default): mirrors Sources/IPTVCore/M3U.swift (parser + M3UClassifier) and SyncService.fetchM3U (first line must be #EXTM3U,
a url+type seen twice is dropped, http(s) only for playback) and prints the entries per type and group.
--online: also sends a HEAD request (curl, redirects followed) to every URL and requires HTTP 200 and a video, HLS or DASH content type (re-run before each submission: hosts change).
Usage: python3 appstore/check-review-playlist.py [--online] [path-or-url]   exit code 1 on any problem."""
import re, sys, pathlib, subprocess, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
args = [a for a in sys.argv[1:] if not a.startswith("--")]
src = args[0] if args else str(ROOT / "docs/review/ReviewPlaylist.m3u")
text = urllib.request.urlopen(src, timeout=30).read().decode("utf-8", "replace") if src.startswith("http") else pathlib.Path(src).read_text(encoding="utf-8")

ATTR = re.compile(r'([A-Za-z0-9_-]+)="([^"]*)"')
def parse_inf(line):                                  # M3UParser.parseInf
    if len(line.encode()) > 8192: return "", {}
    inq, comma = False, None
    for i, ch in enumerate(line):
        if ch == '"': inq = not inq
        elif ch == "," and not inq: comma = i; break
    head = line if comma is None else line[:comma]
    name = "" if comma is None else line[comma + 1:].strip()
    return name, dict(ATTR.findall(head))

def classify(url, group):                             # M3UClassifier.type
    u = url.lower()
    if "/movie/" in u: return "movie"
    if "/series/" in u: return "series"
    g = (group or "").lower()
    if any(k in g for k in ("series", "tv show", "סדר")): return "series"
    if any(k in g for k in ("vod", "movie", "film", "סרט")): return "movie"
    if u.endswith((".mp4", ".mkv", ".avi")): return "movie"
    return "live"

errors, entries, pending, seen = [], [], None, set()
first = text.lstrip("﻿ \t\r\n")
if not first.startswith("#EXTM3U"): errors.append("first line is not #EXTM3U (the app rejects the playlist)")
for raw in text.splitlines():
    line = raw.strip().lstrip("﻿")
    if not line or line.startswith("#EXTM3U"): continue
    if line.startswith("#EXTINF"): pending = parse_inf(line); continue
    if line.startswith("#"): continue
    name, attrs = pending or ("", {}); pending = None
    name = name or line.rsplit("/", 1)[-1] or "Channel"
    group = attrs.get("group-title") or None
    typ = classify(line, group)
    if not re.match(r"^https?://[^/\s]+", line, re.I): errors.append(f"not an http(s) URL: {line}")
    if (typ, line) in seen: errors.append(f"duplicate url in the same type: {line}"); continue
    seen.add((typ, line)); entries.append((typ, group, name, line))

counts = {t: sum(1 for e in entries if e[0] == t) for t in ("live", "movie", "series")}
print("entries:", len(entries), counts)
for t in ("live", "movie", "series"):
    groups = sorted({e[1] or "(no group)" for e in entries if e[0] == t})
    print(f"  {t:6} groups={groups}")
    for e in entries:
        if e[0] == t: print(f"         [{e[1]}] {e[2]}")
for t in ("live", "movie", "series"):
    if not counts[t]: errors.append(f"no {t} entry")

if "--online" in sys.argv:
    ok_types = ("video/", "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "application/dash+xml")
    for typ, group, name, url in entries:          # curl, not urllib: it uses the macOS trust store (python.org builds often have none)
        r = subprocess.run(["curl", "-sIL", "-m", "30", "-A", "IPTVMac-review-check", "-o", "/dev/null", "-w", "%{http_code} %{content_type}", url], capture_output=True, text=True)
        code, _, ct = r.stdout.strip().partition(" "); ct = ct.lower()
        good = code == "200" and ct.startswith(ok_types)
        print(("ok   " if good else "FAIL ") + f"{code} {ct:34} {name}")
        if not good: errors.append(f"{name}: {code} {ct} {r.stderr.strip()}")
print("PROBLEMS:" if errors else "playlist ok", *errors, sep="\n  " if errors else " ")
sys.exit(1 if errors else 0)
