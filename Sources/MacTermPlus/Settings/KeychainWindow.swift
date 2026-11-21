import AppKit
import SwiftUI

/// The Keychain window: SSH keys, reusable identities, known hosts and saved passwords in one place.
struct KeychainWindow: View {
    @EnvironmentObject var store: SessionStore
    @ObservedObject var settings = AppSettings.shared

    enum Page: String, CaseIterable, Identifiable {
        case keys = "Keys", identities = "Identities", hosts = "Known Hosts", passwords = "Passwords"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .keys: return "key.horizontal.fill"
            case .identities: return "person.text.rectangle.fill"
            case .hosts: return "lock.shield.fill"
            case .passwords: return "ellipsis.rectangle.fill"
            }
        }
        var color: Color {
            switch self {
            case .keys: return .orange
            case .identities: return .indigo
            case .hosts: return .green
            case .passwords: return .pink
            }
        }
    }

    @ViewState private var page: Page? = Page(rawValue: ProcessInfo.processInfo.environment["MTP_KEYCHAIN_PAGE"] ?? "") ?? .keys

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label { Text(p.rawValue) } icon: { IconTile(symbol: p.icon, color: p.color, size: 22) }
                    .tag(p)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch page ?? .keys {
            case .keys: KeysPage()
            case .identities: IdentitiesPage()
            case .hosts: KnownHostsSettings()
            case .passwords:
                Form { SavedPasswordsSection() }.formStyle(.grouped)
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .tint(settings.accent.color)
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

// MARK: - Keys

private struct KeysPage: View {
    @EnvironmentObject var store: SessionStore
    @ObservedObject private var identities = IdentityStore.shared
    @ViewState private var keys: [SSHKeyInfo] = []
    @ViewState private var showGenerator = false
    @ViewState private var message: String?

    private let columns = [GridItem(.adaptive(minimum: 270), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { showGenerator = true } label: { Label("New Key", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                Button { importKey() } label: { Label("Add Existing Key…", systemImage: "square.and.arrow.down") }
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }.help("Look again")
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: SSHKeys.sshDir)) } label: { Image(systemName: "folder") }
                    .help("Open ~/.ssh in Finder")
            }
            .padding(12)
            Divider()
            if let message {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 8)
            }
            ScrollView {
                if keys.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "key.horizontal").font(.system(size: 36)).foregroundStyle(.tertiary)
                        Text("No SSH keys in ~/.ssh yet. Click New Key to create one.").foregroundStyle(.secondary)
                    }
                    .padding(.top, 80)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(keys) { k in card(k) }
                }
                .padding(14)
            }
            Divider()
            Text("Private keys stay where they are. MacTerm+ only remembers their location; keys are never copied, uploaded or synced.")
                .font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .navigationTitle("Keys")
        .onAppear(perform: reload)
        .sheet(isPresented: $showGenerator, onDismiss: reload) { KeyGeneratorSheet { msg in flash(msg) } }
    }

    private func card(_ k: SSHKeyInfo) -> some View {
        let used = usage(k)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconTile(symbol: "key.horizontal.fill", color: k.tooOpen ? .red : .orange, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(k.name).font(.headline).lineLimit(1)
                    HStack(spacing: 5) {
                        badge(k.keyType)
                        if k.encrypted { badge("Passphrase") }
                        if k.imported { badge("Added") }
                    }
                }
                Spacer()
                Menu {
                    Button("Copy Public Key") { copy(k.publicKey ?? "") }.disabled(k.publicKey == nil)
                    Button("Copy Fingerprint") { copy(k.fingerprint ?? "") }.disabled(k.fingerprint == nil)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: k.path)]) }
                    Divider()
                    Button("New Identity With This Key…") { newIdentity(k) }
                    if k.imported {
                        Divider()
                        Button("Remove From List") { SSHKeys.extraPaths.removeAll { $0 == k.path }; reload() }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            Text(k.fingerprint ?? "No .pub file next to this key")
                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            HStack {
                Text(k.comment.isEmpty ? (k.path as NSString).abbreviatingWithTildeInPath : k.comment)
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                Spacer()
                if !used.isEmpty { Text(used).font(.caption).foregroundStyle(.secondary) }
            }
            if k.tooOpen {
                HStack {
                    Label("Other users can read this key", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Fix") { SSHKeys.fixPermissions(k.path); reload(); flash("Permissions fixed (only you can read \(k.name)).") }
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        .contextMenu {
            Button("Copy Public Key") { copy(k.publicKey ?? "") }.disabled(k.publicKey == nil)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: k.path)]) }
        }
    }

    private func badge(_ t: String) -> some View {
        Text(t).font(.caption2.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
    }

    private func usage(_ k: SSHKeyInfo) -> String {
        let s = store.sessions.filter { $0.identityID == nil && $0.auth == .privateKey && SSHKeys.same($0.keyPath, k.path) }.count
        let i = identities.identities.filter { $0.auth == .privateKey && SSHKeys.same($0.keyPath, k.path) }.count
        var parts: [String] = []
        if s > 0 { parts.append("\(s) session\(s == 1 ? "" : "s")") }
        if i > 0 { parts.append("\(i) identit\(i == 1 ? "y" : "ies")") }
        return parts.isEmpty ? "" : "Used by " + parts.joined(separator: ", ")
    }

    private func reload() { keys = Showcase.isOn ? Self.demo : SSHKeys.scan() }

    private func importKey() {
        let panel = NSOpenPanel()
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: SSHKeys.sshDir)
        panel.prompt = "Add Key"
        panel.message = "Choose a private key file. MacTerm+ remembers where it is; the file is not copied."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard SSHKeys.inspect(url.path) != nil else { flash("That file isn’t an SSH private key."); return }
        if !url.path.hasPrefix(SSHKeys.sshDir + "/") && !SSHKeys.extraPaths.contains(url.path) { SSHKeys.extraPaths.append(url.path) }
        reload()
        flash("Added \(url.lastPathComponent).")
    }

    private func newIdentity(_ k: SSHKeyInfo) {
        NotificationCenter.default.post(name: IdentitiesPage.newWithKey, object: k.path)
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        flash("Copied.")
    }

    private func flash(_ m: String) {
        message = m
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if message == m { message = nil } }
    }

    /// Made-up keys for screenshots.
    private static let demo: [SSHKeyInfo] = [
        SSHKeyInfo(path: "~/.ssh/id_ed25519", keyType: "ED25519", comment: "me@macbook", publicKey: "ssh-ed25519 " + Data("demo-key-1".utf8).base64EncodedString(), encrypted: true),
        SSHKeyInfo(path: "~/.ssh/deploy_ed25519", keyType: "ED25519", comment: "deploy@ci", publicKey: "ssh-ed25519 " + Data("demo-key-2".utf8).base64EncodedString()),
        SSHKeyInfo(path: "~/.ssh/legacy_rsa", keyType: "RSA", comment: "old servers", publicKey: "ssh-rsa " + Data("demo-key-3".utf8).base64EncodedString(), tooOpen: true),
    ]
}

/// New ED25519 key, optionally with an identity that uses it.
private struct KeyGeneratorSheet: View {
    var done: (String) -> Void
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = "id_ed25519"
    @ViewState private var comment = "\(NSUserName())@\(Host.current().localizedName ?? "mac")"
    @ViewState private var pass1 = ""
    @ViewState private var pass2 = ""
    @ViewState private var makeIdentity = false
    @ViewState private var username = "root"
    @ViewState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconTile(symbol: "key.horizontal.fill", color: .orange, size: 36)
                VStack(alignment: .leading) {
                    Text("New SSH Key").font(.title2.bold())
                    Text("ED25519, saved in ~/.ssh").font(.callout).foregroundStyle(.secondary)
                }
            }
            Form {
                TextField("File name", text: $name)
                TextField("Comment", text: $comment)
                SecureField("Passphrase (recommended)", text: $pass1)
                SecureField("Repeat passphrase", text: $pass2)
                Toggle("Also create an identity that uses this key", isOn: $makeIdentity)
                if makeIdentity { TextField("Username on the servers", text: $username) }
            }
            .formStyle(.grouped)
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Text("Copy the public key to a server’s ~/.ssh/authorized_keys to log in with it.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create Key") { create() }.keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || pass1 != pass2 || (makeIdentity && username.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func create() {
        guard !Showcase.isOn else { dismiss(); return }
        if let e = SSHKeys.generate(name: name, comment: comment, passphrase: pass1) { error = e; return }
        let path = "~/.ssh/" + name.replacingOccurrences(of: "/", with: "")
        if makeIdentity {
            let i = Identity(name: name, username: username, auth: .privateKey, keyPath: path)
            if !pass1.isEmpty { Keychain.save(pass1, account: i.account) }
            IdentityStore.shared.upsert(i, store: store)
        }
        done("Created \(path)\(makeIdentity ? " and an identity for \(username)" : "").")
        dismiss()
    }
}

// MARK: - Identities

struct IdentitiesPage: View {
    static let newWithKey = Notification.Name("MacTermPlus.newIdentityWithKey")
    @EnvironmentObject var store: SessionStore
    @ObservedObject private var identities = IdentityStore.shared
    @ViewState private var editing: Identity?
    @ViewState private var deleting: Identity?
    @ViewState private var search = ""

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 12)]
    private var list: [Identity] {
        let all = Showcase.isOn ? Self.demo : identities.identities
        return search.isEmpty ? all : all.filter { ($0.displayName + " " + $0.username).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { editing = Identity() } label: { Label("New Identity", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            .padding(12)
            Divider()
            ScrollView {
                if list.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.text.rectangle").font(.system(size: 36)).foregroundStyle(.tertiary)
                        Text(search.isEmpty ? "An identity is a login (username + password or key) that many sessions can share.\nChange the password once and every session using it is updated."
                                            : "Nothing matches “\(search)”.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if search.isEmpty { Button("Create an Identity") { editing = Identity() } }
                    }
                    .padding(.top, 70)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(list) { i in card(i) }
                }
                .padding(14)
            }
        }
        .navigationTitle("Identities")
        .sheet(item: $editing) { i in IdentityEditor(identity: i).environmentObject(store) }
        .confirmationDialog(deleting.map { "Delete the identity “\($0.displayName)”?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { i in
            Button("Delete Identity", role: .destructive) { identities.delete(i, store: store) }
        } message: { i in
            let n = identities.sessions(using: i.id, in: store).count
            Text(n == 0 ? "Its saved password is removed too." : "\(n) session\(n == 1 ? "" : "s") use it. They keep working: each gets its own copy of this login.")
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.newWithKey)) { n in
            if let path = n.object as? String {
                editing = Identity(name: (path as NSString).lastPathComponent, username: "root", auth: .privateKey,
                                   keyPath: (path as NSString).abbreviatingWithTildeInPath)
            }
        }
    }

    private func card(_ i: Identity) -> some View {
        let n = identities.sessions(using: i.id, in: store).count
        let hasSecret = !Showcase.isOn && Keychain.read(account: i.account) != nil
        return HStack(spacing: 10) {
            IconTile(symbol: i.auth == .privateKey ? "key.horizontal.fill" : "person.text.rectangle.fill", color: .indigo, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.displayName).font(.headline).lineLimit(1)
                Text("\(i.username) · \(i.detail)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(n == 0 ? "Not used yet" : "Used by \(n) session\(n == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            if !hasSecret && i.auth == .password && !Showcase.isOn {
                Image(systemName: "questionmark.key.filled").foregroundStyle(.orange).help("No password saved; asked when connecting")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = i }
        .contextMenu {
            Button("Edit…") { editing = i }
            Divider()
            Button("Delete…", role: .destructive) { deleting = i }
        }
    }

    private static let demo: [Identity] = [
        Identity(name: "Root (password)", username: "root"),
        Identity(name: "Deploy key", username: "deploy", auth: .privateKey, keyPath: "~/.ssh/deploy_ed25519"),
        Identity(name: "Ubuntu admin", username: "ubuntu", auth: .privateKey, keyPath: "~/.ssh/id_ed25519"),
        Identity(name: "Web FTP", username: "webmaster"),
    ]
}

private struct IdentityEditor: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @ViewState var identity: Identity
    @ViewState private var secret = ""
    @ViewState private var stored: String?
    @ViewState private var keys: [SSHKeyInfo] = []

    private var isNew: Bool { !IdentityStore.shared.identities.contains { $0.id == identity.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconTile(symbol: "person.text.rectangle.fill", color: .indigo, size: 36)
                Text(isNew ? "New Identity" : "Edit Identity").font(.title2.bold())
            }
            Form {
                TextField("Name", text: $identity.name, prompt: Text("e.g. Production root"))
                TextField("Username", text: $identity.username, prompt: Text("root"))
                Picker("Method", selection: $identity.auth) {
                    ForEach(AuthMethod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if identity.auth == .privateKey {
                    HStack {
                        TextField("Key file", text: $identity.keyPath, prompt: Text("~/.ssh/id_ed25519"))
                        Menu("Choose") {
                            ForEach(keys) { k in
                                Button("\(k.name) (\(k.keyType))") { identity.keyPath = (k.path as NSString).abbreviatingWithTildeInPath }
                            }
                            Divider()
                            Button("Other File…") { chooseKey() }
                        }
                        .fixedSize()
                    }
                    RevealableSecretField(title: "Key passphrase", text: $secret, prompt: "Leave empty if none", savedValue: stored)
                } else {
                    RevealableSecretField(title: "Password", text: $secret, prompt: "Empty = ask when connecting", savedValue: stored)
                }
            }
            .formStyle(.grouped)
            if !isNew {
                let n = IdentityStore.shared.sessions(using: identity.id, in: store).count
                if n > 0 { Text("Changes apply to the \(n) session\(n == 1 ? "" : "s") using this identity.").font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(identity.username.trimmingCharacters(in: .whitespaces).isEmpty
                              || (identity.auth == .privateKey && identity.keyPath.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            keys = Showcase.isOn ? [] : SSHKeys.scan()
            if !Showcase.isOn, let s = Keychain.read(account: identity.account) { secret = s; stored = s }
        }
    }

    private func save() {
        guard !Showcase.isOn else { dismiss(); return }
        identity.username = identity.username.trimmingCharacters(in: .whitespaces)
        if secret.isEmpty { Keychain.delete(account: identity.account) } else if secret != stored { Keychain.save(secret, account: identity.account) }
        IdentityStore.shared.upsert(identity, store: store)
        dismiss()
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: SSHKeys.sshDir)
        if panel.runModal() == .OK, let url = panel.url { identity.keyPath = (url.path as NSString).abbreviatingWithTildeInPath }
    }
}
