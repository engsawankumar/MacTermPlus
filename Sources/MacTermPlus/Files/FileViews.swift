import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Table of files shared by the local and remote panes.
struct FileTable<Menu: View>: View {
    let items: [FileItem]
    @Binding var selection: Set<String>
    var compact = false
    let onOpen: (FileItem) -> Void
    @ViewBuilder let menu: (Set<String>) -> Menu

    var body: some View {
        Table(items, selection: $selection) {
            TableColumn("Name") { item in
                Label {
                    Text(item.isParent ? ".. (parent folder)" : item.name)
                        .lineLimit(1)
                        .foregroundStyle(item.isParent ? .secondary : .primary)
                        .opacity(!item.isParent && item.name.hasPrefix(".") ? 0.7 : 1)
                } icon: {
                    FileIconView(item: item, size: 18)
                }
            }
            TableColumn("Size") { item in
                Text(item.sizeText).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 50, ideal: 70, max: 100)
            if !compact {
                TableColumn("Modified") { item in
                    Text(item.modifiedText).foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 130)
                TableColumn("Perms") { item in
                    Text(item.permissions).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 85)
                TableColumn("Owner") { item in
                    Text(item.owner.isEmpty ? "" : "\(item.owner):\(item.group)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 50, ideal: 90)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            menu(ids)
        } primaryAction: { ids in
            if let id = ids.first, let item = items.first(where: { $0.id == id }) { onOpen(item) }
        }
    }
}

// MARK: - Toolbar building blocks

/// Small colored icon button for file toolbars.
struct FileToolButton: View {
    let symbol: String
    let color: Color
    let help: String
    var enabled = true
    let action: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button(action: action) {
            Group {
                if settings.iconStyle == .vivid {
                    IconTile(symbol: symbol, color: color, size: 22)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(settings.iconStyle == .mono ? .secondary : color)
                        .frame(width: 22, height: 22)
                }
            }
            .opacity(enabled ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(help)
    }
}

/// Path field with a recent-folders menu.
struct PathField: View {
    let path: String
    let history: [String]
    let isLoading: Bool
    let onGo: (String) -> Void
    @ViewState private var editing = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField("Path", text: $editing)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .onSubmit { onGo(editing) }
            if isLoading { ProgressView().controlSize(.small) }
            Menu {
                if history.isEmpty { Text("No recent folders") }
                ForEach(history, id: \.self) { p in Button(p) { onGo(p) } }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Recent folders")
        }
        .onAppear { editing = path }
        .onChange(of: path) { _, new in editing = new }
    }
}

// MARK: - Remote pane

/// The remote file list with a full toolbar (sidebar Files panel and the right side of the two-pane view).
struct RemoteFilePane: View {
    @ObservedObject var browser: RemoteFileBrowser
    var compact = false
    @Binding var selection: Set<String>

    @ViewState private var renaming: FileItem?
    @ViewState private var newName = ""
    @ViewState private var creating: CreateKind?
    @ViewState private var confirmDelete: [FileItem] = []
    @ViewState private var dropTargeted = false
    @ViewState private var infoItem: FileItem?
    @ViewState private var permissionItems: [FileItem] = []
    @ViewState private var showFilter = false

    enum CreateKind: Identifiable { case folder, file; var id: Int { self == .folder ? 0 : 1 } }

    private var selectedItems: [FileItem] { browser.items.filter { selection.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 6) {
                if browser.isRoot { RootBadge() }
                PathField(path: browser.path, history: browser.history, isLoading: browser.isLoading) { p in
                    Task { await browser.load(p) }
                }
            }
            .padding(.horizontal, 6).padding(.bottom, 5)
            if showFilter {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                    TextField("Filter names", text: $browser.filter).textFieldStyle(.plain)
                    if !browser.filter.isEmpty { Button { browser.filter = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless) }
                }
                .padding(6)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 6).padding(.bottom, 5)
            }
            Divider()
            if let error = browser.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    if browser.errorIsPermission && browser.canUseRoot && !browser.isRoot {
                        RootModeToggle(browser: browser, label: "Open as root (sudo)…", asButton: true)
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            FileTable(items: browser.visibleItems, selection: $selection, compact: compact,
                      onOpen: { item in Task { await browser.open(item) } }) { ids in
                menu(for: ids)
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .overlay(Text("Drop to upload").font(.headline).padding(8).background(.thinMaterial, in: Capsule()))
                        .padding(2)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                loadURLs(from: providers) { urls in browser.upload(urls) }
                return true
            }
            Divider()
            HStack {
                Text("\(browser.visibleItems.filter { !$0.isParent }.count) items\(selection.isEmpty ? "" : " · \(selection.count) selected")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                TransferStatusLine(queue: browser.queue)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .task { await browser.start() }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let r = renaming { Task { await browser.rename(r, to: newName) } } }
            Button("Cancel", role: .cancel) {}
        }
        .alert(creating == .file ? "New File" : "New Folder", isPresented: Binding(get: { creating != nil }, set: { if !$0 { creating = nil } })) {
            TextField(creating == .file ? "File name" : "Folder name", text: $newName)
            Button("Create") {
                let kind = creating
                Task { if kind == .file { await browser.makeFile(named: newName) } else { await browser.makeDirectory(named: newName) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(confirmDelete.count == 1 ? "“\(confirmDelete.first?.name ?? "")”" : "\(confirmDelete.count) items") on the server?",
            isPresented: Binding(get: { !confirmDelete.isEmpty }, set: { if !$0 { confirmDelete = [] } })
        ) {
            Button("Delete", role: .destructive) {
                let items = confirmDelete
                Task { await browser.delete(items) }
            }
        } message: {
            Text("This cannot be undone. Folders are deleted with everything inside.")
        }
        .sheet(item: $infoItem) { item in
            FileInfoSheet(item: item, location: browser.title) { permissionItems = [item] }
        }
        .sheet(isPresented: Binding(get: { !permissionItems.isEmpty }, set: { if !$0 { permissionItems = [] } })) {
            PermissionsSheet(items: permissionItems) { mode, recursive in
                await browser.setPermissions(permissionItems, mode: mode, recursive: recursive)
            }
        }
    }

    private var toolbar: some View {
        let sel = selectedItems
        let one = sel.count == 1 ? sel.first : nil
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                FileToolButton(symbol: "arrow.up.circle.fill", color: .yellow, help: "Parent folder") { Task { await browser.goUp() } }
                FileToolButton(symbol: "house.fill", color: .orange, help: "Home folder") {
                    Task { if let h = try? await browser.fs.home() { await browser.load(h) } }
                }
                FileToolButton(symbol: "arrow.clockwise.circle.fill", color: .green, help: "Refresh") { Task { await browser.refresh() } }
                Divider().frame(height: 18)
                FileToolButton(symbol: "arrow.down.circle.fill", color: .blue, help: "Download selected…", enabled: !sel.isEmpty) {
                    browser.downloadWithPanel(sel)
                }
                FileToolButton(symbol: "arrow.up.doc.fill", color: .teal, help: "Upload files or folders…") { browser.uploadWithPanel() }
                Divider().frame(height: 18)
                FileToolButton(symbol: "folder.fill.badge.plus", color: .yellow, help: "New folder") { newName = ""; creating = .folder }
                FileToolButton(symbol: "doc.fill.badge.plus", color: .cyan, help: "New empty file") { newName = ""; creating = .file }
                FileToolButton(symbol: "pencil.circle.fill", color: .purple, help: "Rename", enabled: one != nil) {
                    if let one { renaming = one; newName = one.name }
                }
                FileToolButton(symbol: "xmark.circle.fill", color: .red, help: "Delete", enabled: !sel.isEmpty) { requestDelete(sel) }
                Divider().frame(height: 18)
                FileToolButton(symbol: "info.circle.fill", color: .blue, help: "Info", enabled: one != nil) { infoItem = one }
                FileToolButton(symbol: "lock.shield.fill", color: .indigo, help: "Permissions (chmod)", enabled: !sel.isEmpty) { permissionItems = sel }
                FileToolButton(symbol: "square.and.pencil", color: .pink, help: "Edit in a Mac app",
                               enabled: one.map { !$0.isDirectory } ?? false) {
                    if let one { Task { await browser.edit(one) } }
                }
                Divider().frame(height: 18)
                FileToolButton(symbol: browser.showHidden ? "eye.fill" : "eye.slash.fill", color: .gray, help: "Show hidden files") {
                    browser.showHidden.toggle()
                }
                FileToolButton(symbol: "line.3.horizontal.decrease.circle.fill", color: .mint, help: "Filter by name") {
                    showFilter.toggle()
                    if !showFilter { browser.filter = "" }
                }
                FileToolButton(symbol: "doc.on.clipboard.fill", color: .brown, help: "Copy path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(one?.path ?? browser.path, forType: .string)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
        }
    }

    private func requestDelete(_ items: [FileItem]) {
        if AppSettings.shared.confirmDelete { confirmDelete = items } else { Task { await browser.delete(items) } }
    }

    @ViewBuilder
    private func menu(for ids: Set<String>) -> some View {
        let items = browser.items.filter { ids.contains($0.id) }
        if items.count == 1, let item = items.first {
            Button(item.isDirectory ? "Open" : "Edit") { Task { await browser.open(item) } }
            if !item.isDirectory {
                OpenWithMenu(fileName: item.name) { app in Task { await browser.edit(item, with: app) } }
            }
            Button("Rename…") { renaming = item; newName = item.name }
            Button("Info…") { infoItem = item }
        }
        if !items.isEmpty {
            Button("Permissions…") { permissionItems = items }
            Button("Download…") { browser.downloadWithPanel(items) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(items.map(\.path).joined(separator: "\n"), forType: .string)
            }
            Divider()
            Button("Delete…", role: .destructive) { requestDelete(items) }
        } else {
            Button("Upload…") { browser.uploadWithPanel() }
            Button("New Folder…") { newName = ""; creating = .folder }
            Button("New File…") { newName = ""; creating = .file }
            Button("Refresh") { Task { await browser.refresh() } }
        }
    }
}

// MARK: - Local pane

struct LocalFilePane: View {
    @ObservedObject var browser: LocalFileBrowser
    @Binding var selection: Set<String>
    @ViewState private var renaming: FileItem?
    @ViewState private var newName = ""
    @ViewState private var creatingFolder = false
    @ViewState private var infoItem: FileItem?
    @ViewState private var permissionItems: [FileItem] = []

    private var selectedItems: [FileItem] { browser.items.filter { selection.contains($0.id) } }

    var body: some View {
        let sel = selectedItems
        let one = sel.count == 1 ? sel.first : nil
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    FileToolButton(symbol: "arrow.up.circle.fill", color: .yellow, help: "Parent folder") { browser.goUp() }
                    FileToolButton(symbol: "house.fill", color: .orange, help: "Home folder") { browser.load(NSHomeDirectory()) }
                    FileToolButton(symbol: "arrow.clockwise.circle.fill", color: .green, help: "Refresh") { browser.refresh() }
                    Divider().frame(height: 18)
                    FileToolButton(symbol: "folder.fill.badge.plus", color: .yellow, help: "New folder") { newName = ""; creatingFolder = true }
                    FileToolButton(symbol: "pencil.circle.fill", color: .purple, help: "Rename", enabled: one != nil) {
                        if let one { renaming = one; newName = one.name }
                    }
                    FileToolButton(symbol: "trash.circle.fill", color: .red, help: "Move to Trash", enabled: !sel.isEmpty) { browser.moveToTrash(sel) }
                    Divider().frame(height: 18)
                    FileToolButton(symbol: "info.circle.fill", color: .blue, help: "Info", enabled: one != nil) { infoItem = one }
                    FileToolButton(symbol: "lock.shield.fill", color: .indigo, help: "Permissions", enabled: !sel.isEmpty) { permissionItems = sel }
                    FileToolButton(symbol: "magnifyingglass.circle.fill", color: .teal, help: "Reveal in Finder", enabled: !sel.isEmpty) {
                        browser.revealInFinder(sel)
                    }
                    FileToolButton(symbol: browser.showHidden ? "eye.fill" : "eye.slash.fill", color: .gray, help: "Show hidden files") {
                        browser.showHidden.toggle()
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 5)
            }
            PathField(path: browser.path, history: [], isLoading: false) { browser.load(($0 as NSString).expandingTildeInPath) }
                .padding(.horizontal, 6).padding(.bottom, 5)
            Divider()
            if let error = browser.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).padding(6)
            }
            FileTable(items: browser.visibleItems, selection: $selection, onOpen: { browser.open($0) }) { ids in
                let items = browser.items.filter { ids.contains($0.id) }
                if items.count == 1, let item = items.first {
                    Button("Open") { browser.open(item) }
                    if !item.isDirectory {
                        OpenWithMenu(fileName: item.name) { app in OpenWith.open(URL(fileURLWithPath: item.path), with: app) }
                    }
                    Button("Rename…") { renaming = item; newName = item.name }
                    Button("Info…") { infoItem = item }
                }
                if !items.isEmpty {
                    Button("Permissions…") { permissionItems = items }
                    Button("Reveal in Finder") { browser.revealInFinder(items) }
                    Button("Move to Trash", role: .destructive) { browser.moveToTrash(items) }
                } else {
                    Button("New Folder…") { newName = ""; creatingFolder = true }
                    Button("Refresh") { browser.refresh() }
                }
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let r = renaming { browser.rename(r, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Folder", isPresented: $creatingFolder) {
            TextField("Folder name", text: $newName)
            Button("Create") { browser.makeDirectory(named: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $infoItem) { item in
            FileInfoSheet(item: item, location: "This Mac") { permissionItems = [item] }
        }
        .sheet(isPresented: Binding(get: { !permissionItems.isEmpty }, set: { if !$0 { permissionItems = [] } })) {
            PermissionsSheet(items: permissionItems) { mode, recursive in
                var n = 0
                for item in permissionItems {
                    if (try? browser.setPermissions(item, mode: mode, recursive: recursive)) != nil { n += 1 }
                }
                return n
            }
        }
    }
}

// MARK: - Info & permissions

struct FileInfoSheet: View {
    let item: FileItem
    let location: String
    let editPermissions: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FileIconView(item: item, size: 44, styleOverride: .vivid)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.title3.bold()).lineLimit(2).textSelection(.enabled)
                    Text(item.kindDescription).foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                row("Where", location)
                row("Path", item.path)
                if !item.isDirectory, let size = item.size {
                    row("Size", "\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) (\(size.formatted()) bytes)")
                }
                if let m = item.modified { row("Modified", m.formatted(date: .long, time: .standard)) }
                row("Permissions", item.permissions.isEmpty ? "—" : "\(item.permissions)  (\(item.mode.map { String(format: "%03o", $0 & 0o7777) } ?? "?"))")
                if !item.owner.isEmpty { row("Owner", item.owner) }
                if !item.group.isEmpty { row("Group", item.group) }
            }
            HStack {
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.path, forType: .string)
                }
                Spacer()
                Button("Permissions…") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editPermissions() } }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(3).font(label == "Path" || label == "Permissions" ? .system(.body, design: .monospaced) : .body)
        }
    }
}

/// chmod editor: owner / group / others checkboxes, octal field, presets, recursive.
struct PermissionsSheet: View {
    let items: [FileItem]
    /// Applies the mode; returns how many items changed.
    let apply: (UInt32, Bool) async -> Int
    @Environment(\.dismiss) private var dismiss
    @ViewState private var mode: UInt32 = 0o644
    @ViewState private var octal = "644"
    @ViewState private var recursive = false
    @ViewState private var working = false
    @ViewState private var result: String?

    private var hasFolder: Bool { items.contains { $0.isDirectory } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconTile(symbol: "lock.shield.fill", color: .indigo, size: 36)
                VStack(alignment: .leading) {
                    Text("Permissions").font(.title2.bold())
                    Text(items.count == 1 ? items[0].name : "\(items.count) items").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Grid(alignment: .center, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    Text("Read").font(.caption.weight(.semibold))
                    Text("Write").font(.caption.weight(.semibold))
                    Text("Execute").font(.caption.weight(.semibold))
                }
                permRow("Owner", shift: 6)
                permRow("Group", shift: 3)
                permRow("Others", shift: 0)
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("Octal")
                TextField("644", text: $octal)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 70)
                    .onChange(of: octal) { _, v in
                        if let m = UInt32(v, radix: 8), v.count <= 4, m <= 0o7777 { mode = m }
                    }
                Text(FileItem.permissionString(mode | (hasFolder && items.count == 1 ? 0o040000 : 0o100000)))
                    .font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Menu("Presets") {
                    Button("644 — files: owner writes, everyone reads") { set(0o644) }
                    Button("755 — folders / scripts: owner writes, everyone runs") { set(0o755) }
                    Button("600 — private file (keys, secrets)") { set(0o600) }
                    Button("700 — private folder") { set(0o700) }
                    Button("775 — group can write") { set(0o775) }
                    Button("664 — group can write (files)") { set(0o664) }
                    Button("777 — everyone can do everything (unsafe)") { set(0o777) }
                }
                .fixedSize()
            }
            if hasFolder {
                Toggle("Apply to everything inside the folder\(items.count == 1 ? "" : "s") too", isOn: $recursive)
                if recursive {
                    Text("Tip: folders usually need execute (x) to be opened; 755 for folders and 644 for files is the common setup.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let result { Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(working ? "Applying…" : "Apply") {
                    working = true
                    Task {
                        let n = await apply(mode, recursive)
                        working = false
                        result = "Changed \(n) item\(n == 1 ? "" : "s") to \(String(format: "%03o", mode))."
                        try? await Task.sleep(for: .milliseconds(700))
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(working)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            set((items.first?.mode ?? (items.first?.isDirectory == true ? 0o755 : 0o644)) & 0o7777)
        }
    }

    private func set(_ m: UInt32) {
        mode = m
        octal = String(format: "%03o", m)
    }

    private func permRow(_ who: String, shift: UInt32) -> some View {
        GridRow {
            Text(who).gridColumnAlignment(.leading)
            ForEach([4, 2, 1] as [UInt32], id: \.self) { bit in
                Toggle("", isOn: Binding(
                    get: { mode & (bit << shift) != 0 },
                    set: { on in set(on ? mode | (bit << shift) : mode & ~(bit << shift)) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }
        }
    }
}

// MARK: - Transfers

struct TransferStatusLine: View {
    @ObservedObject var queue: TransferQueue

    var body: some View {
        if let running = queue.transfers.first(where: { $0.status == .running }) {
            TransferRowCompact(transfer: running, pending: queue.activeCount - 1)
        } else if let failed = queue.transfers.last(where: { if case .failed = $0.status { return true }; return false }),
                  case .failed(let msg) = failed.status {
            Label("\(failed.name): \(msg)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange).lineLimit(1)
                .help(msg)
        }
    }
}

private struct TransferRowCompact: View {
    @ObservedObject var transfer: Transfer
    let pending: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: transfer.direction == .upload ? "arrow.up" : "arrow.down")
            Text(transfer.name).lineLimit(1).frame(maxWidth: 120, alignment: .leading)
            ProgressView(value: transfer.fraction).frame(width: 60)
            if pending > 0 { Text("+\(pending)").foregroundStyle(.secondary) }
        }
        .font(.caption)
    }
}

struct TransferRow: View {
    @ObservedObject var transfer: Transfer

    var body: some View {
        HStack {
            Image(systemName: transfer.direction == .upload ? "arrow.up.circle" : "arrow.down.circle")
                .foregroundStyle(Color.accentColor)
            Text(transfer.name).lineLimit(1)
            Spacer()
            switch transfer.status {
            case .queued: Text("Queued").foregroundStyle(.secondary)
            case .running:
                ProgressView(value: transfer.fraction).frame(width: 120)
                Text(ByteCountFormatter.string(fromByteCount: Int64(transfer.bytesDone), countStyle: .file))
                    .monospacedDigit().foregroundStyle(.secondary)
                if transfer.speed > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(transfer.speed), countStyle: .file) + "/s")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let msg):
                Label(msg, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(1).help(msg)
            }
        }
        .font(.callout)
    }
}

func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        MainActor.assumeIsolated { completion(urls) }
    }
}
