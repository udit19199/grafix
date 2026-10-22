#!/bin/zsh
# Builds .build/Grafix.app (release) with the MCP server and dev tool inside.
set -euo pipefail
cd "${0:A:h:h}"
config="${1:-release}"
swift build -c "$config" --product Grafix
swift build -c "$config" --product grafix-mcp
bin="$(swift build -c "$config" --show-bin-path)"
app_path="$PWD/.build/Grafix.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp THIRD_PARTY_NOTICES.md "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp Sources/GrafixApp/Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
cp "$bin/Grafix" "$app_path/Contents/MacOS/Grafix"
cp "$bin/grafix-mcp" "$app_path/Contents/MacOS/grafix-mcp"
# SwiftPM resource bundles (fonts) must sit in Contents/Resources.
for bundle in "$bin"/*.bundle; do
  [[ -e "$bundle" ]] && cp -R "$bundle" "$app_path/Contents/Resources/"
done
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.grafix.app</string>
<key>CFBundleName</key><string>Grafix</string>
<key>CFBundleDisplayName</key><string>Grafix</string>
<key>CFBundleExecutable</key><string>Grafix</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app_path" >/dev/null 2>&1 || true
print -r -- "$app_path"
