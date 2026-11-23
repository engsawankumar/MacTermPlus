import AppKit
import Combine
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
    var quickCommands: [QuickCommand] = []
    var quickFolders: [String] = []
    var quickCommandsModified = Date.distantPast
    /// App preferences as a binary property list (types kept exactly).
    var settings: Data?
    var settingsModified = Date.distantPast
    var identities: [Identity] = []
    var identitiesModified = Date.distantPast
    /// Folder-wide choice: is the sync file encrypted? The newest choice wins on every Mac.
    var encrypted = false
    var encryptionModified = Date.distantPast
    var devices: [DeviceInfo] = []
    var vault: SecretVault?

    init() {}

    /// Tolerant: files written by older or newer versions (missing or extra fields) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Int.self, forKey: .format) ?? 1
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? Date()
        sessions = try c.decodeIfPresent([SessionProfile].self, forKey: .sessions) ?? []
        deleted = try c.decodeIfPresent([String: Date].self, forKey: .deleted) ?? [:]
        macros = try c.decodeIfPresent([Macro].self, forKey: .macros) ?? []
        macrosModified = try c.decodeIfPresent(Date.self, forKey: .macrosModified) ?? .distantPast
        tunnels = try c.decodeIfPresent([TunnelConfig].self, forKey: .tunnels) ?? []
        tunnelsModified = try c.decodeIfPresent(Date.self, forKey: .tunnelsModified) ?? .distantPast
        quickCommands = (try? c.decodeIfPresent([QuickCommand].self, forKey: .quickCommands)) ?? []
        quickFolders = (try? c.decodeIfPresent([String].self, forKey: .quickFolders)) ?? []
        quickCommandsModified = (try? c.decodeIfPresent(Date.self, forKey: .quickCommandsModified)) ?? .distantPast
        settings = try? c.decodeIfPresent(Data.self, forKey: .settings)
        settingsModified = (try? c.decodeIfPresent(Date.self, forKey: .settingsModified)) ?? .distantPast
        identities = (try? c.decodeIfPresent([Identity].self, forKey: .identities)) ?? []
        identitiesModified = (try? c.decodeIfPresent(Date.self, forKey: .identitiesModified)) ?? .distantPast
        encrypted = (try? c.decodeIfPresent(Bool.self, forKey: .encrypted)) ?? false
        encryptionModified = (try? c.decodeIfPresent(Date.self, forKey: .encryptionModified)) ?? .distantPast
        devices = try c.decodeIfPresent([DeviceInfo].self, forKey: .devices) ?? []
        vault = try c.decodeIfPresent(SecretVault.self, forKey: .vault)
    }
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
    case wrongPassphrase, noFolder, needsPassphrase, unavailable(String)
    var errorDescription: String? {
        switch self {
        case .needsPassphrase: return "This sync folder is encrypted. Enter your sync passphrase (the same one as on your other Macs) in Settings → Sync."
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
    // What to sync (all on unless turned off).
    @Published var syncSessions: Bool { didSet { d.set(syncSessions, forKey: "sync.sessions") } }
    @Published var syncSettings: Bool { didSet { d.set(syncSettings, forKey: "sync.settings") } }
    @Published var syncMacros: Bool { didSet { d.set(syncMacros, forKey: "sync.macros") } }
    @Published var syncTunnels: Bool { didSet { d.set(syncTunnels, forKey: "sync.tunnels") } }
    /// Encrypt the whole sync file with the sync passphrase (nothing readable in the cloud drive).
    @Published var encryptAll: Bool {
        didSet {
            d.set(encryptAll, forKey: "sync.encrypt")
            guard encryptAll != oldValue else { return }
            // This Mac's own choice. Whole seconds, like the dates in the sync file, so comparisons are exact.
            if !adoptingEncryption { d.set(Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)), forKey: "sync.encryptModified") }
            scheduleSync(0.5)
        }
    }
    private var adoptingEncryption = false
    /// Takes the folder's choice (from another Mac) without counting it as a new choice here.
    func adoptEncryption(_ on: Bool, at date: Date) {
        adoptingEncryption = true
        encryptAll = on
        adoptingEncryption = false
        d.set(date, forKey: "sync.encryptModified")
    }
    /// One-time information from the last sync (e.g. an old unencrypted file was cleaned up).
    @Published var notice: String?
    /// True while synced settings are being applied (so that doesn't count as a local change).
    private var applyingSettings = false

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var devices: [DeviceInfo] = []
    @Published private(set) var lastSummary = ""

    private weak var store: SessionStore?
    private var pending: Task<Void, Never>?
    private var pollTimer: Timer?
    private var lastSeenRemote: Date?
    private var settingsWatch: AnyCancellable?

    let deviceID: String
    var deviceName: String { Host.current().localizedName ?? "Mac" }

    private init() {
        enabled = d.bool(forKey: "sync.enabled")
        folderPath = d.string(forKey: "sync.folder") ?? ""
        syncPasswords = d.bool(forKey: "sync.passwords")
        syncSessions = d.object(forKey: "sync.sessions") as? Bool ?? true
        syncSettings = d.object(forKey: "sync.settings") as? Bool ?? true
        syncMacros = d.object(forKey: "sync.macros") as? Bool ?? true
        syncTunnels = d.object(forKey: "sync.tunnels") as? Bool ?? true
        encryptAll = d.bool(forKey: "sync.encrypt")
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
        nc.addObserver(forName: QuickCommandStore.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(Date(), forKey: "sync.quickCommandsModified")
                self?.scheduleSync(2)
            }
        }
        settingsWatch = AppSettings.shared.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.applyingSettings else { return }
                UserDefaults.standard.set(Date(), forKey: "sync.settingsModified")
                if self.syncSettings { self.scheduleSync(3) }
            }
        }
        nc.addObserver(forName: IdentityStore.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(Date(), forKey: "sync.identitiesModified")
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

    /// Is there already a sync file (from another Mac) in this folder? (`encrypted` tells which kind.)
    static func existingSync(in folder: URL) -> (exists: Bool, encrypted: Bool) {
        let dir = folder.appendingPathComponent("MacTermPlus")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let enc = files.contains(where: EncryptedSyncFile.isEncryptedCopy)
        return (enc || files.contains(where: EncryptedSyncFile.isPlainCopy), enc)
    }

    /// Creates the MacTermPlus folder and a test file in the cloud folder. This is what makes macOS
    /// ask for permission to use iCloud Drive / Google Drive; throws a clear message if access is denied.
    nonisolated static func requestAccess(to folder: URL) throws {
        let fm = FileManager.default
        let dir = folder.appendingPathComponent("MacTermPlus", isDirectory: true)
        do {
            _ = try fm.contentsOfDirectory(atPath: folder.path)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let probe = dir.appendingPathComponent(".access-check")
            try Data("ok".utf8).write(to: probe)
            try? fm.removeItem(at: probe)
        } catch {
            throw SyncError.unavailable("MacTerm+ can’t use this folder yet. Allow access when macOS asks, or turn it on in System Settings → Privacy & Security → Files and Folders (MacTerm+), then try again.")
        }
    }

    /// Finishes the setup assistant: saves the choices, turns sync on and syncs once.
    func finishSetup(folder: URL, sessions: Bool, passwords: Bool, passphrase: String?, settings: Bool,
                     macros: Bool, tunnels: Bool, encrypt: Bool) async {
        guard !Showcase.isOn else { return }   // screenshots never change the real setup
        let existing = Self.existingSync(in: folder)
        let joining = existing.exists
        folderPath = folder.path
        syncSessions = sessions
        syncSettings = settings
        syncMacros = macros
        syncTunnels = tunnels
        if let passphrase, !passphrase.isEmpty { self.passphrase = passphrase }
        syncPasswords = passwords && sessions && self.passphrase != nil
        if existing.encrypted {
            adoptEncryption(true, at: .distantPast)   // an encrypted folder stays encrypted
        } else {
            encryptAll = encrypt && self.passphrase != nil
        }
        // The first Mac shares its settings; Macs that join take the shared ones.
        if !joining { d.set(Date(), forKey: "sync.settingsModified") }
        enabled = true
        pending?.cancel()
        await syncNow()
    }

    func removeDevice(_ device: DeviceInfo) {
        guard let file = syncFile else { return }
        let encURL = file.deletingLastPathComponent().appendingPathComponent(EncryptedSyncFile.fileName)
        if let f = Self.readEncrypted(encURL) {
            guard let pass = passphrase, var doc = try? f.open(passphrase: pass) else { return }
            doc.devices.removeAll { $0.id == device.id }
            if let sealed = try? EncryptedSyncFile.seal(doc, passphrase: pass, salt: f.salt) { try? Self.writeEncrypted(sealed, to: encURL) }
            devices = doc.devices
        } else if var doc = Self.read(file) {
            doc.devices.removeAll { $0.id == device.id }
            try? Self.write(doc, to: file)
            devices = doc.devices
        }
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

    private static func readEncrypted(_ url: URL) -> EncryptedSyncFile? {
        var result: EncryptedSyncFile?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in
            guard let data = try? Data(contentsOf: u) else { return }
            result = try? JSONDecoder().decode(EncryptedSyncFile.self, from: data)
        }
        return result
    }

    private static func writeEncrypted(_ file: EncryptedSyncFile, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(file)
        var err: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            do { try data.write(to: u, options: .atomic) } catch { writeError = error }
        }
        if let e = err ?? writeError { throw e }
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
        let all = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let plainCopies = all.filter(EncryptedSyncFile.isPlainCopy)       // sync.json, "sync 2.json", …
        let encCopies = all.filter(EncryptedSyncFile.isEncryptedCopy)     // sync-encrypted.mtpsync (+ conflict copies)
        var remote = SyncDocument()
        var salt: String?
        if !encCopies.isEmpty {
            guard let pass = manager.passphrase else { throw SyncError.needsPassphrase }
            for url in encCopies {
                guard let f = readEncrypted(url) else { continue }
                remote = merge(remote, try f.open(passphrase: pass))
                if url.lastPathComponent == EncryptedSyncFile.fileName || salt == nil { salt = f.salt }
            }
        }
        var plainFound = false
        for url in plainCopies {
            guard let doc = read(url) else { continue }
            remote = merge(remote, doc)
            plainFound = true
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
        local.quickCommands = QuickCommandStore.shared.commands
        local.quickFolders = QuickCommandStore.shared.folders
        local.quickCommandsModified = ud.object(forKey: "sync.quickCommandsModified") as? Date ?? .distantPast
        local.settings = AppSettings.shared.syncSnapshot()
        local.settingsModified = ud.object(forKey: "sync.settingsModified") as? Date ?? .distantPast
        local.encrypted = manager.encryptAll
        local.encryptionModified = ud.object(forKey: "sync.encryptModified") as? Date ?? .distantPast
        local.identities = IdentityStore.shared.identities
        local.identitiesModified = ud.object(forKey: "sync.identitiesModified") as? Date ?? .distantPast
        // Items this Mac doesn't sync: leave the cloud copy as it is and don't take it either.
        if !manager.syncSessions {
            local.sessions = []; local.deleted = [:]
            local.identities = []; local.identitiesModified = .distantPast
        }
        if !manager.syncMacros {
            local.macros = []; local.macrosModified = .distantPast
            local.quickCommands = []; local.quickFolders = []; local.quickCommandsModified = .distantPast
        }
        if !manager.syncTunnels { local.tunnels = []; local.tunnelsModified = .distantPast }
        if !manager.syncSettings { local.settings = nil; local.settingsModified = .distantPast }

        var merged = merge(remote, local)
        // Another Mac changed the encryption choice more recently (or at the same moment, choosing encryption): follow it.
        if merged.encryptionModified > local.encryptionModified
            || (merged.encryptionModified == local.encryptionModified && merged.encrypted && !local.encrypted) {
            manager.adoptEncryption(merged.encrypted, at: merged.encryptionModified)
        }
        merged.encrypted = manager.encryptAll
        let before = Set(store.sessions.map(\.id))
        let after = Set(merged.sessions.map(\.id))

        // Passwords (optional, end-to-end encrypted with the sync passphrase).
        var secretsIn = 0
        if manager.syncPasswords && manager.syncSessions, let pass = manager.passphrase {
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
            // Sessions are keyed by their id, identities by "identity-<id>" (their Keychain account name).
            let accounts = merged.sessions.map { ($0.id.uuidString, $0.keychainAccount) }
                + merged.identities.map { ($0.account, $0.account) }
            for (id, account) in accounts {
                if let mine = Keychain.read(account: account) {
                    if let theirs = v.secrets[id], (try? SecretVault.open(theirs, key: key)) == mine { continue }
                    v.secrets[id] = try SecretVault.seal(mine, key: key)
                } else if let theirs = v.secrets[id], let plain = try? SecretVault.open(theirs, key: key) {
                    Keychain.save(plain, account: account)
                    secretsIn += 1
                }
            }
            let keep = Set(accounts.map(\.0))
            v.secrets = v.secrets.filter { keep.contains($0.key) }
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

        if manager.encryptAll {
            guard let pass = manager.passphrase else { throw SyncError.needsPassphrase }
            let sealed = try EncryptedSyncFile.seal(merged, passphrase: pass, salt: salt)
            try writeEncrypted(sealed, to: dir.appendingPathComponent(EncryptedSyncFile.fileName))
            for c in encCopies where c.lastPathComponent != EncryptedSyncFile.fileName { try? fm.removeItem(at: c) }
            // No readable copy may stay behind in the cloud drive.
            for c in plainCopies { try? fm.removeItem(at: c) }
            if plainFound && !encCopies.isEmpty {
                manager.notice = "A Mac with an older MacTerm+ wrote an unencrypted sync file. It was merged, encrypted and removed. Update MacTerm+ on all your Macs."
            }
        } else {
            try write(merged, to: file)
            for c in plainCopies where c.lastPathComponent != EncryptedSyncFile.plainName { try? fm.removeItem(at: c) }
            for c in encCopies { try? fm.removeItem(at: c) }   // encryption was turned off: drop the old encrypted copy
        }

        // Apply to this Mac.
        let tomb = Dictionary(uniqueKeysWithValues: merged.deleted.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
        if manager.syncSessions, merged.sessions != store.sessions || tomb != store.deleted {
            store.applySynced(sessions: merged.sessions, deleted: tomb)
        }
        if manager.syncSessions, merged.identitiesModified > local.identitiesModified {
            IdentityStore.shared.replaceAll(merged.identities)
            ud.set(merged.identitiesModified, forKey: "sync.identitiesModified")
        }
        if manager.syncMacros, merged.macrosModified > local.macrosModified {
            MacroStore.shared.replaceAll(merged.macros)
            ud.set(merged.macrosModified, forKey: "sync.macrosModified")
        }
        if manager.syncTunnels, merged.tunnelsModified > local.tunnelsModified {
            TunnelManager.shared.replaceAll(merged.tunnels)
            ud.set(merged.tunnelsModified, forKey: "sync.tunnelsModified")
        }
        if manager.syncMacros, merged.quickCommandsModified > local.quickCommandsModified {
            QuickCommandStore.shared.replaceAll(commands: merged.quickCommands, folders: merged.quickFolders)
            ud.set(merged.quickCommandsModified, forKey: "sync.quickCommandsModified")
        }
        if manager.syncSettings, merged.settingsModified > local.settingsModified, let data = merged.settings {
            manager.applyingSettings = true
            AppSettings.shared.applySynced(data)
            manager.applyingSettings = false
            ud.set(merged.settingsModified, forKey: "sync.settingsModified")
        }
        manager.devices = merged.devices

        let added = manager.syncSessions ? after.subtracting(before).count : 0
        let removed = manager.syncSessions ? before.subtracting(after).count : 0
        var parts = [manager.syncSessions ? "\(merged.sessions.count) sessions" : "sessions not synced"]
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
        if a.quickCommandsModified >= b.quickCommandsModified {
            out.quickCommands = a.quickCommands; out.quickFolders = a.quickFolders; out.quickCommandsModified = a.quickCommandsModified
        } else {
            out.quickCommands = b.quickCommands; out.quickFolders = b.quickFolders; out.quickCommandsModified = b.quickCommandsModified
        }
        if a.encryptionModified == b.encryptionModified {
            out.encrypted = a.encrypted || b.encrypted   // a tie keeps the data encrypted
            out.encryptionModified = a.encryptionModified
        } else if a.encryptionModified > b.encryptionModified { out.encrypted = a.encrypted; out.encryptionModified = a.encryptionModified }
        else { out.encrypted = b.encrypted; out.encryptionModified = b.encryptionModified }
        if a.identitiesModified >= b.identitiesModified { out.identities = a.identities; out.identitiesModified = a.identitiesModified }
        else { out.identities = b.identities; out.identitiesModified = b.identitiesModified }
        if a.settingsModified >= b.settingsModified { out.settings = a.settings ?? b.settings; out.settingsModified = a.settingsModified }
        else { out.settings = b.settings; out.settingsModified = b.settingsModified }
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
