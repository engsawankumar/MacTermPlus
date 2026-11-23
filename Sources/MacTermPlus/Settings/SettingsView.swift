import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ViewState private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            TerminalSettings(settings: settings)
                .tabItem { Label("Terminal", systemImage: "terminal") }.tag("terminal")
            FileSettings(settings: settings)
                .tabItem { Label("Files", systemImage: "folder") }.tag("files")
            StatusBarSettings(settings: settings)
                .tabItem { Label("Status Bar", systemImage: "chart.bar.xaxis") }.tag("statusbar")
            SessionDataSettings()
                .tabItem { Label("Sessions", systemImage: "square.and.arrow.down.on.square") }.tag("sessions")
            SyncSettings()
                .tabItem { Label("Sync", systemImage: "icloud") }.tag("sync")
            KeychainSettings()
                .tabItem { Label("Passwords", systemImage: "key.fill") }.tag("keychain")
            KnownHostsSettings()
                .tabItem { Label("Known Hosts", systemImage: "checkmark.shield") }.tag("knownhosts")
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSyncSettings)) { _ in tab = "sync" }
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsTab)) { note in if let t = note.object as? String { tab = t } }
        .frame(width: 640)
        .tint(settings.accent.color)
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings
    @ViewState private var confirmReset = false

    var body: some View {
        Form {
            Section("Look") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Accent color") {
                    HStack(spacing: 8) {
                        ForEach(AccentChoice.allCases) { choice in
                            ColorDot(color: choice.color, selected: settings.accent == choice)
                                .onTapGesture { settings.accent = choice }
                                .help(choice.rawValue.capitalized)
                        }
                    }
                }
                Picker("Icon style", selection: $settings.iconStyle) {
                    ForEach(IconStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                IconStylePreview(style: settings.iconStyle)
                Toggle("Compact sidebar", isOn: $settings.compactSidebar)
                Toggle("Color tabs with the session’s color", isOn: $settings.coloredTabs)
                Toggle("Show the server’s OS icon on sessions (detected when you connect)", isOn: $settings.showOSIcons)
            }
            Section("Tabs") {
                Toggle("Ask before closing a connected tab", isOn: $settings.confirmCloseTab)
                Toggle("Show the Welcome window when MacTerm+ opens", isOn: Binding(
                    get: { AnnouncementCenter.shared.showAtLaunch },
                    set: { AnnouncementCenter.shared.showAtLaunch = $0 }))
            }
            Section("Updates") {
                UpdateSettingsRows()
            }
            Section("Privacy") {
                Toggle("Show news in the Welcome window", isOn: Binding(
                    get: { AnnouncementCenter.shared.newsEnabled },
                    set: { AnnouncementCenter.shared.newsEnabled = $0 }))
                Text("MacTerm+ only downloads from GitHub: the update check, and the Welcome news if this is on. It never sends your sessions, server names, user names or passwords anywhere; your servers are contacted only when you connect to them.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
            }
            Section {
                HStack {
                    Spacer()
                    Text("MacTerm+ \(AppInfo.version) · \(AppInfo.credit)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 380)
        .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { settings.resetToDefaults() }
        } message: {
            Text("Saved sessions and passwords are not affected.")
        }
    }
}

private struct TerminalSettings: View {
    @ObservedObject var settings: AppSettings
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        Form {
            Section("Theme") {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(TerminalTheme.all) { theme in
                            ThemeCard(theme: theme, selected: settings.themeID == theme.id)
                                .onTapGesture { settings.themeID = theme.id }
                        }
                    }
                    .padding(4)
                }
                .frame(height: 250)
            }
            Section("Text") {
                Picker("Font", selection: $settings.fontName) {
                    ForEach(AppSettings.monospacedFonts, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $settings.fontSize, in: 9...28, step: 1)
                        Text("\(Int(settings.fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Padding") {
                    HStack {
                        Slider(value: $settings.terminalPadding, in: 0...32, step: 2)
                        Text("\(Int(settings.terminalPadding)) px").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Cursor", selection: $settings.cursor) {
                    ForEach(CursorChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Blinking cursor", isOn: $settings.cursorBlink)
            }
            Section("Keyboard") {
                Toggle("Use Option as Meta key", isOn: $settings.optionAsMeta)
                Toggle("Preview and confirm before pasting several lines", isOn: $settings.confirmMultilinePaste)
            }
            Section("Connections") {
                Toggle("Allow older SSH algorithms for older servers", isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "ssh.legacyAlgorithms") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "ssh.legacyAlgorithms") }))
                Text("Lets MacTerm+ connect to routers, NAS boxes and older Linux that only offer Diffie-Hellman group 14, RSA (ssh-rsa) host keys or AES-CTR. Modern algorithms are always tried first.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Turn this off if you type special characters with Option (e.g. @ or € on some keyboards).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Preview") {
                ThemePreview(theme: settings.theme, font: settings.terminalFont)
                    .frame(height: 120)
            }
        }
        .formStyle(.grouped)
        .frame(height: 620)
    }
}

private struct FileSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("File browser") {
                Toggle("Show hidden files (dot files) by default", isOn: $settings.showHiddenFiles)
                Toggle("Follow terminal folder (file browser follows the shell’s cd)", isOn: $settings.followTerminalFolder)
                Toggle("Show the Commands button in the toolbar (Quick Commands, ⇧⌘K)", isOn: $settings.quickCommandsButton)
                Toggle("Ask before deleting files on the server", isOn: $settings.confirmDelete)
            }
            FileAssociationsSection()
            Section {
                Text("Tip: double-click a remote file to edit it in your default Mac app. Every save is uploaded automatically while the tab stays open.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
    }
}

private struct StatusBarSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Show server info bar under SSH terminals", isOn: $settings.showStatusBar)
                LabeledContent("Refresh every") {
                    Picker("", selection: $settings.statusInterval) {
                        Text("2 s").tag(2.0); Text("3 s").tag(3.0); Text("5 s").tag(5.0)
                        Text("10 s").tag(10.0); Text("30 s").tag(30.0)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                .disabled(!settings.showStatusBar)
            }
            Section("Show") {
                ForEach(StatusItem.allCases) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { settings.statusItems.contains(item) },
                        set: { on in if on { settings.statusItems.insert(item) } else { settings.statusItems.remove(item) } }
                    ))
                }
            }
            .disabled(!settings.showStatusBar)
            Section {
                Text("Stats are read from /proc on Linux servers with one small command per refresh. On other systems, fewer items are available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
    }
}

private struct SessionDataSettings: View {
    var body: some View {
        Form {
            Section("Import") {
                Text("Bring in sessions from other SSH, SFTP and FTP apps, spreadsheets (CSV), ~/.ssh/config or a MacTerm+ export.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Import Sessions…") { NotificationCenter.default.post(name: .importSessions, object: nil) }
            }
            Section("Export") {
                Text("Save your sessions as MacTerm+ JSON, an OpenSSH config file, or CSV. Passwords are never exported.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Export Sessions…") { NotificationCenter.default.post(name: .exportSessions, object: nil) }
            }
            Section("Data") {
                Button("Show Data Folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory])
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 340)
    }
}

/// Sample icons so the user sees what each icon style looks like.
private struct IconStylePreview: View {
    let style: IconStyle
    private let samples: [(String, Bool)] = [
        ("Projects", true), ("photo.png", false), ("app.py", false), ("deploy.sh", false),
        ("backup.tar.gz", false), ("nginx.conf", false), ("id_rsa", false), ("db.sql", false), ("report.pdf", false),
    ]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(samples, id: \.0) { name, dir in
                FileIconView(item: FileItem(name: name, path: "/" + name, isDirectory: dir, isSymlink: false,
                                            size: nil, modified: nil, permissions: ""), size: 22, styleOverride: style)
                    .help(name)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct ColorDot: View {
    let color: SwiftUI.Color
    let selected: Bool
    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.95 : 0), lineWidth: 2))
            .shadow(color: color.opacity(selected ? 0.6 : 0), radius: 3)
            .contentShape(Circle())
    }
}

struct ThemeCard: View {
    let theme: TerminalTheme
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text("$ ").foregroundStyle(Color(hex: theme.ansi[2]))
                    Text("ls ").foregroundStyle(Color(hex: theme.foreground))
                    Text("-la").foregroundStyle(Color(hex: theme.ansi[3]))
                }
                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: theme.ansi[i + (i == 0 ? 8 : 0)])).frame(width: 11, height: 8)
                    }
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: theme.background), in: RoundedRectangle(cornerRadius: 6))
            Text(theme.name).font(.caption).lineLimit(1)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.accentColor : .secondary.opacity(0.25), lineWidth: selected ? 2.5 : 1))
        .contentShape(Rectangle())
    }
}

struct ThemePreview: View {
    let theme: TerminalTheme
    let font: NSFont

    var body: some View {
        let f = Font(font)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text("user@server").foregroundStyle(Color(hex: theme.ansi[2]))
                Text(":").foregroundStyle(Color(hex: theme.foreground))
                Text("~/app").foregroundStyle(Color(hex: theme.ansi[4]))
                Text("$ systemctl status nginx").foregroundStyle(Color(hex: theme.foreground))
            }
            HStack(spacing: 0) {
                Text("● ").foregroundStyle(Color(hex: theme.ansi[2]))
                Text("nginx.service - A high performance web server").foregroundStyle(Color(hex: theme.foreground))
            }
            HStack(spacing: 0) {
                Text("   Active: ").foregroundStyle(Color(hex: theme.foreground))
                Text("active (running)").foregroundStyle(Color(hex: theme.ansi[10]))
                Text("  warn: ").foregroundStyle(Color(hex: theme.ansi[3]))
                Text("1  error: ").foregroundStyle(Color(hex: theme.ansi[1]))
                Text("0").foregroundStyle(Color(hex: theme.ansi[5]))
            }
            HStack(spacing: 0) {
                Text("$ ").foregroundStyle(Color(hex: theme.foreground))
                Rectangle().fill(Color(hex: theme.cursor)).frame(width: 8, height: 15)
            }
        }
        .font(f)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: theme.background), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension Notification.Name {
    static let importSessions = Notification.Name("MacTermPlus.importSessions")
    static let exportSessions = Notification.Name("MacTermPlus.exportSessions")
    static let showHelp = Notification.Name("MacTermPlus.showHelp")
    static let showSettingsTab = Notification.Name("MacTermPlus.showSettingsTab")
}

private struct SyncSettings: View {
    @ObservedObject var sync = SyncManager.shared
    @Environment(\.openWindow) private var openWindow
    @ViewState private var locations: [SyncLocation] = []
    @ViewState private var passphrase = ""
    @ViewState private var passphraseSaved = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(sync.enabled ? "Sync is set up. Run the assistant again to change the drive or what is synced."
                                      : "The setup assistant walks you through it: choose iCloud Drive or Google Drive, pick what to sync, allow access.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(sync.enabled ? "Change Setup…" : "Set Up Sync…") { openWindow(id: "sync-setup") }
                        .buttonStyle(.borderedProminent)
                }
                Toggle("Sync across my Macs", isOn: $sync.enabled)
                    .disabled(sync.folderPath.isEmpty)
                Text("Every Mac with MacTerm+ that uses the same cloud folder stays in sync. Changes merge automatically; nothing is sent anywhere except your own cloud folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Where to sync") {
                if locations.isEmpty {
                    Text("No iCloud Drive, Google Drive, Dropbox or OneDrive folder found. Turn on iCloud Drive in System Settings, or install Google Drive for desktop — or choose any folder.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(locations) { loc in
                    HStack {
                        Image(systemName: loc.icon).foregroundStyle(.tint).frame(width: 20)
                        VStack(alignment: .leading) {
                            Text(loc.name)
                            Text((loc.url.path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if sync.folderPath == loc.url.path {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Use") { sync.folderPath = loc.url.path; sync.enabled = true }
                        }
                    }
                }
                HStack {
                    if !sync.folderPath.isEmpty, !locations.contains(where: { $0.url.path == sync.folderPath }) {
                        Label((sync.folderPath as NSString).abbreviatingWithTildeInPath, systemImage: "folder.fill")
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Choose Folder…") { chooseFolder() }
                }
                Text("Google Drive: install “Google Drive for desktop” and sign in; it appears here automatically. A “MacTermPlus” folder is created inside the location you pick.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("What to sync") {
                Toggle("Sessions", isOn: $sync.syncSessions)
                Toggle("Settings (theme, fonts, appearance, toolbar, files, status bar)", isOn: $sync.syncSettings)
                Toggle("Macros & Quick Commands", isOn: $sync.syncMacros)
                Toggle("Tunnels", isOn: $sync.syncTunnels)
            }
            Section("Passwords") {
                Toggle("Also sync saved passwords (end-to-end encrypted)", isOn: $sync.syncPasswords)
                if sync.syncPasswords {
                    HStack {
                        SecureField("Sync passphrase", text: $passphrase, prompt: Text(sync.passphrase == nil ? "Choose a passphrase" : "•••••••• (saved)"))
                        Button("Save") {
                            sync.passphrase = passphrase
                            passphrase = ""
                            passphraseSaved = true
                            sync.scheduleSync(0.2)
                        }
                        .disabled(passphrase.count < 8)
                    }
                    Text("Use the same passphrase on every Mac (at least 8 characters). Passwords are encrypted with it (AES-256) before they reach the cloud folder; the passphrase stays in this Mac’s Keychain and is never uploaded.")
                        .font(.caption).foregroundStyle(.secondary)
                    if passphraseSaved { Label("Passphrase saved", systemImage: "checkmark").font(.caption).foregroundStyle(.green) }
                }
            }
            Section("Status") {
                HStack {
                    if sync.isSyncing { ProgressView().controlSize(.small) }
                    if let e = sync.lastError {
                        Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else if let last = sync.lastSync {
                        Text("Last sync \(last.formatted(date: .abbreviated, time: .shortened))\(sync.lastSummary.isEmpty ? "" : " · " + sync.lastSummary)")
                            .font(.callout)
                    } else {
                        Text("Not synced yet").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sync Now") { Task { await sync.syncNow() } }.disabled(!sync.enabled || sync.isSyncing)
                }
                ForEach(sync.devices) { dev in
                    HStack {
                        Image(systemName: "laptopcomputer").foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(dev.name + (dev.id == sync.deviceID ? " (this Mac)" : ""))
                            Text("\(dev.model) · MacTerm+ \(dev.appVersion) · \(dev.lastSync.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if dev.id != sync.deviceID {
                            Button("Remove") { sync.removeDevice(dev) }.buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 620)
        .onAppear { locations = SyncLocation.detect() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose a folder that your cloud app syncs (for example inside Google Drive or Dropbox)."
        if panel.runModal() == .OK, let url = panel.url {
            sync.folderPath = url.path
            sync.enabled = true
        }
    }
}

/// iCloud Keychain and Passwords-app options.
private struct KeychainSettings: View {
    @EnvironmentObject var store: SessionStore
    @ViewState private var useICloud = Keychain.useICloud
    @ViewState private var message: String?
    @ViewState private var serverCount = 0

    var body: some View {
        Form {
            PasswordStorageSection()
            SavedPasswordsSection()
            Section("iCloud Keychain (direct)") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: Keychain.iCloudAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(Keychain.iCloudAvailable ? .green : .orange)
                    Text(Keychain.iCloudAvailable
                         ? "Available. Passwords can be stored in iCloud Keychain and appear on all your Apple devices."
                         : "Not available in this build. macOS only lets apps signed with an Apple Developer ID (with the Keychain Sharing capability) save to iCloud Keychain. This build is signed for this Mac only. Use the Passwords app options below; they work today and end up in iCloud Keychain too.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Store session passwords in iCloud Keychain", isOn: $useICloud)
                    .disabled(!Keychain.iCloudAvailable)
                    .onChange(of: useICloud) { _, on in
                        Keychain.useICloud = on
                        let n = Keychain.migrateAll(accounts: store.sessions.map(\.keychainAccount) + IdentityStore.shared.accounts)
                        message = on ? "Moved \(n) password\(n == 1 ? "" : "s") to iCloud Keychain."
                                     : "Moved \(n) password\(n == 1 ? "" : "s") back to this Mac’s keychain."
                    }
                HStack {
                    Button("Save Session List to iCloud Keychain") { saveList() }
                    Button("Import from iCloud Keychain…") { NotificationCenter.default.post(name: .importSessions, object: nil) }
                }
                .disabled(!Keychain.iCloudAvailable)
            }
            Section("Passwords app (works now)") {
                Text("Apple’s Passwords app is iCloud Keychain. Export your sessions with their passwords, import that file in Passwords, and they sync to every Apple device you’re signed into. Another Mac can import them back the same way.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Export for Passwords App…") { exportForPasswords() }
                    Button("Open Passwords App") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords") {
                            NSWorkspace.shared.openApplication(at: url, configuration: .init())
                        }
                    }
                }
                Button("Import a Passwords App Export (CSV)…") { NotificationCenter.default.post(name: .importSessions, object: nil) }
                Text("In Passwords: File → Export All Passwords… then use Import → Import from a File → Passwords app. Only entries whose website is ssh://, sftp://, ftp:// or ftps:// are imported.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Servers saved by other apps") {
                Text("\(serverCount) SSH/SFTP/FTP server login\(serverCount == 1 ? "" : "s") found in this Mac’s keychain (saved by Finder and other apps, including iCloud Keychain items).")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Button("Import Them…") { NotificationCenter.default.post(name: .importSessions, object: nil) }
                    .disabled(serverCount == 0)
            }
            if let message {
                Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .formStyle(.grouped)
        .frame(height: 700)
        .onAppear { serverCount = Keychain.serverEntries().count }
    }

    private func saveList() {
        var list = store.sessions
        for i in list.indices { list[i].updatedAt = Date() }
        guard let data = try? JSONEncoder().encode(list) else { return }
        let status = Keychain.saveSessionList(data)
        message = status == errSecSuccess ? "Saved \(list.count) sessions to iCloud Keychain (passwords stay separate)."
                                          : "Couldn’t save (error \(status))."
    }

    private func exportForPasswords() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ExportFormat.applePasswords.fileName
        panel.message = "This file contains passwords in plain text. Import it in Passwords, then delete it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SessionExporter.export(store.sessions, as: .applePasswords).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)   // holds passwords
            message = "Saved \(url.lastPathComponent). Now: Passwords → File → Import Passwords… → choose it. Then delete the file."
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct UpdateSettingsRows: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        Toggle("Check for updates automatically (once a day)", isOn: $updater.autoCheck)
        LabeledContent("GitHub repository") {
            TextField("owner/MacTermPlus", text: $updater.repoOverride, prompt: Text(updater.repo.isEmpty ? "owner/MacTermPlus" : updater.repo))
                .frame(width: 220)
        }
        HStack {
            switch updater.state {
            case .upToDate: Label("Up to date (\(updater.currentVersion))", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            case .available: Label("Version \(updater.latest?.version ?? "") is available", systemImage: "arrow.down.circle.fill").foregroundStyle(.blue)
            case .failed(let m): Text(m).foregroundStyle(.orange).font(.caption).lineLimit(2)
            case .checking: ProgressView().controlSize(.small)
            default: Text("Version \(updater.currentVersion)").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Check Now") {
                Task {
                    await updater.check(userInitiated: true)
                    if updater.state == .available { NotificationCenter.default.post(name: Updater.showWindow, object: nil) }
                }
            }
        }
    }
}
