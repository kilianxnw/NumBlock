#!/bin/bash
# Usage: ./build.sh [install|test]
set -euo pipefail
cd "$(dirname "$0")"

APP="build/TrackNum.app"
BIN="$APP/Contents/MacOS/TrackNum"

mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 \
    -target arm64-apple-macos14.0 \
    -import-objc-header Sources/MTBridge.h \
    Sources/*.swift \
    -o "$BIN"

# A stable signing identity keeps the Accessibility permission across rebuilds.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP" 2>/dev/null
echo "Gebaut: $APP (signiert: ${IDENTITY:-ad-hoc})"

case "${1:-}" in
    test)
        "$BIN" --selftest
        ;;
    install)
        DEST="/Applications"
        [ -w "$DEST" ] || DEST="$HOME/Applications"
        mkdir -p "$DEST"
        pkill -x TrackNum 2>/dev/null && sleep 0.5 || true
        rm -rf "$DEST/TrackNum.app"
        cp -R "$APP" "$DEST/"
        open "$DEST/TrackNum.app"
        echo "Installiert und gestartet: $DEST/TrackNum.app"
        ;;
esac
