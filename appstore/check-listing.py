#!/usr/bin/env python3
"""Checks the App Store Connect texts in appstore/en-US and appstore/localizations/*: field limits and the metadata rules from the App Review Guidelines (2.3.7, 2.3.10).
Limits (App Store Connect help, "Platform version information", read 2026-10-11): name 30 characters, subtitle 30, promotional text 170, description 4000,
keywords 100 BYTES (UTF-8: Cyrillic, Hebrew and Arabic cost 2 bytes a letter, Chinese, Japanese and Korean 3), each keyword longer than two characters (checked for one character in Chinese, Japanese and Korean, where two-character words are normal: if App Store Connect rejects one, drop it).
Usage: python3 appstore/check-listing.py        exit code 1 on any problem."""
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parent
LIMITS = {"name": 30, "subtitle": 30, "promotional-text": 170, "description": 4000}
BRANDS = ["vlc", "kodi", "plex", "netflix", "smarters", "tivimate", "televizo", "iptvnator", "xtream", "disney", "hbo", "sky", "apple tv", "youtube", "windows", "android", "linux"]   # keywords, name, subtitle: no other apps, companies or trademarks (2.3.7)
PRICE = ["free", "gratis", "gratuit", "kostenlos", "бесплат", "ücretsiz", "grátis", "gratuito", "免费", "無料", "무료", "مجاني", "חינם", "best", "#1", "sale"]                   # no pricing terms in indexed fields (2.3.7)
OTHER_PLATFORMS = ["windows", "android", "linux", "iphone", "ipad"]                                                                                                           # 2.3.10: descriptions are about the Mac
bad = 0
def err(loc, msg):
    global bad; bad += 1; print(f"  PROBLEM {loc}: {msg}")
dirs = [ROOT / "en-US"] + sorted((ROOT / "localizations").glob("*"))
for d in dirs:
    loc = d.name; t = {}
    for f in (*LIMITS, "keywords"):
        p = d / f"{f}.txt"
        if not p.exists(): err(loc, f"{f}.txt missing"); continue
        raw = p.read_text(encoding="utf-8"); t[f] = raw[:-1] if raw.endswith("\n") else raw
        if t[f] != t[f].strip() or "\r" in t[f]: err(loc, f"{f}.txt has stray whitespace or CR")
    if len(t) < 5: continue
    for f, lim in LIMITS.items():
        if len(t[f]) > lim: err(loc, f"{f} is {len(t[f])} > {lim} characters")
    kw = t["keywords"]; kws = kw.split(",")
    if len(kw.encode()) > 100: err(loc, f"keywords are {len(kw.encode())} > 100 bytes")
    if re.search(r",\s|\s,", kw): err(loc, "space around a comma in keywords")
    if len(set(k.lower() for k in kws)) != len(kws): err(loc, "duplicate keyword")
    cjk = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]")      # a two-character Chinese, Japanese or Korean word is a normal keyword: the rule is checked at three characters for the other scripts only
    short = [k for k in kws if len(k) <= (1 if cjk.search(k) else 2)]
    if short: err(loc, f"keywords of two characters or fewer: {short}")
    indexed = " ".join([t["name"], t["subtitle"], kw]).lower()
    for w in BRANDS + PRICE:
        if re.search(r"(?<![a-z0-9])" + re.escape(w) + r"(?![a-z0-9])", indexed): err(loc, f"'{w}' in name, subtitle or keywords")
    words = {w.lower() for w in re.findall(r"[^\W_]{3,}", t["name"] + " " + t["subtitle"])}
    dup = [k for k in kws if k.lower() in words]
    if dup: print(f"  note    {loc}: keywords repeat words of the name or subtitle (wasted bytes): {dup}")
    for w in OTHER_PLATFORMS:
        if re.search(r"(?<![a-z])" + w + r"(?![a-z])", (t["description"] + t["promotional-text"]).lower()): err(loc, f"description names '{w}' (2.3.10)")
    if "goelir.github.io/IPTVMac/" not in t["description"] or "privacy" not in t["description"]: err(loc, "description lacks the privacy policy link")
    print(f"{loc:8} name {len(t['name']):2}  subtitle {len(t['subtitle']):2}  promo {len(t['promotional-text']):3}  description {len(t['description']):4}  keywords {len(kw.encode()):3} bytes")
rn = (ROOT / "review-notes.txt").read_text(encoding="utf-8")          # Part 1 of the review notes is pasted into the Notes field: limit 4000 bytes
a = rn.index("\n", rn.index('LINE "END OF PART 1" ================')) + 1
part1 = rn[a:rn.index("================ END OF PART 1")].strip()
print(f"review-notes part 1: {len(part1.encode())} bytes (limit 4000)")
if len(part1.encode()) > 4000: err("review-notes", "part 1 is longer than 4000 bytes")
print("PROBLEMS" if bad else "all listing texts ok"); sys.exit(1 if bad else 0)
