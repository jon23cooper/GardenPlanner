#!/bin/bash
set -e

XCODE="/Volumes/ORICO/Applications/Xcode.app/Contents/Developer"
SWIFT="$XCODE/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SRC="$(dirname "$0")"
APP="$SRC/GardenPlanner.app"

echo "Building..."
DEVELOPER_DIR="$XCODE" "$SWIFT" build -c release --package-path "$SRC"

echo "Assembling bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$SRC/.build/release/GardenPlanner" "$APP/Contents/MacOS/GardenPlanner"
cp "$SRC/Sources/GardenPlanner/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
cp "$SRC/GardenPlanner.app.plist" "$APP/Contents/Info.plist" 2>/dev/null || \
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.jon.gardenplanner</string>
    <key>CFBundleName</key><string>Garden Planner</string>
    <key>CFBundleDisplayName</key><string>Garden Planner</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>GardenPlanner</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
PLIST

echo "Signing..."
codesign --force --deep --sign - "$APP"

echo "Installing to /Applications..."
rm -rf "/Applications/GardenPlanner.app"
cp -R "$APP" "/Applications/GardenPlanner.app"
touch "/Applications/GardenPlanner.app"

echo "Done. Launch from /Applications or Spotlight."
