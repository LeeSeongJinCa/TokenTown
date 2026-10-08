#!/bin/bash
# Build an isolated TokenTown app bundle; never replace the upstream app.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/TokenTown.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TokenTown" "$APP/Contents/MacOS/TokenTown"
if [[ -f assets/TokenTown.icns ]]; then cp assets/TokenTown.icns "$APP/Contents/Resources/TokenTown.icns"; fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.leeseongjinca.tokentown</string>
<key>CFBundleName</key><string>TokenTown</string>
<key>CFBundleDisplayName</key><string>TokenTown</string>
<key>CFBundleExecutable</key><string>TokenTown</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleIconFile</key><string>TokenTown</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built: $PWD/$APP"
echo "Launch: open '$PWD/$APP'"
