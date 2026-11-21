import SwiftUI

/// Settings → Passwords: the passwords MacTerm+ has saved, hidden until Touch ID / the Mac password is given.
struct SavedPasswordsSection: View {
    @EnvironmentObject var store: SessionStore
    @ObservedObject private var guardian = RevealGuard.shared
    @ObservedObject private var identities = IdentityStore.shared
    @ViewState private var shown: Set<String> = []
    @ViewState private var search = ""
    @ViewState private var deleting: Row?
    @ViewState private var copied: String?
    @ViewState private var refresh = 0
    @ViewState private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    struct Row: Identifiable {
        let id: String          // Keychain account
        let title: String
        let detail: String
        let color: Color
        let isIdentity: Bool
        let secret: String
    }

    private var rows: [Row] {
        _ = refresh
        guard !Showcase.isOn, !Keychain.vaultLocked else { return [] }
        let ids: [Row] = identities.identities.compactMap { i in
            guard let s = Keychain.read(account: i.account), !s.isEmpty else { return nil }
            return Row(id: i.account, title: i.displayName, detail: "Identity · \(i.username)\(i.auth == .privateKey ? " · key passphrase" : "")",
                       color: .indigo, isIdentity: true, secret: s)
        }
        let sessions: [Row] = store.sessions.compactMap { p in
            guard let s = Keychain.read(account: p.keychainAccount), !s.isEmpty else { return nil }
            return Row(id: p.keychainAccount, title: p.displayName,
                       detail: "\(p.username.isEmpty ? "" : p.username + "@")\(p.host)\(p.auth == .privateKey ? " · key passphrase" : "")",
                       color: p.color.color, isIdentity: false, secret: s)
        }
        let all = ids + sessions
        guard !search.isEmpty else { return all }
        return all.filter { ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: guardian.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(guardian.isUnlocked ? .green : .secondary)
                if guardian.isUnlocked, let until = guardian.unlockedUntil {
                    Text("Unlocked · locks in \(max(0, Int(until.timeIntervalSince(now))))s").font(.callout)
                    Spacer()
                    Button("Lock Now") { guardian.lock(); shown = [] }
                } else {
                    Text("Hidden. Showing or copying asks for Touch ID or your Mac password.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            TextField("Search", text: $search, prompt: Text("Search saved passwords")).textFieldStyle(.roundedBorder).labelsHidden()
            if Keychain.vaultLocked {
                Label("The MacTerm+ vault is locked. Unlock it above to see saved passwords.", systemImage: "lock.fill")
                    .foregroundStyle(.orange)
            } else if rows.isEmpty {
                Text(search.isEmpty ? "No saved passwords yet." : "Nothing matches “\(search)”.").foregroundStyle(.secondary)
            }
            ForEach(rows) { p in
                let secret = p.secret
                HStack(spacing: 10) {
                    if p.isIdentity {
                        Image(systemName: "person.text.rectangle.fill").foregroundStyle(p.color).frame(width: 8)
                    } else {
                        Circle().fill(p.color).frame(width: 8, height: 8)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).lineLimit(1)
                        Text(p.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(shown.contains(p.id) && guardian.isUnlocked ? secret : "••••••••")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .frame(maxWidth: 170, alignment: .trailing)
                    Button { Task { await toggle(p.id) } } label: {
                        Image(systemName: shown.contains(p.id) && guardian.isUnlocked ? "eye.slash" : "eye")
                    }
                    .help("Show or hide")
                    Button { Task { await copy(p.id, secret) } } label: {
                        Image(systemName: copied == p.id ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy (the clipboard is cleared after a minute)")
                    Button { deleting = p } label: { Image(systemName: "trash").foregroundStyle(.red) }
                        .help("Forget this saved password")
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Saved passwords")
        } footer: {
            Text("Passwords are read from your chosen store (Keychain or vault) only while this list is open. They are never logged, synced in plain text or sent anywhere.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onReceive(tick) { now = $0; if !guardian.isUnlocked && !shown.isEmpty { shown = [] } }
        .confirmationDialog(deleting.map { "Forget the saved password for “\($0.title)”?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { p in
            Button("Forget Password", role: .destructive) {
                Keychain.delete(account: p.id)
                shown.remove(p.id)
                refresh += 1
            }
        } message: { p in Text(p.isIdentity ? "The identity stays; you’ll be asked for the password when you connect."
                                             : "The session stays; you’ll be asked for the password when you connect.") }
        .onDisappear { shown = [] }
    }

    private func toggle(_ id: String) async {
        if shown.contains(id) && guardian.isUnlocked { shown.remove(id); return }
        guard await guardian.unlock(reason: "show a saved password") else { return }
        shown.insert(id)
    }

    private func copy(_ id: String, _ secret: String) async {
        guard await guardian.unlock(reason: "copy a saved password") else { return }
        RevealGuard.copy(secret)
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == id { copied = nil } }
    }
}
