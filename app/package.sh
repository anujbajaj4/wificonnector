#!/bin/bash
#
# Builds the downloadable WiFiConnector.dmg: a universal (Apple silicon and
# Intel) Release build of the app, ad-hoc signed, in a disk image that shows
# the app next to an Applications shortcut. Needs Xcode. The release workflow
# runs this; you can too.
#
#   app/package.sh        # writes app/build/WiFiConnector.dmg

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
build="$here/build"
version=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$here/../bin/wificonnector")
app="$build/xcode/Release/WiFiConnector.app"
dmg="$build/WiFiConnector.dmg"

rm -rf "$build/xcode" "$build/dmg" "$dmg"

# ONLY_ACTIVE_ARCH=NO builds both architectures. The marketing version comes
# from the script, so the app and the agent it installs always agree.
xcodebuild \
    -project "$here/WiFiConnector.xcodeproj" \
    -target WiFiConnector \
    -configuration Release \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$version" \
    SYMROOT="$build/xcode" \
    build

# No Apple Developer ID, so the app is signed ad hoc ("-"). That's enough for
# macOS to run it, after the one-time Open Anyway in System Settings.
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Architectures: $(lipo -archs "$app/Contents/MacOS/WiFiConnector")"

mkdir -p "$build/dmg"
cp -R "$app" "$build/dmg/"
ln -s /Applications "$build/dmg/Applications"
hdiutil create -volname "WiFiConnector $version" -srcfolder "$build/dmg" \
    -fs HFS+ -format UDZO -ov "$dmg"
rm -rf "$build/dmg"

echo "Built $dmg (version $version)"
