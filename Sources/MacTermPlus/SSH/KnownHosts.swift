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
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return .newlyAdded
    }

    func forget(host: String, port: Int) {
        lock.lock(); defer { lock.unlock() }
        entries.removeValue(forKey: "[\(host)]:\(port)")
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
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
