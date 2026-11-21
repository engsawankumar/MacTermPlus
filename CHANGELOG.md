# Changelog

Release notes are taken from this file: the section under `## <version>` becomes the GitHub
release description that users see in **Check for Updates**.

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
