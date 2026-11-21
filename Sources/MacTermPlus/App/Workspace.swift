import Combine
import Foundation
import SwiftUI

/// An open SSH or SFTP tab: one connection shared by the terminal, the file browser and the stats bar.
@MainActor
final class SSHTab: ObservableObject, Identifiable {
    enum Mode: String, CaseIterable, Identifiable {
        case terminal = "Terminal"
        case commander = "Files"
        var id: String { rawValue }
    }

    let id = UUID()
    let connection: SSHConnection
    let terminal: SSHTerminalController
    let remote: RemoteFileBrowser
    let local = LocalFileBrowser()
    let stats = ServerStats()
    let filesOnly: Bool
    @Published var mode: Mode
    private var stateWatch: AnyCancellable?

    init(profile: SessionProfile, secret: String?) {
        connection = SSHConnection(profile: profile, secret: secret)
        terminal = SSHTerminalController(connection: connection)
        remote = RemoteFileBrowser(fs: Showcase.isOn ? ShowcaseFileSystem() : SFTPFileSystem(connection: connection),
                                   title: profile.displayName)
        filesOnly = profile.kind == .sftp
        mode = profile.kind == .sftp ? .commander : .terminal
        terminal.onDirectoryChange = { [weak remote] dir in remote?.terminalChangedDirectory(dir) }
        let profileID = profile.id
        stats.onOSDetected = { os in
            NotificationCenter.default.post(name: SessionStore.osDetected, object: nil,
                                            userInfo: ["id": profileID, "os": os])
        }
        if filesOnly { Task { [weak self] in _ = try? await self?.connection.connectedClient() } }
        if Showcase.isOn {
            connection.state = .connected
            stats.fillShowcase()
            return
        }
        stateWatch = connection.$state.sink { [weak self] state in
            guard let self else { return }
            if state == .connected {
                // Open the stats channel only after the shell channel is up: opening both at the
                // same moment can leave the terminal without output.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for _ in 0..<50 where !self.terminal.ptyReady && (self.terminal.isRunning || self.mode == .terminal) && !self.filesOnly {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    try? await Task.sleep(for: .seconds(1))
                    self.stats.start(connection: self.connection)
                }
            }
            if state == .closed { self.stats.stop() }
        }
    }

    var isLive: Bool { connection.state == .connected || terminal.isRunning }

    func close() {
        stats.stop()
        terminal.stop()
        remote.stop()
        connection.disconnect()
    }
}

/// An open FTP / FTPS tab (files only).
@MainActor
final class FTPTab: ObservableObject, Identifiable {
    let id = UUID()
    let profile: SessionProfile
    let remote: RemoteFileBrowser
    let local = LocalFileBrowser()

    init(profile: SessionProfile, secret: String?) {
        self.profile = profile
        let fs = FTPFileSystem(config: .init(host: profile.host, port: profile.port, username: profile.username,
                                             password: secret ?? "", secure: profile.kind == .ftps,
                                             acceptInvalidCertificates: profile.acceptInvalidCertificates,
                                             initialPath: profile.initialRemotePath))
        remote = RemoteFileBrowser(fs: fs, title: profile.displayName)
    }

    func close() { remote.stop() }
}

@MainActor
final class LocalTab: ObservableObject, Identifiable {
    let id = UUID()
    let terminal = LocalTerminalController()
    func close() { terminal.stop() }
}

enum WorkspaceTab: Identifiable {
    case ssh(SSHTab)
    case ftp(FTPTab)
    case local(LocalTab)

    @MainActor var id: UUID {
        switch self {
        case .ssh(let t): return t.id
        case .ftp(let t): return t.id
        case .local(let t): return t.id
        }
    }

    @MainActor var title: String {
        switch self {
        case .ssh(let t): return t.connection.profile.displayName
        case .ftp(let t): return t.profile.displayName
        case .local: return "Local Shell"
        }
    }

    @MainActor var profile: SessionProfile? {
        switch self {
        case .ssh(let t): return t.connection.profile
        case .ftp(let t): return t.profile
        case .local: return nil
        }
    }

    /// The file browser of this tab, if it has one.
    @MainActor var remote: RemoteFileBrowser? {
        switch self {
        case .ssh(let t): return t.remote
        case .ftp(let t): return t.remote
        case .local: return nil
        }
    }

    @MainActor var hasTerminal: Bool {
        switch self {
        case .ssh(let t): return !t.filesOnly
        case .local: return true
        case .ftp: return false
        }
    }

    @MainActor func sendText(_ text: String) {
        switch self {
        case .ssh(let t): t.terminal.sendText(text)
        case .local(let t): t.terminal.sendText(text)
        case .ftp: break
        }
    }
}

enum SplitLayout: String, CaseIterable, Identifiable {
    case single, sideBySide, stacked, grid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .single: return "Single"
        case .sideBySide: return "2 side by side"
        case .stacked: return "2 stacked"
        case .grid: return "4 in a grid"
        }
    }
    var icon: String {
        switch self {
        case .single: return "rectangle"
        case .sideBySide: return "rectangle.split.2x1"
        case .stacked: return "rectangle.split.1x2"
        case .grid: return "rectangle.split.2x2"
        }
    }
    var capacity: Int {
        switch self {
        case .single: return 1
        case .sideBySide, .stacked: return 2
        case .grid: return 4
        }
    }
}

/// The set of open tabs in the window.
@MainActor
final class Workspace: ObservableObject {
    @Published var tabs: [WorkspaceTab] = []
    @Published var selectedID: UUID?
    @Published var split: SplitLayout = .single
    /// Asks the sidebar to show a panel (e.g. the file browser when a session connects).
    @Published var sidebarRequest: SidebarPanel?
    @Published private(set) var recentIDs: [UUID] =
        (UserDefaults.standard.stringArray(forKey: "recentSessions") ?? []).compactMap(UUID.init(uuidString:))

    var selected: WorkspaceTab? { tabs.first { $0.id == selectedID } }

    /// Terminal tabs shown when the split view is on: the selected one first, then the next ones.
    var splitTabs: [WorkspaceTab] {
        let terms = tabs.filter(\.hasTerminal)
        guard let sel = selected, sel.hasTerminal, let i = terms.firstIndex(where: { $0.id == sel.id }) else {
            return Array(terms.prefix(split.capacity))
        }
        return Array((terms[i...] + terms[..<i]).prefix(split.capacity))
    }

    func isOpen(_ profile: SessionProfile) -> Bool {
        tabs.contains { $0.profile?.id == profile.id }
    }

    private func remember(_ profile: SessionProfile) {
        guard !Showcase.isOn else { return }
        recentIDs.removeAll { $0 == profile.id }
        recentIDs.insert(profile.id, at: 0)
        recentIDs = Array(recentIDs.prefix(12))
        UserDefaults.standard.set(recentIDs.map(\.uuidString), forKey: "recentSessions")
    }

    func open(_ profile: SessionProfile, secret: String?) {
        remember(profile)
        let tab: WorkspaceTab
        switch profile.kind {
        case .ssh, .sftp: tab = .ssh(SSHTab(profile: profile, secret: secret))
        case .ftp, .ftps: tab = .ftp(FTPTab(profile: profile, secret: secret))
        }
        tabs.append(tab)
        selectedID = tab.id
        if profile.openFilesPanel || profile.kind != .ssh { sidebarRequest = .files }
    }

    func openLocal() {
        let tab = WorkspaceTab.local(LocalTab())
        tabs.append(tab)
        selectedID = tab.id
    }

    func close(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        switch tabs[idx] {
        case .ssh(let t): t.close()
        case .ftp(let t): t.close()
        case .local(let t): t.close()
        }
        tabs.remove(at: idx)
        if selectedID == id {
            selectedID = tabs.isEmpty ? nil : tabs[min(idx, tabs.count - 1)].id
        }
    }

    func closeSelected() {
        if let selectedID { close(selectedID) }
    }

    func selectNext(_ delta: Int) {
        guard !tabs.isEmpty else { return }
        guard let idx = tabs.firstIndex(where: { $0.id == selectedID }) else { selectedID = tabs.first?.id; return }
        selectedID = tabs[(idx + delta + tabs.count) % tabs.count].id
    }

    /// Opens "user@host:port", "sftp://…", "ftp://…" or "ftps://…" typed into Quick connect.
    func quickConnect(_ text: String, store: SessionStore) -> String? {
        var t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        var kind = SessionKind.ssh
        for k in [SessionKind.sftp, .ftps, .ftp, .ssh] where t.lowercased().hasPrefix(k.rawValue + "://") {
            kind = k
            t = String(t.dropFirst(k.rawValue.count + 3))
            break
        }
        if t.hasPrefix("ssh ") { t = String(t.dropFirst(4)) }
        var user = ""
        if let at = t.lastIndex(of: "@") { user = String(t[..<at]); t = String(t[t.index(after: at)...]) }
        var port = kind.defaultPort
        if let colon = t.lastIndex(of: ":"), !t.contains("]"), let p = Int(t[t.index(after: colon)...]) {
            port = p
            t = String(t[..<colon])
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "[]/"))
        guard !t.isEmpty else { return "Type a host, e.g. root@192.168.1.10 or ftp://example.com" }
        if user.isEmpty && !kind.isFTP { user = NSUserName() }
        // Reuse a saved session for the same server so its password/key are used.
        if let saved = store.sessions.first(where: { $0.host.caseInsensitiveCompare(t) == .orderedSame && $0.port == port
            && (user.isEmpty || $0.username == user) && $0.kind.isFTP == kind.isFTP }) {
            return "connect:\(saved.id.uuidString)"
        }
        var p = SessionProfile(name: "", host: t, port: port, username: user)
        p.kind = kind
        if kind == .ssh || kind == .sftp, let key = ["id_ed25519", "id_rsa"].map({ NSHomeDirectory() + "/.ssh/" + $0 })
            .first(where: { FileManager.default.fileExists(atPath: $0) }) {
            p.auth = .privateKey
            p.keyPath = key
        }
        return "new:" + (try! String(data: JSONEncoder().encode(p), encoding: .utf8)!)
    }
}

enum SidebarPanel: String, CaseIterable, Identifiable {
    case sessions, files, macros, tools, tunnels
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sessions: return "Sessions"
        case .files: return "Files"
        case .macros: return "Macros"
        case .tools: return "Tools"
        case .tunnels: return "Tunnels"
        }
    }
    var icon: String {
        switch self {
        case .sessions: return "star.fill"
        case .files: return "folder.fill"
        case .macros: return "paperplane.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .tunnels: return "point.3.connected.trianglepath.dotted"
        }
    }
    var color: Color {
        switch self {
        case .sessions: return .yellow
        case .files: return .orange
        case .macros: return .blue
        case .tools: return .red
        case .tunnels: return .green
        }
    }
}
