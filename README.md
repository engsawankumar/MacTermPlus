<div align="center">

<img src="docs/images/icon.png" width="128" alt="MacTerm+ icon">

# MacTerm+

**SSH terminal, SFTP & FTP file manager, tunnels and tools — in one window.**<br>
A native app for Macs with Apple Silicon. Built by Bairagi.

[![Latest release](https://img.shields.io/github/v/release/engsawankumar/MacTermPlus?label=download&color=0a84ff)](https://github.com/engsawankumar/MacTermPlus/releases/latest)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-34c759)
![Free](https://img.shields.io/badge/price-free-ff9f0a)

### [⬇︎ Download MacTerm+](https://github.com/engsawankumar/MacTermPlus/releases/latest)

<img src="docs/images/main.png" alt="MacTerm+ with an SSH terminal, the server's files in the sidebar and live server stats" width="900">

</div>

---

## Why MacTerm+

- **One window for your servers.** Open a server and you get a terminal, its files next to it,
  and live health stats underneath, all over a single secure connection.
- **Every common protocol:** SSH, SFTP, FTP and FTPS.
- **Feels at home on the Mac.** Native, fast on Apple Silicon, light and dark mode, Keychain for passwords.
- **Brings your sessions along.** It finds the sessions you already saved in other SSH/FTP apps and imports them in a few clicks.
- **Keeps itself up to date.** New versions install from inside the app.

## Features

| Feature | What you get |
|---|---|
| 🖥 **Terminal** | Tabs, split view (2 or 4 terminals), 17 color themes, per-server themes, copy & paste with preview, macros |
| 📁 **Files** | File browser beside the terminal, two-pane Mac ↔ server view, drag & drop, upload and download whole folders, edit any file in your favorite Mac app |
| 🔐 **Permissions** | Change file permissions with checkboxes, presets or octal values, for one file or a whole folder |
| 📊 **Server info** | CPU graph, memory, network speed, disk space, uptime and the server's OS at a glance |
| 🔀 **Tunnels** | Reach databases and admin pages behind a server through a port on your Mac |
| ⌨️ **MultiExec** | Type once, run in every open terminal |
| ⬇️ **Import** | Finds sessions saved by other apps on this Mac (including Windows apps in compatibility layers), plus `~/.ssh/config`, CSV and the Passwords app |
| ☁️ **Sync** | Keep sessions, macros and tunnels the same on all your Macs with iCloud Drive or Google Drive; passwords optional and end-to-end encrypted |
| 🎨 **Make it yours** | Colors and OS icons for servers, fonts, padding, icon styles, accent colors |

## Screenshots

<table>
<tr>
<td width="50%"><img src="docs/images/files.png" alt="Two-pane file manager"><br><sub><b>Two-pane files:</b> your Mac on the left, the server on the right.</sub></td>
<td width="50%"><img src="docs/images/sessions.png" alt="Sessions with OS icons"><br><sub><b>Sessions:</b> folders, colors and the server's OS at a glance.</sub></td>
</tr>
<tr>
<td width="50%"><img src="docs/images/welcome.png" alt="Welcome window"><br><sub><b>Welcome:</b> get started in one click.</sub></td>
<td width="50%"><img src="docs/images/themes.png" alt="Terminal themes"><br><sub><b>Themes:</b> 17 terminal color themes, fonts and more.</sub></td>
</tr>
</table>

## Install

1. **Download** `MacTerm+-x.y.z.dmg` from the [latest release](https://github.com/engsawankumar/MacTermPlus/releases/latest).
2. **Open** the DMG and **drag MacTerm+ to Applications**.
3. **Open MacTerm+** from Applications or Launchpad.

**The first time you open it**, macOS may say it can't check MacTerm+ for malicious software, because the
app isn't distributed through the App Store. To open it anyway:

1. Click **Done** in that message.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the message about MacTerm+ and click **Open Anyway**, then confirm.

You only do this once; updates from inside the app open normally.

**Requirements:** a Mac with Apple Silicon (M1 or newer) and macOS 15 Sequoia or later.

## Getting started

- **Add a server:** click **Session** (or press ⌘N), enter the host, user name and password or key, then **Save & Connect**.
- **Import what you have:** press ⇧⌘I. MacTerm+ lists the sessions it found on your Mac; tick the ones you want.
- **Quick connect:** type `user@host` (or `sftp://…`, `ftp://…`) into the field at the top of the sidebar and press Return.
- **Learn more:** press ⌘? for the built-in guide, or read the [User guide](docs/USER_GUIDE.md).

| Shortcut | Action |
|---|---|
| ⌘N | New session |
| ⌘T | New local shell |
| ⇧⌘I | Import sessions |
| ⇧⌘W | Close tab |
| ⇧⌘] / ⇧⌘[ | Next / previous tab |
| ⌘, | Settings |
| ⌘? | Help |

## Updates

MacTerm+ checks for new versions once a day. You can also choose **MacTerm+ → Check for Updates…** at any time.
Updates are downloaded from this page, checked against a published checksum and the developer's signature,
and installed with one click. Your sessions and settings stay as they are.

## Privacy & security

- Passwords stay on your Mac: in the **macOS Keychain**, or in an optional **MacTerm+ encrypted vault** unlocked with one master password (Settings → Passwords).
- Updates and Welcome news are **download-only**: MacTerm+ never sends your sessions, server names or passwords anywhere.
- Server identities are remembered on first connect; if a server's key ever changes, MacTerm+ warns you and doesn't connect.
- Sync only writes to **your own** iCloud Drive or Google Drive folder. Passwords sync only if you turn it on, encrypted with a passphrase that never leaves your Macs.
- No accounts, no tracking. The app contacts GitHub only to check for updates and, if you leave it on, Welcome window news.

## FAQ

<details>
<summary><b>macOS asks for my Keychain password after an update</b></summary>

Update to 1.0.6 or later and choose **Always Allow** one last time if asked. From 1.0.6, all passwords live in
one Keychain item that belongs to MacTerm+, so macOS stops asking, including after updates. Prefer no Keychain prompts at all? Switch to the **MacTerm+ encrypted vault**
in Settings → Passwords.
</details>

<details>
<summary><b>“keyExchangeNegotiationFailure” or “no encryption method in common”</b></summary>

Some older routers and devices only offer older SSH algorithms. Make sure
**Settings → Terminal → Connections → Allow older SSH algorithms** is on (it is by default) and update
to the latest MacTerm+.
</details>

<details>
<summary><b>Can I use an SSH key instead of a password?</b></summary>

Yes. In the session, choose **Private key** and pick your key (Ed25519 or RSA, OpenSSH format).
**Tools → Generate Key** creates one, and **Install my public key** adds it to a server.
</details>

<details>
<summary><b>Does it work on Intel Macs?</b></summary>

Not at the moment. MacTerm+ is built for Apple Silicon.
</details>

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/engsawankumar/MacTermPlus/issues). It helps a lot.

## Credits

**MacTerm+ is built by Bairagi.** It uses a few open-source components; see [Third-party notices](THIRD_PARTY_NOTICES.md).

Developers: build, signing and release instructions are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
