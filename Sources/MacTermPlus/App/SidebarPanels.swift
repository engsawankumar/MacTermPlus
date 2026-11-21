import AppKit
import Network
import SwiftUI

/// Left side: a vertical rail of panels (Sessions, Files, Macros, Tools, Tunnels) plus Quick connect.
struct AppSidebar: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var workspace: Workspace
    @Binding var panel: SidebarPanel
    @Binding var editing: SessionProfile?
    @Binding var connectTarget: SessionProfile?
    let quickConnect: (String) -> String?

    var body: some View {
        HStack(spacing: 0) {
            SidebarRail(panel: $panel)
            Divider()
            VStack(spacing: 0) {
                QuickConnectField(action: quickConnect)
                Divider()
                switch panel {
                case .sessions: SessionSidebar(editing: $editing, connectTarget: $connectTarget)
                case .files: FilesPanel()
                case .macros: MacrosPanel()
                case .tools: ToolsPanel()
                case .tunnels: TunnelsPanel()
                }
            }
        }
        .onChange(of: workspace.sidebarRequest) { _, req in
            if let req { panel = req; workspace.sidebarRequest = nil }
        }
    }
}

/// Vertical tab rail with rotated labels.
private struct SidebarRail: View {
    @Binding var panel: SidebarPanel

    var body: some View {
        VStack(spacing: 4) {
            ForEach(SidebarPanel.allCases) { p in
                Button { panel = p } label: {
                    VStack(spacing: 6) {
                        Image(systemName: p.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(panel == p ? p.color : .secondary)
                        Text(p.label)
                            .font(.system(size: 10, weight: panel == p ? .bold : .regular))
                            .fixedSize()
                            .rotationEffect(.degrees(-90))
                            .frame(width: 14, height: CGFloat(p.label.count) * 6.2 + 4)
                    }
                    .frame(width: 30)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(panel == p ? p.color.opacity(0.18) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(p.label)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 3)
        .background(.bar)
    }
}

/// "user@host:port", "sftp://…", "ftp://…" → connect.
struct QuickConnectField: View {
    let action: (String) -> String?
    @ViewState private var text = ""
    @ViewState private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                TextField("Quick connect… user@host or ftp://host", text: $text)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        hint = action(text)
                        if hint == nil { text = "" }
                    }
            }
            .padding(7)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            if let hint { Text(hint).font(.caption).foregroundStyle(.orange) }
        }
        .padding(8)
    }
}

// MARK: - Files

/// The file browser of the selected tab, shown in the sidebar.
struct FilesPanel: View {
    @EnvironmentObject var workspace: Workspace
    @ViewState private var selection: Set<String> = []

    var body: some View {
        if let tab = workspace.selected, let browser = tab.remote {
            FilesPanelContent(browser: browser, tab: tab, selection: $selection).id(tab.id)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.questionmark").font(.system(size: 34)).foregroundStyle(.secondary)
                Text("Open an SSH, SFTP or FTP session to browse its files here.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FilesPanelContent: View {
    @ObservedObject var browser: RemoteFileBrowser
    let tab: WorkspaceTab
    @Binding var selection: Set<String>
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            RemoteFilePane(browser: browser, compact: true, selection: $selection)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if browser.canUseRoot {
                    RootModeToggle(browser: browser)
                }
                if case .ssh(let t) = tab, !t.filesOnly {
                    Toggle(isOn: $browser.followTerminal) {
                        Label("Follow terminal folder", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                    Toggle(isOn: $settings.showStatusBar) {
                        Label("Remote monitoring", systemImage: "waveform.path.ecg")
                    }
                }
            }
            .toggleStyle(.checkbox)
            .font(.callout)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Macros

struct MacrosPanel: View {
    @EnvironmentObject var workspace: Workspace
    @ObservedObject var macros = MacroStore.shared
    @ViewState private var editing: Macro?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(macros.macros) { m in
                    HStack {
                        IconTile(symbol: "paperplane.fill", color: .blue, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name).lineLimit(1)
                            Text(m.command).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { run(m) } label: { Image(systemName: "play.circle.fill").font(.title3) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.green)
                            .disabled(!(workspace.selected?.hasTerminal ?? false))
                            .help("Send to the current terminal")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { run(m) }
                    .contextMenu {
                        Button("Run") { run(m) }
                        Button("Run in All Terminals") { runEverywhere(m) }
                        Button("Edit…") { editing = m }
                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(m.command, forType: .string)
                        }
                        Divider()
                        Button("Delete", role: .destructive) { macros.delete(m) }
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack {
                Button { editing = Macro(name: "", command: "") } label: { Label("New Macro", systemImage: "plus") }
                Spacer()
                Text("Double-click to run").font(.caption).foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .sheet(item: $editing) { m in MacroEditor(macro: m) }
    }

    private func text(_ m: Macro) -> String { m.command + (m.pressEnter ? "\r" : "") }
    private func run(_ m: Macro) { workspace.selected?.sendText(text(m)) }
    private func runEverywhere(_ m: Macro) { for t in workspace.tabs where t.hasTerminal { t.sendText(text(m)) } }
}

private struct MacroEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState var macro: Macro

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(macro.name.isEmpty ? "New Macro" : "Edit Macro").font(.title2.bold())
            TextField("Name", text: $macro.name, prompt: Text("Restart web server"))
            Text("Command").font(.callout)
            TextEditor(text: $macro.command)
                .font(.system(.body, design: .monospaced))
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
            Toggle("Press Return after sending", isOn: $macro.pressEnter)
            Text("Several lines run one after another.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    MacroStore.shared.upsert(macro)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(macro.name.isEmpty || macro.command.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

// MARK: - Tunnels

struct TunnelsPanel: View {
    @EnvironmentObject var store: SessionStore
    @ObservedObject var manager = TunnelManager.shared
    @ViewState private var editing: TunnelConfig?

    var body: some View {
        VStack(spacing: 0) {
            if manager.tunnels.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 34)).foregroundStyle(.green)
                    Text("SSH tunnels").font(.headline)
                    Text("Reach a service behind a server (a database, a web admin page…) through a port on this Mac.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("New Tunnel…") { editing = TunnelConfig() }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(manager.tunnels) { t in
                    TunnelRow(tunnel: t, state: manager.state(t),
                              session: store.sessions.first { $0.id == t.sessionID }) {
                        switch manager.state(t) {
                        case .running, .starting: manager.stop(t)
                        default: manager.start(t, store: store)
                        }
                    }
                    .contextMenu {
                        Button("Edit…") { editing = t }
                        if case .running = manager.state(t) {
                            Button("Open http://localhost:\(t.localPort)") {
                                NSWorkspace.shared.open(URL(string: "http://localhost:\(t.localPort)")!)
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) { manager.delete(t) }
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            HStack {
                Button { editing = TunnelConfig() } label: { Label("New Tunnel", systemImage: "plus") }
                Spacer()
                Button("Stop All") { manager.stopAll() }
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .sheet(item: $editing) { t in TunnelEditor(tunnel: t).environmentObject(store) }
    }
}

private struct TunnelRow: View {
    let tunnel: TunnelConfig
    let state: TunnelManager.State
    let session: SessionProfile?
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.name.isEmpty ? tunnel.summary : tunnel.name).lineLimit(1)
                Text("\(tunnel.summary) via \(session?.displayName ?? "?")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if case .failed(let m) = state { Text(m).font(.caption).foregroundStyle(.red).lineLimit(2) }
                if case .running(let n) = state, n > 0 { Text("\(n) active connection\(n == 1 ? "" : "s")").font(.caption).foregroundStyle(.green) }
            }
            Spacer()
            Button(action: toggle) {
                Image(systemName: isOn ? "stop.circle.fill" : "play.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isOn ? .red : .green)
        }
    }

    private var isOn: Bool {
        switch state { case .running, .starting: return true; default: return false }
    }

    private var color: Color {
        switch state {
        case .running: return .green
        case .starting: return .orange
        case .failed: return .red
        case .stopped: return .gray
        }
    }
}

private struct TunnelEditor: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @ViewState var tunnel: TunnelConfig

    private var sshSessions: [SessionProfile] { store.sessions.filter { $0.kind == .ssh || $0.kind == .sftp } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IconTile(symbol: "point.3.connected.trianglepath.dotted", color: .green, size: 36)
                VStack(alignment: .leading) {
                    Text("SSH Tunnel").font(.title2.bold())
                    Text("Local port forwarding (like ssh -L)").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding([.top, .horizontal], 20)
            Form {
                TextField("Name", text: $tunnel.name, prompt: Text("e.g. Production database"))
                Picker("Through server", selection: $tunnel.sessionID) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(sshSessions) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                TextField("Local port (on this Mac)", value: $tunnel.localPort, format: .number.grouping(.never))
                TextField("Destination host (as seen from the server)", text: $tunnel.remoteHost)
                TextField("Destination port", value: $tunnel.remotePort, format: .number.grouping(.never))
                Toggle("Start automatically when MacTerm+ opens", isOn: $tunnel.autoStart)
                Text("Then connect your app to localhost:\(tunnel.localPort). Example: forward local 5433 to 127.0.0.1:5432 to reach a server’s PostgreSQL.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    TunnelManager.shared.upsert(tunnel)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tunnel.sessionID == nil || tunnel.remoteHost.isEmpty || tunnel.localPort <= 0)
            }
            .padding(20)
        }
        .frame(width: 500)
    }
}

// MARK: - Tools

struct ToolsPanel: View {
    @EnvironmentObject var workspace: Workspace
    @ViewState private var showKeyGen = false
    @ViewState private var checkHost = ""
    @ViewState private var checkPort = "22"
    @ViewState private var checkResult: String?
    @ViewState private var installResult: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ToolCard(icon: "key.fill", color: .yellow, title: "SSH key generator",
                         subtitle: "Create a new Ed25519 key pair in ~/.ssh") {
                    Button("Generate Key…") { showKeyGen = true }
                }
                ToolCard(icon: "person.badge.key.fill", color: .purple, title: "Install my public key",
                         subtitle: "Adds your public key to the current server’s authorized_keys, so you can log in without a password") {
                    Button("Install on Current Server") { installKey() }
                        .disabled(!isSSHTab)
                    if let installResult { Text(installResult).font(.caption).foregroundStyle(.secondary) }
                }
                ToolCard(icon: "network", color: .blue, title: "Port checker",
                         subtitle: "Is a TCP port reachable from this Mac?") {
                    HStack {
                        TextField("Host", text: $checkHost).textFieldStyle(.roundedBorder)
                        TextField("Port", text: $checkPort).textFieldStyle(.roundedBorder).frame(width: 60)
                    }
                    Button("Check") { check() }.disabled(checkHost.isEmpty)
                    if let checkResult { Text(checkResult).font(.caption) }
                }
                ToolCard(icon: "terminal.fill", color: .gray, title: "Local shell",
                         subtitle: "A terminal on this Mac (⌘T)") {
                    Button("Open") { workspace.openLocal() }
                }
            }
            .padding(10)
        }
        .sheet(isPresented: $showKeyGen) { KeyGenerator() }
    }

    private var isSSHTab: Bool {
        if case .ssh = workspace.selected { return true }
        return false
    }

    private func check() {
        checkResult = "Checking…"
        let host = checkHost, port = UInt16(checkPort) ?? 22
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let started = Date()
        var finished = false
        func finish(_ text: String) {
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                checkResult = text
                conn.cancel()
            }
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready: finish("✅ \(host):\(port) is open (\(Int(Date().timeIntervalSince(started) * 1000)) ms)")
            case .failed(let e): finish("❌ \(host):\(port) — \(e.localizedDescription)")
            case .waiting(let e): finish("❌ \(host):\(port) — \(e.localizedDescription)")
            default: break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { finish("⏱ \(host):\(port) — no answer within 6 s (filtered or down)") }
    }

    private func installKey() {
        guard case .ssh(let tab) = workspace.selected else { return }
        let home = NSHomeDirectory()
        guard let pubPath = ["id_ed25519.pub", "id_ecdsa.pub", "id_rsa.pub"].map({ "\(home)/.ssh/\($0)" })
            .first(where: { FileManager.default.fileExists(atPath: $0) }),
              let pub = try? String(contentsOfFile: pubPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
            installResult = "No public key found in ~/.ssh — generate one first."
            return
        }
        let safe = pub.replacingOccurrences(of: "'", with: "")
        let cmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && (grep -qxF '\(safe)' ~/.ssh/authorized_keys || echo '\(safe)' >> ~/.ssh/authorized_keys) && echo MTP_KEY_OK"
        installResult = "Installing…"
        Task {
            do {
                let client = try await tab.connection.connectedClient()
                let out = String(buffer: try await client.executeCommand(cmd + " 2>/dev/null; true"))
                installResult = out.contains("MTP_KEY_OK")
                    ? "✅ Installed \((pubPath as NSString).lastPathComponent). Switch this session to “Private key” to log in without a password."
                    : "Couldn’t write ~/.ssh/authorized_keys on the server."
            } catch {
                installResult = SSHConnection.describe(error)
            }
        }
    }
}

private struct ToolCard<Content: View>: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconTile(symbol: icon, color: color, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct KeyGenerator: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = "id_ed25519"
    @ViewState private var comment = "\(NSUserName())@\(Host.current().localizedName ?? "mac")"
    @ViewState private var passphrase = ""
    @ViewState private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate SSH Key").font(.title2.bold())
            Form {
                TextField("File name (in ~/.ssh)", text: $name)
                TextField("Comment", text: $comment)
                SecureField("Passphrase (optional)", text: $passphrase)
            }
            .formStyle(.grouped)
            if let result { Text(result).font(.callout).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Generate") { generate() }.keyboardShortcut(.defaultAction).disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func generate() {
        let dir = NSHomeDirectory() + "/.ssh"
        let path = dir + "/" + name.replacingOccurrences(of: "/", with: "")
        if FileManager.default.fileExists(atPath: path) {
            result = "⚠️ \(path) already exists — choose another name."
            return
        }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        p.arguments = ["-q", "-t", "ed25519", "-f", path, "-N", passphrase, "-C", comment]
        do {
            try p.run()
            p.waitUntilExit()
            result = p.terminationStatus == 0
                ? "✅ Created \(path) and \(path).pub"
                : "ssh-keygen failed (exit \(p.terminationStatus))."
        } catch {
            result = error.localizedDescription
        }
    }
}
