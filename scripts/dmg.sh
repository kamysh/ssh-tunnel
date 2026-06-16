#!/usr/bin/env bash
# Wrap dist/Tunnels.app into a compressed drag-install DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_DISPLAY="Tunnels"
APP="dist/$APP_DISPLAY.app"
DMG="dist/$APP_DISPLAY.dmg"

[ -d "$APP" ] || { echo "missing $APP — run scripts/package.sh first" >&2; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target

rm -f "$DMG"
hdiutil create -volname "$APP_DISPLAY" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

echo "built $DMG ($(du -h "$DMG" | cut -f1)), universal: $(lipo -archs "$APP/Contents/MacOS/TunnelsApp")"
