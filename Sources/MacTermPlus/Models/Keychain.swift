import Foundation
import Security

/// Session secrets in the macOS Keychain.
///
/// Normally items go to this Mac's login keychain. When "Use iCloud Keychain" is on **and** the app
/// is signed with an Apple Developer ID that has the keychain entitlement, items are saved as
/// synchronizable, so iCloud Keychain carries them to the user's other Apple devices.
enum Keychain {
    private static let service = "com.macterm-plus.session"
    private static let listService = "com.macterm-plus.sessions-list"

    // MARK: iCloud Keychain availability

    /// Whether this build may write iCloud (synchronizable) keychain items. Ad-hoc / unsigned
    /// builds get errSecMissingEntitlement (-34018).
    static let iCloudAvailable: Bool = {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.macterm-plus.probe",
            kSecAttrAccount as String: "probe",
            kSecAttrSynchronizable as String: true,
            kSecValueData as String: Data("x".utf8),
        ]
        var status = SecItemAdd(probe as CFDictionary, nil)
        if status == errSecDuplicateItem { status = errSecSuccess }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.macterm-plus.probe",
                       kSecAttrSynchronizable as String: kSecAttrSynchronizableAny] as CFDictionary)
        return status == errSecSuccess
    }()

    /// User preference; only takes effect when `iCloudAvailable`.
    static var useICloud: Bool {
        get { UserDefaults.standard.bool(forKey: "keychain.iCloud") }
        set { UserDefaults.standard.set(newValue, forKey: "keychain.iCloud") }
    }

    private static var syncing: Bool { useICloud && iCloudAvailable }

    // MARK: Secrets

    private static func keychainSave(_ secret: String, account: String) {
        // Remove every older copy (local or iCloud) so there is exactly one.
        keychainDelete(account: account)
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "MacTerm+ session",
            kSecValueData as String: Data(secret.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        if syncing { add[kSecAttrSynchronizable as String] = true }
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ] as CFDictionary)
    }

    /// Re-saves every session secret, so they move to (or out of) iCloud Keychain after the setting changes.
    static func migrateAll(accounts: [String]) -> Int {
        var moved = 0
        for a in accounts {
            if let s = keychainRead(account: a) { keychainSave(s, account: a); moved += 1 }
        }
        return moved
    }

    // MARK: Where passwords are stored (macOS Keychain or MacTerm+ vault)

    enum Storage: String, CaseIterable, Identifiable {
        case keychain, vault
        var id: String { rawValue }
        var label: String { self == .keychain ? "macOS Keychain" : "MacTerm+ encrypted vault" }
    }

    static var storage: Storage {
        get { Storage(rawValue: UserDefaults.standard.string(forKey: "secrets.storage") ?? "") ?? .keychain }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "secrets.storage") }
    }

    /// True when passwords live in the vault and it hasn't been unlocked yet this launch.
    static var vaultLocked: Bool { storage == .vault && PasswordVault.shared.exists && !PasswordVault.shared.isUnlocked }

    static func save(_ secret: String, account: String) {
        if storage == .vault { PasswordVault.shared.save(secret, account: account) } else { keychainSave(secret, account: account) }
    }

    static func read(account: String) -> String? {
        storage == .vault ? PasswordVault.shared.read(account: account) : keychainRead(account: account)
    }

    /// Removes the secret from both stores.
    static func delete(account: String) {
        keychainDelete(account: account)
        PasswordVault.shared.delete(account: account)
    }

    /// Moves secrets for these accounts into the chosen store and removes them from the other one.
    /// The vault must already be unlocked (or just created). Returns how many were moved.
    @discardableResult
    static func moveSecrets(to target: Storage, accounts: [String]) -> Int {
        var moved = 0
        for a in accounts {
            switch target {
            case .vault:
                if let s = keychainRead(account: a) {
                    PasswordVault.shared.save(s, account: a)
                    if PasswordVault.shared.read(account: a) == s { keychainDelete(account: a); moved += 1 }
                }
            case .keychain:
                if let s = PasswordVault.shared.read(account: a) {
                    keychainSave(s, account: a)
                    if keychainRead(account: a) == s { PasswordVault.shared.delete(account: a); moved += 1 }
                }
            }
        }
        storage = target
        return moved
    }

    // MARK: Session list in iCloud Keychain

    /// Stores the whole session list (no passwords) as one iCloud Keychain item, so another Mac
    /// signed into the same Apple Account can import it.
    static func saveSessionList(_ data: Data) -> OSStatus {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: listService,
                       kSecAttrSynchronizable as String: kSecAttrSynchronizableAny] as CFDictionary)
        return SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: listService,
            kSecAttrAccount as String: "sessions",
            kSecAttrLabel as String: "MacTerm+ session list",
            kSecAttrSynchronizable as String: true,
            kSecValueData as String: data,
        ] as CFDictionary, nil)
    }

    static func readSessionList() -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: listService,
            kSecAttrAccount as String: "sessions",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    // MARK: Server logins other apps saved (Finder and others)

    struct ServerEntry: Hashable {
        let server: String
        let account: String
        let port: Int
        let kind: SessionKind
        let label: String
        let synchronizable: Bool
    }

    /// Internet-password items for SSH / SFTP / FTP / FTPS. Only attributes are read here, so
    /// macOS doesn't ask for permission; passwords are fetched later, on request.
    static func serverEntries() -> [ServerEntry] {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        var out: [ServerEntry] = []
        for item in items {
            guard let server = item[kSecAttrServer as String] as? String, !server.isEmpty else { continue }
            let proto = protocolCode(item[kSecAttrProtocol as String])
            let kind: SessionKind
            switch proto {
            case "ssh ": kind = .ssh
            case "sftp": kind = .sftp
            case "ftp ", "ftpp": kind = .ftp
            case "ftps", "fpts": kind = .ftps
            default: continue
            }
            let port = (item[kSecAttrPort as String] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? kind.defaultPort
            let entry = ServerEntry(server: server, account: item[kSecAttrAccount as String] as? String ?? "",
                                    port: port, kind: kind, label: item[kSecAttrLabel as String] as? String ?? server,
                                    synchronizable: (item[kSecAttrSynchronizable as String] as? Bool) ?? false)
            if !out.contains(entry) { out.append(entry) }
        }
        return out
    }

    /// Fetches one internet password. macOS may ask the user to allow access (once per item).
    static func password(for e: ServerEntry) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: e.server,
            kSecAttrAccount as String: e.account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// kSecAttrProtocol is a FourCharCode, exposed as a CFString on macOS.
    private static func protocolCode(_ value: Any?) -> String {
        if let s = value as? String { return s.lowercased() }
        if let n = value as? NSNumber {
            let v = n.uint32Value
            let bytes = [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
            return String(decoding: bytes, as: UTF8.self).lowercased()
        }
        return ""
    }
}
