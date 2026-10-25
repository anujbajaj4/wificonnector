#!/bin/bash
#
# Runs bin/wificonnector against fake macOS tools (tests/stubs) so its
# decisions can be checked on any machine, Linux included.
#
#   tests/run-tests.sh
#   TEST_BASH=/path/to/bash-3.2 tests/run-tests.sh   # under another bash

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/bin/wificonnector"
STUBS="$ROOT/tests/stubs"
BASE_TMP=${TMPDIR:-/tmp}
# The bash that runs the script under test; macOS uses 3.2.
TEST_BASH=${TEST_BASH:-bash}

PASSED=0
FAILED=0

PRONTO_REDIRECT="http://phc.prontonetworks.com/cgi-bin/authlogin?URI=http://clients3.google.com/generate_204"

# Each test gets a fresh HOME and stub-recording directory.
fresh() {
    local v
    for v in ${!STUB_@}; do unset "$v"; done
    SANDBOX=$(mktemp -d "$BASE_TMP/wificonnector-test.XXXXXX")
    export HOME="$SANDBOX/home" TMPDIR="$SANDBOX/tmp" STUB_DIR="$SANDBOX/stub"
    mkdir -p "$HOME" "$TMPDIR" "$STUB_DIR"
    export WIFICONNECTOR_REVALIDATE_DELAY=0 WIFICONNECTOR_IP_WAIT_DELAY=0
    STATE="$HOME/Library/Caches/wificonnector"
}

# A saved registration number and Keychain password.
with_credentials() {
    mkdir -p "$HOME/.config/wificonnector"
    printf 'USERNAME=22BCE1234\n' > "$HOME/.config/wificonnector/config"
    export STUB_PASSWORD='p@ss&w=rd 1'
}

behind_pronto() {
    export STUB_PROBE_CODE=302 STUB_PROBE_LOCATION="$PRONTO_REDIRECT"
}

wc_run() {
    PATH="$STUBS:$PATH" "$TEST_BASH" "$SCRIPT" "$@" > "$SANDBOX/out" 2>&1
}

count() {
    if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi
}

# check takes a command, so negation needs a command too.
not() {
    ! "$@"
}

state() {
    cat "$STATE/state" 2>/dev/null
}

check() {
    local description=$1
    shift
    if "$@"; then
        return 0
    fi
    CHECK_FAILED="$CHECK_FAILED\n    - $description"
    return 1
}

test_case() {
    local name=$1
    CHECK_FAILED=""
    fresh
    "$name"
    if [ -z "$CHECK_FAILED" ]; then
        PASSED=$((PASSED + 1))
        printf '  ok    %s\n' "$name"
    else
        FAILED=$((FAILED + 1))
        printf '  FAIL  %s%b\n' "$name" "$CHECK_FAILED"
        printf '        output:\n'
        sed 's/^/          /' "$SANDBOX/out"
    fi
    rm -rf "$SANDBOX"
}

# --- Scenarios ---------------------------------------------------------------

online_sends_nothing() {
    with_credentials
    wc_run run
    check "no login POST" [ "$(count "$STUB_DIR/login_urls")" = 0 ]
    check "state is online" [ "$(state)" = online ]
    check "keychain not read" [ "$(count "$STUB_DIR/security_calls")" = 0 ]
}

pronto_redirect_logs_in() {
    with_credentials
    behind_pronto
    wc_run run
    check "one login POST" [ "$(count "$STUB_DIR/login_urls")" = 1 ]
    check "posted to the Pronto login URL" \
        grep -qxF "http://phc.prontonetworks.com/cgi-bin/authlogin?URI=http://example.com" "$STUB_DIR/login_urls"
    check "state is online" [ "$(state)" = online ]
    check "notified" grep -q "Logged in" "$STUB_DIR/notifications"
}

password_only_on_stdin() {
    with_credentials
    behind_pronto
    wc_run run
    check "password arrived on stdin" [ "$(cat "$STUB_DIR/stdin_password")" = 'p@ss&w=rd 1' ]
    check "no trailing newline" [ "$(wc -c < "$STUB_DIR/stdin_password" | tr -d ' ')" = 11 ]
    check "password never in curl's arguments" not grep -qF 'p@ss&w=rd' "$STUB_DIR/curl_calls"
    check "password never logged" not grep -qF 'p@ss&w=rd' "$SANDBOX/out"
    check "form fields as Latch sends them" \
        grep -qF -- "--data-urlencode userId=22BCE1234 --data-urlencode password@- --data-urlencode serviceName=ProntoAuthentication" "$STUB_DIR/curl_calls"
    # --interface en0 made every request fail on a real MacBook (curl exit 7).
    check "requests use the system's normal route" not grep -qF -- "--interface" "$STUB_DIR/curl_calls"
}

pronto_in_page_body_logs_in() {
    with_credentials
    export STUB_PROBE_CODE=200
    export STUB_PROBE_BODY='<meta http-equiv="refresh" content="0;url=http://phc.prontonetworks.com/cgi-bin/authlogin">'
    wc_run run
    check "one login POST" [ "$(count "$STUB_DIR/login_urls")" = 1 ]
}

foreign_portal_gets_no_credentials() {
    with_credentials
    export STUB_PROBE_CODE=302 STUB_PROBE_LOCATION="http://wifi.cafe.example/login"
    wc_run run
    check "no login POST" [ "$(count "$STUB_DIR/login_urls")" = 0 ]
    check "keychain not read" [ "$(count "$STUB_DIR/security_calls")" = 0 ]
    check "state is foreign-portal" [ "$(state)" = foreign-portal ]
}

readable_non_vit_ssid_refused() {
    with_credentials
    behind_pronto
    export STUB_SSID="Starbucks"
    wc_run run
    check "no login POST" [ "$(count "$STUB_DIR/login_urls")" = 0 ]
    check "state is not-vit" [ "$(state)" = not-vit ]
}

readable_vit_ssid_logs_in() {
    with_credentials
    behind_pronto
    export STUB_SSID="VIT5G"
    wc_run run
    check "one login POST" [ "$(count "$STUB_DIR/login_urls")" = 1 ]
    check "log names the network" grep -q "'VIT5G'" "$SANDBOX/out"
}

networksetup_ssid_fallback() {
    with_credentials
    behind_pronto
    export STUB_SSID="<redacted>" STUB_NETWORKSETUP_SSID="Cafe"
    wc_run run
    check "no login POST" [ "$(count "$STUB_DIR/login_urls")" = 0 ]
    check "state is not-vit" [ "$(state)" = not-vit ]
}

allowed_ssids_from_config() {
    with_credentials
    behind_pronto
    printf 'ALLOWED_SSIDS=MH-Block, LH-Block\n' >> "$HOME/.config/wificonnector/config"
    export STUB_SSID="lh-block-2"
    wc_run run
    check "one login POST" [ "$(count "$STUB_DIR/login_urls")" = 1 ]
}

redirect_response_is_success() {
    with_credentials
    behind_pronto
    export STUB_LOGIN_CODE=302 STUB_LOGIN_BODY=""
    wc_run run
    check "state is online" [ "$(state)" = online ]
}

rejected_login_backs_off() {
    with_credentials
    behind_pronto
    export STUB_LOGIN_BODY="<html>Sorry, Invalid Username or Password</html>" STUB_ONLINE_AFTER_LOGIN=0
    wc_run run
    check "state is rejected" [ "$(state)" = rejected ]
    check "notified" grep -q "refused" "$STUB_DIR/notifications"
    wc_run run
    check "no retry during backoff" [ "$(count "$STUB_DIR/login_urls")" = 1 ]
    check "state is backoff" [ "$(state)" = backoff ]
    wc_run login
    check "manual login ignores backoff" [ "$(count "$STUB_DIR/login_urls")" = 2 ]
}

dns_failure_retries_via_gateway() {
    with_credentials
    behind_pronto
    export STUB_LOGIN_RC=6
    wc_run run
    check "second POST went to the gateway" \
        grep -qxF "http://172.18.0.1/cgi-bin/authlogin?URI=http://example.com" "$STUB_DIR/login_urls"
    check "state is online" [ "$(state)" = online ]
}

network_error_retries_once() {
    with_credentials
    behind_pronto
    export STUB_LOGIN_RC=28 STUB_ONLINE_AFTER_LOGIN=0
    wc_run run
    check "two POSTs" [ "$(count "$STUB_DIR/login_urls")" = 2 ]
    check "state is login-failed" [ "$(state)" = login-failed ]
    check "no backoff for a network error" [ ! -f "$STATE/rejected" ]
}

accepted_but_still_offline() {
    with_credentials
    behind_pronto
    export STUB_ONLINE_AFTER_LOGIN=0
    wc_run run
    check "state is no-internet" [ "$(state)" = no-internet ]
    check "probe + 4 revalidation probes" [ "$(grep -c generate_204 "$STUB_DIR/curl_calls")" = 5 ]
}

missing_credentials() {
    behind_pronto
    wc_run run
    check "no login POST" [ "$(count "$STUB_DIR/login_urls")" = 0 ]
    check "state is no-credentials" [ "$(state)" = no-credentials ]
    check "notified" grep -q "setup" "$STUB_DIR/notifications"
}

not_connected() {
    with_credentials
    export STUB_IP=""
    wc_run run
    check "state is disconnected" [ "$(state)" = disconnected ]
    check "no probe" [ "$(count "$STUB_DIR/curl_calls")" = 0 ]
}

no_wifi_hardware() {
    export STUB_NO_WIFI=1
    wc_run run
    check "state is no-wifi" [ "$(state)" = no-wifi ]
}

logout_pauses_auto_login() {
    with_credentials
    wc_run logout
    check "logout URL called" grep -qF "authlogout" "$STUB_DIR/logout_urls"
    check "paused" [ -f "$STATE/paused" ]
    behind_pronto
    wc_run run
    check "no login while paused" [ "$(count "$STUB_DIR/login_urls")" = 0 ]
    wc_run login
    check "login clears the pause" [ ! -f "$STATE/paused" ]
    check "login resumes" [ "$(count "$STUB_DIR/login_urls")" = 1 ]
}

logout_no_pause() {
    with_credentials
    wc_run logout --no-pause
    check "not paused" [ ! -f "$STATE/paused" ]
}

quiet_when_nothing_changes() {
    with_credentials
    wc_run run
    wc_run run
    check "second online run logs nothing" [ ! -s "$SANDBOX/out" ]
}

run_skips_when_locked() {
    with_credentials
    behind_pronto
    mkdir -p "$STATE/lock"
    wc_run run
    check "no login POST" [ "$(count "$STUB_DIR/login_urls")" = 0 ]
}

setup_saves_to_keychain() {
    printf ' 22bce1234 \n' | PATH="$STUBS:$PATH" "$TEST_BASH" "$SCRIPT" setup > "$SANDBOX/out" 2>&1
    check "next step names the command as invoked" grep -qF "Run '$SCRIPT login'" "$SANDBOX/out"
    check "username normalized into config" grep -qx "USERNAME=22BCE1234" "$HOME/.config/wificonnector/config"
    check "config is private" [ "$(stat -c %a "$HOME/.config/wificonnector/config" 2>/dev/null || stat -f %Lp "$HOME/.config/wificonnector/config")" = 600 ]
    check "keychain item, security pre-authorized, password prompted by security" \
        grep -qx "add-generic-password -U -s wificonnector -a 22BCE1234 -l wificonnector (VIT Wi-Fi) -T /usr/bin/security -w" "$STUB_DIR/security_calls"
}

install_writes_valid_agent() {
    wc_run install
    local plist="$HOME/Library/LaunchAgents/com.wificonnector.agent.plist"
    check "script copied" [ -x "$HOME/.local/bin/wificonnector" ]
    check "plist parses with a 15s interval and the installed script" python3 - "$plist" "$HOME/.local/bin/wificonnector" <<'EOF'
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
assert p["Label"] == "com.wificonnector.agent"
assert p["StartInterval"] == 15
assert p["ProgramArguments"] == ["/bin/bash", sys.argv[2], "run"]
assert p["RunAtLoad"] is True
assert "/Library/Preferences/SystemConfiguration" in p["WatchPaths"]
EOF
    check "agent bootstrapped" grep -q "^bootstrap gui/" "$STUB_DIR/launchctl_calls"
}

uninstall_purge() {
    with_credentials
    wc_run install
    wc_run uninstall --purge
    check "plist removed" [ ! -f "$HOME/Library/LaunchAgents/com.wificonnector.agent.plist" ]
    check "keychain item deleted" grep -q "^delete-generic-password -s wificonnector -a 22BCE1234" "$STUB_DIR/security_calls"
    check "config removed" [ ! -d "$HOME/.config/wificonnector" ]
}

status_reports_portal() {
    with_credentials
    behind_pronto
    wc_run status
    check "shows the portal" grep -q "behind the VIT portal (pronto" "$SANDBOX/out"
    check "shows credentials" grep -q "22BCE1234 (in Keychain)" "$SANDBOX/out"
    check "sends no login" [ "$(count "$STUB_DIR/login_urls")" = 0 ]
}

# shellcheck disable=SC2016 # expanded by the bash under test
echo "wificonnector tests ($("$TEST_BASH" -c 'echo "bash $BASH_VERSION"'))"
for t in \
    online_sends_nothing \
    pronto_redirect_logs_in \
    password_only_on_stdin \
    pronto_in_page_body_logs_in \
    foreign_portal_gets_no_credentials \
    readable_non_vit_ssid_refused \
    readable_vit_ssid_logs_in \
    networksetup_ssid_fallback \
    allowed_ssids_from_config \
    redirect_response_is_success \
    rejected_login_backs_off \
    dns_failure_retries_via_gateway \
    network_error_retries_once \
    accepted_but_still_offline \
    missing_credentials \
    not_connected \
    no_wifi_hardware \
    logout_pauses_auto_login \
    logout_no_pause \
    quiet_when_nothing_changes \
    run_skips_when_locked \
    setup_saves_to_keychain \
    install_writes_valid_agent \
    uninstall_purge \
    status_reports_portal
do
    test_case "$t"
done

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
