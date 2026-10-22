#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
app_path="$PWD/.build/Grafix.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp THIRD_PARTY_NOTICES.md "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp .build/release/Grafix "$app_path/Contents/MacOS/Grafix"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.grafix.app</string>
<key>CFBundleName</key><string>Grafix</string>
<key>CFBundleExecutable</key><string>Grafix</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_path"
print -r -- "$app_path"
