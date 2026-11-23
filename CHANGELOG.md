# Changelog

Release notes are taken from this file: the section under `## <version>` becomes the GitHub
release description that users see in **Check for Updates**.

## 1.3.2
Security hardening:
- New SSH key passphrases are typed into ssh-keygen privately instead of being passed on its command
  line, where other programs on the Mac could have seen them.
- Root (sudo) uploads use a temporary file on the server that only you can read.
- MacTerm+'s data folder and files (sessions, known hosts, identities…) are now readable only by you.
- Exported files that contain passwords are saved readable only by you.
- Local copies of server files you opened for editing are deleted when the tab closes.
- Shown passwords are never spell-checked or auto-corrected.
- Release builds no longer contain the build Mac's folder paths.
- Clearer warning that plain FTP sends passwords unencrypted.

## 1.3.1
- **License & terms on first launch**: MacTerm+ now shows its license and terms of use once (and again only if
  they change). Tick “I have read and accept…” and click Accept & Continue to start, or Quit.
- **Help → License & Terms of Use** shows the terms, the full license and when you accepted them;
  **Help → Report a Copyright Concern or Complaint…** opens the project's complaint form.

## 1.3.0
- **Host Details panel**: click ⓘ on a session (or ⌘I) to edit it on the right side while you work: address,
  name, folder, tags, color, theme, protocol, port, login (or identity), password with Touch ID reveal, start folder,
  Backspace key and notes. Changes save as you type; Connect, Duplicate, Copy SSH Command and Delete are one click away.
- **Tags** for sessions, shown in the sidebar, with a tag filter next to the search box. Search also finds
  usernames, notes and tags.
- **Backspace sends Ctrl-H** option per session, for old systems and network devices.

## 1.2.0
- **Keychain window** (toolbar → Keychain, ⌥⌘K): Keys, Identities, Known Hosts and Passwords in one place.
- **Keys**: your SSH keys with type, passphrase status, fingerprint and usage; create a new ED25519 key,
  add an existing one, copy the public key, and fix keys that other users could read.
- **Identities**: a reusable login (username + password or key) that many sessions share. Pick one under
  Authentication → Login; change it once and every session follows. Identities sync with your sessions;
  their passwords only inside the encrypted password sync.

## 1.1.0
- **See your saved passwords**, safely: an 👁 button on the password in each session, and a **Saved passwords**
  list in Settings → Passwords with search, show, copy and forget. Each needs **Touch ID or your Mac password**;
  it stays unlocked for one minute, locks when you switch apps, and copied passwords leave the clipboard after a minute.
- **Known Hosts** (Settings): every trusted server key with type, SHA256 fingerprint and the sessions using it.
  Import from `~/.ssh/known_hosts`, export, copy fingerprints, and remove a key after a server is reinstalled.
- **File types**: choose the app for each extension (e.g. `.xml` → your editor) in Settings → Files, or
  right-click → Open With → Always Open … With. Synced with your settings.
- Every release is checked first for private data (keys, real IP addresses, e-mail addresses).

## 1.0.10
- **Sync setup assistant** (Sync → Set Up Sync…), in three steps: choose **iCloud Drive or Google Drive**,
  pick **what to sync** (Sessions, Passwords, Settings, Macros & Quick Commands, Tunnels; all ticked, with
  Select all), then **allow access** when macOS asks. It ends with a summary and the list of your Macs.
- **Settings now sync** between Macs: theme, fonts, appearance, toolbar, files and status bar options.
- Each item can be turned off later in Settings → Sync → What to sync; an item that's off stays on this Mac only.

## 1.0.9
- **Quick Commands**: a panel of ready-made server commands, opened with the new **Commands** toolbar button
  or **⇧⌘K** and closed with ✕. More than 50 commands in folders: Common, System & Logs, Apache, LiteSpeed,
  Nginx, MySQL / MariaDB, PHP, Docker, Firewall & Network, Updates. The 10 most used (top -c, htop, disk check,
  restart Apache / LiteSpeed / Nginx / MySQL…) are starred at the top; star any other to add it.
- Search box (⌥⌘F), add / edit / delete / duplicate commands, your own folders, “ask before running”,
  run in all terminals, and Restore Built-in Commands. Quick Commands sync between your Macs.

## 1.0.8
- **Browse as root (sudo)** for SSH/SFTP sessions: open folders your user can't access, and upload, edit,
  rename, chmod and delete as root. Turn it on from the Files panel or the **Open as root** button on a
  “Permission denied” message. A red **ROOT** badge shows while it's on; the sudo password stays in memory only.
- Clear messages instead of raw codes for “permission denied” and “no such file”.

## 1.0.7
- Unticking **“Show this window when MacTerm+ opens”** now really keeps the Welcome window closed,
  also after updates.
- Clearer explanation of Keychain permission: with all passwords in one item, macOS asks **once per update**.
  For no prompts at all, use the MacTerm+ encrypted vault (Settings → Passwords).

## 1.0.6
- **No more repeated Keychain prompts.** All MacTerm+ passwords now live in one Keychain item that
  MacTerm+ itself owns, so macOS no longer asks at launch or after updates. On the first launch of
  1.0.6, macOS may ask one final time while your existing passwords are moved over. Choose **Always Allow**.

## 1.0.5
- **Choose where passwords are saved** (Settings → Passwords): the macOS Keychain, or a new
  **MacTerm+ encrypted vault** unlocked with one master password per launch, with no Keychain prompts.
  Saved passwords move across automatically when you switch.
- New **Privacy** settings: turn Welcome-window news off. Updates and news are download-only; MacTerm+
  never sends sessions, server names or passwords anywhere.

## 1.0.4
- Connects to older SSH servers (routers, NAS boxes, older Linux) that only offer Diffie-Hellman group 14,
  RSA (ssh-rsa) host keys or AES-CTR. Fixes “keyExchangeNegotiationFailure”. Modern algorithms are still preferred.
- New setting: Settings → Terminal → Connections → “Allow older SSH algorithms”.
- Clearer message when a server and MacTerm+ have no encryption method in common.

## 1.0.3
- MacTerm+ is now signed with a permanent developer identity. After this update macOS asks for
  Keychain and folder access **one last time**: choose **Always Allow** and future updates keep it.
- Updates are only installed if they're signed by the same MacTerm+ developer identity.

## 1.0.2
- New **Welcome window**: quick start (add a server, import, sync, guide) and news from the MacTerm+ team.
  It opens on first launch, after an update, or when there's a new message; turn it off in the window or in Settings → General.
- Help → **Welcome to MacTerm+** opens it any time.

## 1.0.1
- First stable release of **MacTerm+**.
- New **DMG installer**: open it and drag MacTerm+ to Applications.
- Release files are now named **MacTerm+** (`MacTerm+-1.0.1.dmg` / `.zip`).
- Clearer, neutral wording for importing sessions from other apps (by file type).
- Fixed building on GitHub's Mac builders.

## 0.5.0
- File toolbar: up, home, refresh, upload, download, new folder, new file, rename, delete, info, permissions, edit, hidden files, filter, copy path.
- Permission manager (chmod) with owner/group/others checkboxes, octal field, presets and recursive apply, for SFTP, FTP and local files.
- File info window with size, dates, permissions, owner and group; owner column in the two-pane view.
- Recent folders menu in the path field.
- Check for Updates (app menu and Settings → General), with automatic daily checks and in-place install.

## 0.4.0
- Distro badges in the server info bar and on sessions; total and free disk items.
- Terminal right-click menu with paste preview and multi-line paste confirmation.
- "Built by Bairagi" branding and About window.

## 0.3.1
- Per-session terminal themes and colored tabs; Keychain tab (Passwords app export/import, keychain server import).

## 0.3.0
- FTP/FTPS/SFTP sessions, all-in-one layout, tunnels, MultiExec, split view, macros, tools, multi-Mac sync.
