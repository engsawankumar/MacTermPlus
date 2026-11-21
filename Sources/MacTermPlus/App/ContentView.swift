import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var workspace: Workspace
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @ViewState private var editing: SessionProfile?
    @ViewState private var connectTarget: SessionProfile?
    @ViewState private var passwordFor: SessionProfile?
    @ViewState private var showImport = false
    @ViewState private var showExport = false
    @ViewState private var panel: SidebarPanel = .sessions
    @ViewState private var showSidebar = true
    @ViewState private var showUnlock = false
    @ViewState private var pendingConnect: SessionProfile?

    var body: some View {
        VStack(spacing: 0) {
            MainToolbar(panel: $panel, showSidebar: $showSidebar, newSession: { editing = SessionProfile() })
            Divider()
            HSplitView {
                if showSidebar {
                    AppSidebar(panel: $panel, editing: $editing, connectTarget: $connectTarget, quickConnect: quickConnect)
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 520)
                }
                VStack(spacing: 0) {
                    TabStrip()
                    Divider()
                    MainArea(newSession: { editing = SessionProfile() }, importSessions: { showImport = true },
                             connect: { connect($0) })
                }
                .frame(minWidth: 500)
                .layoutPriority(1)
                if settings.showQuickCommands {
                    QuickCommandsPanel()
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 520)
                }
            }
        }
        .tint(settings.accent.color)
        .preferredColorScheme(settings.appearance.colorScheme)
        .sheet(item: $editing) { profile in
            SessionEditor(profile: profile) { saved, secret in
                workspace.open(saved.resolved(), secret: secret ?? Keychain.read(account: saved.secretAccount))
            }
            .environmentObject(store)
        }
        .sheet(item: $passwordFor) { profile in
            PasswordPrompt(profile: profile) { pw in workspace.open(profile, secret: pw) }
        }
        .sheet(isPresented: $showImport) { ImportSessionsView().environmentObject(store) }
        .sheet(isPresented: $showUnlock) {
            MasterPasswordSheet(mode: .unlock, onSkip: { pendingConnect.map(askOrOpen); pendingConnect = nil },
                                onForgot: { PasswordVault.shared.destroy(); Keychain.storage = .keychain }) { pw in
                try PasswordVault.shared.unlock(master: pw)
                if let p = pendingConnect { pendingConnect = nil; DispatchQueue.main.async { connect(p) } }
            }
        }
        .sheet(isPresented: $showExport) { ExportSessionsView().environmentObject(store) }
        .onChange(of: connectTarget) { _, target in
            guard let target else { return }
            connectTarget = nil
            connect(target)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSession)) { _ in editing = SessionProfile() }
        .onReceive(NotificationCenter.default.publisher(for: .importSessions)) { _ in showImport = true }
        .onReceive(NotificationCenter.default.publisher(for: .exportSessions)) { _ in showExport = true }
        .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in openWindow(id: "help") }
        .onReceive(NotificationCenter.default.publisher(for: .debugOpenWindow)) { n in if let id = n.object as? String { openWindow(id: id) } }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in openSettings() }
        .onReceive(NotificationCenter.default.publisher(for: Updater.showWindow)) { _ in openWindow(id: "update") }
        .onReceive(NotificationCenter.default.publisher(for: AnnouncementCenter.showWindow)) { _ in openWindow(id: "welcome") }
        .task {
            if Keychain.vaultLocked && !Showcase.isOn { showUnlock = true }
            if !Showcase.isOn {
                SyncManager.shared.attach(store: store)
                TunnelManager.shared.startAutoTunnels(store: store)
                Updater.shared.checkAtLaunchIfDue()
            }
            if ProcessInfo.processInfo.environment["MTP_DEMO"] == nil && !Showcase.isOn { AnnouncementCenter.shared.checkAtLaunch() }
            DebugHooks.run(workspace: workspace)
        }
    }

    private func connect(_ profile: SessionProfile) {
        if Keychain.vaultLocked && profile.auth == .password {
            pendingConnect = profile
            showUnlock = true
            return
        }
        askOrOpen(profile)
    }

    private func askOrOpen(_ profile: SessionProfile) {
        let profile = profile.resolved()
        let secret = Keychain.read(account: profile.secretAccount)
        let anonymousFTP = profile.kind.isFTP && profile.username.isEmpty
        if profile.auth == .password && secret == nil && !anonymousFTP {
            passwordFor = profile
        } else {
            workspace.open(profile, secret: secret)
        }
    }

    /// Returns a hint to show under the field, or nil when it connected.
    private func quickConnect(_ text: String) -> String? {
        guard let result = workspace.quickConnect(text, store: store) else { return nil }
        if result.hasPrefix("connect:"), let id = UUID(uuidString: String(result.dropFirst(8))),
           let p = store.sessions.first(where: { $0.id == id }) {
            connect(p)
            return nil
        }
        if result.hasPrefix("new:"), let data = result.dropFirst(4).data(using: .utf8),
           let p = try? JSONDecoder().decode(SessionProfile.self, from: data) {
            connect(p)
            return nil
        }
        return result
    }
}

// MARK: - Big-icon toolbar

struct MainToolbar: View {
    @EnvironmentObject var workspace: Workspace
    @ObservedObject var multiExec = MultiExec.shared
    @ObservedObject var sync = SyncManager.shared
    @ObservedObject var settings = AppSettings.shared
    @Binding var panel: SidebarPanel
    @Binding var showSidebar: Bool
    let newSession: () -> Void
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @ViewState private var showSync = false
    @ViewState private var showSplit = false

    var body: some View {
        HStack(spacing: 2) {
            ToolButton(icon: "plus.rectangle.on.rectangle", color: .teal, title: "Session", help: "New session (⌘N)", action: newSession)
            ToolButton(icon: "star.fill", color: .yellow, title: "Sessions", help: "Saved sessions") { show(.sessions) }
            ToolButton(icon: "folder.fill", color: .orange, title: "Files", help: "File browser of the current tab") { show(.files) }
            ToolButton(icon: "terminal.fill", color: .gray, title: "Terminal", help: "New local shell (⌘T)") { workspace.openLocal() }
            Divider().frame(height: 36).padding(.horizontal, 4)
            ToolButton(icon: "sidebar.left", color: .indigo, title: "View", help: "Show or hide the sidebar", active: showSidebar) {
                withAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
            }
            ToolButton(icon: workspace.split.icon, color: .cyan, title: "Split", help: "Show 2 or 4 terminals at once",
                       active: workspace.split != .single || showSplit) { showSplit.toggle() }
                .popover(isPresented: $showSplit) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Split terminals").font(.headline)
                        ForEach(SplitLayout.allCases) { l in
                            Button { workspace.split = l; showSplit = false } label: {
                                HStack {
                                    Image(systemName: l.icon).frame(width: 22)
                                    Text(l.label)
                                    Spacer()
                                    if workspace.split == l { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                        }
                        Text("Shows the current terminal plus the next open ones.").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(width: 240)
                }
            ToolButton(icon: "square.stack.3d.down.forward.fill", color: .pink, title: "MultiExec",
                       help: "Type in all terminals at once", active: multiExec.enabled) { multiExec.enabled.toggle() }
            ToolButton(icon: "point.3.connected.trianglepath.dotted", color: .green, title: "Tunneling", help: "SSH tunnels") { show(.tunnels) }
            if settings.quickCommandsButton {
                ToolButton(icon: "bolt.horizontal.fill", color: .mint, title: "Commands",
                           help: "Quick Commands: ready-made server commands (⇧⌘K)", active: settings.showQuickCommands) {
                    withAnimation(.easeOut(duration: 0.15)) { settings.showQuickCommands.toggle() }
                }
                .contextMenu {
                    Button(settings.showQuickCommands ? "Close Quick Commands" : "Open Quick Commands") { settings.showQuickCommands.toggle() }
                    Button("Hide This Button") { settings.showQuickCommands = false; settings.quickCommandsButton = false }
                }
            }
            ToolButton(icon: "key.horizontal.fill", color: .orange, title: "Keychain",
                       help: "SSH keys, identities, known hosts and saved passwords (⌥⌘K)") { openWindow(id: "keychain") }
            ToolButton(icon: "paperplane.fill", color: .blue, title: "Macros", help: "Saved commands") { show(.macros) }
            ToolButton(icon: "wrench.and.screwdriver.fill", color: .red, title: "Tools", help: "Key generator, port checker…") { show(.tools) }
            Divider().frame(height: 36).padding(.horizontal, 4)
            ToolButton(icon: sync.isSyncing ? "arrow.triangle.2.circlepath.icloud.fill" : (sync.enabled ? "checkmark.icloud.fill" : "icloud.slash.fill"),
                       color: sync.lastError != nil ? .orange : (sync.enabled ? .blue : .gray), title: "Sync",
                       help: "Sync sessions across your Macs", active: showSync) { showSync.toggle() }
                .popover(isPresented: $showSync) { SyncPopover() }
            ToolButton(icon: "gearshape.fill", color: .gray, title: "Settings", help: "Settings (⌘,)") { openSettings() }
            ToolButton(icon: "questionmark.circle.fill", color: .purple, title: "Help", help: "Help (⌘?)") { openWindow(id: "help") }
            Spacer(minLength: 8)
            if multiExec.enabled {
                Label("MultiExec ON — typing goes to all \(multiExec.terminalCount) terminals", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.pink, in: Capsule())
            }
            ToolButton(icon: "power", color: .red, title: "Exit", help: "Quit MacTerm+ (⌘Q)") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func show(_ p: SidebarPanel) {
        panel = p
        if !showSidebar { showSidebar = true }
    }
}

private struct ToolLabel: View {
    let icon: String
    let color: Color
    let title: String
    var active = false
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 3) {
            Group {
                if settings.iconStyle == .vivid {
                    IconTile(symbol: icon, color: color, size: 30)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(settings.iconStyle == .mono ? .secondary : color)
                        .frame(width: 30, height: 30)
                }
            }
            Text(title).font(.system(size: 11)).foregroundStyle(.primary).lineLimit(1)
        }
        .frame(minWidth: 56)
        .padding(.vertical, 3)
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 7).fill(active ? color.opacity(0.2) : .clear))
        .contentShape(Rectangle())
    }
}

private struct ToolButton: View {
    let icon: String
    let color: Color
    let title: String
    let help: String
    var active = false
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            ToolLabel(icon: icon, color: color, title: title, active: active || hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct SyncPopover: View {
    @ObservedObject var sync = SyncManager.shared
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconTile(symbol: "icloud.fill", color: .blue, size: 32)
                VStack(alignment: .leading) {
                    Text("Sync").font(.headline)
                    Text(sync.enabled ? (sync.folderPath as NSString).abbreviatingWithTildeInPath : "Off")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            if sync.enabled {
                if let e = sync.lastError { Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout) }
                if let last = sync.lastSync {
                    Text("Last sync \(last.formatted(.relative(presentation: .named)))\(sync.lastSummary.isEmpty ? "" : " · " + sync.lastSummary)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !sync.devices.isEmpty {
                    Text("Devices").font(.caption.weight(.semibold))
                    ForEach(sync.devices) { d in
                        Label("\(d.name)\(d.id == sync.deviceID ? " (this Mac)" : "")", systemImage: "laptopcomputer")
                            .font(.callout)
                    }
                }
                HStack {
                    Button(sync.isSyncing ? "Syncing…" : "Sync Now") { Task { await sync.syncNow() } }.disabled(sync.isSyncing)
                    Spacer()
                    Button("Change Setup…") { openWindow(id: "sync-setup") }
                    Button("Settings…") { openSettings(); NotificationCenter.default.post(name: .showSyncSettings, object: nil) }
                }
            } else {
                Text("Keep sessions, passwords, settings, macros and tunnels the same on all your Macs using iCloud Drive or Google Drive.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Set Up Sync…") { openWindow(id: "sync-setup") }.buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

// MARK: - Tabs

struct TabStrip: View {
    @EnvironmentObject var workspace: Workspace
    @ViewState private var confirmClose: UUID?

    var body: some View {
        HStack(spacing: 0) {
            Button { workspace.selectedID = nil } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(workspace.selectedID == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 34, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(workspace.selectedID == nil ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.clear)))
            }
            .buttonStyle(.plain)
            .help("Home")
            .padding(.leading, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabButton(tab: tab, number: index + 1, selected: tab.id == workspace.selectedID,
                                  onSelect: { workspace.selectedID = tab.id },
                                  onClose: { requestClose(tab) })
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
            }
            Button { workspace.openLocal() } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 24)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("New local shell (⌘T)")
            .padding(.horizontal, 8)
        }
        .background(.bar)
        .confirmationDialog("Close this tab?", isPresented: Binding(get: { confirmClose != nil }, set: { if !$0 { confirmClose = nil } })) {
            Button("Close Tab", role: .destructive) { if let id = confirmClose { workspace.close(id) } }
        } message: {
            Text("The connection will be closed. You can turn this question off in Settings → General.")
        }
    }

    private func requestClose(_ tab: WorkspaceTab) {
        if AppSettings.shared.confirmCloseTab, case .ssh(let t) = tab, t.isLive {
            confirmClose = tab.id
        } else {
            workspace.close(tab.id)
        }
    }
}

private struct TabButton: View {
    let tab: WorkspaceTab
    let number: Int
    let selected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @ViewState private var hovering = false
    @ObservedObject private var settings = AppSettings.shared

    private var tint: Color { tab.profile?.color.color ?? .gray }
    private var useSessionColor: Bool { settings.coloredTabs && tab.profile != nil }

    var body: some View {
        HStack(spacing: 7) {
            switch tab {
            case .ssh(let t): SSHTabBadge(tab: t)
            case .ftp(let t): Image(systemName: t.profile.kind.icon).font(.caption).foregroundStyle(t.profile.color.color)
            case .local: Image(systemName: "laptopcomputer").font(.caption).foregroundStyle(.secondary)
            }
            Text("\(number). \(tab.title)").lineLimit(1).font(.callout.weight(selected ? .semibold : .regular))
            if let kind = tab.profile?.kind, kind != .ssh {
                Text(kind.label).font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.secondary.opacity(0.2), in: Capsule())
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .opacity(hovering || selected ? 1 : 0)
            .help("Close tab (⇧⌘W)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(useSessionColor
                      ? AnyShapeStyle(tint.opacity(selected ? 0.32 : (hovering ? 0.18 : 0.12)))
                      : (selected ? AnyShapeStyle(.tint.opacity(0.20)) : AnyShapeStyle(hovering ? Color.primary.opacity(0.07) : .clear)))
        }
        .overlay(alignment: .bottom) {
            if selected { Capsule().fill(useSessionColor ? AnyShapeStyle(tint) : AnyShapeStyle(.tint)).frame(height: 2).padding(.horizontal, 10) }
        }
        .overlay(alignment: .leading) {
            if useSessionColor { Capsule().fill(tint).frame(width: 3).padding(.vertical, 5) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}

/// Session-colored dot that reflects connection state.
private struct SSHTabBadge: View {
    @ObservedObject var tab: SSHTab
    @ObservedObject var connection: SSHConnection

    init(tab: SSHTab) {
        self.tab = tab
        self.connection = tab.connection
    }

    var body: some View {
        ZStack {
            Circle().fill(tab.connection.profile.color.color).frame(width: 9, height: 9)
            if connection.state == .connecting {
                Circle().stroke(.orange, lineWidth: 2).frame(width: 13, height: 13)
            } else if case .failed = connection.state {
                Circle().stroke(.red, lineWidth: 2).frame(width: 13, height: 13)
            }
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Main area

private struct MainArea: View {
    @EnvironmentObject var workspace: Workspace
    let newSession: () -> Void
    let importSessions: () -> Void
    let connect: (SessionProfile) -> Void

    var body: some View {
        if workspace.split != .single, workspace.tabs.filter(\.hasTerminal).count > 1, workspace.selected?.hasTerminal ?? false {
            SplitTerminals()
        } else if let tab = workspace.selected {
            switch tab {
            case .ssh(let t): SSHTabView(tab: t).id(t.id)
            case .ftp(let t): FTPTabView(tab: t).id(t.id)
            case .local(let t): LocalTerminalRepresentable(controller: t.terminal).id(t.id)
            }
        } else {
            WelcomeView(newSession: newSession, importSessions: importSessions, connect: connect)
        }
    }
}

/// 2 or 4 terminals at once.
private struct SplitTerminals: View {
    @EnvironmentObject var workspace: Workspace

    var body: some View {
        let tabs = workspace.splitTabs
        Group {
            switch workspace.split {
            case .sideBySide: HSplitView { ForEach(tabs, id: \.id) { cell($0) } }
            case .stacked: VSplitView { ForEach(tabs, id: \.id) { cell($0) } }
            default:
                VSplitView {
                    HSplitView { ForEach(tabs.prefix(2), id: \.id) { cell($0) } }
                    if tabs.count > 2 { HSplitView { ForEach(tabs.dropFirst(2), id: \.id) { cell($0) } } }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ tab: WorkspaceTab) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(tab.title).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tab.id == workspace.selectedID ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.bar))
            .onTapGesture { workspace.selectedID = tab.id }
            switch tab {
            case .ssh(let t): SSHTerminalRepresentable(controller: t.terminal)
            case .local(let t): LocalTerminalRepresentable(controller: t.terminal)
            case .ftp: EmptyView()
            }
        }
        .frame(minWidth: 200, minHeight: 120)
    }
}

/// Terminal (or two-pane files) with the server info bar below.
struct SSHTabView: View {
    @ObservedObject var tab: SSHTab
    @ObservedObject var connection: SSHConnection
    @ObservedObject var terminal: SSHTerminalController
    @ObservedObject var settings = AppSettings.shared

    init(tab: SSHTab) {
        self.tab = tab
        self.connection = tab.connection
        self.terminal = tab.terminal
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !tab.filesOnly {
                    Picker("", selection: $tab.mode) {
                        Label("Terminal", systemImage: "terminal").tag(SSHTab.Mode.terminal)
                        Label("Files", systemImage: "rectangle.split.2x1").tag(SSHTab.Mode.commander)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                } else {
                    Label("SFTP — files only", systemImage: "externaldrive.connected.to.line.below.fill").font(.callout)
                }
                Spacer()
                Text(connection.profile.endpoint).font(.caption).foregroundStyle(.secondary)
                StatusBadge(state: connection.state)
                if terminal.hasEnded, !terminal.isRunning {
                    Button { tab.mode = .terminal; terminal.start() } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            switch tab.mode {
            case .terminal:
                SSHTerminalRepresentable(controller: tab.terminal)
            case .commander:
                CommanderView(remote: tab.remote, local: tab.local, title: connection.profile.displayName,
                              color: connection.profile.color.color, icon: connection.profile.kind.icon)
            }
            if settings.showStatusBar {
                Divider()
                ServerStatusBar(stats: tab.stats)
            }
        }
    }
}

/// FTP / FTPS: two-pane files.
private struct FTPTabView: View {
    @ObservedObject var tab: FTPTab
    @ObservedObject var remote: RemoteFileBrowser

    init(tab: FTPTab) {
        self.tab = tab
        self.remote = tab.remote
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(tab.profile.kind == .ftps ? "FTPS — encrypted (TLS)" : "FTP — not encrypted",
                      systemImage: tab.profile.kind == .ftps ? "lock.fill" : "lock.open.fill")
                    .font(.callout)
                    .foregroundStyle(tab.profile.kind == .ftps ? .green : .orange)
                Spacer()
                Text(tab.profile.endpoint).font(.caption).foregroundStyle(.secondary)
                if remote.errorMessage != nil {
                    Button { Task { await remote.refresh() } } label: { Label("Retry", systemImage: "arrow.clockwise") }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            CommanderView(remote: tab.remote, local: tab.local, title: tab.profile.displayName,
                          color: tab.profile.color.color, icon: tab.profile.kind.icon)
        }
    }
}

private struct StatusBadge: View {
    let state: SSHConnection.State
    var body: some View {
        let (text, color): (String, Color) = {
            switch state {
            case .idle: return ("Idle", .secondary)
            case .connecting: return ("Connecting…", .orange)
            case .connected: return ("Connected", .green)
            case .failed: return ("Failed", .red)
            case .closed: return ("Closed", .secondary)
            }
        }()
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .help({ if case .failed(let m) = state { return m }; return text }())
    }
}

/// Two panes: your Mac on the left, the server on the right, transfer queue below.
struct CommanderView: View {
    @ObservedObject var remote: RemoteFileBrowser
    let local: LocalFileBrowser
    let title: String
    let color: Color
    let icon: String
    @ObservedObject var queue: TransferQueue
    @ViewState private var remoteSelection: Set<String> = []
    @ViewState private var localSelection: Set<String> = []

    init(remote: RemoteFileBrowser, local: LocalFileBrowser, title: String, color: Color, icon: String) {
        self.remote = remote
        self.local = local
        self.title = title
        self.color = color
        self.icon = icon
        self.queue = remote.queue
    }

    var body: some View {
        VSplitView {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    paneHeader("This Mac", icon: "laptopcomputer", color: .gray)
                    LocalFilePane(browser: local, selection: $localSelection)
                }
                VStack(spacing: 14) {
                    Button { upload() } label: {
                        Image(systemName: "arrow.right.circle.fill").font(.system(size: 26)).foregroundStyle(.tint)
                    }
                    .disabled(localSelection.isEmpty)
                    .help("Upload selected to server")
                    Button { download() } label: {
                        Image(systemName: "arrow.left.circle.fill").font(.system(size: 26)).foregroundStyle(.green)
                    }
                    .disabled(remoteSelection.isEmpty)
                    .help("Download selected to this Mac")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
                VStack(spacing: 0) {
                    paneHeader(title, icon: icon, color: color)
                    RemoteFilePane(browser: remote, selection: $remoteSelection)
                }
            }
            .frame(minHeight: 250, maxHeight: .infinity)
            .layoutPriority(1)
            transferList
                .frame(minHeight: 80, idealHeight: 140, maxHeight: 260)
        }
    }

    private func paneHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            IconTile(symbol: icon, color: color, size: 22)
            Text(title).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var transferList: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Transfers", systemImage: "arrow.up.arrow.down.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                Button("Clear Finished") { queue.clearFinished() }
                    .buttonStyle(.borderless)
                    .disabled(!queue.transfers.contains { $0.status == .done })
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            if queue.transfers.isEmpty {
                Text("Select files and use the arrows, or drag files from Finder onto the server pane.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(queue.transfers.reversed()) { TransferRow(transfer: $0) }
                    .listStyle(.plain)
            }
        }
    }

    private func upload() {
        let urls = local.items.filter { localSelection.contains($0.id) }.map { URL(fileURLWithPath: $0.path) }
        remote.upload(urls)
    }

    private func download() {
        let items = remote.items.filter { remoteSelection.contains($0.id) }
        let local = self.local
        remote.download(items, to: local.url) { local.refresh() }
    }
}

// MARK: - Home

struct WelcomeView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var store: SessionStore
    @Environment(\.openWindow) private var openWindow
    let newSession: () -> Void
    let importSessions: () -> Void
    let connect: (SessionProfile) -> Void

    private var recent: [SessionProfile] {
        workspace.recentIDs.compactMap { id in store.sessions.first { $0.id == id } }.prefix(8).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 10) {
                    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let img = NSImage(contentsOf: url) {
                        Image(nsImage: img).resizable().frame(width: 96, height: 96)
                    } else {
                        IconTile(symbol: "terminal.fill", color: .teal, size: 84)
                    }
                    Text("MacTerm+").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("SSH terminal, SFTP & FTP file manager, tunnels and tools — in one window.")
                        .foregroundStyle(.secondary)
                    BuiltByBadge()
                }
                .padding(.top, 34)

                HStack(spacing: 14) {
                    ActionCard(icon: "plus.rectangle.on.rectangle", color: .teal, title: "New Session",
                               subtitle: "SSH, SFTP, FTP, FTPS", shortcut: "⌘N", action: newSession)
                    ActionCard(icon: "terminal.fill", color: .gray, title: "Local Shell",
                               subtitle: "Terminal on this Mac", shortcut: "⌘T") { workspace.openLocal() }
                    ActionCard(icon: "square.and.arrow.down.fill", color: .orange, title: "Import",
                               subtitle: "From other apps", shortcut: "⇧⌘I", action: importSessions)
                    ActionCard(icon: "questionmark.circle.fill", color: .purple, title: "Help",
                               subtitle: "Guide & shortcuts", shortcut: "⌘?") { openWindow(id: "help") }
                }

                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent sessions").font(.headline).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                            ForEach(recent) { p in
                                Button { connect(p) } label: {
                                    HStack(spacing: 10) {
                                        IconTile(symbol: p.kind.icon, color: p.color.color, size: 32)
                                        VStack(alignment: .leading) {
                                            Text(p.displayName).lineLimit(1)
                                            Text(p.endpoint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.right.circle").foregroundStyle(.tertiary)
                                    }
                                    .padding(10)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: 760)
                } else {
                    Text("Double-click a saved session in the sidebar, or type user@host in Quick connect.")
                        .font(.callout).foregroundStyle(.tertiary)
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ActionCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let shortcut: String
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                IconTile(symbol: icon, color: color, size: 44)
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                Text(shortcut).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            .frame(width: 150, height: 140)
            .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(hovering ? 0.9 : 0.45)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(hovering ? 0.6 : 0), lineWidth: 1.5))
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension Notification.Name {
    static let newSession = Notification.Name("MacTermPlus.newSession")
    static let showSettings = Notification.Name("MacTermPlus.showSettings")
    static let showSyncSettings = Notification.Name("MacTermPlus.showSyncSettings")
    static let debugOpenWindow = Notification.Name("MacTermPlus.debugOpenWindow")
}
