import Foundation

/// A reusable login: a username plus a password or an SSH key. Many sessions can use one identity,
/// so changing the password once updates every server that uses it. The secret lives in the
/// Keychain / vault under "identity-<id>", never in this file.
struct Identity: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var username: String = ""
    var auth: AuthMethod = .password
    var keyPath: String = ""
    var updatedAt = Date()

    var account: String { Self.account(for: id) }
    static func account(for id: UUID) -> String { "identity-" + id.uuidString }

    var displayName: String { name.isEmpty ? username : name }
    var detail: String {
        auth == .privateKey ? "Key · " + ((keyPath as NSString).lastPathComponent) : "Password"
    }

    init(name: String = "", username: String = "", auth: AuthMethod = .password, keyPath: String = "") {
        self.name = name; self.username = username; self.auth = auth; self.keyPath = keyPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        auth = (try? c.decodeIfPresent(AuthMethod.self, forKey: .auth)) ?? .password
        keyPath = try c.decodeIfPresent(String.self, forKey: .keyPath) ?? ""
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }
}

@MainActor
final class IdentityStore: ObservableObject {
    static let shared = IdentityStore()
    static let changed = Notification.Name("MacTermPlus.identitiesChanged")

    @Published private(set) var identities: [Identity] = []
    private var url: URL { AppPaths.supportDirectory.appendingPathComponent("identities.json") }

    private init() {
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Identity].self, from: data) {
            identities = list
        }
    }

    func identity(_ id: UUID?) -> Identity? { id.flatMap { i in identities.first { $0.id == i } } }

    func sessions(using id: UUID, in store: SessionStore) -> [SessionProfile] {
        store.sessions.filter { $0.identityID == id }
    }

    /// Saves an identity and keeps the username shown on its sessions up to date.
    func upsert(_ identity: Identity, store: SessionStore?) {
        var i = identity
        i.updatedAt = Date()
        if let k = identities.firstIndex(where: { $0.id == i.id }) { identities[k] = i } else { identities.append(i) }
        identities.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        save()
        if let store {
            for var p in store.sessions where p.identityID == i.id && (p.username != i.username || p.auth != i.auth || p.keyPath != i.keyPath) {
                p.username = i.username; p.auth = i.auth; p.keyPath = i.keyPath
                store.upsert(p)
            }
        }
    }

    /// Deletes an identity. Sessions that used it keep working: they get its username, method,
    /// key and a copy of its saved secret.
    func delete(_ identity: Identity, store: SessionStore) {
        let secret = Keychain.read(account: identity.account)
        for var p in store.sessions where p.identityID == identity.id {
            p.identityID = nil
            p.username = identity.username; p.auth = identity.auth; p.keyPath = identity.keyPath
            if let secret { Keychain.save(secret, account: p.keychainAccount) }
            store.upsert(p)
        }
        Keychain.delete(account: identity.account)
        identities.removeAll { $0.id == identity.id }
        save()
    }

    func replaceAll(_ list: [Identity]) {
        identities = list
        save(notify: false)
    }

    var accounts: [String] { identities.map(\.account) }

    private func save(notify: Bool = true) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(identities).write(to: url, options: .atomic)
        if notify { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }
}

extension SessionProfile {
    /// The session as it connects: with its identity's username, method and key filled in.
    @MainActor
    func resolved() -> SessionProfile {
        guard let i = IdentityStore.shared.identity(identityID) else { return self }
        var p = self
        p.username = i.username
        p.auth = i.auth
        p.keyPath = i.keyPath
        return p
    }
}
