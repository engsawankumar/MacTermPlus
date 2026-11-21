import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Known Hosts: the server keys MacTerm+ trusts, with fingerprints, import, export and remove.
struct KnownHostsSettings: View {
    @EnvironmentObject var store: SessionStore
    @ViewState private var entries: [KnownHosts.Entry] = []
    @ViewState private var search = ""
    @ViewState private var removing: KnownHosts.Entry?
    @ViewState private var message: String?

    private var filtered: [KnownHosts.Entry] {
        guard !search.isEmpty else { return entries }
        return entries.filter { e in
            (e.host + " " + String(e.port) + " " + e.keyLabel + " " + sessionNames(e)).localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search hosts", text: $search).textFieldStyle(.plain)
                Spacer()
                Menu {
                    Button("From ~/.ssh/known_hosts") { importDefault() }
                    Button("From a File…") { importFile() }
                } label: { Label("Import", systemImage: "square.and.arrow.down") }
                .fixedSize()
                Button { exportFile() } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                    .disabled(entries.isEmpty)
            }
            .padding(10)
            .background(.bar)
            Divider()
            if let message {
                Label(message, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6)
            }
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.shield").font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text(entries.isEmpty ? "No known hosts yet. A server’s key is saved the first time you connect."
                                         : "Nothing matches “\(search)”.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                List {
                    ForEach(filtered) { e in row(e) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            Divider()
            Text("When a server’s key changes, MacTerm+ refuses to connect (it could be an attack). If you know the server was reinstalled, remove its old key here and connect again.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(10)
        }
        .frame(height: 560)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: KnownHosts.changed)) { _ in reload() }
        .confirmationDialog(removing.map { "Remove the saved key for \($0.host)?" } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { e in
            Button("Remove Key", role: .destructive) { KnownHosts.shared.forget(id: e.id) }
        } message: { _ in Text("The next connection will save the server’s current key.") }
    }

    private func row(_ e: KnownHosts.Entry) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: "lock.shield.fill", color: .indigo, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.port == 22 ? e.host : "\(e.host):\(e.port)").font(.body.weight(.medium)).lineLimit(1)
                    Text(e.keyLabel).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                    let names = sessionNames(e)
                    if !names.isEmpty { Text(names).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Text(e.fingerprint).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Menu {
                Button("Copy Fingerprint") { copy(e.fingerprint) }
                Button("Copy Public Key") { copy(e.key) }
                Divider()
                Button("Remove…", role: .destructive) { removing = e }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Copy Fingerprint") { copy(e.fingerprint) }
            Button("Copy Public Key") { copy(e.key) }
            Divider()
            Button("Remove…", role: .destructive) { removing = e }
        }
    }

    private func sessionNames(_ e: KnownHosts.Entry) -> String {
        store.sessions.filter { $0.host.caseInsensitiveCompare(e.host) == .orderedSame && $0.port == e.port }
            .map(\.displayName).joined(separator: ", ")
    }

    private func reload() { entries = Showcase.isOn ? Self.demo : KnownHosts.shared.all() }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func flash(_ m: String) {
        message = m
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if message == m { message = nil } }
    }

    private func report(_ r: (added: Int, skipped: Int)) {
        flash("Imported \(r.added) host\(r.added == 1 ? "" : "s")" + (r.skipped > 0 ? " · \(r.skipped) hashed or special lines skipped" : ""))
    }

    private func importDefault() {
        guard !Showcase.isOn else { return }
        let path = NSHomeDirectory() + "/.ssh/known_hosts"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { flash("No ~/.ssh/known_hosts file on this Mac."); return }
        report(KnownHosts.shared.importOpenSSH(text))
    }

    private func importFile() {
        guard !Showcase.isOn else { return }
        let panel = NSOpenPanel()
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        report(KnownHosts.shared.importOpenSSH(text))
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "known_hosts"
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? KnownHosts.shared.exportOpenSSH().write(to: url, atomically: true, encoding: .utf8)
        flash("Exported \(entries.count) hosts.")
    }

    /// Made-up entries for screenshots (documentation IP ranges and example.com only).
    private static let demo: [KnownHosts.Entry] = [
        ("web-01.example.com", 22, "ssh-ed25519"), ("db-01.example.com", 22, "ssh-ed25519"), ("203.0.113.10", 22, "ssh-rsa"),
        ("198.51.100.7", 2222, "ecdsa-sha2-nistp256"), ("192.0.2.44", 22, "ssh-ed25519"), ("files.example.net", 22, "ssh-rsa"),
    ].map { h, p, t in
        let blob = Data((h + t).utf8).base64EncodedString()
        return KnownHosts.Entry(id: "[\(h)]:\(p)", host: h, port: p, keyType: t, key: "\(t) \(blob)")
    }
}
