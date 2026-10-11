#!/bin/bash
# Downloads the iOS libmpv (media-kit/libmpv-darwin-build, the project make-app.sh uses for macOS) into build/vendor/ios-mpv:
# 18 xcframeworks (device + simulator slices), mpv 0.36.0 + FFmpeg 6.0, LGPL flavour ("video-full"). About 67 MB unpacked, git-ignored.
# The hash is pinned like make-app.sh pins the macOS one. Also checks that Sources/CLibMPViOS/include/mpv/*.h (committed, used to
# compile IPTVPlayer for iOS) are still the headers of this build. Safe to run again: it does nothing once the pinned build is there.
set -euo pipefail
cd "$(dirname "$0")/.."

MK_VERSION=v0.7.3
MK_NAME="libmpv-xcframeworks_${MK_VERSION}_ios-universal-video-full"
MK_SHA256=8d9068dd553b39f07ed9efe67f9acd212e7f7cebaba1caa39320e99ef85757a9
DEST=build/vendor/ios-mpv

if [ "$(cat "$DEST/.sha256" 2>/dev/null)" != "$MK_SHA256" ]; then
  rm -rf "$DEST"; mkdir -p "$DEST"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  curl -fsSL -o "$TMP/mk.tgz" "https://github.com/media-kit/libmpv-darwin-build/releases/download/$MK_VERSION/$MK_NAME.tar.gz"
  echo "$MK_SHA256  $TMP/mk.tgz" | shasum -a 256 -c -
  tar xzf "$TMP/mk.tgz" -C "$DEST" --strip-components=1
  echo "$MK_SHA256" > "$DEST/.sha256"
fi

for h in client render render_gl stream_cb; do
  cmp -s "$DEST/Mpv.xcframework/ios-arm64/Mpv.framework/Headers/$h.h" "Sources/CLibMPViOS/include/mpv/$h.h" \
    || { echo "Sources/CLibMPViOS/include/mpv/$h.h differs from the headers of $MK_NAME: copy them over" >&2; exit 1; }
done
echo "iOS libmpv $MK_VERSION ready in $DEST ($(ls -d "$DEST"/*.xcframework | wc -l | tr -d ' ') xcframeworks)"
