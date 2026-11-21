import CryptoKit
import Foundation

/// Optional alternative to the macOS Keychain: session passwords stored in an encrypted file
/// (~/Library/Application Support/MacTermPlus/passwords.vault), unlocked with a master password once per
/// launch. Key derivation: PBKDF2-SHA256 (200,000 rounds); encryption: AES-256-GCM. The master password
/// is never stored.
final class PasswordVault: @unchecked Sendable {
    static let shared = PasswordVault()
    static let changed = Notification.Name("MacTermPlus.vaultChanged")

    private struct File: Codable {
        var format = 1
        var salt: String
        var check: String
        var items: [String: String] = [:]
    }

    enum VaultError: LocalizedError {
        case wrongPassword, locked, tooShort
        var errorDescription: String? {
            switch self {
            case .wrongPassword: return "That master password isn’t correct."
            case .locked: return "The password vault is locked."
            case .tooShort: return "Use at least 8 characters."
            }
        }
    }

    private let lock = NSLock()
    private var key: SymmetricKey?
    private var file: File?
    private var url: URL { AppPaths.supportDirectory.appendingPathComponent("passwords.vault") }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
    var isUnlocked: Bool { lock.lock(); defer { lock.unlock() }; return key != nil }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return (file ?? load())?.items.count ?? 0
    }

    private func load() -> File? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }

    private func write(_ f: File) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(f).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func post() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }

    /// Creates a new, empty vault (replacing any old one) and unlocks it.
    func create(master: String) throws {
        guard master.count >= 8 else { throw VaultError.tooShort }
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let k = SecretVault.key(passphrase: master, salt: salt)
        let f = File(salt: salt.base64EncodedString(), check: try SecretVault.seal(SecretVault.checkText, key: k))
        lock.lock(); defer { lock.unlock() }
        try write(f)
        file = f
        key = k
        post()
    }

    func unlock(master: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let f = load(), let salt = Data(base64Encoded: f.salt) else { throw VaultError.locked }
        let k = SecretVault.key(passphrase: master, salt: salt)
        guard (try? SecretVault.open(f.check, key: k)) == SecretVault.checkText else { throw VaultError.wrongPassword }
        file = f
        key = k
        post()
    }

    func lockNow() {
        lock.lock(); key = nil; file = nil; lock.unlock()
        post()
    }

    func changeMaster(from old: String, to new: String) throws {
        guard new.count >= 8 else { throw VaultError.tooShort }
        try unlock(master: old)
        let plain = allSecrets()
        try create(master: new)
        for (account, secret) in plain { save(secret, account: account) }
    }

    /// Deletes the vault file and everything in it (for a forgotten master password).
    func destroy() {
        lock.lock(); key = nil; file = nil; lock.unlock()
        try? FileManager.default.removeItem(at: url)
        post()
    }

    // MARK: Items

    func save(_ secret: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        guard let k = key, var f = file ?? load(), let sealed = try? SecretVault.seal(secret, key: k) else { return }
        f.items[account] = sealed
        try? write(f)
        file = f
    }

    func read(account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let k = key, let sealed = (file ?? load())?.items[account] else { return nil }
        return try? SecretVault.open(sealed, key: k)
    }

    func delete(account: String) {
        lock.lock(); defer { lock.unlock() }
        guard var f = file ?? load(), f.items[account] != nil else { return }
        f.items.removeValue(forKey: account)
        try? write(f)
        file = f
    }

    /// Decrypted copy of every item (only while unlocked), for moving passwords between stores.
    func allSecrets() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        guard let k = key, let f = file ?? load() else { return [:] }
        var out: [String: String] = [:]
        for (a, s) in f.items { if let p = try? SecretVault.open(s, key: k) { out[a] = p } }
        return out
    }
}
