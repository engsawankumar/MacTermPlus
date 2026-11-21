# MacTerm+ — Developer guide

Everything needed to build, test, sign and release MacTerm+. For using the app, see the
[README](../README.md) and the [User guide](USER_GUIDE.md).

- [Requirements](#requirements)
- [Build and run](#build-and-run)
- [Self-tests](#self-tests)
- [Project layout](#project-layout)
- [Code signing](#code-signing)
- [Releasing an update](#releasing-an-update)
- [Welcome window messages](#welcome-window-messages)
- [README screenshots](#readme-screenshots)
- [iCloud Keychain (Developer ID builds)](#icloud-keychain-developer-id-builds)
- [Dependencies and licenses](#dependencies-and-licenses)
- [Roadmap](#roadmap)

## Requirements

- macOS 15 or later on Apple Silicon.
- Swift 6.2 or newer: Xcode, or just the Command Line Tools (`xcode-select --install`).
  The project builds without full Xcode: `@State` is used through a `ViewState` alias because the
  Command Line Tools ship without SwiftUI's macro plugin.

## Build and run

```bash
./scripts/build-app.sh            # → dist/MacTerm+.app (version from ./VERSION)
open "dist/MacTerm+.app"
```

During development:

```bash
swift build && .build/debug/MacTermPlus
```

User data lives in `~/Library/Application Support/MacTermPlus/` (`sessions.json`, `known_hosts.json`,
`macros.json`, `tunnels.json`). Passwords and key passphrases are stored only in the Keychain.

## Self-tests

Headless checks that exercise the same code as the app:

```bash
.build/debug/MacTermPlus --selftest HOST PORT USER ~/.ssh/id_ed25519      # SSH login, shell, SFTP files, chmod
.build/debug/MacTermPlus --selftest HOST PORT USER password:SECRET
.build/debug/MacTermPlus --ftptest HOST PORT USER PASSWORD ftp|ftps [insecure]
.build/debug/MacTermPlus --scan-test                                      # importable sessions on this Mac
.build/debug/MacTermPlus --import-test FILE                               # parse one import file
.build/debug/MacTermPlus --distro-test                                    # OS badge detection
```

The SSH/FTP tests create and remove a temporary folder on the server and compare uploads and downloads
byte-for-byte.

## Project layout

```
Sources/MacTermPlus/
  App/        app entry, window, tabs, sidebar, session editor, self-tests, showcase mode
  Models/     saved sessions (JSON) and Keychain storage
  SSH/        connection handling and host-key checking
  Terminal/   SSH and local terminal views (SwiftTerm), right-click menu, MultiExec
  Files/      SFTP / FTP / local browsers, transfer queue, permissions, file UI
  Settings/   preferences, terminal themes, Settings window
  Stats/      server info bar and OS detection
  Import/     importers, exporter, installed-app scanner
  Sync/       multi-Mac sync (cloud folder + encrypted password vault)
  Tools/      tunnels, macros
  Update/     GitHub Releases updater
  Welcome/    Welcome window and announcements
  Help/       in-app help (also generates docs/USER_GUIDE.md)
Sources/CCurlShim/   small C wrapper around the system libcurl (FTP/FTPS)
scripts/             build-app.sh, release.sh, setup-signing.sh, make-icon.swift, update-notices.sh
docs/                user guide, announcements format, this file, screenshots
```

Regenerate the user guide after editing the in-app help:

```bash
swift build && .build/debug/MacTermPlus --export-help docs/USER_GUIDE.md
```

## Code signing

Run once on the Mac you release from:

```bash
./scripts/setup-signing.sh
```

It creates a permanent signing certificate in its own keychain file (`~/.macterm-signing/`), and
`build-app.sh` signs every build with it. Because the signature stays the same, macOS keeps users'
Keychain **Always Allow** choices and folder permissions after updates, and the in-app updater refuses
updates signed by anyone else.

> **Back up `~/.macterm-signing/`** (it contains the private key) and never commit it. Every release
> must be signed with the same certificate; a new one makes every user's Mac ask for permissions again.

The certificate isn't issued by Apple, so first-time installs still need the Gatekeeper step described
in the README. Signing with an Apple **Developer ID** and notarizing would remove that step.

## Releasing an update

The app checks `https://github.com/<GITHUB_REPO>/releases/latest` (from `release.config`) and installs
newer versions in place after verifying the SHA-256 checksum and the signer.

One-time setup: `brew install gh && gh auth login`.

For each release:

```bash
echo 1.0.5 > VERSION                     # bump the version
# add a "## 1.0.5" section to CHANGELOG.md — shown to users as "What's new"
./scripts/release.sh                     # build, sign, DMG + zip, checksums, GitHub release
```

`./scripts/release.sh --dry-run` builds and packages without publishing. The script refuses to publish
builds that aren't signed with the permanent identity.

GitHub Actions (`.github/workflows/`) compile every push on macOS 26 runners as a check. A tagged build on
GitHub doesn't publish, because the signing certificate stays on your Mac.

## Welcome window messages

The Welcome window shows messages from [`announcements.json`](../announcements.json) on the `main`
branch. Edit it on GitHub to publish news, tips or sponsored messages without a new release.
Format: [ANNOUNCEMENTS.md](ANNOUNCEMENTS.md).

## README screenshots

Screenshots come from a built app in **showcase mode**, which shows made-up servers, files and stats,
makes no network connections, and refuses to run unless it has its own data folder:

```bash
APP="dist/MacTerm+.app/Contents/MacOS/MacTermPlus"; OUT=/tmp/shots; mkdir -p $OUT
MTP_SHOWCASE=1 MTP_DATA_DIR=/tmp/mtp-showcase MTP_SHOWCASE_OPEN=1 MTP_WINDOW_SIZE=1500x900 \
  MTP_DELAY=6 MTP_SNAPSHOT=$OUT/main.png MTP_QUIT=1 "$APP"
```

Other options: `MTP_MODE=files` (two-pane view), `MTP_PANEL=sessions`, `MTP_OPEN=welcome|settings`,
`MTP_SETTINGS_TAB=terminal`, `MTP_LOCAL_DIR=<folder for the Mac pane>`. Resize with `sips -Z 1600`
and save to `docs/images/`.

## iCloud Keychain (Developer ID builds)

Writing directly to iCloud Keychain requires a Developer ID signature with the Keychain Sharing
entitlement (a provisioning profile for the bundle ID):

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" TEAM_ID=TEAMID \
PROVISIONING_PROFILE=~/Downloads/MacTermPlus.provisionprofile ./scripts/build-app.sh
```

Without it, users can move sessions into iCloud Keychain through the Passwords app
(Settings → Keychain → Export for Passwords App).

## Dependencies and licenses

All app code is original. Dependencies are permissive: SwiftTerm and Citadel (MIT); SwiftNIO,
swift-nio-ssh and swift-crypto (Apache-2.0). FTP uses the libcurl that ships with macOS.
Notices are in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) and are copied into the app bundle;
run `./scripts/update-notices.sh` after changing dependencies.

## Roadmap

Remote and dynamic (SOCKS) tunnels, jump hosts, ssh-agent support, folder sync with a diff preview,
X11 forwarding, CBC ciphers for very old devices, and RDP/VNC launchers.
