# WiFiConnector menu-bar app

A macOS menu-bar app for wificonnector: an icon in the top bar that shows
whether you're online, with a menu to log in or out, pause auto-login, and a
Settings window for your credentials, so you never need Terminal.

For now the app is a front end. The proven `bin/wificonnector` script, bundled
inside the app, still does all the logging in, and the background agent it
installs keeps working with the app closed. Later versions move that work into
Swift one piece at a time (see [Roadmap](#roadmap)).

## Download it

Most people should get the ready-made app: download **WiFiConnector.dmg**
from the [latest release](https://github.com/anujbajaj4/wificonnector/releases/latest)
and follow the install steps in the [main README](../README.md#install-the-app).
The rest of this page is for building and changing it.

## Run it from Xcode

You need macOS 15 or later and Xcode 16 or later.

1. Open `app/WiFiConnector.xcodeproj` in Xcode.
2. Press **Run** (⌘R). Nothing opens on screen: look for the Wi-Fi icon at the
   right of the menu bar.
3. Click it and choose **Settings…**. Enter your registration number and
   password and click **Save**. If you already ran `wificonnector setup`, the
   number is filled in and you can skip this.
4. If the menu offers **Install Background Agent** or **Update Background
   Agent**, click it. That installs the app's copy of the script as the agent
   that logs you in every 15 seconds and on network changes.

To keep the app, drag it from Xcode's **Product ▸ Show Build Folder in
Finder** (`Products/Debug/WiFiConnector.app`) into **Applications**, open it
from there, and tick **Start at Login** in its menu.

**To make the downloadable disk image**, run `app/package.sh`. It builds a
universal Release app, signs it ad hoc and writes `app/build/WiFiConnector.dmg`.
The Release workflow runs the same script.

**If the project won't open or build**, run `app/build-app.sh` in Terminal.
It builds the same app without the project file, into
`app/build/WiFiConnector.app`. Either way, please send the error text.

## What you'll see

| Icon | Meaning |
|---|---|
| Wi-Fi | online |
| circling arrows | a login, logout or install is running |
| Wi-Fi with `!` | something needs attention: refused login, no internet, no credentials, no agent |
| Wi-Fi with a slash | Wi-Fi is off or not connected |
| Wi-Fi in a circle | not on VIT Wi-Fi |
| pause | auto-login paused |

The menu's first lines say what's going on in words, who's logged in, and the
background agent's latest log entry.

## How it works

Five small Swift files in `WiFiConnector/`:

| File | What it does |
|---|---|
| `WiFiConnectorApp.swift` | The app's entry point (`@main`). Declares two *scenes*: a `MenuBarExtra` (the icon and its menu) and a `Window` for Settings |
| `MenuContent.swift` | The menu. With `.menuBarExtraStyle(.menu)`, SwiftUI turns `Text` into a greyed-out line, `Button` into a menu item, `Toggle` into an item with a checkmark |
| `SettingsView.swift` | The Settings form (`TextField`, `SecureField`, Save) |
| `StatusModel.swift` | The app's state, an `ObservableObject`. Every 3 seconds it runs `wificonnector info`; SwiftUI redraws whatever reads its `@Published` properties when they change |
| `EngineInfo.swift` | Plain Swift with no UI: parses the `info` output and decides the icon, headline and detail line |
| `Engine.swift` | Runs the bundled script and collects its output |

**The script as an engine.** The app talks to the script through a few
commands made for it:

```text
wificonnector info                    # state as key=value lines, no network requests
wificonnector login | logout | pause | resume | install
wificonnector set-credentials 22BCE1234 < password
```

`info` is cheap (it reads a few files and asks launchd and the Keychain about
attributes, never the password), so polling it every 3 seconds costs nothing.

**Passing the password safely.** The Settings window sends the password to
`set-credentials` on stdin. The script hands it to macOS's `security` tool,
which normally prompts on a terminal. `Engine.swift` starts every command
with `POSIX_SPAWN_SETSID`, in a new session with no controlling terminal, so
`security` reads its prompt answers from the pipe instead. The password never
appears in a command line, and the item is created by `security` itself,
exactly like `wificonnector setup` does, so the background agent can read it
without a permission dialog.

**Menu-bar app details:**

- `LSUIElement = YES` in the Info.plist (set through the target's build
  settings in Xcode) hides the Dock icon and the app menu.
- Such an app is never in front on its own, so "Settings…" calls
  `NSApp.activate()` after opening the window, or it would open behind other
  windows.
- `.defaultLaunchBehavior(.suppressed)` keeps the Settings window from
  opening at launch (macOS 15+).
- **Start at Login** uses `SMAppService.mainApp` (ServiceManagement), and the
  app shows up in System Settings ▸ General ▸ Login Items.

**The project file.** `WiFiConnector.xcodeproj` uses a *synchronized folder*
(Xcode 16+): every file in `WiFiConnector/` belongs to the app automatically,
so adding a Swift file needs no project change. A build phase ("Bundle the
wificonnector script") copies `bin/wificonnector` into the app's Resources, so
every build carries the current script.

## Roadmap

The engine moves into Swift one piece at a time, each a step you can try on
its own:

1. **Read the network name.** An app can ask for Location permission, which
   a script can't. Then the "is this VIT?" check reads the real SSID instead of
   "hidden by macOS".
2. **React to network changes instantly** with `NWPathMonitor` instead of
   polling.
3. **Do the login in Swift** with `URLSession`, including the network-DNS and
   gateway fallbacks the script learned the hard way.
4. **Replace the launchd agent** with the app itself, started at login.
