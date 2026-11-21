# MacTerm+ User Guide

_This guide is generated from the in-app Help (Help → MacTerm+ Help)._

- [Getting Started](#getting-started)
- [Sessions](#sessions)
- [Terminal](#terminal)
- [Files & Transfers](#files--transfers)
- [Server Info Bar](#server-info-bar)
- [Import & Export](#import--export)
- [Window Layout](#window-layout)
- [SSH, SFTP, FTP & FTPS](#ssh,-sftp,-ftp--ftps)
- [Split & MultiExec](#split--multiexec)
- [SSH Tunnels](#ssh-tunnels)
- [Macros & Tools](#macros--tools)
- [Sync Across Macs](#sync-across-macs)
- [Keychain & iCloud Keychain](#keychain--icloud-keychain)
- [Updates](#updates)
- [Settings](#settings)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Troubleshooting](#troubleshooting)

## Getting Started

### About

MacTerm+ is built by **Bairagi**. Version and licenses: **MacTerm+ → About MacTerm+**.

### Welcome

MacTerm+ combines an SSH terminal with an SFTP/FTP file manager, tunnels, macros, multi-terminal tools and sync across your Macs. Connect once and you get a terminal, a file browser for the same server, and a live server-info bar, all over one secure connection.

### Add your first server

1. Click **+** at the bottom of the sidebar (or press **⌘N**).
2. Enter **Host**, **Port** (usually 22) and **Username**.
3. Choose **Password** or **Private key**. Tick **Save in Keychain** so you aren't asked every time.
4. Click **Save & Connect**.

### Connect to a saved server

Double-click the session in the sidebar, or right-click it → **Connect**. A green dot next to a session means it's open in a tab.

### Already using another app?

Press **⇧⌘I** to import sessions from other SSH, SFTP and FTP apps, a spreadsheet (CSV) or your ~/.ssh/config. See **Import & Export**.

## Sessions

### Folders

Type a **Folder** name in the session editor to group sessions. Use slashes for sub-folders, e.g. `Clients/Acme`. Click a folder header to collapse it.

### OS icons

After you connect once, MacTerm+ remembers the server's operating system and shows its badge on the session in the sidebar (with a small dot in the session's color). Turn it off in Settings → General → Show the server's OS icon.

### Colors & themes

Give each session a **color** (editor, or right-click → **Color**): it tints the sidebar icon and the session's tab. Each session can also have its own **terminal theme** (editor → Terminal theme, or right-click → **Terminal Theme**), for example a red theme for production. Turn tab coloring off in Settings → General.

### Passwords & keys

Secrets are stored only in the **macOS Keychain**, never in MacTerm+'s files. Keys must be in OpenSSH format (Ed25519 or RSA). To create one: `ssh-keygen -t ed25519`. If the session has no saved password, you're asked when connecting.

### Context menu

Right-click a session to **Connect, Edit, Duplicate**, change its **Color**, **Copy SSH Command** (ready to paste into any terminal), **Forget Host Key**, or **Delete** it.

### Host key security

The first time you connect, the server's key is remembered. If it ever changes, MacTerm+ refuses to connect and warns you, because that can mean someone is intercepting the connection. If you know the server was reinstalled, right-click → **Forget Host Key** and connect again.

## Terminal

### Tabs

Every connection opens in its own tab. **⌘T** opens a local shell on your Mac. **⇧⌘]** and **⇧⌘[** switch tabs; **⇧⌘W** closes the current one.

### Copy & paste

Select text with the mouse, then **⌘C** / **⌘V**, or **right-click** the terminal: the menu shows **Copy**, **Paste** (with a preview of what's on the clipboard), Paste Selection, Select All, Clear Scrollback, Send Ctrl-C, **Run Macro**, and text size. Pasting several lines first shows the text and asks before sending it, because each line may run as a command (turn this off in Settings → Terminal). ⌘-click a link to open it.

### Reconnect

When a session ends (you typed `exit`, the network dropped, or the server restarted), a **Reconnect** button appears in the tab toolbar.

### Look & feel

Open **Settings → Terminal** (⌘,) to pick from 17 color themes, change the font and size, and choose the cursor style. Changes apply to open terminals immediately.

### Option key

By default Option works as **Meta** (useful in Emacs, or for Alt+key shortcuts in tmux). If you type characters like @ or € with Option, turn this off in **Settings → Terminal**.

## Files & Transfers

### File panel

Sidebar → **Files** shows the current tab's server files (SSH, SFTP or FTP). The toolbar's **Files** button opens it too. Double-click a folder to open it, or **..** to go back to the parent folder. Type a path in the path field and press Return to jump there.

### Two-pane Files view

Switch the tab to **Files** for a two-pane view: your Mac on the left, the server on the right. Select files and click → to upload or ← to download. Progress shows in **Transfers** at the bottom.

### Drag & drop

Drag files or folders from Finder onto the server pane to upload them. Folders are copied with everything inside.

### Edit remote files

Double-click a remote file to open it in your default Mac app (TextEdit or any code editor). Each time you save, MacTerm+ uploads the change automatically while the tab stays open.

### Open With

Right-click any file → **Open With** to choose the app: the default app is listed first, then other apps for that file type, installed code editors and **Other…**. For server files, MacTerm+ downloads a copy, opens it in that app, and uploads every save back.

### File toolbar

Above every file list: **Up**, **Home**, **Refresh**, **Download**, **Upload**, **New Folder**, **New File**, **Rename**, **Delete**, **Info**, **Permissions**, **Edit**, **Show hidden files**, **Filter** (type to narrow the list) and **Copy path**. The clock button next to the path lists recently visited folders.

### Permissions (chmod)

Select files or folders → **Permissions** (toolbar or right-click). Tick Read/Write/Execute for Owner, Group and Others, or type the octal value (e.g. 755), or pick a **preset** (644 files, 755 folders/scripts, 600 private keys…). For folders, **Apply to everything inside** changes the whole tree. Works over SFTP, FTP (via SITE CHMOD, if the server allows it) and on this Mac.

### Permission denied? Browse as root

If the server says **Permission denied**, the user you logged in as can't open or change that folder. If you have **sudo** rights, click **Open as root (sudo)…** in the message, or turn on **Browse as root (sudo)** at the bottom of the Files panel. A red **ROOT** badge shows while it's on. MacTerm+ asks for your sudo password if needed (usually your login password), keeps it only in memory for that tab, and sends it over the encrypted connection, never on the command line. Turn the switch off to go back to your normal user. Be careful: as root you can change system files.

### File info

**Info** shows the full path, size, modified date, permissions (with the octal value), owner and group.

### Other actions

Right-click files for **Rename, Download, Copy Path, Delete**. The eye button shows hidden (dot) files. Server deletes ask first; you can change this in **Settings → Files**.

## Server Info Bar

### What it shows

Under every SSH tab: host name, **OS with a distro badge** (Ubuntu, Debian, Raspberry Pi OS, Fedora, CentOS, RHEL, Rocky, Alma, Arch, Alpine, openSUSE, Mint, Kali, Proxmox and more), **CPU %** with a live graph, **memory**, **network** download/upload speed, **user** (red when root), **disk usage** of / (red above 90%), **total disk** and **free disk** (red below 10% free), **uptime** and **load average**.

### How it works

MacTerm+ runs one small read-only command over your existing connection every few seconds (it reads `/proc` on Linux). Nothing is installed on the server.

### Customize

**Settings → Status Bar** lets you turn the bar off, choose which items appear, and set the refresh interval (2–30 s).

### Non-Linux servers

On macOS, BSD or routers, fewer items are available. Items that can't be read are hidden automatically.

## Import & Export

### Import (automatic)

**File → Import Sessions…** (⇧⌘I) scans this Mac for saved sessions and lists what it finds, with the number of sessions in each: SSH/SFTP/FTP apps on the Mac, Windows apps running in compatibility bottles, server logins in the Keychain, and `~/.ssh/config`. Tick what you want, click **Continue**, review the sessions (ones you already have are unticked) and click **Import**. Passwords are never copied; you'll be asked once when connecting.

### Import from a file (Advanced)

If your sessions are somewhere else, for example a file copied from a Windows PC, click **Import from a File… (Advanced)**, pick the format (or Auto-detect) and choose the file or folder.

### Supported formats

• **Session bookmarks** (`.mxtsessions` or the matching `.ini`): SSH, SFTP and FTP entries; usernames stored as saved credentials are resolved (passwords are not).
• **Registry sessions** (`.reg` export, or a bottle's `user.reg`): saved SSH and SFTP sessions.
• **Session list** (`.ini`): SFTP, SCP, FTP and FTPS sites, with folders kept.
• **Site manager** (`sitemanager.xml`): SFTP, FTP and FTPS sites.
• **Router address book** (`Addresses.cdb`): imported as SSH sessions on port 22, best effort.
• **Spreadsheet (CSV)** with a header row such as `Label,Group,Hostname,Port,Username`.
• **Passwords app** export (CSV) and **MacTerm+** JSON exports.

### Apps with encrypted storage

Some apps keep their hosts in an encrypted vault that other apps can't read. MacTerm+ shows that the app was found; export your hosts from it as CSV or SSH config, then use **Import from a File**.

### OpenSSH config

Choose **OpenSSH config → Use ~/.ssh/config**. Each `Host` entry becomes a session; `IdentityFile` sets key login.

### Export

**File → Export Sessions…** (⇧⌘E) saves **MacTerm+ JSON** (complete, for backup or moving to another Mac), an **OpenSSH config**, or **CSV**. Passwords are never exported.

## Window Layout

### Toolbar

The big buttons along the top: **Session** (new), **Sessions**, **Files**, **Terminal** (local shell), **View** (hide or show the sidebar), **Split**, **MultiExec**, **Tunneling**, **Macros**, **Tools**, **Sync**, **Settings**, **Help** and **Exit**. Settings → General → Icon style changes how the icons look.

### Sidebar

The vertical tabs on the left switch the sidebar between **Sessions**, **Files** (the server's files for the current tab), **Macros**, **Tools** and **Tunnels**. When you connect, the sidebar switches to Files automatically (you can turn this off per session).

### Quick connect

Type into the field at the top of the sidebar and press Return: `root@192.168.1.10`, `admin@host:2222`, `sftp://user@host`, `ftp://user@ftp.example.com` or `ftps://…`. If a saved session matches, its password or key is used.

### Home tab & tabs

The house button returns to the Home screen with your recent sessions. Tabs are numbered; SFTP/FTP tabs show a small protocol badge.

### Follow terminal folder

With **Follow terminal folder** ticked (bottom of the Files panel), the file browser moves along when you `cd` in the terminal (bash and zsh). MacTerm+ installs a tiny prompt hook in the shell session for this. Nothing is changed on the server permanently.

### Remote monitoring

The bar under SSH tabs shows CPU, memory, network, disk and more. Toggle it with **Remote monitoring** in the Files panel or in Settings → Status Bar.

## SSH, SFTP, FTP & FTPS

### Session types

In the session editor pick the **Protocol**:
• **SSH**: terminal + file browser over one secure connection.
• **SFTP**: files only, over SSH (no terminal).
• **FTP**: classic FTP. Not encrypted, so passwords travel in clear text. Use it only on trusted networks.
• **FTPS**: FTP over TLS (encrypted). Port 21 uses explicit TLS; port 990 uses implicit TLS.

### Self-signed certificates

If an FTPS server uses a self-signed certificate, tick **Accept invalid / self-signed certificates** in the session. Only do this for servers you trust.

### Anonymous FTP

Leave the username empty to log in anonymously.

### What works over FTP

Browsing, upload/download (including whole folders), drag & drop, rename, new folder, delete, Open With and edit-and-save-back all work over FTP and FTPS, just as with SFTP. Terminal, tunnels and the server info bar need SSH.

## Split & MultiExec

### Split

**Split** in the toolbar shows 2 terminals side by side or stacked, or 4 in a grid: the current terminal plus the next open ones. Click a pane's title bar to make it current. Choose **Single** to go back.

### MultiExec

Turn on **MultiExec** to type into **all open terminals at once**: handy for running the same command on several servers. A pink banner reminds you it's on. Turn it off before typing anything server-specific.

## SSH Tunnels

### What a tunnel does

A tunnel opens a port on this Mac and forwards it through an SSH server to a host and port the server can reach. It's like `ssh -L`. Example: forward local port **5433** to **127.0.0.1:5432** through your database server, then point your database app at `localhost:5433`.

### Create one

Sidebar → **Tunnels** → **New Tunnel**: pick the SSH session, the local port, and the destination host and port. Press ▶ to start and ■ to stop. Tick **Start automatically** to open it when MacTerm+ starts.

### Requirements

The session must use a private key, or have its password saved in the Keychain, because tunnels run in the background without asking. If the local port is already used by another app, pick another one.

## Macros & Tools

### Macros

Sidebar → **Macros** holds saved commands. Double-click (or ▶) sends one to the current terminal; right-click → **Run in All Terminals** sends it everywhere. **New Macro** adds your own; multi-line commands run line by line. A few useful ones are included to start with.

### SSH key generator

Sidebar → **Tools** → **Generate Key…** creates an Ed25519 key pair in `~/.ssh` (with an optional passphrase).

### Install my public key

With an SSH tab open, **Install on Current Server** adds your public key to the server's `~/.ssh/authorized_keys` (only if it isn't already there). Then switch the session to **Private key** to log in without a password.

### Port checker

Checks whether a TCP port on any host can be reached from this Mac, and how fast it answers.

## Sync Across Macs

### How it works

MacTerm+ keeps a small file (`MacTermPlus/sync.json`) in a cloud folder you choose. Each Mac reads it, merges it with its own sessions, macros and tunnels, and writes the result back. Changes from different Macs combine; for the same session the newest edit wins, and deletions sync too.

### iCloud Drive

Turn on iCloud Drive in System Settings → Apple Account → iCloud. Then in MacTerm+: **Settings → Sync** → iCloud Drive → **Use**. Do the same on your other Macs.

### Google Drive

Install **Google Drive for desktop** and sign in. Your Drive then appears in **Settings → Sync**; click **Use**. Dropbox, OneDrive and Box are detected the same way, or click **Choose Folder…** for any folder that your cloud app syncs.

### Passwords

Passwords are **not** synced unless you turn on **Also sync saved passwords** and set a **sync passphrase**. They are then encrypted with AES-256 using a key derived from your passphrase before they reach the cloud folder. Use the same passphrase on every Mac; it is kept in each Mac's Keychain and never uploaded.

### Devices

**Settings → Sync** lists every Mac that has synced, with when it last synced. The **Sync** toolbar button shows the status and has **Sync Now**. Sync also runs automatically a moment after every change, and checks for changes from other Macs every 30 seconds.

## Keychain & iCloud Keychain

### Where passwords live

Choose in **Settings → Passwords**:
• **macOS Keychain** (default): all passwords are kept in **one** Keychain item. After each MacTerm+ update, macOS asks **once** whether the new version may use it; choose **Always Allow**. (Apps without an Apple-issued developer Team ID are re-approved by macOS after every update.)
• **MacTerm+ encrypted vault**: passwords are kept in an encrypted file (AES-256) that only MacTerm+ reads. You type a **master password** once each time MacTerm+ opens, and there are no Keychain prompts. Switching moves your saved passwords across automatically.
If you forget the master password, the vault's passwords can't be recovered; **Forgot Master Password** erases them so you can start again (your sessions stay).

### Privacy

MacTerm+ only downloads from GitHub: the update check and, if enabled, Welcome-window news (Settings → General → Privacy). It never sends your sessions, server names, user names or passwords anywhere.

### Passwords app = iCloud Keychain

To get your servers into iCloud Keychain: **Settings → Keychain → Export for Passwords App…**, then in the **Passwords** app choose **File → Import Passwords…** and pick the file. Your servers (with passwords) then sync to all your Apple devices. Delete the exported CSV afterwards; it contains passwords in plain text.

### Import from iCloud Keychain

On another Mac: in **Passwords**, **File → Export All Passwords…**; then in MacTerm+ **Import → Import from a File → Passwords app**. Only entries whose website starts with `ssh://`, `sftp://`, `ftp://` or `ftps://` become sessions, and their passwords go straight into the Keychain.

### Servers saved by other apps

Import also lists SSH/SFTP/FTP logins that Finder and other apps saved in your keychain (including iCloud Keychain items). With **Copy their passwords** ticked, macOS asks you to allow each one.

### Direct iCloud Keychain storage

Apple only lets apps signed with a paid **Apple Developer ID** (with the Keychain Sharing capability) save items into iCloud Keychain themselves. Builds made with `build-app.sh` are signed for your Mac only, so this option is shown as unavailable. If you sign with a Developer ID (see the README), **Store session passwords in iCloud Keychain** and **Save Session List to iCloud Keychain** switch on automatically.

## Updates

### Check for updates

**MacTerm+ → Check for Updates…** asks GitHub for the newest release. If one is available you see what's new and can click **Install & Relaunch**. MacTerm+ downloads it, checks it against the published SHA-256 checksum, makes sure it really is MacTerm+ and newer, swaps itself and restarts. Your sessions and settings are kept.

### Automatic checks

**Settings → General → Updates → Check for updates automatically** looks once a day at launch and only shows a window when there is something new. **Skip This Version** hides a release you don't want.

### Where updates come from

Updates come from the GitHub repository shown in Settings → General → Updates (set when the app was built). Nothing else is sent: just a request to GitHub's public releases page.

## Settings

### General

Light/Dark/System appearance, accent color, **icon style** (Monochrome, Colorful, or Vivid multi-color tiles, with a live preview), compact sidebar, and whether to confirm before closing a connected tab.

### Terminal

Color theme, font, size, **padding** around the terminal text, cursor shape and blinking, and Option-as-Meta.

### Files

Show hidden files by default; confirm before deleting on the server.

### Status Bar

Show or hide the server info bar, pick its items, and set how often it refreshes.

### Sessions

Import, export, and open the data folder (`~/Library/Application Support/MacTermPlus`).

### Sync

Choose iCloud Drive, Google Drive, Dropbox, OneDrive or any folder; optionally sync passwords with an encryption passphrase; see your devices.

### Keychain

iCloud Keychain status, Passwords-app export/import, and importing servers saved by other apps.

## Keyboard Shortcuts

### Sessions & tabs

**⌘N**  New session
**⌘T**  New local shell
**⇧⌘W**  Close tab
**⇧⌘]**  Next tab
**⇧⌘[**  Previous tab

### App

**⌘,**  Settings
**⇧⌘I**  Import sessions
**⇧⌘E**  Export sessions
**⌘?**  This help
**⌘Q**  Quit

### Terminal

**⌘C / ⌘V**  Copy / paste
**⌘-click**  Open link

## Troubleshooting

### “Authentication failed”

Check the username and password. For keys, make sure the file is an OpenSSH private key (it starts with `-----BEGIN OPENSSH PRIVATE KEY-----`) and that its public key is in the server's `~/.ssh/authorized_keys`.

### “Connection refused” / timeout

Check that the host and port are right, that SSH is running on the server (`sudo systemctl status ssh`), and that no firewall blocks the port.

### “Host key has changed”

If you reinstalled the server, right-click the session → **Forget Host Key**. If you didn't, don't connect: something may be intercepting your traffic.

### Unsupported key

Keys in the older `.ppk` format must first be converted to OpenSSH format (most key tools have an “Export OpenSSH key” option).

### Server info bar is empty

It needs a Linux server for most items. Also check **Settings → Status Bar** is turned on.

### Command-line self test

Run `MacTermPlus --selftest HOST PORT USER ~/.ssh/id_ed25519` from the app bundle's `Contents/MacOS` folder to test login, shell and file transfer without the UI.
