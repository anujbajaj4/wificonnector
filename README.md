# wificonnector

[![Downloads](https://img.shields.io/github/downloads/anujbajaj4/wificonnector/total)](https://github.com/anujbajaj4/wificonnector/releases)
[![Latest release](https://img.shields.io/github/v/release/anujbajaj4/wificonnector)](https://github.com/anujbajaj4/wificonnector/releases/latest)

Automatic login to **VIT hostel Wi-Fi on macOS**. Joining the hostel network
puts you behind a Pronto Networks captive portal that asks for your
registration number and password every time. wificonnector notices the portal
and logs you in, in the background, usually within a few seconds of
connecting. It also logs you in again if the portal drops your session.

It's a menu-bar app you install with one command in Terminal (or from a
`.dmg`), or a single bash script if you'd rather skip the app. Both use the
same engine and the same launchd background agent. The portal protocol comes
from VinnovateIT's [Latch](https://github.com/vinnovateit/latch), which does
the same job on Android, Windows and Linux.

**Website:** [anujbajaj4.github.io/wificonnector](https://anujbajaj4.github.io/wificonnector/)

Want to know how it works, or build your own? Read
[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## Tested on

A MacBook Air running macOS 27 on VIT Vellore hostel Wi-Fi: manual login,
logout and automatic re-login by the background agent, also with Cloudflare's
1.1.1.1 app switched on. v0.3.2 was installed with the one-line command and
set up in its welcome window on the same Mac.

## Requirements

- The app: macOS 13 (Ventura) or later, on an Apple silicon or Intel Mac
- The script on its own: macOS 12 or later (everything it uses ships with macOS)
- Your VIT registration number and hostel Wi-Fi password

## Install the app

Open Terminal (⌘ Space, type Terminal, press Return), paste this and press
Return:

```sh
curl -fsSL https://anujbajaj4.github.io/wificonnector/install.sh | bash
```

It downloads the latest release into Applications and opens it. Installed
this way, macOS shows no security warning, because files curl downloads
aren't marked as coming from the internet.
[Read the installer](site/install.sh) before you run it if you like.

The app opens a welcome window (if you don't see it, click the Wi-Fi icon in
the menu bar and choose **Set Up…**). Type your registration number and Wi-Fi
password and click **Save and Turn On**. That saves the password in your
Keychain, turns on the background agent, sets the app to start at login and
logs you in. From then on it lives in the menu bar, at the top right. If you
can't see its icon, the notch may be hiding it: quit an app with a menu-bar
icon to make room.

### Or download the .dmg

1. Download **WiFiConnector.dmg** from the
   [latest release](https://github.com/anujbajaj4/wificonnector/releases/latest)
   and open it.
2. Drag **WiFiConnector** onto **Applications**.
3. Open WiFiConnector from Applications. macOS says it can't verify the app,
   because it isn't signed with a paid Apple Developer ID. Click **Done**, not
   Move to Trash.
4. Open **System Settings ▸ Privacy & Security**, scroll down, and click
   **Open Anyway** next to WiFiConnector. You only do this once. The button
   shows for about an hour after the blocked launch; if it's gone, open the
   app again first.
5. Fill in the welcome window, as above.

## Install only the script

```sh
git clone https://github.com/anujbajaj4/wificonnector.git
cd wificonnector

bin/wificonnector setup     # registration number, then the password (twice)
bin/wificonnector login     # try it now, showing every step
bin/wificonnector install   # run it in the background from now on
```

`setup` stores the password in your **login Keychain**. macOS prompts for it
directly, so the script never handles it as text. `install` copies the script
to `~/.local/bin/wificonnector` and starts a launchd agent that checks:

- whenever your network configuration changes (joining, waking, roaming), and
- every 15 seconds, so a session the portal drops gets renewed.

Add `~/.local/bin` to your `PATH` to type `wificonnector` from anywhere:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

## Usage

```text
wificonnector setup          Save or change your credentials
wificonnector login          Log in now (also resumes auto-login)
wificonnector logout         Log out and pause auto-login
wificonnector logout --no-pause   Log out but keep auto-login running
wificonnector status         Wi-Fi, portal, credentials and agent state
wificonnector diagnose       Network details for troubleshooting, safe to share (no addresses)
wificonnector pause | resume Hold or restart auto-login without logging out
wificonnector install        Install or update the background agent
wificonnector uninstall      Remove the agent (--purge also deletes credentials)
```

Watch it work:

```sh
tail -f ~/Library/Logs/wificonnector.log
```

## When does it send your password?

Only when **both** of these hold:

1. The internet check is intercepted by a portal that redirects to
   `phc.prontonetworks.com`, the VIT hostel portal. If your DNS is blocked
   before login, the network's gateway must redirect there instead. A café or
   hotel portal never gets your credentials.
2. The Wi-Fi network's name contains `VIT`, if macOS reveals the name. Since
   macOS 14 the name is location data and usually hidden from command-line
   tools; then the portal check alone decides.

If the portal refuses your password, auto-login waits 5 minutes before trying
again, so a wrong password can't get your account locked.

## Configuration

`~/.config/wificonnector/config` holds simple `key=value` lines:

| Key | Example | Meaning |
|---|---|---|
| `USERNAME` | `26BCE0000` | set by `setup` |
| `ALLOWED_SSIDS` | `MH-Block,LH-Block` | extra network names to accept besides those containing "VIT" |
| `WIFI_DEVICE` | `en1` | override the Wi-Fi device if detection picks the wrong one |

## Troubleshooting

| Symptom | What to do |
|---|---|
| `status` shows `(name hidden by macOS)` | Normal on macOS 14+. To make it visible to the script: `sudo ipconfig setverbose 1` |
| "DNS lookup failed" or "curl exit 7" before login | You use a custom DNS, the Cloudflare 1.1.1.1/WARP app, a VPN or Private Relay. The script works around it (via the network's own DNS, then the gateway); if it still fails, send the output of `wificonnector diagnose` |
| Log says "not a VIT portal" | The portal isn't Pronto (an academic block, perhaps). Run `curl -sv http://clients3.google.com/generate_204 -o /dev/null` and open an issue with the `Location:` line |
| Log says "Login refused" | Check your password with `wificonnector setup`, then `wificonnector login` |
| A "security wants to access" dialog | Choose **Always Allow**. It shows up if the Keychain item was created some other way |
| No notifications | System Settings ▸ Notifications ▸ Script Editor, allow notifications |
| macOS's own login window still pops up | It closes once you're logged in. To disable it for all networks, see [the docs](docs/HOW-IT-WORKS.md#the-captive-network-assistant) |
| Agent not running | `launchctl print gui/$(id -u)/com.wificonnector.agent`, then `wificonnector install` again |

## Development

```sh
tests/run-tests.sh                       # stub-based tests; run on macOS or Linux
TEST_BASH=/bin/bash tests/run-tests.sh   # under macOS's bash 3.2 explicitly
shellcheck bin/wificonnector tests/run-tests.sh tests/stubs/* site/install.sh
```

The tests replace `curl`, `security`, `ipconfig`, `networksetup`,
`osascript` and `launchctl` with fakes, so they never touch your Keychain or
network.

## Menu-bar app

The app's source is in [`app/`](app/README.md): a SwiftUI menu-bar app that
shows whether you're online and lets you log in or out, pause auto-login and
enter your credentials. To build it yourself, open
`app/WiFiConnector.xcodeproj` in Xcode and press Run, or run `app/package.sh`
to make the same `.dmg` the releases ship.

### The website

The site in [`site/`](site/) is published to GitHub Pages by the Website
workflow whenever it changes on `main`. Its images (favicon, the link preview
image) come from `app/tools/make_site_images.py`, which draws them from the
app icon.

### Launch dashboard

[`terminal/`](terminal/README.md) is a private, Bloomberg-style dashboard of
downloads, visits, the install funnel and the Reddit post, deployed on
Vercel. Its README has the setup.

### Releasing

Bump `VERSION` in `bin/wificonnector`, merge to `main`, then run
**Actions ▸ Release ▸ Run workflow**. It runs the tests, builds a universal
`WiFiConnector.dmg` and publishes it as a GitHub Release. The download link
`releases/latest/download/WiFiConnector.dmg` always points at the newest one.

## Roadmap

- Academic-block Wi-Fi (a different portal; its protocol needs capturing first)
- Move the menu-bar app's engine from the script into Swift, step by step

## License

MIT, © 2026 Anuj Bajaj. See [LICENSE](LICENSE). The portal protocol is ported
from [Latch](https://github.com/vinnovateit/latch) (MIT, © VinnovateIT); see
[NOTICE](NOTICE).
