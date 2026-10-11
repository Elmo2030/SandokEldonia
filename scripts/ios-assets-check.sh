#!/bin/bash
# Verifies everything in ios/Resources without touching it (temp dirs only, safe to run any number of times):
#   plutil -lint on every plist/.strings, actool compile of Assets.xcassets (device and iPad, deployment target 17.0, no warnings),
#   the compiled catalog really holds AppIcon / AccentColor / LogoMark / the colour sets, the icon is 1024x1024 without alpha,
#   then scripts/ios-assets-check.py (31 InfoPlist.strings parity, Info-extra.plist, privacy manifest, acknowledgements).
# Needs Xcode (actool, assetutil) and python3. Exit status 1 on any problem.
set -uo pipefail
cd "$(dirname "$0")/.."
R=ios/Resources
fails=0
bad() { echo "  FAIL $*"; fails=$((fails + 1)); }

echo "plutil -lint"
for f in $R/PrivacyInfo.xcprivacy $R/Info-extra.plist $R/*.lproj/InfoPlist.strings; do
  plutil -lint "$f" >/dev/null || bad "$f"
done
echo "  checked $(ls $R/PrivacyInfo.xcprivacy $R/Info-extra.plist $R/*.lproj/InfoPlist.strings | wc -l | tr -d ' ') files"

echo "actool"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
if ! xcrun --find actool >/dev/null 2>&1; then bad "actool not found (install Xcode)"; else
  LOG="$(xcrun actool --compile "$OUT" --platform iphoneos --minimum-deployment-target 17.0 --target-device iphone --target-device ipad \
        --app-icon AppIcon --accent-color AccentColor --output-partial-info-plist "$OUT/partial.plist" \
        --warnings --errors --notices --output-format human-readable-text $R/Assets.xcassets 2>&1)"
  rc=$?
  [ $rc -eq 0 ] || bad "actool exit status $rc"
  echo "$LOG" | grep -qiE "warning|error|notice" && { bad "actool reported:"; echo "$LOG" | grep -iE "warning|error|notice"; }
  NAMES="$(xcrun assetutil --info "$OUT/Assets.car" 2>/dev/null | python3 -I -c "import json,sys; print(' '.join(sorted({x['Name'] for x in json.load(sys.stdin) if x.get('Name')})))")"
  for n in AccentColor AccentText AppIcon LaunchBackground LogoMark PosterPlaceholder; do
    case " $NAMES " in *" $n "*) ;; *) bad "Assets.car lacks $n";; esac
  done
  grep -q "<string>AppIcon</string>" "$OUT/partial.plist" && grep -q "NSAccentColorName" "$OUT/partial.plist" || bad "partial Info.plist lacks CFBundleIconName / NSAccentColorName"
  echo "  compiled: $NAMES"
fi

echo "app icon"
ICON=$R/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
[ "$(sips -g pixelWidth -g pixelHeight "$ICON" | awk '/pixel/ {print $2}' | tr '\n' x)" = "1024x1024x" ] || bad "icon is not 1024x1024"
[ "$(sips -g hasAlpha "$ICON" | awk '/hasAlpha/ {print $2}')" = "no" ] || bad "icon has an alpha channel (App Store rejects it)"
echo "  1024x1024, no alpha"

echo
python3 scripts/ios-assets-check.py || fails=$((fails + 1))
echo
[ $fails -eq 0 ] && echo "ios-assets-check: ALL OK" || { echo "ios-assets-check: $fails step(s) failed"; exit 1; }
