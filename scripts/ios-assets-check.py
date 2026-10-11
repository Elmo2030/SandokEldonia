#!/usr/bin/env python3
"""Semantic checks for ios/Resources (called by scripts/ios-assets-check.sh; read-only, writes nothing).
  1. InfoPlist.strings: one per Sources/IPTVMac/Resources/*.lproj, the keys of English, no empty values, translations differ from English,
     the product name survives (the same rules as scripts/check-strings.py, which only reads Localizable.strings).
  2. Info-extra.plist: the keys the iOS app needs, CFBundleLocalizations == the lproj list, launch screen names exist in the asset catalog,
     none of the keys that were rejected on purpose (UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace, NSBonjourServices).
  3. PrivacyInfo.xcprivacy: no tracking, no collected data, categories and reason codes from Apple's list (read 2026-10-11), no SDK-only
     reasons in an app manifest, and every required-reason API found in the Swift sources belongs to a declared category.
  4. Acknowledgements.txt is current and names every shipped library."""
import json, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "ios/Resources"
LPROJ = ROOT / "Sources/IPTVMac/Resources"
bad = []

def fail(msg): bad.append(msg); print("  FAIL", msg)
def ok(msg): print("  ok  ", msg)
def plist(path):
    r = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)], capture_output=True, text=True)
    if r.returncode: fail(f"{path.relative_to(ROOT)}: {r.stderr.strip()}"); return {}
    return json.loads(r.stdout)

# 1. InfoPlist.strings ------------------------------------------------------------------------------------------------------------
print("InfoPlist.strings")
langs = sorted(p.name[:-6] for p in LPROJ.glob("*.lproj"))
have = sorted(p.name[:-6] for p in RES.glob("*.lproj"))
if langs != have: fail(f"languages differ from Sources/IPTVMac/Resources: missing {sorted(set(langs) - set(have))}, extra {sorted(set(have) - set(langs))}")
S = {l: plist(RES / f"{l}.lproj/InfoPlist.strings") for l in have if (RES / f"{l}.lproj/InfoPlist.strings").exists()}
en = S.get("en", {})
for l, t in S.items():
    if set(t) != set(en): fail(f"{l}: keys {sorted(t)} differ from English {sorted(en)}")
    for k, v in t.items():
        if not v.strip(): fail(f"{l}: empty value for {k}")
        if "IPTVMac" not in v: fail(f"{l}: {k} lost the product name IPTVMac")
        if l != "en" and k == "NSLocalNetworkUsageDescription" and v == en.get(k): fail(f"{l}: {k} is an untouched copy of English")
        if len(v) > 400: fail(f"{l}: {k} is {len(v)} characters (a permission sheet is not a page)")
if not bad: ok(f"{len(S)} languages, keys {sorted(en)}")

# 2. Info-extra.plist -------------------------------------------------------------------------------------------------------------
print("Info-extra.plist")
n0 = len(bad)
info = plist(RES / "Info-extra.plist")
if sorted(info.get("CFBundleLocalizations", [])) != langs: fail("CFBundleLocalizations differs from the lproj list")
for k, want in (("ITSAppUsesNonExemptEncryption", False), ("UIRequiredDeviceCapabilities", ["arm64"]), ("UIBackgroundModes", ["audio"])):
    if info.get(k) != want: fail(f"{k} is {info.get(k)!r}, expected {want!r}")
if info.get("NSLocalNetworkUsageDescription") != en.get("NSLocalNetworkUsageDescription"): fail("NSLocalNetworkUsageDescription differs from en.lproj")
for k in ("UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace", "NSBonjourServices"):
    if k in info: fail(f"{k} must stay out (reasons in ios/RESOURCES.md); add it only together with the code that needs it")
if not {"UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~ipad", "CFBundleDisplayName", "UILaunchScreen"} <= set(info): fail("orientation / display name / launch screen keys missing")
catalog = RES / "Assets.xcassets"
for key, suffix in (("UIColorName", "colorset"), ("UIImageName", "imageset")):
    name = info.get("UILaunchScreen", {}).get(key)
    if not name or not (catalog / f"{name}.{suffix}").is_dir(): fail(f"UILaunchScreen.{key} = {name!r} is not in Assets.xcassets")
declared = {t["UTTypeIdentifier"] for t in info.get("UTImportedTypeDeclarations", [])}
for d in info.get("CFBundleDocumentTypes", []):
    for uti in d["LSItemContentTypes"]:
        if uti.startswith("io.github.goelir.") and uti not in declared: fail(f"document type {uti} has no UTImportedTypeDeclarations entry")
for p in catalog.rglob("Contents.json"):
    try: json.loads(p.read_text())
    except ValueError as e: fail(f"{p.relative_to(ROOT)}: {e}")
if len(bad) == n0: ok("keys, languages, launch screen, document types, catalog JSON")

# 3. PrivacyInfo.xcprivacy --------------------------------------------------------------------------------------------------------
print("PrivacyInfo.xcprivacy")
n0 = len(bad)
P = plist(RES / "PrivacyInfo.xcprivacy")
REASONS = {  # Apple, "Describing use of required reason API"
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1", "8FFB.1", "3D61.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {"3EC4.1", "54BD.1"},
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"}}
SDK_ONLY = {"0A2A.1", "C56D.1"}
if P.get("NSPrivacyTracking") is not False: fail("NSPrivacyTracking must be false")
if P.get("NSPrivacyTrackingDomains") != []: fail("NSPrivacyTrackingDomains must be empty")
if P.get("NSPrivacyCollectedDataTypes") != []: fail("NSPrivacyCollectedDataTypes must be empty (the app collects nothing); change the code and this together")
cats = {}
for e in P.get("NSPrivacyAccessedAPITypes", []):
    c, rs = e["NSPrivacyAccessedAPIType"], e["NSPrivacyAccessedAPITypeReasons"]
    if c not in REASONS: fail(f"unknown category {c}"); continue
    if c in cats: fail(f"category {c} listed twice")
    cats[c] = set(rs)
    for r in rs:
        if r not in REASONS[c]: fail(f"{r} is not a reason of {c}")
        if r in SDK_ONLY: fail(f"{r} may only be declared by a third-party SDK")
USES = {  # symbols and APIs from the same Apple page; a hit means "review", the category must at least be declared
    "NSPrivacyAccessedAPICategoryUserDefaults": r"UserDefaults|@AppStorage|\bAppStorage\(|@SceneStorage",
    "NSPrivacyAccessedAPICategoryFileTimestamp": r"\bcreationDate\b|\bmodificationDate\b|fileModificationDate|fileCreationDate|contentModificationDate|creationDateKey|NSFileCreationDate|NSFileModificationDate|getattrlist|\b(?:l|f)?stat\(",
    "NSPrivacyAccessedAPICategorySystemBootTime": r"systemUptime|mach_absolute_time",
    "NSPrivacyAccessedAPICategoryDiskSpace": r"volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|\bsystemSize\b|\bf?statv?fs\(",
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"activeInputModes"}
# ponytail: macOS-only files (updater, downloads, Settings panels) are scanned too, so a hit there is a hint to look, not proof; the iOS
# target decides. The binaries were scanned with nm -u (see ios/RESOURCES.md); this only guards new Swift code.
srcs = [p for d in (ROOT / "Sources", ROOT / "ios") if d.is_dir() for p in d.rglob("*.swift")]
for c, rx in USES.items():
    hits = sorted({p.relative_to(ROOT).as_posix() for p in srcs if re.search(rx, p.read_text(errors="ignore"))})
    if hits and c not in cats: fail(f"{c.replace('NSPrivacyAccessedAPICategory', '')} used in {hits[:4]} but not declared")
if len(bad) == n0: ok(f"{len(cats)} categories declared, {len(srcs)} Swift files scanned")

# 4. Acknowledgements -------------------------------------------------------------------------------------------------------------
print("Acknowledgements")
n0 = len(bad)
r = subprocess.run([sys.executable, str(ROOT / "scripts/ios-acknowledgements.py"), "--check"], capture_output=True, text=True)
if r.returncode: fail(r.stderr.strip())
md = (RES / "Acknowledgements.md").read_text()
for lib in ("mpv 0.36.0", "FFmpeg 6.0", "mbedTLS 3.4.1", "dav1d 1.2.1", "libass 0.17.1", "HarfBuzz 8.1.1", "FreeType 2.13.2", "FriBidi 1.0.13",
            "libxml2 2.11.5", "uchardet 0.0.8", "libpng 1.6.40", "GRDB.swift 7.11.1", "Apache License", "GNU Lesser General Public License", "libmpv-darwin-build"):
    if lib not in md: fail(f"Acknowledgements.md does not mention {lib}")
if "Sintel" in md: fail("Sintel is credited but not shipped")
if len(bad) == n0: ok("txt current, every library and licence present")

print(f"\n{'FAILED: ' + str(len(bad)) + ' problem(s)' if bad else 'semantic checks passed'}")
sys.exit(1 if bad else 0)
