import CryptoKit
import Foundation
import NIOCore
import NIOSSH

/// Trust-on-first-use host key checking. The first key seen for host:port is saved;
/// a different key later is refused (possible man-in-the-middle).
final class KnownHosts: @unchecked Sendable {
    static let shared = KnownHosts()

    private let lock = NSLock()
    private let fileURL = AppPaths.supportDirectory.appendingPathComponent("known_hosts.json")
    private var entries: [String: String]

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    enum Verdict { case trusted, newlyAdded, mismatch(expected: String) }

    func check(host: String, port: Int, key: NIOSSHPublicKey) -> Verdict {
        let id = "[\(host)]:\(port)"
        let presented = String(openSSHPublicKey: key)
        lock.lock(); defer { lock.unlock() }
        if let known = entries[id] {
            return known == presented ? .trusted : .mismatch(expected: known)
        }
        entries[id] = presented
        saveLocked()
        post()
        return .newlyAdded
    }

    func forget(host: String, port: Int) {
        forget(id: "[\(host)]:\(port)")
    }

    // MARK: Manager

    static let changed = Notification.Name("MacTermPlus.knownHostsChanged")

    struct Entry: Identifiable, Hashable {
        let id: String          // "[host]:port"
        let host: String
        let port: Int
        let keyType: String
        let key: String         // "type base64"
        /// OpenSSH-style fingerprint, e.g. "SHA256:abc…"
        var fingerprint: String {
            let parts = key.split(separator: " ")
            guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return "unknown" }
            let digest = SHA256.hash(data: blob)
            return "SHA256:" + Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        }
        var keyLabel: String {
            switch keyType {
            case "ssh-ed25519": return "ED25519"
            case "ssh-rsa": return "RSA"
            case let t where t.hasPrefix("ecdsa"): return "ECDSA"
            default: return keyType
            }
        }
    }

    static func split(_ id: String) -> (String, Int) {
        if id.hasPrefix("["), let close = id.lastIndex(of: "]") {
            let host = String(id[id.index(after: id.startIndex)..<close])
            let port = Int(id[id.index(after: close)...].dropFirst()) ?? 22
            return (host, port)
        }
        return (id, 22)
    }

    func all() -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries.map { id, key in
            let (h, p) = Self.split(id)
            return Entry(id: id, host: h, port: p, keyType: String(key.split(separator: " ").first ?? ""), key: key)
        }
        .sorted { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
    }

    func forget(id: String) {
        lock.lock()
        entries.removeValue(forKey: id)
        saveLocked()
        lock.unlock()
        post()
    }

    /// Adds hosts from an OpenSSH known_hosts file. Existing entries are never replaced.
    /// Returns (added, skipped) — hashed or certificate lines can't be imported.
    func importOpenSSH(_ text: String) -> (added: Int, skipped: Int) {
        var added = 0, skipped = 0
        lock.lock()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard f.count >= 3, !f[0].hasPrefix("@"), !f[0].hasPrefix("|"), Data(base64Encoded: f[2]) != nil else { skipped += 1; continue }
            for name in f[0].split(separator: ",").map(String.init) where !name.contains("*") && !name.contains("?") && !name.hasPrefix("!") {
                let id: String
                if name.hasPrefix("[") { id = name } else { id = "[\(name)]:22" }
                if entries[id] == nil { entries[id] = f[1] + " " + f[2]; added += 1 }
            }
        }
        saveLocked()
        lock.unlock()
        post()
        return (added, skipped)
    }

    /// OpenSSH known_hosts text for all entries (for export).
    func exportOpenSSH() -> String {
        all().map { e in (e.port == 22 ? e.host : "[\(e.host)]:\(e.port)") + " " + e.key }.joined(separator: "\n") + "\n"
    }

    private func saveLocked() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: fileURL, options: .atomic) }
    }

    private func post() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }
}

struct HostKeyMismatchError: LocalizedError {
    let host: String
    var errorDescription: String? {
        "The host key for \(host) has CHANGED since you last connected. This could mean someone is intercepting the connection. If the server was legitimately reinstalled, use “Forget host key” on the session and try again."
    }
}

final class TOFUHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate {
    let host: String
    let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        switch KnownHosts.shared.check(host: host, port: port, key: hostKey) {
        case .trusted, .newlyAdded:
            validationCompletePromise.succeed(())
        case .mismatch:
            validationCompletePromise.fail(HostKeyMismatchError(host: host))
        }
    }
}
