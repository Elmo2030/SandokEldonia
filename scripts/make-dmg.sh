#!/bin/bash
# Builds build/IPTVMac.dmg: a Finder window with the app, an Applications shortcut, an arrow and instructions.
# dmgbuild writes the window layout directly (no Finder/AppleScript automation needed). Ad-hoc signed and not notarized, unless
# IPTVMAC_SIGN_IDENTITY is set: then the app and the DMG are signed, notarized and stapled (see scripts/NOTARIZE.md).
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/make-app.sh
SIGNED="${IPTVMAC_SIGN_IDENTITY:-}"
[ -n "$SIGNED" ] && scripts/notarize.sh build/IPTVMac.app   # staple the app first: it works offline once copied out of the DMG
[ -x build/venv/bin/dmgbuild ] || { python3 -m venv build/venv && build/venv/bin/pip install -q --require-hashes -r scripts/dmg/requirements.txt; }
swift scripts/dmg/background.swift build/dmg-background.png
rm -f build/IPTVMac.dmg
DMG_ARGS=(-s scripts/dmg/settings.py -D app=build/IPTVMac.app -D background=build/dmg-background.png -D icon=build/IPTVMac.app/Contents/Resources/AppIcon.icns "IPTVMac" build/IPTVMac.dmg)
build/venv/bin/dmgbuild "${DMG_ARGS[@]}" || {
  echo "dmgbuild failed (a plain 'hdiutil detach' can be refused while the simulator service shuts down): retrying with a forced detach"
  build/venv/bin/python scripts/dmg/force-detach.py "${DMG_ARGS[@]}"
}
if [ -n "$SIGNED" ]; then
  codesign --force --sign "$SIGNED" --timestamp build/IPTVMac.dmg
  scripts/notarize.sh build/IPTVMac.dmg
fi
ls -lh build/IPTVMac.dmg
