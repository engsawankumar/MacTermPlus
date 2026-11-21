import CryptoKit
import Foundation

/// An SSH private key found on this Mac. Only the key's header is inspected; MacTerm+ never copies,
/// uploads or syncs private keys — sessions and identities store just the file path.
struct SSHKeyInfo: Identifiable, Hashable {
    let path: String
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var keyType = "Unknown"
    var comment = ""
    var publicKey: String?          // "type base64 [comment]" from the .pub file
    var encrypted = false           // protected by a passphrase
    var tooOpen = false             // readable by other users
    var imported = false            // added from outside ~/.ssh

    var fingerprint: String? {
        guard let publicKey else { return nil }
        let parts = publicKey.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return nil }
        return "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}

enum SSHKeys {
    static let extraKey = "keys.extraPaths"
    static var sshDir: String { NSHomeDirectory() + "/.ssh" }

    static var extraPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: extraKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: extraKey) }
    }

    /// Private keys in ~/.ssh plus any added from elsewhere.
    static func scan() -> [SSHKeyInfo] {
        let fm = FileManager.default
        var paths = ((try? fm.contentsOfDirectory(atPath: sshDir)) ?? [])
            .filter { !$0.hasPrefix(".") && !$0.hasSuffix(".pub") && !["known_hosts", "known_hosts.old", "config", "authorized_keys"].contains($0) }
            .map { sshDir + "/" + $0 }
        let extra = extraPaths.filter { fm.fileExists(atPath: $0) && !paths.contains($0) }
        paths += extra
        return paths.compactMap { p in inspect(p, imported: extra.contains(p)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func inspect(_ path: String, imported: Bool = false) -> SSHKeyInfo? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let head = String(decoding: (try? h.read(upToCount: 600)) ?? Data(), as: UTF8.self)
        guard head.contains("PRIVATE KEY-----") else { return nil }
        var k = SSHKeyInfo(path: path, imported: imported)
        if head.contains("BEGIN OPENSSH PRIVATE KEY") {
            k.encrypted = openSSHCipher(head) != "none"
        } else {
            k.encrypted = head.contains("ENCRYPTED")
            if head.contains("BEGIN RSA") { k.keyType = "RSA" } else if head.contains("BEGIN EC") { k.keyType = "ECDSA" }
        }
        if let pub = try? String(contentsOfFile: path + ".pub", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !pub.isEmpty {
            k.publicKey = pub
            let f = pub.split(separator: " ", maxSplits: 2).map(String.init)
            k.keyType = label(f.first ?? "")
            if f.count > 2 { k.comment = f[2] }
        }
        if let perms = (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? Int {
            k.tooOpen = perms & 0o077 != 0
        }
        return k
    }

    static func label(_ type: String) -> String {
        switch type {
        case "ssh-ed25519": return "ED25519"
        case "ssh-rsa": return "RSA"
        case let t where t.hasPrefix("ecdsa"): return "ECDSA"
        case let t where t.hasPrefix("sk-"): return "Security key"
        default: return type.isEmpty ? "Unknown" : type
        }
    }

    /// Reads the cipher name from an OpenSSH key ("none" = no passphrase).
    private static func openSSHCipher(_ pem: String) -> String {
        // The first base64 line is enough: magic, then the cipher name.
        let line = pem.components(separatedBy: "\n").first { !$0.hasPrefix("-----") && !$0.isEmpty } ?? ""
        let chunk = String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard let data = Data(base64Encoded: String(chunk.prefix(chunk.count / 4 * 4))), data.count > 19 else { return "unknown" }
        let magic = "openssh-key-v1\0".utf8.count
        let len = data[magic..<magic + 4].reduce(0) { $0 << 8 | Int($1) }
        guard len > 0, len < 64, data.count >= magic + 4 + len else { return "unknown" }
        return String(decoding: data[(magic + 4)..<(magic + 4 + len)], as: UTF8.self)
    }

    /// chmod 600 (private keys must not be readable by others).
    static func fixPermissions(_ path: String) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// Creates a new ED25519 key with ssh-keygen. Returns an error message, or nil on success.
    static func generate(name: String, comment: String, passphrase: String) -> String? {
        let clean = name.replacingOccurrences(of: "/", with: "").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return "Enter a file name." }
        let path = sshDir + "/" + clean
        if FileManager.default.fileExists(atPath: path) { return "\(clean) already exists. Choose another name." }
        try? FileManager.default.createDirectory(atPath: sshDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        p.arguments = ["-q", "-t", "ed25519", "-a", "100", "-f", path, "-N", passphrase, "-C", comment]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return error.localizedDescription }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? nil : "ssh-keygen failed (exit \(p.terminationStatus))."
    }

    /// True when a session or identity path points to this key.
    static func same(_ a: String, _ b: String) -> Bool {
        (a as NSString).expandingTildeInPath == (b as NSString).expandingTildeInPath
    }
}
