# How wificonnector works

This is the long version: what a captive portal is, how VIT's portal expects
to be spoken to, how [Latch](https://github.com/vinnovateit/latch) automates it
on other platforms, and how each piece maps onto macOS. Read it top to bottom
once and you should be able to rebuild the tool from scratch.

- [1. What a captive portal is](#1-what-a-captive-portal-is)
- [2. Detecting the portal](#2-detecting-the-portal)
- [3. The Pronto login protocol](#3-the-pronto-login-protocol)
- [4. How Latch is built](#4-how-latch-is-built)
- [5. From Latch to a shell script](#5-from-latch-to-a-shell-script)
- [6. The macOS pieces](#6-the-macos-pieces)
- [7. Security model](#7-security-model)
- [8. Choosing the health-check interval](#8-choosing-the-health-check-interval)
- [9. How it is tested](#9-how-it-is-tested)
- [10. What comes next](#10-what-comes-next)

## 1. What a captive portal is

Joining the hostel Wi-Fi only gets you onto the local network. The gateway
lets DHCP and (usually) DNS through, but blocks everything else until you've
logged in. The block looks like this: any plain-HTTP request you make gets
*intercepted*, and instead of the real page you get a redirect to the login
page. Once you post valid credentials, the gateway adds your device (by MAC
or IP address) to an allow-list for the length of a session, and traffic flows.

That's why "logging in every single time" happens: the allow-list entry dies
when you disconnect, when your Mac sleeps long enough, when the session
times out, or when you log in on another device that takes your slot.

VIT's hostel Wi-Fi is run by **Pronto Networks**, and its login page lives at
`phc.prontonetworks.com`.

## 2. Detecting the portal

You can't ask a network "do you have a captive portal?". You can only try to
reach the internet and see what comes back. Every OS does this with a URL
whose real answer is known in advance:

| Who | URL | Real answer |
|---|---|---|
| Android, Latch, wificonnector | `http://clients3.google.com/generate_204` | `204 No Content`, empty body |
| macOS / iOS | `http://captive.apple.com/hotspot-detect.html` | a tiny page saying `Success` |

If you get anything other than the known answer (a `302` redirect, or a `200`
with someone's login page), something is intercepting you. The probe must:

- be **plain HTTP**: a portal can't intercept HTTPS without a certificate error,
- **not follow redirects**, because the redirect itself is the evidence,
- have a **short timeout** (3s), so a dead network fails fast.

`probe()` in `bin/wificonnector` sorts the result into four cases, the same as
Latch's `CaptivePortalDetector`: `online` (204), `portal` (anything else),
`dns` (the name didn't resolve) and `error` (timeout and the like).

Try it yourself on the hostel Wi-Fi before logging in:

```sh
curl -sv --max-time 3 http://clients3.google.com/generate_204 -o /dev/null
```

Behind the portal you'll see a `302` with a `Location:` header pointing at
`phc.prontonetworks.com`. Once you're logged in it's `HTTP/1.1 204 No Content`.

### When DNS is blocked too

Before you log in, a portal usually answers DNS lookups only through **its
own** DNS server, the one the network hands out when you connect. If your Mac
uses another resolver (a custom DNS like `1.1.1.1`, the Cloudflare 1.1.1.1
app, a VPN, iCloud Private Relay), every lookup fails until you're logged in.
curl then can't even start the probe (exit 6, "DNS lookup failed"), so there's
no redirect to see.

This was the first real-world failure on a MacBook Air at VIT running the
Cloudflare app. The script handles it in two layers:

1. **Ask the network's DNS server directly.** `ipconfig getoption en0
   domain_name_server` gives the server the network handed out, `dig
   @<server> <host>` asks it, and `curl --resolve host:80:<address>` uses the
   answer for that one request. Only the probe, login and logout requests do
   this; everything else on the Mac keeps using your resolver.
2. **Recognize the portal from the gateway.** If the probe still fails, the
   script requests the gateway by its IP address (`http://<gateway>/`). VIT's
   gateway answers with a `302` to `phc.prontonetworks.com`, which is the same
   fingerprint, obtained without DNS or the internet.

That second layer also covers **VPNs**. The same Mac turned out to run the
Cloudflare app in WARP mode, a VPN that routes all traffic into a tunnel. Before
login the tunnel can't come up, so the probe's connection was dropped on the
Mac itself: curl exit 7, "failed to connect after 0 ms". VPNs leave the local
network outside the tunnel, so the gateway still answers.

The catch: VIT's gateway redirects to the portal *even when you're logged
in*, so the gateway alone can't tell logged in from logged out. If the probe
were failing for some other reason while you're online, every run would log in
again. So a login that the portal accepts but that doesn't bring the internet
check back starts a 2-minute pause on auto-login (`UNVERIFIED_BACKOFF_SECONDS`).
Being online is still noticed during the pause, because it only holds back
logins. Revalidation also waits a little longer than Latch's (5 retries, 2s
apart), because a VPN needs a few seconds to reconnect once the portal opens.

`wificonnector diagnose` prints all of this (resolvers, routes, gateway answer)
with every address replaced by its kind, so the output can be shared safely.

Then the login POST goes to `phc.prontonetworks.com` (resolved through the
network's DNS), or, if that can't be resolved or reached, to the gateway IP,
Latch's fallback.

**No route before login.** On that MacBook (macOS 27), `diagnose` showed that
while logged out the Mac had **no default route** at all, even with the
Cloudflare app off: every address outside the local subnet failed instantly
(exit 7), including the portal's own private address, while the gateway (on the
subnet) answered. Apple's login pop-up still worked, since system services
can get exceptions ordinary programs don't. So the gateway is the one thing a
script can always reach before login, and both the fingerprint and the login
fall back to it.

## 3. The Pronto login protocol

Everything here comes from Latch's
[`AutoLoginManager.kt`](https://github.com/vinnovateit/latch/blob/main/core/src/commonMain/kotlin/com/vinnovateit/latch/core/wifi/AutoLoginManager.kt).
The login page in your browser is just an HTML form; submitting it is one
HTTP request, which is all an automated client needs to repeat:

```http
POST /cgi-bin/authlogin?URI=http://example.com HTTP/1.1
Host: phc.prontonetworks.com
Content-Type: application/x-www-form-urlencoded
User-Agent: Mozilla/5.0 (Android)

userId=22BCE1234&password=...&serviceName=ProntoAuthentication
```

- `userId` is your registration number, `password` your Wi-Fi password.
  Both are **URL-encoded** (`@` → `%40`, `&` → `%26`, space → `+`), or a
  password containing `&` would cut the form in half.
- `serviceName=ProntoAuthentication` is a fixed hidden field from the form.
- `URI=` is where the portal sends you afterwards; any URL works.
- It's plain HTTP. Latch notes that the HTTPS endpoint's certificate chain
  is rejected by modern TLS stacks, so HTTP is what actually works (more on
  what that means in [§7](#7-security-model)).

**Reading the answer.** The portal has no API, so success has to be guessed:

| Response | Meaning |
|---|---|
| `301` / `302` | accepted (the portal redirects you onwards) |
| `200`, page contains `invalid`, `incorrect`, `wrong password`, `authentication failed`, `user not found`, `account expired`, `session limit`, `max session` or `login failed` | refused |
| `200`, none of those | accepted |
| anything else | failed |

Latch's comment on this is worth repeating: *"Matching on response HTML is ugly
but it is the only signal Pronto's portal gives us."* So the real test comes
afterwards. Re-run the probe (immediately, then up to 3 more times 2s apart in
Latch; 5 in wificonnector, see §2) and only call it a success when it returns
`204`.

**Two fallbacks**, also from Latch:

- If `phc.prontonetworks.com` doesn't resolve, send the same request to the
  network's **gateway IP** (`ipconfig getoption en0 router`) instead.
  wificonnector also does this when the portal resolves but can't be
  *reached* (curl exit 7), for the reason in §2.
- If the request fails on the network (timeout, reset), try once more.

**Logout** is `GET http://phc.prontonetworks.com/cgi-bin/authlogout`.

You can do a full login by hand with curl. This is exactly what the script
does, minus the safety checks:

```sh
printf '%s' 'your-password' | curl -s -o /dev/null -w '%{http_code}\n' \
  -A 'Mozilla/5.0 (Android)' \
  --data-urlencode userId=22BCE1234 \
  --data-urlencode password@- \
  --data-urlencode serviceName=ProntoAuthentication \
  'http://phc.prontonetworks.com/cgi-bin/authlogin?URI=http://example.com'
```

`password@-` makes curl read the value from standard input. That keeps the
password out of the command line, where any process could see it in `ps`.

## 4. How Latch is built

Latch is a Kotlin Multiplatform project. The part that knows about VIT is
shared, and each platform supplies a thin layer of OS-specific services:

```
core/src/commonMain/          shared by every platform
  wifi/AutoLoginManager.kt      the POST above, and its success heuristics
  wifi/CaptivePortalDetector.kt the generate_204 probe
  wifi/CampusSsid.kt            "is this a VIT network?" (SSID contains "VIT")
  engine/LatchEngine.kt         the state machine that ties it together
  platform/Platform.kt          interfaces each OS implements:
                                  WifiPlatform, CredentialStore, HttpTransport...
core/src/androidMain/         ConnectivityManager callbacks, encrypted prefs
core/src/desktopMain/
  platform/windows/             netsh/WLAN API, DPAPI-encrypted credentials
  platform/linux/               NetworkManager, Secret Service
  platform/mac/                 CoreWLAN through JNA, Keychain, Location Services
app/       Android UI (Jetpack Compose), foreground service, QS tile, widget
desktop/   Compose Desktop UI and tray icon for Windows/Linux/macOS
cli/       latch-cli, a headless daemon for terminals
```

`LatchEngine.checkAndAct()` is the heart of it. On every "Wi-Fi available"
event (and from a 60-second health check) it:

1. probes `generate_204`. If the answer is `204` and the SSID is VIT,
   you're latched; start the health check.
2. If DNS is blocked, gives up with a clear reason (on Android this is
   usually Private DNS).
3. Checks auto-login is on and the network is the target (VIT SSID).
4. Reads the credentials and POSTs them, retrying via the gateway IP.
5. Revalidates with the probe, up to 3 retries 2s apart.

The health check counts 3 failed probes in a row before deciding the session
expired, so one flaky probe doesn't trigger a login.

Latch's own macOS layer (`platform/mac/`, in preview since 1.5.0) reads the
SSID through CoreWLAN and **refuses to log in when it can't read it**. Since
macOS 14 that means the packaged app needs Location permission, and a
bare `java` process never gets it.

## 5. From Latch to a shell script

Each Latch piece has a much smaller macOS equivalent:

| Latch | wificonnector |
|---|---|
| `CaptivePortalDetector.probe()` | `probe()`: `curl -D headers -w '%{http_code}'` |
| `AutoLoginManager.attemptLogin()` | `pronto_post()` + `login_pronto()` |
| `LatchEngine.checkAndAct()` | `check_and_login()` |
| revalidation loop | `revalidate()` |
| `WifiEvent.Available` (OS network callbacks) | launchd `WatchPaths` |
| 60s health-check coroutine | launchd `StartInterval` (15s, see §8) |
| `CredentialStore` (Keychain via JNA) | `security` command-line tool |
| `isVitCampusSsid()` | `is_campus_ssid()`, plus the portal fingerprint (§7) |
| `NetworkHandle` / `bindProcess()` | nothing: requests take the normal route (see §6) |
| file logger | launchd's `StandardOutPath` |
| tray/system notifications | `osascript -e 'display notification ...'` |

A few things the script adds because it runs **every 15 seconds, unattended**:

- **Quiet logging.** The last state (`online`, `rejected`, `not-vit`...) is
  saved in `~/Library/Caches/wificonnector/state`, and a line is logged only
  when it changes.
- **Credential backoff.** After the portal refuses your password, auto-login
  waits 5 minutes. Otherwise a wrong password would be retried 20 times a
  minute, which looks like a brute-force attack and could lock the account.
- **A lock.** A network change and the timer can fire at the same moment.
  `mkdir` is atomic, so only one run gets the lock directory; a lock older
  than two minutes is treated as a crashed run's and removed.
- **Pause on logout.** Without it, the agent would log you straight back in.

## 6. The macOS pieces

### launchd: running in the background

launchd is macOS's process supervisor, used instead of cron or systemd. A
**LaunchAgent** is a job that runs as you, in your login session (a
LaunchDaemon runs as root, system-wide, which we don't need). It's described by
a property list in `~/Library/LaunchAgents/`, which `wificonnector install`
writes:

| Key | Value | Why |
|---|---|---|
| `Label` | `com.wificonnector.agent` | the job's unique name |
| `ProgramArguments` | `/bin/bash ~/.local/bin/wificonnector run` | what to run (launchd doesn't expand `~`, so the real path is written in) |
| `RunAtLoad` | true | run once as soon as you log in |
| `WatchPaths` | `/Library/Preferences/SystemConfiguration`, `/private/var/run/resolv.conf` | run whenever these change. macOS rewrites its network configuration and DNS settings when you join, leave or roam between networks |
| `StartInterval` | 15 | the health check |
| `ThrottleInterval` | 10 | launchd's default: never start the job more often than every 10s |
| `StandardOutPath` / `StandardErrorPath` | `~/Library/Logs/wificonnector.log` | where `log` lines go |

It's loaded with `launchctl bootstrap gui/<uid> <plist>` and removed with
`launchctl bootout gui/<uid>/com.wificonnector.agent`. The `gui/<uid>` part
is the *domain*: your graphical login session, which is also what gives the
job access to your unlocked login Keychain. Check on it with:

```sh
launchctl print gui/$(id -u)/com.wificonnector.agent
```

`WatchPaths` is a coarse signal. It fires on many configuration writes, not
exactly one per Wi-Fi join, and Apple doesn't promise which files change on
each macOS version. That's fine here, because each run is cheap and decides
for itself what to do, and the 15-second timer catches anything it misses.

### Keychain: storing the password

The login Keychain is macOS's encrypted credential store, unlocked when you
log in. `wificonnector setup` runs:

```sh
security add-generic-password -U -s wificonnector -a 22BCE1234 \
  -l "wificonnector (VIT Wi-Fi)" -T /usr/bin/security -w
```

- `-s`/`-a`: service and account, the item's lookup key.
- `-U`: update the item if it already exists.
- `-T /usr/bin/security`: put the `security` tool on the item's access list,
  so background reads don't pop up "allow access?" dialogs.
- `-w` as the **last** argument makes `security` prompt for the password
  itself, so the password never goes through the script or the command line.

It's read back with `security find-generic-password -s wificonnector -a
22BCE1234 -w`. You can see (and delete) the item in Keychain Access.

### Reading the network

| Fact | Command |
|---|---|
| Wi-Fi device (`en0`) | `networksetup -listallhardwareports` (the "Hardware Port: Wi-Fi" block) |
| IP address | `ipconfig getifaddr en0` |
| Gateway | `ipconfig getoption en0 router` |
| Network name | `ipconfig getsummary en0` (the `SSID :` line), else `networksetup -getairportnetwork en0` |

**The SSID problem.** Since macOS 14 the Wi-Fi network's name counts as
*location data*. An app has to be granted Location Services permission to read
it, and command-line tools have no way to ask, so `ipconfig getsummary`
usually shows `SSID : <redacted>`, and `networksetup` claims you're not
associated. (`sudo ipconfig setverbose 1` makes `ipconfig` print the real
name again on many versions.) That's why wificonnector can't rely on the
SSID alone. See §7.

### Not binding to Wi-Fi

On Android, Latch pins its requests to the Wi-Fi network
(`bindProcess(handle)`), because a phone also has mobile data. The first
version of this script did the same with `curl --interface en0`. On a real
MacBook Air at VIT that made *every* request fail in milliseconds with curl
exit 7 ("couldn't connect"), while the same request without the option got
its `204`. A likely cause is that binding to a device makes curl choose a
source address on it that can't reach the destination (e.g. the link-local
IPv6 address). The option was removed. Requests now leave the way macOS
routes everything else, which is through Wi-Fi unless an Ethernet cable is
also plugged in. In that rare case the script just sees Ethernet's
connectivity, which is harmless.

The lesson generalises: a stub-based test can only check that the script
*passes* an option, not that the option does what you think on the real OS.
That gap is why every change still gets a run on a real Mac.

### The Captive Network Assistant

When macOS notices a portal it opens its own little login window, the
*Captive Network Assistant*. wificonnector usually logs in within seconds, and
the window then reports that you're connected and can be closed. If it bothers
you, you can turn it off for **every** network (including hotel and airport
Wi-Fi, where you'd then log in through a normal browser):

```sh
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.captive.control Active -bool false
# undo:
sudo defaults delete /Library/Preferences/SystemConfiguration/com.apple.captive.control Active
```

## 7. Security model

The script holds your university password and sends it, automatically, to
whatever network you happen to be on. The question is **when is it safe to send?**

**The threat.** Someone sets up a fake network that imitates a captive portal
and harvests whatever a naive auto-login tool sends.

**Gate 1: the portal fingerprint.** Credentials are sent only when the
probe's redirect (or the page it returns) names `phc.prontonetworks.com`, or,
when DNS is blocked, when the gateway's redirect does. A café portal, a hotel
portal or your home router never triggers a login. Asking the network's own
DNS server doesn't weaken this: a network that can fake a redirect controls
its own DNS answers anyway.

**Gate 2: the SSID, when macOS shows it.** If the name is readable and
doesn't contain `VIT` (or one of your `ALLOWED_SSIDS`), nothing is sent,
whatever the portal says.

**What it can't stop.** Someone who deliberately builds a network named
`VIT...` that redirects to a fake `phc.prontonetworks.com` passes both gates.
Latch's macOS build closes part of this by insisting on a readable SSID, but an
SSID is just as easy to fake as a redirect. The real limit is the portal
itself: the login is **plain HTTP**, so your password crosses the network
unencrypted, exactly as it does when you log in through the browser. The
script doesn't make this worse, and can't make it better.

Practical advice: use a Wi-Fi password you don't use anywhere else.

**What the script does to protect the password locally:**

- It's stored only in the login Keychain, never in a file.
- It never appears in a command line (`security -w` prompts for it, and
  curl reads it from stdin), so other processes can't see it in `ps`.
- It's never logged. The log has your registration number and the result.
- The config file (`~/.config/wificonnector/config`) holds only your
  registration number, is `chmod 600`, and is parsed, never `source`d.

## 8. Choosing the health-check interval

Joining, waking and roaming are handled by `WatchPaths`. The timer exists for
one case: the portal ends your session while you stay connected (a timeout,
or a login on your phone took the slot). Each check is one empty `204`
request, about 1 KB including the TCP handshake.

| Interval | Worst-case time offline after a kick | Checks per hour | Data per day |
|---|---|---|---|
| 60s (Latch) | ~60s | 60 | ~1.4 MB |
| 30s | ~30s | 120 | ~3 MB |
| **15s (chosen)** | ~15s | 240 | ~6 MB |
| 10s | ~10s | 360 | ~9 MB |
| 5s | ~5s | 720 | ~17 MB |

Below 10s you hit launchd's `ThrottleInterval`, which would have to be lowered
(launchd then logs warnings). You also spend measurably more CPU wake-ups on a
laptop, and a slow login attempt (timeouts plus revalidation) can outlast the
interval, so runs just bump into the lock. A shorter interval doesn't cause *extra logins*,
though. Unlike Latch's health check, the script logs in only when it actually
sees the Pronto redirect; a slow or failed probe does nothing. No checks run
while the Mac is asleep.

To change it, edit `HEALTH_CHECK_INTERVAL` at the top of `bin/wificonnector`
and run `wificonnector install` again.

## 9. How it is tested

The script talks to macOS through six commands: `curl`, `security`,
`ipconfig`, `networksetup`, `osascript` and `launchctl`. `tests/stubs/` has a
fake of each. They answer from environment variables (`STUB_PROBE_CODE=302`,
`STUB_SSID=Starbucks`...) and record how they were called.
`tests/run-tests.sh` puts them first on `PATH` and runs real scenarios: online,
behind Pronto, behind a café portal, wrong SSID, wrong password (and the
backoff), DNS failure (and the gateway retry), logout pausing auto-login,
the launchd plist parsing correctly...

Some checks are about the password specifically: it must reach curl on stdin,
without a trailing newline, and appear in no command line and no log line.

**bash 3.2.** macOS still ships bash 3.2 from 2007 as `/bin/bash`, because later
versions are GPLv3. The script avoids everything newer (associative arrays,
`${var,,}`, `mapfile`...). The test runner accepts `TEST_BASH=/path/to/bash`,
and the suite was run under bash 3.2.57 built from
[Apple's own bash sources](https://github.com/apple-oss-distributions/bash) as
well as under bash 5.

What the stubs can't check: the exact text real macOS tools print, and how the
real portal behaves. Those get checked once, on a real Mac at VIT
(see the README).

## 10. What comes next

- **Academic-block Wi-Fi** (phase 1b). It uses a different portal that Latch
  doesn't handle. The script is already split into portal *profiles*
  (`PROFILES`, `<name>_fingerprint`, `login_<name>`, `logout_<name>`), so
  adding one means learning its protocol, which you can capture from a Mac in
  an academic block:
  1. `curl -sv http://clients3.google.com/generate_204 -o /dev/null` shows
     the redirect, i.e. the portal's host (the fingerprint).
  2. Safari ▸ Settings ▸ Advanced ▸ "Show features for web developers", then
     Develop ▸ Show Web Inspector ▸ Network. Log in by hand and look at the
     request the form sends: its URL, method, fields (including hidden ones
     and any token copied from the page), and what success and failure
     responses look like.
  3. Write `login_academic` from that, add its fingerprint to `PROFILES`, and
     add stub tests.
- **A Swift menu-bar app** (phase 2) using the same logic natively: CoreWLAN
  for the SSID (after asking for Location permission, which an app can do),
  the Keychain API, `URLSession`, network-change callbacks from
  `NWPathMonitor`, and `SMAppService` to start at login.
