import AppKit
import CommonCrypto
import CryptoKit
import Foundation

/// A cloud folder the Mac already syncs (iCloud Drive, Google Drive, Dropbox, OneDrive) or a custom folder.
struct SyncLocation: Identifiable, Hashable {
    enum Provider: String { case iCloud, google, dropbox, oneDrive, box, custom }
    let provider: Provider
    let name: String
    let url: URL
    var id: String { url.path }

    var icon: String {
        switch provider {
        case .iCloud: return "icloud.fill"
        case .google: return "g.circle.fill"
        case .dropbox: return "shippingbox.fill"
        case .oneDrive: return "cloud.fill"
        case .box: return "cube.box.fill"
        case .custom: return "folder.fill"
        }
    }

    /// Finds cloud folders on this Mac. Google Drive, Dropbox, OneDrive and Box show up in
    /// ~/Library/CloudStorage when their desktop apps are installed and signed in.
    static func detect() -> [SyncLocation] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var out: [SyncLocation] = []
        let icloud = URL(fileURLWithPath: "\(home)/Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: icloud.path) { out.append(SyncLocation(provider: .iCloud, name: "iCloud Drive", url: icloud)) }
        let cloudStorage = URL(fileURLWithPath: "\(home)/Library/CloudStorage")
        for name in ((try? fm.contentsOfDirectory(atPath: cloudStorage.path)) ?? []).sorted() where !name.hasPrefix(".") {
            let root = cloudStorage.appendingPathComponent(name)
            if name.hasPrefix("GoogleDrive") {
                let account = name.replacingOccurrences(of: "GoogleDrive-", with: "")
                // "My Drive" (localized on some systems): the first normal folder that isn't a shared/other area.
                let kids = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { !$0.hasPrefix(".") }
                let skip = ["Shared drives", "Other computers", "Computers", ".shortcut-targets-by-id"]
                let my = kids.first { $0 == "My Drive" } ?? kids.first { !skip.contains($0) }
                if let my { out.append(SyncLocation(provider: .google, name: "Google Drive (\(account))", url: root.appendingPathComponent(my))) }
            } else if name.hasPrefix("Dropbox") {
                out.append(SyncLocation(provider: .dropbox, name: name.replacingOccurrences(of: "-", with: " "), url: root))
            } else if name.hasPrefix("OneDrive") {
                out.append(SyncLocation(provider: .oneDrive, name: name.replacingOccurrences(of: "-", with: " – "), url: root))
            } else if name.hasPrefix("Box") {
                out.append(SyncLocation(provider: .box, name: "Box", url: root))
            }
        }
        let legacyDropbox = URL(fileURLWithPath: "\(home)/Dropbox")
        if fm.fileExists(atPath: legacyDropbox.path), !out.contains(where: { $0.provider == .dropbox }) {
            out.append(SyncLocation(provider: .dropbox, name: "Dropbox", url: legacyDropbox))
        }
        return out
    }
}

struct DeviceInfo: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var model: String
    var appVersion: String
    var lastSync: Date
}

/// The file shared between devices: <cloud folder>/MacTermPlus/sync.json
struct SyncDocument: Codable {
    var format = 1
    var updated = Date()
    var sessions: [SessionProfile] = []
    var deleted: [String: Date] = [:]
    var macros: [Macro] = []
    var macrosModified = Date.distantPast
    var tunnels: [TunnelConfig] = []
    var tunnelsModified = Date.distantPast
    var devices: [DeviceInfo] = []
    var vault: SecretVault?
}

/// Passwords encrypted with a key derived from the user's sync passphrase (PBKDF2-SHA256 + AES-GCM).
/// The passphrase itself never leaves the Mac.
struct SecretVault: Codable {
    var salt: String
    var check: String
    var secrets: [String: String] = [:]

    static let checkText = "MacTerm+ vault v1"
    static let rounds: UInt32 = 200_000

    static func key(passphrase: String, salt: Data) -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let pw = Array(passphrase.utf8)
        salt.withUnsafeBytes { s in
            _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &derived, derived.count)
        }
        return SymmetricKey(data: derived)
    }

    static func seal(_ text: String, key: SymmetricKey) throws -> String {
        try AES.GCM.seal(Data(text.utf8), using: key).combined!.base64EncodedString()
    }

    static func open(_ b64: String, key: SymmetricKey) throws -> String {
        guard let data = Data(base64Encoded: b64) else { throw CocoaError(.coderReadCorrupt) }
        return String(decoding: try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key), as: UTF8.self)
    }
}

enum SyncError: LocalizedError {
    case wrongPassphrase, noFolder, unavailable(String)
    var errorDescription: String? {
        switch self {
        case .wrongPassphrase: return "The sync passphrase doesn’t match the one used on your other devices."
        case .noFolder: return "Choose a sync folder first."
        case .unavailable(let m): return m
        }
    }
}

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    private let d = UserDefaults.standard
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "sync.enabled"); if enabled { scheduleSync(0.2) } } }
    @Published var folderPath: String { didSet { d.set(folderPath, forKey: "sync.folder") } }
    @Published var syncPasswords: Bool { didSet { d.set(syncPasswords, forKey: "sync.passwords") } }

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var devices: [DeviceInfo] = []
    @Published private(set) var lastSummary = ""

    private weak var store: SessionStore?
    private var pending: Task<Void, Never>?
    private var pollTimer: Timer?
    private var lastSeenRemote: Date?

    let deviceID: String
    var deviceName: String { Host.current().localizedName ?? "Mac" }

    private init() {
        enabled = d.bool(forKey: "sync.enabled")
        folderPath = d.string(forKey: "sync.folder") ?? ""
        syncPasswords = d.bool(forKey: "sync.passwords")
        if let id = ProcessInfo.processInfo.environment["MTP_DEVICE_ID"] { deviceID = id }   // tests only
        else if let id = d.string(forKey: "sync.deviceID") { deviceID = id } else {
            deviceID = UUID().uuidString
            d.set(deviceID, forKey: "sync.deviceID")
        }
        lastSync = d.object(forKey: "sync.last") as? Date
    }

    var passphrase: String? {
        get { Keychain.read(account: "sync-passphrase") }
        set {
            if let v = newValue, !v.isEmpty { Keychain.save(v, account: "sync-passphrase") } else { Keychain.delete(account: "sync-passphrase") }
            objectWillChange.send()
        }
    }

    var syncFile: URL? {
        folderPath.isEmpty ? nil : URL(fileURLWithPath: folderPath).appendingPathComponent("MacTermPlus/sync.json")
    }

    /// Hooks up change notifications and the poller. Call once at launch.
    func attach(store: SessionStore) {
        guard !Showcase.isOn else { return }   // screenshots must never touch the user's synced data
        self.store = store
        let nc = NotificationCenter.default
        nc.addObserver(forName: SessionStore.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync(2) }
        }
        nc.addObserver(forName: MacroStore.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(Date(), forKey: "sync.macrosModified")
                self?.scheduleSync(2)
            }
        }
        nc.addObserver(forName: TunnelManager.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(Date(), forKey: "sync.tunnelsModified")
                self?.scheduleSync(2)
            }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollRemote() }
        }
        if enabled { scheduleSync(1) }
    }

    func scheduleSync(_ delay: Double) {
        guard enabled, !Showcase.isOn else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Another device changed the file → sync.
    private func pollRemote() {
        guard enabled, let file = syncFile else { return }
        let dir = file.deletingLastPathComponent()
        let latest = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("sync") }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
        if let latest, latest != lastSeenRemote, lastSeenRemote != nil { scheduleSync(0.5) }
        lastSeenRemote = latest
    }

    func syncNow() async {
        guard !Showcase.isOn, let store, !isSyncing else { return }
        guard let file = syncFile else { lastError = SyncError.noFolder.errorDescription; return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let summary = try await Self.sync(file: file, store: store, manager: self)
            lastSync = Date()
            d.set(lastSync, forKey: "sync.last")
            lastError = nil
            lastSummary = summary
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func removeDevice(_ device: DeviceInfo) {
        guard let file = syncFile, var doc = Self.read(file) else { return }
        doc.devices.removeAll { $0.id == device.id }
        try? Self.write(doc, to: file)
        devices = doc.devices
    }

    // MARK: Engine

    private static func read(_ url: URL) -> SyncDocument? {
        var result: SyncDocument?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in
            guard let data = try? Data(contentsOf: u) else { return }
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            result = try? dec.decode(SyncDocument.self, from: data)
        }
        return result
    }

    private static func write(_ doc: SyncDocument, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(doc)
        var err: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            do { try data.write(to: u, options: .atomic) } catch { writeError = error }
        }
        if let e = err ?? writeError { throw e }
    }

    /// Reads every copy (sync.json plus conflict copies like "sync 2.json"), merges them with
    /// this Mac's data, writes the result back to both places. Returns a short summary.
    private static func sync(file: URL, store: SessionStore, manager: SyncManager) async throws -> String {
        let fm = FileManager.default
        let dir = file.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // iCloud may leave a placeholder until the file is downloaded.
        for item in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where item.hasSuffix(".icloud") {
            try? fm.startDownloadingUbiquitousItem(at: dir.appendingPathComponent(item))
        }
        let copies = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("sync") && $0.pathExtension == "json" }
        var remote = SyncDocument()
        var conflictCopies: [URL] = []
        for url in copies {
            guard let doc = read(url) else { continue }
            remote = merge(remote, doc)
            if url.lastPathComponent != "sync.json" { conflictCopies.append(url) }
        }

        // Local state as a document.
        let ud = UserDefaults.standard
        var local = SyncDocument()
        local.sessions = store.sessions
        local.deleted = Dictionary(uniqueKeysWithValues: store.deleted.map { ($0.key.uuidString, $0.value) })
        local.macros = MacroStore.shared.macros
        local.macrosModified = ud.object(forKey: "sync.macrosModified") as? Date ?? .distantPast
        local.tunnels = TunnelManager.shared.tunnels
        local.tunnelsModified = ud.object(forKey: "sync.tunnelsModified") as? Date ?? .distantPast

        var merged = merge(remote, local)
        let before = Set(store.sessions.map(\.id))
        let after = Set(merged.sessions.map(\.id))

        // Passwords (optional, end-to-end encrypted with the sync passphrase).
        var secretsIn = 0
        if manager.syncPasswords, let pass = manager.passphrase {
            var vault = remote.vault
            let key: SymmetricKey
            if let v = vault, let salt = Data(base64Encoded: v.salt) {
                key = SecretVault.key(passphrase: pass, salt: salt)
                guard (try? SecretVault.open(v.check, key: key)) == SecretVault.checkText else { throw SyncError.wrongPassphrase }
            } else {
                var salt = Data(count: 16)
                _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
                key = SecretVault.key(passphrase: pass, salt: salt)
                vault = SecretVault(salt: salt.base64EncodedString(), check: try SecretVault.seal(SecretVault.checkText, key: key))
            }
            var v = vault!
            for p in merged.sessions {
                let id = p.id.uuidString
                if let mine = Keychain.read(account: p.keychainAccount) {
                    if let theirs = v.secrets[id], (try? SecretVault.open(theirs, key: key)) == mine { continue }
                    v.secrets[id] = try SecretVault.seal(mine, key: key)
                } else if let theirs = v.secrets[id], let plain = try? SecretVault.open(theirs, key: key) {
                    Keychain.save(plain, account: p.keychainAccount)
                    secretsIn += 1
                }
            }
            v.secrets = v.secrets.filter { id, _ in merged.sessions.contains { $0.id.uuidString == id } }
            merged.vault = v
        } else {
            merged.vault = remote.vault   // keep other devices' vault untouched
        }

        // This device.
        let me = DeviceInfo(id: manager.deviceID, name: manager.deviceName, model: modelName(),
                            appVersion: AppInfo.version, lastSync: Date())
        merged.devices.removeAll { $0.id == me.id }
        merged.devices.append(me)
        merged.devices.sort { $0.lastSync > $1.lastSync }
        merged.updated = Date()

        try write(merged, to: file)
        for c in conflictCopies { try? fm.removeItem(at: c) }

        // Apply to this Mac.
        let tomb = Dictionary(uniqueKeysWithValues: merged.deleted.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
        if merged.sessions != store.sessions || tomb != store.deleted {
            store.applySynced(sessions: merged.sessions, deleted: tomb)
        }
        if merged.macrosModified > local.macrosModified {
            MacroStore.shared.replaceAll(merged.macros)
            ud.set(merged.macrosModified, forKey: "sync.macrosModified")
        }
        if merged.tunnelsModified > local.tunnelsModified {
            TunnelManager.shared.replaceAll(merged.tunnels)
            ud.set(merged.tunnelsModified, forKey: "sync.tunnelsModified")
        }
        manager.devices = merged.devices

        let added = after.subtracting(before).count, removed = before.subtracting(after).count
        var parts = ["\(merged.sessions.count) sessions"]
        if added > 0 { parts.append("\(added) new") }
        if removed > 0 { parts.append("\(removed) removed") }
        if secretsIn > 0 { parts.append("\(secretsIn) passwords received") }
        parts.append("\(merged.devices.count) device\(merged.devices.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    /// Per-session last-writer-wins, deletions win over older edits, lists by newest change.
    static func merge(_ a: SyncDocument, _ b: SyncDocument) -> SyncDocument {
        var out = SyncDocument()
        var tomb = a.deleted
        for (k, v) in b.deleted { tomb[k] = max(tomb[k] ?? .distantPast, v) }
        let horizon = Date().addingTimeInterval(-180 * 86400)
        tomb = tomb.filter { $0.value > horizon }
        var byID: [UUID: SessionProfile] = [:]
        for p in a.sessions + b.sessions {
            if let existing = byID[p.id], existing.updatedAt >= p.updatedAt { continue }
            byID[p.id] = p
        }
        out.sessions = byID.values
            .filter { p in (tomb[p.id.uuidString].map { $0 < p.updatedAt }) ?? true }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        out.deleted = tomb
        if a.macrosModified >= b.macrosModified { out.macros = a.macros; out.macrosModified = a.macrosModified }
        else { out.macros = b.macros; out.macrosModified = b.macrosModified }
        if a.tunnelsModified >= b.tunnelsModified { out.tunnels = a.tunnels; out.tunnelsModified = a.tunnelsModified }
        else { out.tunnels = b.tunnels; out.tunnelsModified = b.tunnelsModified }
        var devs: [String: DeviceInfo] = [:]
        for dv in a.devices + b.devices where (devs[dv.id]?.lastSync ?? .distantPast) < dv.lastSync { devs[dv.id] = dv }
        out.devices = Array(devs.values)
        out.vault = a.vault ?? b.vault
        return out
    }

    private static func modelName() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }
}
