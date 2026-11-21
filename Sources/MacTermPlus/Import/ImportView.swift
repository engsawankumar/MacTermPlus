import AppKit
import SwiftUI

/// Import sessions. By default it scans this Mac (and CrossOver/Wine/Whisky bottles) for installed
/// SSH clients; importing from a chosen file is the Advanced fallback.
struct ImportSessionsView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    enum Step { case scanning, found, advanced, preview, done }

    @ViewState private var step: Step = .scanning
    @ViewState private var sources: [DiscoveredSource] = []
    @ViewState private var chosenSources: Set<String> = []
    @ViewState private var fileSource: ImportSource = .auto
    @ViewState private var result = ImportResult()
    @ViewState private var previewTitle = ""
    @ViewState private var selected: Set<UUID> = []
    @ViewState private var folderPrefix = ""
    @ViewState private var error: String?
    @ViewState private var importedCount = 0
    @ViewState private var cameFromAdvanced = false
    @ViewState private var copyKeychainPasswords = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Group {
                switch step {
                case .scanning: scanning
                case .found: foundList
                case .advanced: advanced
                case .preview: preview
                case .done: doneView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 660, height: 580)
        .task { await runScan() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "square.and.arrow.down.on.square.fill", color: .orange, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Import Sessions").font(.title2.bold())
                Text(step == .advanced ? "Advanced: import from a file you choose."
                                       : "Found automatically from SSH apps on this Mac. Passwords are not imported.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    // MARK: Scan

    private var scanning: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Looking for MobaXterm, PuTTY, WinSCP, FileZilla, WinBox, Cyberduck, Termius, the Keychain and ~/.ssh/config…")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Includes Windows apps in CrossOver, Wine and Whisky bottles.").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func runScan() async {
        let found = await Task.detached(priority: .userInitiated) { InstalledClientScanner.scan() }.value
        sources = found
        chosenSources = Set(found.filter { $0.count > 0 }.map(\.id))
        step = .found
    }

    private var foundList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sources.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("No SSH apps with saved sessions were found on this Mac.").font(.headline)
                    Text("If your sessions are in a file (for example copied from a Windows PC), use Import from a File.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Choose the apps to import from:").font(.headline)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(sources) { src in sourceRow(src) }
                    }
                }
            }
            HStack {
                Button { step = .advanced; error = nil } label: {
                    Label("Import from a File… (Advanced)", systemImage: "folder")
                }
                Button { step = .scanning; Task { await runScan() } } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Continue") { previewSelectedSources() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosenSources.isEmpty)
            }
        }
        .padding(20)
    }

    private func sourceRow(_ src: DiscoveredSource) -> some View {
        let color = SessionColor(rawValue: src.colorName)?.color ?? .accentColor
        let usable = src.count > 0
        return HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { chosenSources.contains(src.id) },
                set: { if $0 { chosenSources.insert(src.id) } else { chosenSources.remove(src.id) } }))
                .labelsHidden()
                .disabled(!usable)
            IconTile(symbol: src.icon, color: usable ? color : .gray, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(src.app).font(.headline)
                    if usable {
                        Text("\(src.count) session\(src.count == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(color.opacity(0.18), in: Capsule())
                    }
                }
                Text(src.location).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let note = src.note {
                    Text(note).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                } else if !usable {
                    Text("No SSH/SFTP sessions — \(src.result.skipped.count) other entr\(src.result.skipped.count == 1 ? "y" : "ies") (\(src.result.skipped.joined(separator: ", ")))")
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                } else if !src.result.skipped.isEmpty {
                    Text("Skipped (not SSH): \(src.result.skipped.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(chosenSources.contains(src.id) ? color.opacity(0.10) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(chosenSources.contains(src.id) ? color.opacity(0.6) : .secondary.opacity(0.2)))
        .opacity(usable || src.note != nil ? 1 : 0.65)
        .contentShape(Rectangle())
        .onTapGesture { if usable { if chosenSources.contains(src.id) { chosenSources.remove(src.id) } else { chosenSources.insert(src.id) } } }
    }

    private func previewSelectedSources() {
        var merged = ImportResult()
        for src in sources where chosenSources.contains(src.id) {
            for p in src.result.sessions where !merged.sessions.contains(where: { $0.sameEndpoint(as: p) }) {
                merged.sessions.append(p)
                if let s = src.result.secrets[p.id] { merged.secrets[p.id] = s }
                if let k = src.result.keychainEntries[p.id] { merged.keychainEntries[p.id] = k }
            }
            merged.skipped += src.result.skipped
        }
        let apps = Set(sources.filter { chosenSources.contains($0.id) }.map(\.app))
        showPreview(merged, title: apps.sorted().joined(separator: ", "), fromAdvanced: false)
    }

    // MARK: Advanced (file)

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(ImportSource.allCases) { s in
                    SourceTile(source: s, selected: fileSource == s).onTapGesture { fileSource = s }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(.tint)
                Text(fileSource.hint).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Spacer()
            HStack {
                Button { step = .found } label: { Label("Back to Detected Apps", systemImage: "chevron.left") }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Choose File or Folder…") { pickFile() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = fileSource == .putty || fileSource == .auto
        panel.showsHiddenFiles = true
        panel.message = fileSource.hint
        panel.prompt = "Import"
        if fileSource == .sshConfig { panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh") }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let r = try SessionImporter.importFile(at: url, as: fileSource)
            showPreview(r, title: r.detected.title, fromAdvanced: true)
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Preview

    private func showPreview(_ r: ImportResult, title: String, fromAdvanced: Bool) {
        result = r
        previewTitle = title
        cameFromAdvanced = fromAdvanced
        selected = Set(r.sessions.filter { p in !store.sessions.contains { $0.sameEndpoint(as: p) } }.map(\.id))
        step = .preview
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(result.sessions.count) session\(result.sessions.count == 1 ? "" : "s") from \(previewTitle)")
                    .font(.headline)
                Spacer()
                Button(selected.count == result.sessions.count ? "Select None" : "Select All") {
                    selected = selected.count == result.sessions.count ? [] : Set(result.sessions.map(\.id))
                }
                .buttonStyle(.link)
            }
            List(result.sessions) { p in
                let exists = store.sessions.contains { $0.sameEndpoint(as: p) }
                Toggle(isOn: Binding(get: { selected.contains(p.id) },
                                     set: { if $0 { selected.insert(p.id) } else { selected.remove(p.id) } })) {
                    HStack {
                        IconTile(symbol: "server.rack", color: p.color.color, size: 24)
                        VStack(alignment: .leading) {
                            Text(p.displayName)
                            Text("\(p.endpoint)\(p.group.isEmpty ? "" : "  ·  \(p.group)")\(p.auth == .privateKey ? "  ·  key" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if result.secrets[p.id] != nil {
                            Label("password", systemImage: "key.fill").font(.caption).foregroundStyle(.green)
                        } else if result.keychainEntries[p.id] != nil {
                            Label("keychain", systemImage: "key").font(.caption).foregroundStyle(.secondary)
                        }
                        if exists { Text("Already saved").font(.caption).foregroundStyle(.orange) }
                        if p.username.isEmpty { Text("No user").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            if !result.skipped.isEmpty {
                DisclosureGroup("\(result.skipped.count) entr\(result.skipped.count == 1 ? "y" : "ies") skipped (not SSH/SFTP)") {
                    Text(result.skipped.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if !result.keychainEntries.isEmpty {
                Toggle("Copy their passwords from the Keychain (macOS asks you to allow each one)", isOn: $copyKeychainPasswords)
                    .font(.callout)
            }
            if !result.secrets.isEmpty {
                Label("\(result.secrets.count) password\(result.secrets.count == 1 ? "" : "s") will be saved to the Keychain. Delete the CSV file afterwards.",
                      systemImage: "key.fill")
                    .font(.callout).foregroundStyle(.green)
            }
            HStack {
                TextField("Put into folder (optional)", text: $folderPrefix)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Spacer()
                Button("Back") { step = cameFromAdvanced ? .advanced : .found }
                Button("Import \(selected.count)") { doImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(20)
    }

    private func doImport() {
        let prefix = folderPrefix.trimmingCharacters(in: .whitespaces)
        let chosen = result.sessions.filter { selected.contains($0.id) }.map { p -> SessionProfile in
            var p = p
            if !prefix.isEmpty { p.group = p.group.isEmpty ? prefix : "\(prefix)/\(p.group)" }
            return p
        }
        var secrets = result.secrets
        if copyKeychainPasswords {
            for p in chosen {
                if let entry = result.keychainEntries[p.id], let pw = Keychain.password(for: entry) { secrets[p.id] = pw }
            }
        }
        importedCount = store.importSessions(chosen, secrets: secrets)
        step = .done
    }

    private var doneView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(.green)
            Text("Imported \(importedCount) session\(importedCount == 1 ? "" : "s")").font(.title3.bold())
            if importedCount < selected.count {
                Text("\(selected.count - importedCount) already existed (same host, port and user) and were skipped.")
                    .foregroundStyle(.secondary)
            }
            Text("Sessions without a saved password will ask for it the first time you connect.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SourceTile: View {
    let source: ImportSource
    let selected: Bool

    var body: some View {
        let color = SessionColor(rawValue: source.colorName)?.color ?? .accentColor
        VStack(spacing: 6) {
            IconTile(symbol: source.icon, color: color, size: 40)
            Text(source.title).font(.callout).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? color.opacity(0.15) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? color : .secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
    }
}
