import AppKit
import Foundation

/// State and actions for the remote file list of one tab (SFTP or FTP).
@MainActor
final class RemoteFileBrowser: ObservableObject {
    @Published var path: String = ""
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var showHidden = AppSettings.shared.showHiddenFiles
    /// Follow the shell's current folder (SSH tabs).
    @Published var followTerminal = AppSettings.shared.followTerminalFolder
    /// Recently visited folders (newest first), for the path menu.
    @Published private(set) var history: [String] = []
    /// Live filter typed in the toolbar.
    @Published var filter = ""

    private(set) var fs: RemoteFileSystem
    /// Root mode (sudo): set for SSH/SFTP tabs. Takes a sudo password (nil = try without) and returns
    /// a verified root file system.
    var rootSwitcher: ((String?) async throws -> RemoteFileSystem)?
    @Published private(set) var isRoot = false
    private var normalFS: RemoteFileSystem?
    let title: String
    let queue = TransferQueue()
    private var editWatchers: [RemoteEditWatcher] = []
    /// Local copies of server files opened for editing; deleted when the tab closes.
    private var editDirs: [URL] = []
    private var started = false

    init(fs: RemoteFileSystem, title: String) {
        self.fs = fs
        self.title = title
    }

    var visibleItems: [FileItem] {
        var list = showHidden ? items : items.filter { !$0.name.hasPrefix(".") }
        if !filter.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(filter) } }
        guard !path.isEmpty, path != "/" else { return list }
        return [FileItem.parentRow(of: path, parent: RemotePath.parent(path))] + list
    }

    func start() async {
        guard !started else { return }
        started = true
        do {
            await load(try await fs.home())
        } catch {
            started = false
            errorMessage = SSHConnection.describe(error)
        }
    }

    func load(_ newPath: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await fs.list(newPath)
            path = newPath
            items = FileItem.sort(list)
            errorMessage = nil
            history.removeAll { $0 == newPath }
            history.insert(newPath, at: 0)
            if history.count > 15 { history.removeLast(history.count - 15) }
        } catch {
            errorMessage = SSHConnection.describe(error)
        }
    }

    func refresh() async { await load(path) }

    var canUseRoot: Bool { rootSwitcher != nil }

    /// Last error was a permission problem the root mode could solve.
    var errorIsPermission: Bool {
        guard let e = errorMessage?.lowercased() else { return false }
        return e.contains("permission denied") || e.contains("not allowed to open")
    }

    /// Switch to root mode; throws SudoError.needsPassword when a password is required.
    func enableRoot(password: String?) async throws {
        guard let rootSwitcher, !isRoot else { return }
        let rootFS = try await rootSwitcher(password)
        normalFS = fs
        fs = rootFS
        isRoot = true
        errorMessage = nil
        await load(path.isEmpty ? "/" : path)
    }

    func disableRoot() async {
        guard isRoot, let normalFS else { return }
        fs = normalFS
        isRoot = false
        errorMessage = nil
        await load(path)
    }
    func goUp() async { await load(RemotePath.parent(path)) }

    /// Called when the terminal reports a new working directory.
    func terminalChangedDirectory(_ dir: String) {
        guard followTerminal, dir != path else { return }
        Task { await load(dir) }
    }

    func open(_ item: FileItem) async {
        if item.isParent {
            await load(item.parentTarget)
        } else if item.isDirectory {
            await load(item.path)
        } else if item.isSymlink, await fs.isDirectory(item.path) {
            await load(item.path)
        } else {
            await edit(item)
        }
    }

    // MARK: Actions

    func upload(_ urls: [URL]) {
        let dir = path
        for url in urls {
            let t = Transfer(name: url.lastPathComponent, direction: .upload)
            queue.enqueue(t, work: { [fs] transfer in
                try await TransferQueue.upload(local: url, toRemoteDir: dir, fs: fs, transfer: transfer)
            }, onFinish: { [weak self] in
                guard let self, self.path == dir else { return }
                Task { await self.refresh() }
            })
        }
    }

    func download(_ selected: [FileItem], to dir: URL, onFinish: @escaping @MainActor () -> Void = {}) {
        for item in selected {
            let t = Transfer(name: item.name, direction: .download)
            queue.enqueue(t, work: { [fs] transfer in
                try await TransferQueue.download(remote: item, toLocalDir: dir, fs: fs, transfer: transfer)
            }, onFinish: onFinish)
        }
    }

    func downloadWithPanel(_ selected: [FileItem]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Download Here"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        download(selected, to: dir)
    }

    func uploadWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        guard panel.runModal() == .OK else { return }
        upload(panel.urls)
    }

    func makeDirectory(named name: String) async {
        guard !name.isEmpty else { return }
        do {
            try await fs.makeDirectory(RemotePath.join(path, name))
            await refresh()
        } catch { errorMessage = SSHConnection.describe(error) }
    }

    /// Creates an empty file on the server.
    func makeFile(named name: String) async {
        guard !name.isEmpty else { return }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tmp.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try await fs.upload(tmp, to: RemotePath.join(path, name)) { _ in }
            await refresh()
        } catch { errorMessage = SSHConnection.describe(error) }
    }

    func rename(_ item: FileItem, to newName: String) async {
        guard !newName.isEmpty, newName != item.name else { return }
        do {
            try await fs.rename(item.path, to: RemotePath.join(RemotePath.parent(item.path), newName))
            await refresh()
        } catch { errorMessage = SSHConnection.describe(error) }
    }

    /// chmod one or more items; folders can be changed recursively (files and sub-folders).
    func setPermissions(_ selected: [FileItem], mode: UInt32, recursive: Bool) async -> Int {
        var changed = 0
        do {
            for item in selected {
                try await fs.setPermissions(item.path, mode: mode)
                changed += 1
                if recursive && item.isDirectory { changed += try await chmodTree(item.path, mode: mode) }
            }
            errorMessage = nil
        } catch { errorMessage = SSHConnection.describe(error) }
        await refresh()
        return changed
    }

    private func chmodTree(_ dir: String, mode: UInt32) async throws -> Int {
        var n = 0
        for child in try await fs.list(dir) {
            try await fs.setPermissions(child.path, mode: mode)
            n += 1
            if child.isDirectory && !child.isSymlink { n += try await chmodTree(child.path, mode: mode) }
        }
        return n
    }

    func delete(_ selected: [FileItem]) async {
        do {
            for item in selected { try await fs.removeRecursively(item) }
        } catch { errorMessage = SSHConnection.describe(error) }
        await refresh()
    }

    /// Download to a temp folder, open in a Mac app, and upload again on every save.
    func edit(_ item: FileItem, with app: URL? = nil) async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacTermPlus-edit", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        editDirs.append(dir)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) } catch {
            errorMessage = error.localizedDescription
            return
        }
        let t = Transfer(name: item.name, direction: .download)
        queue.enqueue(t, work: { [fs] transfer in
            try await TransferQueue.download(remote: item, toLocalDir: dir, fs: fs, transfer: transfer)
        }, onFinish: { [weak self] in
            guard let self, t.status == .done else { return }
            let local = dir.appendingPathComponent(item.name)
            self.editWatchers.append(RemoteEditWatcher(local: local, remotePath: item.path, browser: self))
            OpenWith.open(local, with: app)
        })
    }

    func uploadEdited(local: URL, remotePath: String) {
        let t = Transfer(name: "↻ " + local.lastPathComponent, direction: .upload)
        let dir = RemotePath.parent(remotePath)
        queue.enqueue(t, work: { [fs] transfer in
            try await TransferQueue.upload(local: local, toRemoteDir: dir, fs: fs, transfer: transfer)
        }, onFinish: { [weak self] in
            Task { await self?.refresh() }
        })
    }

    func stop() {
        editWatchers.forEach { $0.stop() }
        editWatchers.removeAll()
        for d in editDirs { try? FileManager.default.removeItem(at: d) }
        editDirs.removeAll()
        fs.close()
    }
}

/// Polls a locally edited copy and pushes it back to the server whenever it changes.
@MainActor
final class RemoteEditWatcher {
    private var timer: Timer?
    private var lastModified: Date?

    init(local: URL, remotePath: String, browser: RemoteFileBrowser) {
        lastModified = Self.modDate(local)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak browser] _ in
            MainActor.assumeIsolated {
                guard let self, let browser else { return }
                let now = Self.modDate(local)
                if let now, now != self.lastModified {
                    self.lastModified = now
                    browser.uploadEdited(local: local, remotePath: remotePath)
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private static func modDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
