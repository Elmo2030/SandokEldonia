#!/bin/bash
# Uploads the signed .pkg from scripts/make-appstore.sh to App Store Connect (it then appears under TestFlight and "Mac App > Build").
# Usage: scripts/upload-appstore.sh [build-appstore/IPTVMac-<version>-<build>.pkg]   (default: the package of VERSION and APPSTORE_BUILD_NUMBER)
# Authentication: an App Store Connect API key (App Store Connect > Users and Access > Integrations > App Store Connect API), never a password:
#   IPTVMAC_ASC_KEY_ID=ABC123DEFG        the key's ID
#   IPTVMAC_ASC_ISSUER_ID=<uuid>         the Issuer ID shown above the key list
#   IPTVMAC_ASC_KEY_FILE=/path/AuthKey_ABC123DEFG.p8    the downloaded private key (keep it outside the repository, chmod 600)
# Options: DRY_RUN=1 only prints the exact command. VALIDATE_ONLY=1 runs `altool --validate-app` instead of uploading (checks the package
# against App Store Connect without creating a build). WAIT=1 waits until App Store Connect has processed the build (can take a while).
# After a real upload the build number in scripts/APPSTORE_BUILD_NUMBER is raised by one (commit it): App Store Connect refuses a build
# number it has already received for that version. The key file is only passed by path; nothing secret is ever printed.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "upload-appstore: $*" >&2; exit 1; }

VERSION="$(cat VERSION)"
BUILD_FILE=scripts/APPSTORE_BUILD_NUMBER
BUILD_NUMBER="$(tr -d ' \t\r\n' < "$BUILD_FILE")"
PKG="${1:-build-appstore/IPTVMac-$VERSION-$BUILD_NUMBER.pkg}"
# DRY_RUN only shows the command: missing pieces are shown as <PLACEHOLDERS> and reported, not fatal.
problem() { if [ -n "${DRY_RUN:-}" ]; then echo "note (DRY_RUN): $*" >&2; else fail "$*"; fi; }
[ -f "$PKG" ] || problem "package not found: $PKG (build it with scripts/make-appstore.sh)"
case "$PKG" in *.pkg) ;; *) problem "the Mac App Store takes a .pkg, not '$PKG'" ;; esac

KEY_ID="${IPTVMAC_ASC_KEY_ID:-}"; ISSUER="${IPTVMAC_ASC_ISSUER_ID:-}"; KEY_FILE="${IPTVMAC_ASC_KEY_FILE:-}"
[ -n "$KEY_ID" ] || { problem "set IPTVMAC_ASC_KEY_ID (App Store Connect API key id)"; KEY_ID="<IPTVMAC_ASC_KEY_ID>"; }
[ -n "$ISSUER" ] || { problem "set IPTVMAC_ASC_ISSUER_ID (the Issuer ID of the API keys page)"; ISSUER="<IPTVMAC_ASC_ISSUER_ID>"; }
[ -n "$KEY_FILE" ] || { problem "set IPTVMAC_ASC_KEY_FILE (path of AuthKey_<id>.p8)"; KEY_FILE="<IPTVMAC_ASC_KEY_FILE>"; }
if [ -f "$KEY_FILE" ]; then
  [ -r "$KEY_FILE" ] || problem "API key file is not readable: $KEY_FILE"
  [ -z "$(find "$KEY_FILE" -perm -004 2>/dev/null)" ] || echo "warning: $KEY_FILE is readable by everyone: chmod 600 it" >&2
elif [[ "$KEY_FILE" != "<"* ]]; then
  problem "API key file not found: $KEY_FILE"
fi

# The altool syntax changed between Xcode versions: check this Mac's before using it.
HELP="$(xcrun altool --help 2>&1)" || fail "xcrun altool is not available (install Xcode)"
ACTION=--upload-package; [ -z "${VALIDATE_ONLY:-}" ] || ACTION=--validate-app
grep -q -- "$ACTION" <<< "$HELP" || fail "this altool has no $ACTION: upload with the Transporter app instead (scripts/APPSTORE.md)"
grep -q -- "--p8-file-path" <<< "$HELP" || fail "this altool has no --p8-file-path: put the key at ~/.appstoreconnect/private_keys/AuthKey_<id>.p8 and use --api-key only (scripts/APPSTORE.md)"

CMD=(xcrun altool "$ACTION" "$PKG" --api-key "$KEY_ID" --api-issuer "$ISSUER" --p8-file-path "$KEY_FILE")
[ -z "${WAIT:-}" ] || [ "$ACTION" = --validate-app ] || CMD+=(--wait)
if [ -n "${DRY_RUN:-}" ]; then
  printf '+'; printf ' %q' "${CMD[@]}"; echo
  exit 0
fi
"${CMD[@]}"

if [ "$ACTION" = --upload-package ]; then
  # Raise the build number only if this package is the current one (an older package re-uploaded must not move the counter).
  if [ "$(basename "$PKG")" = "IPTVMac-$VERSION-$BUILD_NUMBER.pkg" ]; then
    echo $((BUILD_NUMBER + 1)) > "$BUILD_FILE"
    echo "Uploaded build $BUILD_NUMBER. $BUILD_FILE is now $((BUILD_NUMBER + 1)): commit it."
  else
    echo "Uploaded $PKG. $BUILD_FILE was left as it is (the package is not version $VERSION build $BUILD_NUMBER)."
  fi
fi
