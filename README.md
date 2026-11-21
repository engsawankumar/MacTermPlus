# MacTerm+

**Built by Bairagi.**

## Download

Get the latest version from **[Releases](https://github.com/engsawankumar/MacTermPlus/releases/latest)**:

- **MacTerm+-x.y.z.dmg**: open it and drag **MacTerm+** to **Applications**.
- **MacTerm+-x.y.z.zip**: unzip and move **MacTerm+** to Applications.

Requires macOS 15 or later on Apple Silicon. The app isn't notarized by Apple yet, so the first time:
**right-click MacTerm+ → Open → Open**. After that, **MacTerm+ → Check for Updates…** keeps it current.

A native macOS (Apple Silicon) SSH terminal and SFTP file manager in one window.
Open a server and you get a terminal with a live file browser beside it, plus a two-pane
Mac ↔ server commander with a transfer queue.

## Features

- **All-in-one layout**: a big-icon toolbar, a sidebar rail (Sessions / Files / Macros / Tools / Tunnels), Quick connect, a Home tab, numbered tabs, and a welcome box in each SSH terminal.
- **Protocols**: SSH (terminal + files), SFTP (files only), FTP and FTPS (explicit TLS, or implicit on port 990). FTP uses the libcurl that ships with macOS.
- **Files**: a sidebar browser for the current tab with **Follow terminal folder**, a two-pane Mac ↔ server view, a transfer queue, drag & drop, folder up/download, `..` row, Open With, and edit-and-save-back. All of this works over SFTP and FTP.
- **Server info bar** (Remote monitoring): host, OS, CPU with a graph, memory, network, user, disk, uptime and load.
- **Split view** (2 or 4 terminals) and **MultiExec** (type into all terminals at once).
- **SSH tunnels** (local port forwarding, auto-start), **Macros** (saved commands, run in one or all terminals), **Tools** (SSH key generator, install your public key on a server, port checker).
- **Sync across Macs** through iCloud Drive, Google Drive (desktop app), Dropbox, OneDrive or any folder. Sessions, macros and tunnels merge automatically, with a device list. Passwords can optionally sync end-to-end encrypted (PBKDF2 + AES-256-GCM, passphrase never uploaded).
- **Import**: automatic scan of this Mac for sessions saved by other SSH, SFTP and FTP apps (including Windows apps running in compatibility bottles), Keychain logins and ~/.ssh/config, plus import from common session files and CSV. **Export**: JSON, OpenSSH config or CSV.
- **Look**: 17 terminal themes, fonts, padding, icon styles (Monochrome / Colorful / Vivid), accent colors, light/dark mode.
- **Keychain**: export sessions with passwords to Apple's Passwords app (iCloud Keychain) and import them back; import SSH/FTP logins other apps saved in the keychain; direct iCloud Keychain storage on Developer ID builds.
- **Per-session colors & terminal themes**, with session-colored tabs.
- **File management**: a full toolbar, permission manager (chmod, recursive, presets), file info with owner/group, recent folders, filter.
- **Updates**: Check for Updates from GitHub Releases, with daily auto-check and verified in-place install.
- **Security**: secrets only in the Keychain; host keys are trusted on first use and a changed key is refused.

## Build

Requires macOS 15+ on Apple Silicon, with Xcode or just the Command Line Tools (`xcode-select --install`).

```bash
./scripts/build-app.sh        # → dist/MacTerm+.app
open "dist/MacTerm+.app"
```

During development: `swift build && .build/debug/MacTermPlus`

### Self-tests (no UI)

```bash
.build/debug/MacTermPlus --selftest HOST PORT USER ~/.ssh/id_ed25519     # SSH shell + SFTP
.build/debug/MacTermPlus --ftptest HOST PORT USER PASSWORD ftp|ftps [insecure]
.build/debug/MacTermPlus --scan-test                                     # installed clients
```

### Connection self-test (no UI)

```bash
.build/debug/MacTermPlus --selftest <host> <port> <user> <~/.ssh/id_ed25519 | password:SECRET>
```

The self-test checks login, an interactive shell, and SFTP list, upload, download (compared byte-for-byte) and delete. It uses a temporary folder under `/tmp` on the server.

## Shortcuts

| Keys | Action |
|---|---|
| ⌘N | New session |
| ⌘T | New local shell |
| ⇧⌘W | Close tab |
| ⇧⌘] / ⇧⌘[ | Next / previous tab |

## Project layout

```
Sources/MacTermPlus/
  App/        app entry, window, tabs, session editor, self-test
  Models/     saved sessions (JSON) and Keychain storage
  SSH/        connection handling and host key checking
  Terminal/   SSH and local terminal views (SwiftTerm)
  Files/      SFTP/local browsers, transfer queue, file UI
  Settings/   preferences, terminal themes, Settings window
  Stats/      server info bar (polling + view)
  Import/     importers for other apps, exporter, import/export sheets
  Help/       in-app help (also generates docs/USER_GUIDE.md)
  Sync/       multi-device sync (cloud folder + encrypted password vault)
  Tools/      tunnels, macros
Sources/CCurlShim/  tiny C wrapper around the system libcurl (FTP/FTPS)
docs/         USER_GUIDE.md
scripts/      build-app.sh, make-icon.swift, update-notices.sh
```

User data is stored in `~/Library/Application Support/MacTermPlus/` (`sessions.json`, `known_hosts.json`). Secrets are kept only in the Keychain.

## Licensing

All of the code is original. The dependencies are permissive: SwiftTerm and Citadel (MIT), and SwiftNIO, swift-nio-ssh and swift-crypto (Apache-2.0). Their notices are in `THIRD_PARTY_NOTICES.md` and are copied into the app bundle. Run `./scripts/update-notices.sh` after changing dependencies.

## Welcome window messages

The Welcome window shows messages from [`announcements.json`](announcements.json): edit it on GitHub to
publish news, tips or sponsored messages without releasing a new version. Format: [docs/ANNOUNCEMENTS.md](docs/ANNOUNCEMENTS.md).

## iCloud Keychain (Developer ID builds)

Writing to iCloud Keychain requires an app signed with an Apple Developer ID and the Keychain Sharing entitlement (a provisioning profile for your bundle ID). With those:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" TEAM_ID=TEAMID \
PROVISIONING_PROFILE=~/Downloads/MacTermPlus.provisionprofile ./scripts/build-app.sh
```

Without them, the Passwords-app export/import (Settings → Keychain) gets sessions into iCloud Keychain instead.

## Publishing an update (GitHub Releases)

The app checks `https://github.com/<GITHUB_REPO>/releases/latest` and installs newer versions in place
(SHA-256 verified). One-time setup:

1. Create the GitHub repository and set `GITHUB_REPO=<you>/MacTermPlus` in `release.config`.
2. `brew install gh && gh auth login`

For each release:

```bash
echo 0.5.1 > VERSION                     # bump the version
# add a "## 0.5.1" section to CHANGELOG.md (shown to users as "What's new")
./scripts/release.sh                     # builds, zips, checksums, creates the GitHub release
```

Or let GitHub build it: commit, then `git tag v0.5.1 && git push --follow-tags`. The workflow in
`.github/workflows/release.yml` builds on a macOS runner and publishes the release.

`./scripts/release.sh --dry-run` builds and packages without publishing.

Users install the first time from the release page (unzip → move to Applications → right-click → Open,
because the build isn't notarized). After that, **MacTerm+ → Check for Updates…** handles it.

## Distribution

`build-app.sh` signs the app ad-hoc, which is fine on your own Mac. To share it with others, sign it with an Apple Developer ID and notarize it. Without that, Gatekeeper will block the app on other people's Macs.

## Regenerating the user guide

```bash
swift build && .build/debug/MacTermPlus --export-help docs/USER_GUIDE.md
```

## Roadmap

Remote/dynamic (SOCKS) tunnels, jump hosts, ssh-agent support, folder sync with a diff preview, X11 forwarding via XQuartz, and RDP/VNC launchers.
