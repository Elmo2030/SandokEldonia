#!/bin/bash
# Builds the Mac App Store variant: build-appstore/IPTVMac.app (compiled with -DAPPSTORE: no updater, App Sandbox entitlements) and,
# when the installer identity is set, build-appstore/IPTVMac-<version>-<build>.pkg ready for scripts/upload-appstore.sh.
# Step by step guide for the owner: scripts/APPSTORE.md. The direct-download build (scripts/make-app.sh) is not touched.
#
#   no variable set          LOCAL SANDBOX TEST: ad-hoc signed with the sandbox entitlements (runs on this Mac without a profile),
#                            then runs --selftest and --sandbox-probe on it and checks the sandbox is really on. No .pkg.
#   IPTVMAC_APPSTORE_IDENTITY="Apple Distribution: Name (TEAMID)"   signs for the store (needs the profile below)
#   IPTVMAC_PROVISIONING_PROFILE=/path/IPTVMac.provisionprofile      Mac App Store profile: embedded as Contents/embedded.provisionprofile
#   IPTVMAC_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Name (TEAMID)"   (the "Mac Installer Distribution" certificate) makes the .pkg
#   IPTVMAC_BUILD_NUMBER=n   one-off build number (default: scripts/APPSTORE_BUILD_NUMBER, raised by upload-appstore.sh after an upload)
#   IPTVMAC_COPYRIGHT="Copyright © 2026 Your Name"   NSHumanReadableCopyright
#   IPTVMAC_NON_EXEMPT_ENCRYPTION=1   declares ITSAppUsesNonExemptEncryption=true instead of false (see APPSTORE.md, "Encryption")
#   IPTVMAC_APPSTORE_HARDENED=1       also signs with the hardened runtime (not required for the store; see APPSTORE.md)
#   IPTVMAC_SKIP_PROBE=1              skip the local --selftest / --sandbox-probe run of an ad-hoc build
# Idempotent: every run rebuilds build-appstore/ from the sources. Nothing secret is read or printed (no keychain access here: codesign
# and productbuild do that themselves).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"
fail() { echo "make-appstore: $*" >&2; exit 1; }

OUT=build-appstore
APP="$OUT/IPTVMac.app"
VERSION="$(cat VERSION)"
BUNDLE_ID=io.github.goelir.IPTVMac
IDENTITY="${IPTVMAC_APPSTORE_IDENTITY:--}"
INSTALLER="${IPTVMAC_INSTALLER_IDENTITY:-}"
PROFILE="${IPTVMAC_PROVISIONING_PROFILE:-}"
BUILD_NUMBER="${IPTVMAC_BUILD_NUMBER:-$(tr -d ' \t\r\n' < scripts/APPSTORE_BUILD_NUMBER)}"
COPYRIGHT="${IPTVMAC_COPYRIGHT:-Copyright © $(date +%Y) IPTVMac contributors}"

# Fail before the long build, not after it.
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail "the build number must be a positive integer (scripts/APPSTORE_BUILD_NUMBER or IPTVMAC_BUILD_NUMBER), got '$BUILD_NUMBER'"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION must look like 1.2.3 for the App Store, got '$VERSION'"
if [ "$IDENTITY" = "-" ]; then
  [ -z "$INSTALLER" ] || fail "IPTVMAC_INSTALLER_IDENTITY is set but IPTVMAC_APPSTORE_IDENTITY is not: a package of an ad-hoc signed app is useless"
  [ -z "$PROFILE" ] || fail "IPTVMAC_PROVISIONING_PROFILE is set but IPTVMAC_APPSTORE_IDENTITY is not: set both, or neither for the local sandbox test"
else
  [ -n "$PROFILE" ] || fail "IPTVMAC_APPSTORE_IDENTITY needs IPTVMAC_PROVISIONING_PROFILE (the Mac App Store profile, see scripts/APPSTORE.md)"
  [ -f "$PROFILE" ] || fail "provisioning profile not found: $PROFILE"
  [ -n "$INSTALLER" ] || fail "IPTVMAC_INSTALLER_IDENTITY is not set: without the Mac Installer Distribution certificate there is no .pkg to upload. Set it, or unset IPTVMAC_APPSTORE_IDENTITY for a local sandbox test."
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# The embedded profile says which team and which app id the store will accept: read both from it, and refuse a profile of another app.
TEAM=""; APPID=""
if [ -n "$PROFILE" ]; then
  # The profile is a CMS-signed plist: openssl unwraps it without touching the keychain (-noverify: Apple's chain is not needed to read it).
  openssl smime -inform der -verify -noverify -in "$PROFILE" -out "$TMP/profile.plist" 2>/dev/null || fail "cannot read $PROFILE: is it a .provisionprofile?"
  pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$TMP/profile.plist" 2>/dev/null || true; }
  APPID="$(pb Entitlements:com.apple.application-identifier)"
  TEAM="$(pb Entitlements:com.apple.developer.team-identifier)"
  [ -n "$APPID" ] && [ -n "$TEAM" ] || fail "$PROFILE has no application-identifier / team-identifier: it is not an app profile (a Mac App Store one is needed)"
  [ "$APPID" = "$TEAM.$BUNDLE_ID" ] || fail "the profile is for '$APPID', this app is '$TEAM.$BUNDLE_ID'. Create the profile for the bundle id $BUNDLE_ID."
  [ -z "$(pb ProvisionedDevices)" ] || fail "$PROFILE lists devices: it is a development profile. The store needs a 'Mac App Store' distribution profile."
  EXPIRY="$(pb ExpirationDate)"
  python3 - "$TMP/profile.plist" <<'PY' || fail "the provisioning profile has expired: create a new one in the developer portal"
import plistlib, sys, datetime
p = plistlib.load(open(sys.argv[1], "rb"))
exp = p.get("ExpirationDate")
now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
sys.exit(1 if exp is not None and exp.replace(tzinfo=None) < now else 0)
PY
  echo "Profile: team $TEAM, app $APPID, expires ${EXPIRY:-unknown}"
fi

# 1. Compile with -DAPPSTORE into its own scratch folder (the debug/release caches of the direct build stay as they are) and assemble the bundle.
IPTVMAC_OUT_DIR="$OUT" IPTVMAC_BUILD_NUMBER="$BUILD_NUMBER" IPTVMAC_SKIP_SIGN=1 \
  IPTVMAC_SWIFT_ARGS="-Xswiftc -DAPPSTORE --scratch-path $OUT/.build" scripts/make-app.sh
[ -d "$APP" ] || fail "make-app.sh did not produce $APP"

# 2. Info.plist keys the store wants. NSAppTransportSecurity stays as in the direct build on purpose: users add their own http:// sources
# (see "App Review notes" in scripts/APPSTORE.md).
PL="$APP/Contents/Info.plist"
plutil -replace ITSAppUsesNonExemptEncryption -bool "$([ -n "${IPTVMAC_NON_EXEMPT_ENCRYPTION:-}" ] && echo true || echo false)" "$PL"
plutil -replace LSApplicationCategoryType -string public.app-category.entertainment "$PL"
plutil -replace NSHumanReadableCopyright -string "$COPYRIGHT" "$PL"
plutil -lint "$PL" >/dev/null
[ "$(plutil -extract CFBundleVersion raw -o - "$PL")" = "$BUILD_NUMBER" ] || fail "CFBundleVersion is not $BUILD_NUMBER"
[ "$(plutil -extract CFBundleShortVersionString raw -o - "$PL")" = "$VERSION" ] || fail "CFBundleShortVersionString is not $VERSION"

# 3. A copy of the system's root certificates, used by the player only if a later macOS closes /etc/ssl/cert.pem to the sandbox
# (it is readable today: `--sandbox-probe` reports it). Refuse an empty or truncated file: TLS verification stays on and would fail closed.
CA=/etc/ssl/cert.pem
[ "$(grep -c 'BEGIN CERTIFICATE' "$CA")" -ge 100 ] || fail "$CA looks wrong (fewer than 100 certificates)"
cp "$CA" "$APP/Contents/Resources/cacert.pem"

# 4. Profile.
if [ -n "$PROFILE" ]; then cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"; fi

# 5. Entitlements: the fixed ones, plus (store build) the team and application identifiers, which restricted entitlements require.
ENT="$OUT/signing.entitlements"
cp scripts/appstore.entitlements "$ENT"
if [ -n "$PROFILE" ]; then
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APPID" -c "Add :com.apple.developer.team-identifier string $TEAM" "$ENT"
fi
plutil -lint "$ENT" >/dev/null

# 6. Signing: every bundled dylib first, then the app with the entitlements (no --deep). The hardened runtime is NOT required for the Mac
# App Store (it is a notarization requirement, and the sandbox is the store's containment); it is also untestable here with an ad-hoc
# signature (library validation needs a Team ID), so it is opt-in: IPTVMAC_APPSTORE_HARDENED=1.
FLAGS=(--force --sign "$IDENTITY")
[ "$IDENTITY" = "-" ] || FLAGS+=(--timestamp)
[ -z "${IPTVMAC_APPSTORE_HARDENED:-}" ] || FLAGS+=(--options runtime)
find "$APP/Contents/Frameworks" -name '*.dylib' -exec codesign "${FLAGS[@]}" {} \;
codesign "${FLAGS[@]}" --entitlements "$ENT" "$APP"
codesign --verify --strict --deep "$APP"
# The sandbox entitlement must really be in the signature (a missing one is the classic silent failure: the app runs, unsandboxed).
codesign -d --xml --entitlements - "$APP" 2>/dev/null > "$TMP/ent.plist" || codesign -d --entitlements :- "$APP" 2>/dev/null > "$TMP/ent.plist" || true
[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$TMP/ent.plist" 2>/dev/null || true)" = "true" ] || fail "the signed app lacks com.apple.security.app-sandbox"
echo "Signed $APP ($([ "$IDENTITY" = "-" ] && echo ad-hoc || echo "$IDENTITY"))"

# 7a. Ad-hoc build: the local sandbox test (headless: both flags print and exit, no window).
if [ "$IDENTITY" = "-" ]; then
  if [ -z "${IPTVMAC_SKIP_PROBE:-}" ]; then
    EXE="$APP/Contents/MacOS/IPTVMac"
    "$EXE" --selftest
    "$EXE" --sandbox-probe | tee "$TMP/probe.json"
    python3 - "$TMP/probe.json" <<'PY' || fail "the sandbox probe failed (see the JSON above)"
import json, sys
p = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
sys.exit(0 if p.get("ok") and p.get("sandbox") and p.get("build") == "appstore" and not p.get("updaterCompiledIn") else 1)
PY
  fi
  echo "Built $APP (ad-hoc, for local sandbox testing only: it cannot be uploaded). No .pkg: set IPTVMAC_APPSTORE_IDENTITY, IPTVMAC_PROVISIONING_PROFILE and IPTVMAC_INSTALLER_IDENTITY."
  exit 0
fi

# 7b. Store build: the installer package, signed with the Mac Installer Distribution certificate.
PKG="$OUT/IPTVMac-$VERSION-$BUILD_NUMBER.pkg"
rm -f "$PKG"
productbuild --component "$APP" /Applications --sign "$INSTALLER" "$PKG"
pkgutil --check-signature "$PKG" >/dev/null || fail "the package signature does not verify"
echo "Built $PKG (version $VERSION, build $BUILD_NUMBER). Next: scripts/upload-appstore.sh $PKG"
