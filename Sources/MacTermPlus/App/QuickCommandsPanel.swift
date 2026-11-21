import AppKit
import SwiftUI

/// Right-hand panel: searchable, starred, folder-organised commands sent to the current terminal.
struct QuickCommandsPanel: View {
    @EnvironmentObject var workspace: Workspace
    @ObservedObject var store = QuickCommandStore.shared
    @ObservedObject var settings = AppSettings.shared
    @ViewState private var search = ""
    @ViewState private var editing: QuickCommand?
    @ViewState private var collapsed: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "quickCommands.collapsed") ?? QuickFolders.builtInOrder.filter { $0 != QuickFolders.common })
    @ViewState private var folderPrompt: FolderPrompt?
    @ViewState private var folderName = ""
    @ViewState private var confirming: QuickCommand?
    @ViewState private var deletingFolder: String?
    @ViewState private var notice: String?
    @FocusState private var searchFocused: Bool

    enum FolderPrompt: Identifiable, Equatable {
        case new, rename(String)
        var id: String { if case .rename(let f) = self { return "rename:" + f }; return "new" }
    }

    private var target: WorkspaceTab? { workspace.selected.flatMap { $0.hasTerminal ? $0 : nil } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .background(.background)
        .sheet(item: $editing) { c in QuickCommandEditor(command: c, folders: store.folders) }
        .alert(folderPrompt == .new ? "New Folder" : "Rename Folder", isPresented: Binding(
            get: { folderPrompt != nil }, set: { if !$0 { folderPrompt = nil } })) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) { folderPrompt = nil }
            Button(folderPrompt == .new ? "Create" : "Rename") {
                switch folderPrompt {
                case .new: store.addFolder(folderName)
                case .rename(let old): store.renameFolder(old, to: folderName)
                case nil: break
                }
                folderPrompt = nil
            }
        }
        .confirmationDialog(confirming.map { "Run “\($0.name)”?" } ?? "", isPresented: Binding(
            get: { confirming != nil }, set: { if !$0 { confirming = nil } }), presenting: confirming) { c in
            Button("Run", role: .destructive) { send(c, force: true) }
        } message: { c in Text(c.command) }
        .confirmationDialog(deletingFolder.map { "Delete the folder “\($0)”?" } ?? "", isPresented: Binding(
            get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }), presenting: deletingFolder) { f in
            Button("Delete Folder and \(store.commands(in: f).count) Commands", role: .destructive) { store.deleteFolder(f) }
        } message: { _ in Text("Built-in commands can be brought back later with Restore Built-in Commands.") }
        .onReceive(NotificationCenter.default.publisher(for: .focusQuickCommandSearch)) { _ in searchFocused = true }
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: "bolt.horizontal.fill", color: .mint, size: 22)
                Text("Quick Commands").font(.headline)
                Spacer()
                Button { editing = QuickCommand(name: "", command: "", folder: QuickFolders.common) } label: {
                    Image(systemName: "plus")
                }
                .help("New command")
                Menu {
                    Button("New Command…") { editing = QuickCommand(name: "", command: "", folder: QuickFolders.common) }
                    Button("New Folder…") { folderName = ""; folderPrompt = .new }
                    Divider()
                    Button("Expand All Folders") { setCollapsed([]) }
                    Button("Collapse All Folders") { setCollapsed(Set(store.folders)) }
                    Divider()
                    Button("Restore Built-in Commands") {
                        let n = store.restoreBuiltins()
                        flash(n == 0 ? "All built-in commands are already here." : "Restored \(n) command\(n == 1 ? "" : "s").")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Button { withAnimation(.easeOut(duration: 0.15)) { settings.showQuickCommands = false } } label: {
                    Image(systemName: "xmark")
                }
                .help("Close Quick Commands (⇧⌘K)")
            }
            .buttonStyle(.borderless)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search commands", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let first = store.search(search).first { send(first) } }
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.12)))
        }
        .padding(10)
    }

    @ViewBuilder private var list: some View {
        if !search.isEmpty {
            let found = store.search(search)
            if found.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No command matches “\(search)”").foregroundStyle(.secondary)
                    Button("Create It…") { editing = QuickCommand(name: search, command: "", folder: QuickFolders.common) }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(found) { c in row(c, showFolder: true) }
                }
                .listStyle(.sidebar)
            }
        } else {
            List {
                Section {
                    if store.starred.isEmpty {
                        Text("Click ☆ on any command to pin it here.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(store.starred) { c in row(c, showFolder: true) }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).frame(width: 16)
                        Text("Starred")
                        Text("\(store.starred.count)").foregroundStyle(.tertiary)
                    }
                }
                ForEach(store.folders, id: \.self) { f in
                    Section(isExpanded: expandedBinding(f)) {
                        ForEach(store.commands(in: f)) { c in row(c, showFolder: false) }
                        if store.commands(in: f).isEmpty {
                            Text("Empty folder").font(.caption).foregroundStyle(.tertiary)
                        }
                    } header: {
                        folderHeader(f)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func folderHeader(_ f: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: QuickFolders.icon(f)).foregroundStyle(QuickFolders.color(f)).frame(width: 16)
            Text(f)
            Text("\(store.commands(in: f).count)").foregroundStyle(.tertiary)
        }
        .contextMenu {
            Button("New Command Here…") { editing = QuickCommand(name: "", command: "", folder: f) }
            Button("Rename Folder…") { folderName = f; folderPrompt = .rename(f) }
            Divider()
            Button("Delete Folder…", role: .destructive) { deletingFolder = f }
        }
    }

    private func row(_ c: QuickCommand, showFolder: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: QuickFolders.icon(c.folder))
                .foregroundStyle(QuickFolders.color(c.folder))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(c.name).lineLimit(1)
                    if c.confirm { Image(systemName: "exclamationmark.shield.fill").font(.caption2).foregroundStyle(.orange) }
                }
                Text(showFolder ? "\(c.folder) · \(c.command)" : c.command)
                    .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { store.toggleStar(c) } label: {
                Image(systemName: c.starred ? "star.fill" : "star").foregroundStyle(c.starred ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(c.starred ? "Unstar" : "Star (pin to the top)")
            Button { send(c) } label: { Image(systemName: "play.circle.fill").font(.title3) }
                .buttonStyle(.borderless)
                .foregroundStyle(.green)
                .disabled(target == nil)
                .help("Run in the current terminal")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { send(c) }
        .help(c.command)
        .contextMenu {
            Button("Run") { send(c) }.disabled(target == nil)
            Button("Run in All Terminals") { sendEverywhere(c) }
            Button("Type Without Running") { target?.sendText(c.command) }.disabled(target == nil)
            Divider()
            Button(c.starred ? "Unstar" : "Star") { store.toggleStar(c) }
            Button("Edit…") { editing = c }
            Button("Duplicate") { store.duplicate(c) }
            Menu("Move to Folder") {
                ForEach(store.folders.filter { $0 != c.folder }, id: \.self) { f in Button(f) { store.move(c, to: f) } }
            }
            Button("Copy Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(c.command, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) { store.delete(c) }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let notice {
                Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else if let t = target {
                Image(systemName: "terminal").foregroundStyle(.secondary)
                Text("Runs in: \(t.title)").lineLimit(1).truncationMode(.middle)
            } else {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                Text("Open a terminal tab to run commands")
            }
            Spacer()
            Text("Double-click to run").foregroundStyle(.tertiary)
        }
        .font(.caption)
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    // MARK: Actions

    private func expandedBinding(_ f: String) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(f) }, set: { open in
            var s = collapsed
            if open { s.remove(f) } else { s.insert(f) }
            setCollapsed(s)
        })
    }

    private func setCollapsed(_ s: Set<String>) {
        collapsed = s
        UserDefaults.standard.set(Array(s), forKey: "quickCommands.collapsed")
    }

    private func flash(_ text: String) {
        notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if notice == text { notice = nil } }
    }

    private func text(_ c: QuickCommand) -> String { c.command + (c.pressEnter ? "\r" : "") }

    private func send(_ c: QuickCommand, force: Bool = false) {
        guard let t = target else { flash("Open a terminal tab first."); return }
        if c.confirm && !force { confirming = c; return }
        t.sendText(text(c))
    }

    private func sendEverywhere(_ c: QuickCommand) {
        let terms = workspace.tabs.filter(\.hasTerminal)
        guard !terms.isEmpty else { flash("Open a terminal tab first."); return }
        for t in terms { t.sendText(text(c)) }
    }
}

private struct QuickCommandEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState var command: QuickCommand
    let folders: [String]
    @ViewState private var newFolder = ""
    private static let newFolderTag = "\u{1}new"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(QuickCommandStore.shared.commands.contains { $0.id == command.id } ? "Edit Command" : "New Command")
                .font(.title2.bold())
            TextField("Name", text: $command.name, prompt: Text("Restart web server"))
            Picker("Folder", selection: $command.folder) {
                ForEach(folders, id: \.self) { f in Label(f, systemImage: QuickFolders.icon(f)).tag(f) }
                Divider()
                Text("New Folder…").tag(Self.newFolderTag)
            }
            if command.folder == Self.newFolderTag {
                TextField("New folder name", text: $newFolder, prompt: Text("e.g. WordPress"))
            }
            Text("Command").font(.callout)
            TextEditor(text: $command.command)
                .font(.system(.body, design: .monospaced))
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
            Toggle("Star (show at the top)", isOn: $command.starred)
            Toggle("Press Return after sending", isOn: $command.pressEnter)
            Toggle("Ask before running", isOn: $command.confirm)
            Text("Commands that use sudo will ask for your password in the terminal.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    var c = command
                    if c.folder == Self.newFolderTag { c.folder = newFolder }
                    QuickCommandStore.shared.upsert(c)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(command.name.trimmingCharacters(in: .whitespaces).isEmpty
                          || command.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || (command.folder == Self.newFolderTag && newFolder.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

extension Notification.Name {
    static let focusQuickCommandSearch = Notification.Name("MacTermPlus.focusQuickCommandSearch")
}
