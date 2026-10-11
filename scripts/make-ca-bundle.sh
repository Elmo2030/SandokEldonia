#!/bin/bash
# iOS has no /etc/ssl/cert.pem and the bundled mbedTLS has no system trust store, so the iOS app ships its own CA bundle
# (mpv option tls-ca-file, see EngineOptions in Sources/IPTVPlayer/PlayerOptions.swift). It is made from this Mac's /etc/ssl/cert.pem
# (the file the macOS app already trusts), stamped with the date and the hash of its source, and NOT committed: it is a trust list,
# so it is regenerated for every iOS build instead of going stale in git. Output: ios/Generated/cacert.pem (git-ignored, ~180 KB).
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=/etc/ssl/cert.pem
OUT=ios/Generated/cacert.pem
mkdir -p ios/Generated
{
  echo "# CA bundle for IPTVMac (iOS). Generated $(date -u +%Y-%m-%d) by scripts/make-ca-bundle.sh from $SRC (sha256 $(shasum -a 256 "$SRC" | cut -d' ' -f1))."
  # Only the PEM blocks: the source also has a text dump of every certificate.
  awk '/^-----BEGIN CERTIFICATE-----$/ {on=1} on {print} /^-----END CERTIFICATE-----$/ {on=0}' "$SRC"
} > "$OUT"
N="$(grep -c '^-----BEGIN CERTIFICATE-----$' "$OUT")"
[ "$N" -ge 100 ] || { echo "only $N certificates in $OUT: $SRC is not what this script expects" >&2; exit 1; }
echo "$OUT: $N certificates"
