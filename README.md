# wificonnector

Automatic login to **VIT hostel Wi-Fi on macOS**. Joining the hostel network
puts you behind a Pronto Networks captive portal that asks for your
registration number and password every time. wificonnector notices the portal
and logs you in, in the background, usually within a few seconds of
connecting. It also logs you in again if the portal drops your session.

It comes as a menu-bar app you download, or as a single bash script for
Terminal; both use the same engine and the same launchd background agent. The
portal protocol comes from VinnovateIT's
[Latch](https://github.com/vinnovateit/latch), which does the same job on
Android, Windows and Linux.

Want to know how it works, or build your own? Read
[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## Tested on

A MacBook Air running macOS 27 on VIT Vellore hostel Wi-Fi: manual login,
logout, automatic re-login by the background agent, and all of these with
Cloudflare's 1.1.1.1 app switched on. The v0.2.0 `.dmg` was downloaded,
installed and opened through Open Anyway on the same Mac.

## Requirements

- The app: macOS 15 or later, on an Apple silicon or Intel Mac
- The Terminal version: macOS 12 or later (everything it uses ships with macOS)
- Your VIT registration number and hostel Wi-Fi password

## Install the app

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
   app again first. Or skip Settings and run this in Terminal instead:
   `xattr -dr com.apple.quarantine /Applications/WiFiConnector.app`
5. Click the Wi-Fi icon in the menu bar. Choose **Settings…** to save your
   registration number and password, then **Install Background Agent**, and
   tick **Start at Login**.

## Install with Terminal

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
| `USERNAME` | `22BCE1234` | set by `setup` |
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
shellcheck bin/wificonnector tests/run-tests.sh tests/stubs/*
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

### Releasing

Bump `VERSION` in `bin/wificonnector`, merge to `main`, then run
**Actions ▸ Release ▸ Run workflow**. It runs the tests, builds a universal
`WiFiConnector.dmg` and publishes it as a GitHub Release. The download link
`releases/latest/download/WiFiConnector.dmg` always points at the newest one.

## Roadmap

- Academic-block Wi-Fi (a different portal; its protocol needs capturing first)
- Move the menu-bar app's engine from the script into Swift, step by step

## License

MIT. See [LICENSE](LICENSE). The portal protocol is ported from
[Latch](https://github.com/vinnovateit/latch) (MIT, © VinnovateIT).
