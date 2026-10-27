#!/bin/bash
#
# Installs the WiFiConnector menu-bar app with one command:
#
#   curl -fsSL https://anujbajaj4.github.io/wificonnector/install.sh | bash
#
# It downloads the latest WiFiConnector.dmg from GitHub Releases, copies the
# app into Applications and opens it. Files that curl downloads aren't marked
# as coming from the internet, so macOS doesn't show its "could not verify"
# warning, and there's no Open Anyway step.
#
# Read it before you run it: https://github.com/anujbajaj4/wificonnector
#
# For testing:
#   WIFICONNECTOR_DMG_URL    download from here instead (file:// works too)
#   WIFICONNECTOR_APPS_DIR   install here instead of /Applications
#   WIFICONNECTOR_NO_OPEN=1  don't open the app afterwards

# Everything is inside main, called on the last line, so a download cut off
# halfway runs nothing at all.
main() {
    set -euo pipefail

    local url="${WIFICONNECTOR_DMG_URL:-https://github.com/anujbajaj4/wificonnector/releases/latest/download/WiFiConnector.dmg}"
    local apps="${WIFICONNECTOR_APPS_DIR:-/Applications}"
    local name="WiFiConnector.app"

    if [ "$(uname -s)" != Darwin ]; then
        fail "WiFiConnector is a Mac app; this computer isn't a Mac."
    fi
    local version major
    version=$(sw_vers -productVersion)
    major=${version%%.*}
    if [ "$major" -lt 13 ]; then
        fail "The app needs macOS 13 (Ventura) or later, and this Mac has macOS $version.
  The script on its own works on macOS 12 and later:
  https://github.com/anujbajaj4/wificonnector#install-only-the-script"
    fi

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/wificonnector.XXXXXX")
    mnt="$tmp/mnt"
    trap cleanup EXIT

    say "Downloading WiFiConnector…"
    curl -fL --progress-bar --retry 2 -o "$tmp/WiFiConnector.dmg" "$url" ||
        fail "The download didn't work. Check that you're online, then run the command again."

    say "Opening the disk image…"
    mkdir "$mnt"
    hdiutil attach -nobrowse -readonly -noautoopen -quiet -mountpoint "$mnt" \
        "$tmp/WiFiConnector.dmg" </dev/null ||
        fail "macOS couldn't open the downloaded disk image. Run the command again."
    [ -d "$mnt/$name" ] || fail "The disk image doesn't contain $name."

    if ! mkdir -p "$apps" 2>/dev/null || [ ! -w "$apps" ]; then
        apps="$HOME/Applications"
        mkdir -p "$apps"
        say "You can't write to /Applications, so it goes in $apps instead."
    fi

    quit_running_app

    say "Copying WiFiConnector to ${apps}…"
    rm -rf "${apps:?}/$name"
    ditto "$mnt/$name" "$apps/$name"
    # Nothing should have set it, but if it is set macOS shows the warning.
    xattr -dr com.apple.quarantine "$apps/$name" 2>/dev/null || true

    # Once it's detached, cleanup has nothing left to detach.
    hdiutil detach -quiet "$mnt" </dev/null && rmdir "$mnt" || true

    local installed
    installed=$(defaults read "$apps/$name/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
    say "Installed WiFiConnector $installed."

    if [ "${WIFICONNECTOR_NO_OPEN:-0}" = 1 ]; then
        return
    fi
    open "$apps/$name"
    cat <<'EOF'

WiFiConnector is opening. In its welcome window, type your registration
number and Wi-Fi password and click Save and Turn On. From then on it logs
you in by itself, and its Wi-Fi icon sits in the menu bar at the top right.

No welcome window? Click that Wi-Fi icon in the menu bar and choose Set Up…
EOF
}

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

fail() {
    printf '\033[31mError:\033[0m %s\n' "$*" >&2
    exit 1
}

# An app that is running while it's replaced keeps running the old copy.
quit_running_app() {
    pgrep -xq WiFiConnector || return 0
    say "Quitting the WiFiConnector that's running…"
    osascript -e 'tell application id "com.wificonnector.app" to quit' </dev/null >/dev/null 2>&1 || true
    local tries=0
    while pgrep -xq WiFiConnector && [ "$tries" -lt 10 ]; do
        tries=$((tries + 1))
        sleep 0.5
    done
    pgrep -xq WiFiConnector || return 0
    pkill -x WiFiConnector || true
}

cleanup() {
    if [ -d "$mnt" ]; then
        hdiutil detach -quiet -force "$mnt" </dev/null 2>/dev/null || true
    fi
    rm -rf "$tmp"
}

main "$@"
