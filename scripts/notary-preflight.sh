#!/bin/bash
# Checks everything needed to sign and notarize IPTVMac and says what is still missing. Changes nothing.
PROFILE="${IPTVMAC_NOTARY_PROFILE:-IPTVMac-notary}"; ok=0
chk() { if [ "$1" = ok ]; then echo "ok    $2"; else echo "MISSING $2"; echo "        -> $3"; ok=1; fi; }
T="$(xcrun --find notarytool 2>&1)"; S="$(xcrun --find stapler 2>&1)"
if echo "$T$S" | grep -qi "license"; then chk no "Xcode license not accepted" "sudo xcodebuild -license accept   (then run this check again)"
elif [ -x "$T" ] && [ -x "$S" ]; then chk ok "notarytool and stapler"
else chk no "notarytool / stapler" "install Xcode or run: xcode-select --install"; fi
ID="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
if [ -n "$ID" ]; then chk ok "signing identity: $ID"; else chk no "a 'Developer ID Application' certificate in your Keychain" "see scripts/NOTARIZE.md, step 2"; fi
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then chk ok "notarytool keychain profile '$PROFILE'"; else chk no "notarytool keychain profile '$PROFILE'" "see scripts/NOTARIZE.md, step 3"; fi
[ -f scripts/entitlements.plist ] && chk ok "scripts/entitlements.plist" || chk no "scripts/entitlements.plist" "restore it from git"
[ "$ok" = 0 ] && echo "Ready. Release with: IPTVMAC_SIGN_IDENTITY=\"$ID\" scripts/release.sh notes.md" || echo "Not ready yet."
exit $ok
