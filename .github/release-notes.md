Automatic login to VIT hostel Wi-Fi, from your Mac's menu bar. Needs macOS 15 or later; works on Apple silicon and Intel Macs.

## What's new in 0.3.1

- **The welcome window now opens by itself** the first time you open the app. In 0.3.0 you had to choose **Set Up…** from the menu-bar icon.

## What's new in 0.3.0

- **One-command install.** Paste one line in Terminal; there's no security warning to get past.
- **A welcome window.** It opens on first launch and does the whole setup with one button: saves your password, turns on automatic login and Start at Login, and logs you in.
- **Logs in again after sleep.** Right after the Mac wakes, it now waits for the network to come back instead of giving up for two minutes.

## Install

Open Terminal (⌘ Space, type Terminal, press Return), paste this and press Return:

```sh
curl -fsSL https://anujbajaj4.github.io/wificonnector/install.sh | bash
```

It installs the app into Applications and opens it, with no security warning. In the welcome window, type your registration number and Wi-Fi password and click **Save and Turn On**. That's all: it logs you in by itself from now on, and its Wi-Fi icon sits at the top right of the menu bar. If you can't see the icon, the notch may be hiding it.

### Or download it yourself

1. Download **WiFiConnector.dmg** below and open it, then drag **WiFiConnector** onto **Applications**.
2. Open WiFiConnector from Applications. macOS says it can't verify the app, because it isn't signed with a paid Apple Developer ID. Click **Done**, not Move to Trash.
3. Open **System Settings ▸ Privacy & Security**, scroll down, and click **Open Anyway** next to WiFiConnector. You only do this once.
4. Fill in the welcome window.

The app is open source. You can read every line it runs at https://github.com/anujbajaj4/wificonnector.
