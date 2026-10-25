#!/bin/bash
#
# Builds WiFiConnector.app without the Xcode project: compiles the Swift
# sources with swiftc and assembles the app bundle by hand. A fallback if the
# project won't open, and a look at what Xcode does for you. Needs Xcode or
# the Command Line Tools (xcode-select --install).
#
#   app/build-app.sh      # then: open app/build/WiFiConnector.app

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
version=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$here/../bin/wificonnector")
app="$here/build/WiFiConnector.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

# An app bundle is a folder: the executable in Contents/MacOS, everything else
# in Contents/Resources, and Contents/Info.plist describing it to macOS.
xcrun swiftc -O -parse-as-library \
    -target "$(uname -m)-apple-macos15.0" \
    -o "$app/Contents/MacOS/WiFiConnector" \
    "$here"/WiFiConnector/*.swift

cp "$here/../bin/wificonnector" "$app/Contents/Resources/wificonnector"
chmod 755 "$app/Contents/Resources/wificonnector"

# LSUIElement: a menu-bar app, with no Dock icon and no main menu.
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WiFiConnector</string>
    <key>CFBundleIdentifier</key>
    <string>com.wificonnector.app</string>
    <key>CFBundleName</key>
    <string>WiFiConnector</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
EOF

# Ad-hoc signature ("-"): enough to run on this Mac, not to hand out.
codesign --force --sign - "$app"

echo "Built $app"
echo "Run it with: open \"$app\""
