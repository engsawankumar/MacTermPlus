import Foundation
import SwiftUI

/// How a saved session authenticates.
enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password
    case privateKey

    var id: String { rawValue }
    var label: String {
        switch self {
        case .password: return "Password"
        case .privateKey: return "Private key"
        }
    }
}

/// What kind of connection a session opens.
enum SessionKind: String, Codable, CaseIterable, Identifiable {
    case ssh, sftp, ftp, ftps
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ssh: return "SSH"
        case .sftp: return "SFTP"
        case .ftp: return "FTP"
        case .ftps: return "FTPS"
        }
    }
    var detail: String {
        switch self {
        case .ssh: return "Terminal + file browser"
        case .sftp: return "Files only, over SSH"
        case .ftp: return "Files, unencrypted"
        case .ftps: return "Files, FTP over TLS"
        }
    }
    var defaultPort: Int { self == .ftp || self == .ftps ? 21 : 22 }
    var isFTP: Bool { self == .ftp || self == .ftps }
    var icon: String {
        switch self {
        case .ssh: return "server.rack"
        case .sftp: return "externaldrive.connected.to.line.below.fill"
        case .ftp: return "arrow.up.arrow.down.square.fill"
        case .ftps: return "lock.square.stack.fill"
        }
    }
}

/// Color label for a session (sidebar icon and tab dot).
enum SessionColor: String, Codable, CaseIterable, Identifiable {
    case teal, blue, indigo, purple, pink, red, orange, yellow, green, gray
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .teal: return Color(hex: "1FB5A6")
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .gray: return .gray
        }
    }
}

/// A saved SSH/SFTP connection. Secrets (password, key passphrase) live in the Keychain, never here.
struct SessionProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var group: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var auth: AuthMethod = .password
    var keyPath: String = ""
    var initialRemotePath: String = ""
    var openFilesPanel: Bool = true
    var color: SessionColor = .teal
    var notes: String = ""
    var kind: SessionKind = .ssh
    /// FTPS: allow self-signed / mismatched certificates.
    var acceptInvalidCertificates: Bool = false
    /// Terminal color theme for this session ("" = the default from Settings).
    var themeID: String = ""
    /// Server OS detected on the last connection (Distro id), for the OS icon.
    var osID: String = ""
    /// Saved identity (username + password or key) this session uses instead of its own credentials.
    var identityID: UUID?
    /// Last change, used to merge edits from other devices during sync.
    var updatedAt: Date = Date()

    var displayName: String { name.isEmpty ? "\(username)@\(host)" : name }
    var keychainAccount: String { id.uuidString }
    /// Where this session's password / key passphrase is saved: its identity's, or its own.
    var secretAccount: String { identityID.map(Identity.account(for:)) ?? keychainAccount }
    var endpoint: String {
        let scheme = kind == .ssh ? "" : "\(kind.rawValue)://"
        return "\(scheme)\(username.isEmpty ? "" : username + "@")\(host)\(port == kind.defaultPort ? "" : ":\(port)")"
    }

    init(id: UUID = UUID(), name: String = "", group: String = "", host: String = "", port: Int = 22,
         username: String = "", auth: AuthMethod = .password, keyPath: String = "") {
        self.id = id; self.name = name; self.group = group; self.host = host; self.port = port
        self.username = username; self.auth = auth; self.keyPath = keyPath
    }

    // Tolerant decoding: files written by older versions (or hand-edited) may lack newer keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        auth = try c.decodeIfPresent(AuthMethod.self, forKey: .auth) ?? .password
        keyPath = try c.decodeIfPresent(String.self, forKey: .keyPath) ?? ""
        initialRemotePath = try c.decodeIfPresent(String.self, forKey: .initialRemotePath) ?? ""
        openFilesPanel = try c.decodeIfPresent(Bool.self, forKey: .openFilesPanel) ?? true
        color = try c.decodeIfPresent(SessionColor.self, forKey: .color) ?? .teal
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        kind = try c.decodeIfPresent(SessionKind.self, forKey: .kind) ?? .ssh
        acceptInvalidCertificates = try c.decodeIfPresent(Bool.self, forKey: .acceptInvalidCertificates) ?? false
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? ""
        osID = try c.decodeIfPresent(String.self, forKey: .osID) ?? ""
        identityID = try? c.decodeIfPresent(UUID.self, forKey: .identityID)
    }

    /// Same server, regardless of name — used to skip duplicates on import.
    func sameEndpoint(as other: SessionProfile) -> Bool {
        host.caseInsensitiveCompare(other.host) == .orderedSame && port == other.port && username == other.username
            && kind.isFTP == other.kind.isFTP
    }
}

/// Persists sessions as JSON in ~/Library/Application Support/MacTermPlus.
/// Deleted session IDs are remembered (tombstones) so a deletion also syncs to other devices.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [SessionProfile] = []
    @Published private(set) var deleted: [UUID: Date] = [:]

    static let changed = Notification.Name("MacTermPlus.sessionsChanged")
    static let osDetected = Notification.Name("MacTermPlus.sessionOSDetected")

    private let fileURL: URL
    private let tombstoneURL: URL

    init() {
        let dir = AppPaths.supportDirectory
        fileURL = dir.appendingPathComponent("sessions.json")
        tombstoneURL = dir.appendingPathComponent("deleted-sessions.json")
        load()
        if Showcase.isOn { sessions = Showcase.sessions(); deleted = [:] }   // never the user's own sessions
        NotificationCenter.default.addObserver(forName: Self.osDetected, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let id = note.userInfo?["id"] as? UUID, let os = note.userInfo?["os"] as? String,
                      let i = self.sessions.firstIndex(where: { $0.id == id }), self.sessions[i].osID != os else { return }
                var p = self.sessions[i]
                p.osID = os
                self.upsert(p)
            }
        }
    }

    var groups: [String] {
        Array(Set(sessions.map { $0.group })).sorted { a, b in
            if a.isEmpty { return false }
            if b.isEmpty { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    func sessions(in group: String) -> [SessionProfile] {
        sessions.filter { $0.group == group }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func upsert(_ profile: SessionProfile) {
        var p = profile
        p.updatedAt = Date()
        if let i = sessions.firstIndex(where: { $0.id == p.id }) {
            sessions[i] = p
        } else {
            sessions.append(p)
        }
        save()
    }

    /// Adds many sessions at once; returns how many were new (same host/port/user are skipped).
    @discardableResult
    func importSessions(_ list: [SessionProfile], secrets: [UUID: String] = [:]) -> Int {
        var added = 0
        for var p in list where !sessions.contains(where: { $0.sameEndpoint(as: p) }) {
            let secret = secrets[p.id]
            p.id = UUID()
            p.updatedAt = Date()
            sessions.append(p)
            if let secret, !secret.isEmpty { Keychain.save(secret, account: p.keychainAccount) }
            added += 1
        }
        save()
        return added
    }

    func renameGroup(_ old: String, to new: String) {
        for i in sessions.indices where sessions[i].group == old {
            sessions[i].group = new
            sessions[i].updatedAt = Date()
        }
        save()
    }

    func delete(_ profile: SessionProfile) {
        sessions.removeAll { $0.id == profile.id }
        deleted[profile.id] = Date()
        Keychain.delete(account: profile.keychainAccount)
        save()
    }

    /// Replaces the local state with a merged result from sync (does not re-trigger sync).
    func applySynced(sessions newSessions: [SessionProfile], deleted newDeleted: [UUID: Date]) {
        let removed = sessions.filter { s in !newSessions.contains { $0.id == s.id } }
        for r in removed { Keychain.delete(account: r.keychainAccount) }
        sessions = newSessions
        deleted = newDeleted
        save(notify: false)
    }

    private func load() {
        let dec = JSONDecoder()
        if let data = try? Data(contentsOf: fileURL) {
            sessions = (try? dec.decode([SessionProfile].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: tombstoneURL),
           let t = try? dec.decode([String: Date].self, from: data) {
            deleted = Dictionary(uniqueKeysWithValues: t.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
        }
    }

    private func save(notify: Bool = true) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(sessions).write(to: fileURL, options: .atomic)
            let t = Dictionary(uniqueKeysWithValues: deleted.map { ($0.key.uuidString, $0.value) })
            try encoder.encode(t).write(to: tombstoneURL, options: .atomic)
        } catch {
            NSLog("MacTerm+: failed to save sessions: \(error)")
        }
        if notify { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }
}

enum AppPaths {
    static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["MTP_DATA_DIR"] {   // tests only
            let dir = URL(fileURLWithPath: override, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MacTermPlus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
