#!/bin/bash
# Builds build/IPTVMac.app with a prebuilt libmpv bundled (nothing to install on the target Mac, macOS 14+, Apple Silicon).
#
# The player library is the media-kit "libmpv-darwin-build" release (mpv 0.36 + ffmpeg 6, built for macOS 11+, GPL).
# Homebrew's mpv is NOT bundled: its bottles require the macOS version of the build machine (27), so the app would not
# open on older Macs. Homebrew's mpv is still used at build time for the C headers and to link against.
# Requires on the build machine: brew install mpv pkgconf
#
# scripts/make-appstore.sh reuses this script for the Mac App Store build through these variables (all unset = the direct-download build):
#   IPTVMAC_OUT_DIR=dir          where the app is assembled (default build; the downloaded libmpv stays in build/vendor)
#   IPTVMAC_SWIFT_ARGS="..."     extra arguments of `swift build` (the App Store build passes -Xswiftc -DAPPSTORE and its own --scratch-path)
#   IPTVMAC_BUILD_NUMBER=n       CFBundleVersion (default: the version, as before)
#   IPTVMAC_SKIP_SIGN=1          leave the bundle unsigned: the caller signs it
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"

# Single source of the app version: the VERSION file (IPTVMAC_VERSION overrides it for update tests).
VERSION="${IPTVMAC_VERSION:-$(cat VERSION)}"
OUT="${IPTVMAC_OUT_DIR:-build}"
BUILD_NUMBER="${IPTVMAC_BUILD_NUMBER:-$VERSION}"
read -r -a SWIFT_ARGS <<< "${IPTVMAC_SWIFT_ARGS:-}"
MK_VERSION=v0.7.3
MK_NAME="libmpv-libs_${MK_VERSION}_macos-arm64-video-full"
MK_SHA256=9bb168ec908b4801f4231f411e3278a0aea644a2b03ce375c880d2813ab7f949
VENDOR=build/vendor
if [ ! -d "$VENDOR/$MK_NAME" ]; then
  mkdir -p "$VENDOR"
  curl -fsSL -o "$VENDOR/mk.tgz" "https://github.com/media-kit/libmpv-darwin-build/releases/download/$MK_VERSION/$MK_NAME.tar.gz"
  echo "$MK_SHA256  $VENDOR/mk.tgz" | shasum -a 256 -c -
  tar xzf "$VENDOR/mk.tgz" -C "$VENDOR"
fi

# (bash 3.2 and `set -u`: an empty array must be expanded with the ${a[@]+...} form)
scripts/swift.sh build -c release ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"}
BIN="$(scripts/swift.sh build -c release ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"} --show-bin-path)"
APP="$OUT/IPTVMac.app"
EXE="$APP/Contents/MacOS/IPTVMac"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/IPTVMac" "$EXE"
cp -R "$BIN/IPTVMac_IPTVMac.bundle" "$APP/Contents/Resources/"
cp "$VENDOR/$MK_NAME"/*.dylib "$APP/Contents/Frameworks/"

# Point the executable at the bundled libmpv instead of Homebrew's, and resolve @rpath dependencies inside the app.
OLD="$(otool -L "$EXE" | awk '/libmpv/ {print $1; exit}')"
install_name_tool -change "$OLD" "@rpath/libmpv.dylib" "$EXE"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE"
# The prebuilt dylibs carry build-machine rpaths (/nix/store/...) that do not exist anywhere else.
for f in "$APP"/Contents/Frameworks/*.dylib; do
  for rp in $(otool -l "$f" | awk '/path \/nix\/store/ {print $2}'); do install_name_tool -delete_rpath "$rp" "$f"; done
done

# App icon: use the custom SandokEldonia icon.
CUSTOM_ICON="$HOME/Downloads/SandokEldonia.icns"
if [ ! -f "$CUSTOM_ICON" ]; then
  echo "Missing custom icon: $CUSTOM_ICON" >&2
  exit 1
fi
cp "$CUSTOM_ICON" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>SandokEldonia</string>
<key>CFBundleDisplayName</key><string>SandokEldonia</string>
<key>CFBundleIdentifier</key><string>io.github.goelir.IPTVMac</string>
<key>CFBundleExecutable</key><string>IPTVMac</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>__VERSION__</string>
<key>CFBundleVersion</key><string>__BUILD__</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleLocalizations</key><array>__LOCALIZATIONS__</array>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
sed -i '' -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD_NUMBER/g" "$APP/Contents/Info.plist"
# every Resources/<lang>.lproj folder is a UI language macOS may pick
LOCS="$(cd Sources/IPTVMac/Resources && for d in *.lproj; do printf '<string>%s</string>' "${d%.lproj}"; done)"
sed -i '' "s|__LOCALIZATIONS__|$LOCS|" "$APP/Contents/Info.plist"
# Signing. Default: ad-hoc (works for the curl installer and the in-app updater, but macOS shows a warning for a downloaded DMG).
# IPTVMAC_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" signs for notarization: hardened runtime + secure timestamp,
# every bundled dylib first, then the app (no --deep). IPTVMAC_HARDENED=1 applies the hardened runtime to an ad-hoc build, to test locally.
IDENTITY="${IPTVMAC_SIGN_IDENTITY:--}"
if [ -n "${IPTVMAC_SKIP_SIGN:-}" ]; then
  echo "Built $APP (unsigned: IPTVMAC_SKIP_SIGN is set)"; exit 0
fi
if [ "$IDENTITY" != "-" ] || [ -n "${IPTVMAC_HARDENED:-}" ]; then
  FLAGS=(--force --options runtime --sign "$IDENTITY"); [ "$IDENTITY" != "-" ] && FLAGS+=(--timestamp)
  find "$APP/Contents/Frameworks" -name '*.dylib' -exec codesign "${FLAGS[@]}" {} \;
  ENT=scripts/entitlements.plist
  if [ "$IDENTITY" = "-" ]; then
    # An ad-hoc signature has no Team ID, so library validation can never pass: for this local test only, switch it off.
    # It proves nothing else breaks under the hardened runtime; the real Team ID signing needs no exception.
    ENT="$(mktemp)"; trap 'rm -f "$ENT"' EXIT
    printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>com.apple.security.cs.disable-library-validation</key><true/></dict></plist>' > "$ENT"
  fi
  codesign "${FLAGS[@]}" --entitlements "$ENT" "$APP"
  codesign --verify --strict --deep "$APP"
  "$APP/Contents/MacOS/IPTVMac" --selftest   # the bundled libmpv must still load under the hardened runtime
else
  find "$APP/Contents/Frameworks" -name '*.dylib' -exec codesign --force --sign - {} \;
  codesign --force --deep --sign - "$APP"
fi
echo "Built $APP"
