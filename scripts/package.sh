#!/usr/bin/env bash
# Build a universal (arm64 + x86_64) release and assemble Tunnels.app.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_DISPLAY="Tunnels"
EXEC="TunnelsApp"
BUNDLE_ID="org.kamysh.tunnels"
# Version: single source of truth is AppVersion in TunnelKit. Build number is the
# git commit count (monotonic), falling back to 1 outside a git checkout.
VERSION="$(grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' Sources/TunnelKit/Version.swift | head -1 | tr -d '"')"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
ARCHS=(--arch arm64 --arch x86_64)

echo ">> building universal release…"
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"
echo "   products: $BIN"

echo ">> arch check:"
for b in "$EXEC" tunnels-askpass tunnelctl; do
    printf '   %-16s %s\n' "$b" "$(lipo -archs "$BIN/$b")"
done

DIST="dist"
APP="$DIST/$APP_DISPLAY.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# The app finds tunnels-askpass as a sibling of its own executable → both go in MacOS/.
cp "$BIN/$EXEC" "$APP/Contents/MacOS/$EXEC"
cp "$BIN/tunnels-askpass" "$APP/Contents/MacOS/tunnels-askpass"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_DISPLAY</string>
    <key>CFBundleDisplayName</key><string>SSH Tunnels</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXEC</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc sign so it runs locally (Developer ID + notarization is a separate step
# for distribution to other machines).
codesign --force --deep --sign - "$APP"
echo ">> codesign:"; codesign -dv "$APP" 2>&1 | sed 's/^/   /'

# Universal CLI alongside the app.
cp "$BIN/tunnelctl" "$DIST/tunnelctl"

# Zip the app for hand-off.
( cd "$DIST" && rm -f "$APP_DISPLAY.app.zip" && ditto -c -k --keepParent "$APP_DISPLAY.app" "$APP_DISPLAY.app.zip" )

# Wrap as a drag-install DMG.
"$(dirname "$0")/dmg.sh"

echo ">> done:"
echo "   $APP  ($(lipo -archs "$APP/Contents/MacOS/$EXEC"))"
echo "   $DIST/$APP_DISPLAY.app.zip"
echo "   $DIST/$APP_DISPLAY.dmg"
echo "   $DIST/tunnelctl"
