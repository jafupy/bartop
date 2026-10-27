#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
app="$PWD/dist/bartop.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/bartop "$app/Contents/MacOS/bartop"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>bartop</string>
    <key>CFBundleIdentifier</key><string>com.jafupy.bartop</string>
    <key>CFBundleName</key><string>bartop</string>
    <key>CFBundleDisplayName</key><string>bartop</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "Built: $app"
