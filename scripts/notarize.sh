#!/bin/bash
# Sends a signed build/IPTVMac.app or build/IPTVMac.dmg to Apple's notary service, waits for the verdict, staples the ticket and checks
# that Gatekeeper accepts it. Needs a notarytool keychain profile (see scripts/NOTARIZE.md); DRY_RUN=1 only prints the commands.
# Usage: scripts/notarize.sh build/IPTVMac.app   (or .dmg)
set -euo pipefail
TARGET="${1:?usage: scripts/notarize.sh build/IPTVMac.app|build/IPTVMac.dmg}"
PROFILE="${IPTVMAC_NOTARY_PROFILE:-IPTVMac-notary}"
run() { if [ -n "${DRY_RUN:-}" ]; then echo "+ $*"; else "$@"; fi; }
case "$TARGET" in
  *.app) UPLOAD="$(mktemp -d)/IPTVMac.zip"; run ditto -c -k --keepParent "$TARGET" "$UPLOAD" ;;
  *.dmg) UPLOAD="$TARGET" ;;
  *) echo "Expected a .app or a .dmg"; exit 1 ;;
esac
OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT
echo "Submitting $UPLOAD to Apple (this usually takes a few minutes)..."
run xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait --output-format json > "$OUT" || true
if [ -z "${DRY_RUN:-}" ]; then
  STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$OUT" 2>/dev/null || true)"
  ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$OUT" 2>/dev/null || true)"
  if [ "$STATUS" != "Accepted" ]; then
    echo "Notarization status: ${STATUS:-unknown}. Apple's log:"; cat "$OUT" | head -c 600; echo
    [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" || true
    exit 1
  fi
fi
run xcrun stapler staple "$TARGET"
run xcrun stapler validate "$TARGET"
case "$TARGET" in
  *.app) run spctl --assess --type execute -vv "$TARGET" ;;
  *.dmg) run spctl --assess --type open --context context:primary-signature -vv "$TARGET" ;;
esac
echo "Notarized and stapled: $TARGET"
