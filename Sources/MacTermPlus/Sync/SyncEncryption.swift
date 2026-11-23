import CryptoKit
import Foundation

/// The whole sync document encrypted with the sync passphrase (PBKDF2-SHA256 + AES-256-GCM), so the
/// cloud drive only ever holds unreadable data: no server names, addresses, usernames or notes.
///
/// It uses its own file name (`sync-encrypted.mtpsync`): older MacTerm+ versions only read `sync*.json`,
/// so they can't misread it and overwrite it with plain text.
struct EncryptedSyncFile: Codable {
    var format = 2
    var salt: String
    var check: String
    var data: String

    static let fileName = "sync-encrypted.mtpsync"
    static let plainName = "sync.json"

    static func isEncryptedCopy(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("sync-encrypted") && url.pathExtension == "mtpsync"
    }

    static func isPlainCopy(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("sync") && url.pathExtension == "json"
    }

    // PBKDF2 with 200,000 rounds takes a moment, so derived keys are kept in memory for this run.
    nonisolated(unsafe) private static var keyCache: [String: SymmetricKey] = [:]
    private static let cacheLock = NSLock()

    static func key(passphrase: String, salt: String) -> SymmetricKey? {
        guard let saltData = Data(base64Encoded: salt) else { return nil }
        let id = salt + "|" + SHA256.hash(data: Data(passphrase.utf8)).map { String(format: "%02x", $0) }.joined()
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let k = keyCache[id] { return k }
        let k = SecretVault.key(passphrase: passphrase, salt: saltData)
        keyCache[id] = k
        return k
    }

    static func newSalt() -> String {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return salt.base64EncodedString()
    }

    /// Encrypts a document. Reuses the folder's salt so every Mac derives the same key.
    static func seal(_ doc: SyncDocument, passphrase: String, salt: String?) throws -> EncryptedSyncFile {
        let s = salt ?? newSalt()
        guard let k = key(passphrase: passphrase, salt: s) else { throw SyncError.unavailable("Couldn’t prepare encryption.") }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let plain = try enc.encode(doc)
        let sealed = try AES.GCM.seal(plain, using: k).combined!.base64EncodedString()
        return EncryptedSyncFile(salt: s, check: try SecretVault.seal(SecretVault.checkText, key: k), data: sealed)
    }

    /// Decrypts; throws `wrongPassphrase` when the passphrase doesn't match.
    func open(passphrase: String) throws -> SyncDocument {
        guard let k = Self.key(passphrase: passphrase, salt: salt),
              (try? SecretVault.open(check, key: k)) == SecretVault.checkText else { throw SyncError.wrongPassphrase }
        guard let blob = Data(base64Encoded: data) else { throw SyncError.unavailable("The encrypted sync file is damaged.") }
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: blob), using: k)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(SyncDocument.self, from: plain)
    }
}
