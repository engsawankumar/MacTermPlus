import AppKit
import SwiftUI

/// Left sidebar: local shell, then saved sessions grouped into collapsible folders.
struct SessionSidebar: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var workspace: Workspace
    @ObservedObject var settings = AppSettings.shared
    @Binding var editing: SessionProfile?
    @Binding var connectTarget: SessionProfile?
    @ViewState private var search = ""
    @ViewState private var confirmDelete: SessionProfile?
    @ViewState private var collapsed: Set<String> = []

    private func filtered(_ list: [SessionProfile]) -> [SessionProfile] {
        guard !search.isEmpty else { return list }
        return list.filter {
            $0.displayName.localizedCaseInsensitiveContains(search) || $0.host.localizedCaseInsensitiveContains(search)
                || $0.group.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            Section {
                Button { workspace.openLocal() } label: {
                    HStack(spacing: 10) {
                        IconTile(symbol: "laptopcomputer", color: .gray, size: settings.compactSidebar ? 22 : 28)
                        Text("Local Shell")
                    }
                }
                .buttonStyle(.plain)
            }
            if store.sessions.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No saved sessions yet.")
                        Button("New Session…") { editing = SessionProfile() }
                        Button("Import from another app…") {
                            NotificationCenter.default.post(name: .importSessions, object: nil)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(store.groups, id: \.self) { group in
                let items = filtered(store.sessions(in: group))
                if !items.isEmpty {
                    Section(isExpanded: Binding(
                        get: { !collapsed.contains(group) || !search.isEmpty },
                        set: { open in if open { collapsed.remove(group) } else { collapsed.insert(group) } }
                    )) {
                        ForEach(items) { profile in
                            SessionRow(profile: profile, compact: settings.compactSidebar,
                                       isOpen: workspace.isOpen(profile))
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { connectTarget = profile }
                                .contextMenu { menu(for: profile) }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: group.isEmpty ? "tray.full.fill" : "folder.fill")
                                .foregroundStyle(settings.colorfulIcons ? AnyShapeStyle(Color(hex: "4A9EFF")) : AnyShapeStyle(.secondary))
                            Text(group.isEmpty ? "Sessions" : group)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search sessions", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 8).padding(.top, 6)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button { editing = SessionProfile() } label: { Image(systemName: "plus") }
                    .help("New session (⌘N)")
                Button { NotificationCenter.default.post(name: .importSessions, object: nil) } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import sessions (⇧⌘I)")
                Button { NotificationCenter.default.post(name: .exportSessions, object: nil) } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export sessions (⇧⌘E)")
                Spacer()
                Text("\(store.sessions.count)").font(.caption).foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .confirmationDialog("Delete session “\(confirmDelete?.displayName ?? "")”?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) { if let p = confirmDelete { store.delete(p) } }
        } message: {
            Text("Its saved password is removed from the Keychain too.")
        }
    }

    @ViewBuilder
    private func menu(for profile: SessionProfile) -> some View {
        Button("Connect") { connectTarget = profile }
        Button("Edit…") { editing = profile }
        Button("Duplicate") {
            var copy = profile
            copy.id = UUID()
            copy.name = profile.displayName + " copy"
            store.upsert(copy)
        }
        Menu("Color") {
            ForEach(SessionColor.allCases) { c in
                Button {
                    var p = profile
                    p.color = c
                    store.upsert(p)
                } label: {
                    Label(c.rawValue.capitalized, systemImage: profile.color == c ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        }
        Menu("Terminal Theme") {
            Button {
                var p = profile; p.themeID = ""; store.upsert(p)
            } label: { Label("Default (from Settings)", systemImage: profile.themeID.isEmpty ? "checkmark" : "circle") }
            Divider()
            ForEach(TerminalTheme.all) { t in
                Button {
                    var p = profile; p.themeID = t.id; store.upsert(p)
                } label: { Label(t.name, systemImage: profile.themeID == t.id ? "checkmark" : "paintpalette") }
            }
        }
        Button("Copy SSH Command") {
            var cmd = "ssh "
            if profile.port != 22 { cmd += "-p \(profile.port) " }
            if profile.auth == .privateKey, !profile.keyPath.isEmpty { cmd += "-i \(profile.keyPath) " }
            cmd += profile.username.isEmpty ? profile.host : "\(profile.username)@\(profile.host)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
        }
        Button("Forget Host Key") { KnownHosts.shared.forget(host: profile.host, port: profile.port) }
        Divider()
        Button("Delete…", role: .destructive) { confirmDelete = profile }
    }
}

/// Rounded colored square with a white symbol, used for sessions and sources.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                let shape = RoundedRectangle(cornerRadius: size * 0.27)
                if settings.iconStyle == .vivid {
                    // Multi-color: the color blends into a second hue, with a soft top highlight.
                    shape.fill(LinearGradient(colors: [color, color.mix(with: .pink, by: 0.45), color.mix(with: .purple, by: 0.6)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center)))
                        .shadow(color: color.opacity(0.4), radius: 2, y: 1)
                } else {
                    shape.fill(color.gradient)
                }
            }
    }
}

private struct SessionRow: View {
    let profile: SessionProfile
    let compact: Bool
    let isOpen: Bool
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            if settings.showOSIcons && !profile.osID.isEmpty {
                DistroBadge(osID: profile.osID, size: compact ? 22 : 28)
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(profile.color.color)
                            .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                            .offset(x: 3, y: 3)
                    }
            } else {
                IconTile(symbol: profile.kind == .ssh && profile.auth == .privateKey ? "key.horizontal.fill" : profile.kind.icon,
                         color: settings.colorfulIcons ? profile.color.color : .gray,
                         size: compact ? 22 : 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName).lineLimit(1)
                if !compact {
                    Text(profile.endpoint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isOpen {
                Circle().fill(.green).frame(width: 7, height: 7).help("Open in a tab")
            }
        }
        .padding(.vertical, compact ? 0 : 2)
        .help(profile.notes.isEmpty ? profile.endpoint : "\(profile.endpoint)\n\(profile.notes)")
    }
}

/// Create / edit a saved session.
struct SessionEditor: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @ViewState var profile: SessionProfile
    @ViewState private var secret = ""
    @ViewState private var storedSecret: String?
    @ViewState private var saveSecret = true
    @ObservedObject private var identityStore = IdentityStore.shared
    @Environment(\.openWindow) private var openWindow
    var onSaveAndConnect: (SessionProfile, String?) -> Void

    private var identity: Identity? { identityStore.identity(profile.identityID) }
    private var usableIdentities: [Identity] {
        identityStore.identities.filter { !profile.kind.isFTP || $0.auth == .password }
    }

    private var isNew: Bool { !store.sessions.contains { $0.id == profile.id } }
    private var valid: Bool { !profile.host.trimmingCharacters(in: .whitespaces).isEmpty && !profile.username.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "server.rack", color: profile.color.color, size: 40)
                VStack(alignment: .leading) {
                    Text(isNew ? "New Session" : "Edit Session").font(.title2.bold())
                    Text(profile.host.isEmpty ? "SSH + SFTP" : profile.endpoint).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding([.top, .horizontal], 20)
            Form {
                Section {
                    TextField("Name", text: $profile.name, prompt: Text("My server"))
                    TextField("Folder", text: $profile.group, prompt: Text("Optional, e.g. Production"))
                    LabeledContent("Color") {
                        HStack(spacing: 6) {
                            ForEach(SessionColor.allCases) { c in
                                ColorDot(color: c.color, selected: profile.color == c)
                                    .onTapGesture { profile.color = c }
                                    .help(c.rawValue.capitalized)
                            }
                        }
                    }
                    Picker("Terminal theme", selection: $profile.themeID) {
                        Text("Default (from Settings)").tag("")
                        Divider()
                        ForEach(TerminalTheme.all) { t in
                            HStack {
                                Image(nsImage: ThemeSwatch.image(t))
                                Text(t.name)
                            }
                            .tag(t.id)
                        }
                    }
                    if !profile.themeID.isEmpty {
                        ThemePreview(theme: TerminalTheme.named(profile.themeID), font: AppSettings.shared.terminalFont)
                            .frame(height: 96)
                    }
                    Text("Tip: give production servers a red color and a different theme so you always know where you are.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Server") {
                    Picker("Protocol", selection: $profile.kind) {
                        ForEach(SessionKind.allCases) { k in Text(k.label).tag(k) }
                    }
                    .pickerStyle(.segmented)
                    Text(profile.kind.detail).font(.caption).foregroundStyle(.secondary)
                    TextField("Host", text: $profile.host, prompt: Text("example.com or 10.0.0.5"))
                    TextField("Port", value: $profile.port, format: .number.grouping(.never))
                    if let identity {
                        LabeledContent("Username") { Text(identity.username).foregroundStyle(.secondary) }
                    } else {
                        TextField("Username", text: $profile.username, prompt: Text("root"))
                    }
                }
                Section("Authentication") {
                    Picker("Login", selection: $profile.identityID) {
                        Text("Enter for this session").tag(UUID?.none)
                        if !usableIdentities.isEmpty { Divider() }
                        ForEach(usableIdentities) { i in
                            Label("\(i.displayName) — \(i.username)", systemImage: "person.text.rectangle").tag(UUID?.some(i.id))
                        }
                    }
                    if let identity {
                        HStack(spacing: 10) {
                            IconTile(symbol: "person.text.rectangle.fill", color: .indigo, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(identity.displayName)
                                Text("\(identity.username) · \(identity.detail)\(Keychain.read(account: identity.account) == nil && identity.auth == .password ? " · asked when connecting" : "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Manage…") { openWindow(id: "keychain") }
                        }
                        Text("The username, password and key come from this identity. Change them there and every session using it is updated.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if identity == nil && !profile.kind.isFTP {
                        Picker("Method", selection: $profile.auth) {
                            ForEach(AuthMethod.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if profile.kind == .ftps {
                        Toggle("Accept invalid / self-signed certificates", isOn: $profile.acceptInvalidCertificates)
                    }
                    if identity != nil {
                        EmptyView()
                    } else if profile.auth == .privateKey && !profile.kind.isFTP {
                        HStack {
                            TextField("Key file", text: $profile.keyPath, prompt: Text("~/.ssh/id_ed25519"))
                            Button("Choose…") { chooseKey() }
                        }
                        RevealableSecretField(title: "Passphrase", text: $secret, prompt: "Leave empty if none", savedValue: storedSecret)
                    } else {
                        RevealableSecretField(title: "Password", text: $secret, prompt: saveSecret ? "" : "Asked when connecting", savedValue: storedSecret)
                    }
                    if identity == nil {
                        Toggle(Keychain.storage == .vault ? "Save in the MacTerm+ vault" : "Save in the Keychain", isOn: $saveSecret)
                        Button("Save as a Reusable Identity") { makeIdentity() }
                            .disabled(profile.username.isEmpty)
                            .help("Use this login for other sessions too")
                    }
                }
                Section("Options") {
                    TextField("Start folder", text: $profile.initialRemotePath, prompt: Text("Home folder"))
                    Toggle("Show the file browser in the sidebar when connected", isOn: $profile.openFilesPanel)
                    TextField("Notes", text: $profile.notes, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(); dismiss() }.disabled(!valid)
                Button("Save & Connect") {
                    save()
                    onSaveAndConnect(profile, secret.isEmpty || identity != nil ? nil : secret)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
            .padding(20)
        }
        .frame(width: 540, height: 760)
        .onAppear {
            if profile.auth == .privateKey && profile.keyPath.isEmpty { profile.keyPath = defaultKeyPath() }
            if let s = Keychain.read(account: profile.keychainAccount) { secret = s; storedSecret = s }
        }
        .onChange(of: profile.kind) { old, new in
            if profile.port == old.defaultPort { profile.port = new.defaultPort }
            if new.isFTP { profile.auth = .password }
        }
        .onChange(of: profile.identityID) { _, _ in
            if let i = identity { profile.username = i.username; profile.auth = i.auth; profile.keyPath = i.keyPath }
        }
        .onChange(of: profile.auth) { _, new in
            if new == .privateKey && profile.keyPath.isEmpty { profile.keyPath = defaultKeyPath() }
        }
    }

    private func makeIdentity() {
        let i = Identity(name: profile.username, username: profile.username,
                         auth: profile.kind.isFTP ? .password : profile.auth, keyPath: profile.keyPath)
        if !secret.isEmpty { Keychain.save(secret, account: i.account) }
        identityStore.upsert(i, store: nil)
        profile.identityID = i.id
    }

    private func save() {
        profile.host = profile.host.trimmingCharacters(in: .whitespaces)
        store.upsert(profile)
        guard identity == nil else { return }   // the identity holds the secret
        if saveSecret && !secret.isEmpty {
            Keychain.save(secret, account: profile.keychainAccount)
        } else {
            Keychain.delete(account: profile.keychainAccount)
        }
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url { profile.keyPath = url.path }
    }

    private func defaultKeyPath() -> String {
        for name in ["id_ed25519", "id_rsa"] {
            let p = NSHomeDirectory() + "/.ssh/" + name
            if FileManager.default.fileExists(atPath: p) { return "~/.ssh/" + name }
        }
        return ""
    }
}

/// Asks for a password when the session has none saved.
struct PasswordPrompt: View {
    let profile: SessionProfile
    var onConnect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewState private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconTile(symbol: "lock.fill", color: profile.color.color, size: 32)
                VStack(alignment: .leading) {
                    Text("Connect to \(profile.displayName)").font(.headline)
                    Text(profile.endpoint).font(.callout).foregroundStyle(.secondary)
                }
            }
            SecureField(profile.auth == .password ? "Password" : "Key passphrase", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onConnect(password); dismiss() }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Connect") { onConnect(password); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
