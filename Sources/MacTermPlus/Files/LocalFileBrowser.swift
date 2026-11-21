import AppKit
import Foundation

/// The Mac-side list in the two-pane commander.
@MainActor
final class LocalFileBrowser: ObservableObject {
    @Published var path: String = NSHomeDirectory()
    @Published private(set) var items: [FileItem] = []
    @Published var errorMessage: String?
    @Published var showHidden = AppSettings.shared.showHiddenFiles

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    var visibleItems: [FileItem] {
        let list = showHidden ? items : items.filter { !$0.name.hasPrefix(".") }
        guard path != "/" else { return list }
        return [FileItem.parentRow(of: path, parent: url.deletingLastPathComponent().path)] + list
    }

    init() { load(path) }

    func load(_ newPath: String) {
        let dir = URL(fileURLWithPath: newPath, isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)
            items = FileItem.sort(urls.map { u in
                let v = try? u.resourceValues(forKeys: Set(keys))
                let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
                let mode = (attrs?[.posixPermissions] as? NSNumber)?.uint32Value
                let isDir = v?.isDirectory ?? false
                var item = FileItem(
                    name: u.lastPathComponent,
                    path: u.path,
                    isDirectory: isDir,
                    isSymlink: v?.isSymbolicLink ?? false,
                    size: v?.fileSize.map { UInt64($0) },
                    modified: v?.contentModificationDate,
                    permissions: FileItem.permissionString(mode.map { $0 | (isDir ? 0o040000 : 0) })
                )
                item.owner = attrs?[.ownerAccountName] as? String ?? ""
                item.group = attrs?[.groupOwnerAccountName] as? String ?? ""
                return item
            })
            path = dir.path
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() { load(path) }
    func goUp() { load(url.deletingLastPathComponent().path) }

    func open(_ item: FileItem) {
        if item.isParent {
            load(item.parentTarget)
        } else if item.isDirectory {
            load(item.path)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
        }
    }

    func revealInFinder(_ selected: [FileItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(selected.map { URL(fileURLWithPath: $0.path) })
    }

    func setPermissions(_ item: FileItem, mode: UInt32, recursive: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: item.path)
        if recursive, item.isDirectory, let e = FileManager.default.enumerator(atPath: item.path) {
            for case let rel as String in e {
                try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)],
                                                       ofItemAtPath: (item.path as NSString).appendingPathComponent(rel))
            }
        }
        refresh()
    }

    func makeDirectory(named name: String) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).appendingPathComponent(name), withIntermediateDirectories: false)
        refresh()
    }

    func makeFile(named name: String) {
        FileManager.default.createFile(atPath: (path as NSString).appendingPathComponent(name), contents: Data())
        refresh()
    }

    func rename(_ item: FileItem, to newName: String) {
        try? FileManager.default.moveItem(atPath: item.path, toPath: ((item.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(newName))
        refresh()
    }

    func moveToTrash(_ selected: [FileItem]) {
        for item in selected {
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
        }
        refresh()
    }
}
