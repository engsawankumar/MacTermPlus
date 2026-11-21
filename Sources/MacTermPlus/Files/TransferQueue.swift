import Foundation

/// One upload or download shown in the queue.
@MainActor
final class Transfer: ObservableObject, Identifiable {
    enum Direction { case upload, download }
    enum Status: Equatable { case queued, running, done, failed(String) }

    let id = UUID()
    let name: String
    let direction: Direction
    @Published var status: Status = .queued
    @Published var bytesDone: UInt64 = 0
    @Published var bytesTotal: UInt64 = 0
    let started = Date()

    init(name: String, direction: Direction) {
        self.name = name
        self.direction = direction
    }

    var fraction: Double {
        bytesTotal == 0 ? (status == .done ? 1 : 0) : min(1, Double(bytesDone) / Double(bytesTotal))
    }

    /// Bytes per second since the transfer started.
    var speed: Double {
        let t = Date().timeIntervalSince(started)
        return t > 0.5 ? Double(bytesDone) / t : 0
    }

    nonisolated func add(_ n: UInt64) {
        Task { @MainActor in self.bytesDone += n }
    }
}

/// Runs transfers one at a time, in order — predictable over a single connection.
@MainActor
final class TransferQueue: ObservableObject {
    @Published private(set) var transfers: [Transfer] = []
    private var tail: Task<Void, Never>?

    nonisolated static let chunkSize = 64 * 1024

    var activeCount: Int { transfers.filter { $0.status == .queued || $0.status == .running }.count }

    func clearFinished() {
        transfers.removeAll { $0.status == .done }
    }

    /// Queue work; `onFinish` runs on the main actor after the job (success or failure).
    func enqueue(_ transfer: Transfer,
                 work: @escaping (Transfer) async throws -> Void,
                 onFinish: @escaping @MainActor () -> Void = {}) {
        transfers.append(transfer)
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            transfer.status = .running
            do {
                try await work(transfer)
                transfer.status = .done
            } catch {
                transfer.status = .failed(SSHConnection.describe(error))
            }
            onFinish()
        }
    }

    // MARK: - Upload (file or folder, recursive)

    nonisolated static func upload(local: URL, toRemoteDir dir: String, fs: RemoteFileSystem, transfer: Transfer) async throws {
        let total = sizeOfLocal(local)
        await MainActor.run { transfer.bytesTotal = total }
        try await uploadItem(local: local, remoteDir: dir, fs: fs, transfer: transfer)
    }

    nonisolated private static func uploadItem(local: URL, remoteDir: String, fs: RemoteFileSystem, transfer: Transfer) async throws {
        try Task.checkCancellation()
        let remotePath = RemotePath.join(remoteDir, local.lastPathComponent)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: local.path, isDirectory: &isDir)
        if isDir.boolValue {
            try? await fs.makeDirectory(remotePath)
            for child in try FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: nil) {
                try await uploadItem(local: child, remoteDir: remotePath, fs: fs, transfer: transfer)
            }
        } else {
            try await fs.upload(local, to: remotePath) { transfer.add($0) }
        }
    }

    // MARK: - Download (file or folder, recursive)

    nonisolated static func download(remote item: FileItem, toLocalDir dir: URL, fs: RemoteFileSystem, transfer: Transfer) async throws {
        if !item.isDirectory, let size = item.size {
            await MainActor.run { transfer.bytesTotal = size }
        }
        try await downloadItem(remotePath: item.path, name: item.name, isDirectory: item.isDirectory, localDir: dir, fs: fs, transfer: transfer)
    }

    nonisolated static func downloadItem(remotePath: String, name: String, isDirectory: Bool, localDir: URL,
                                         fs: RemoteFileSystem, transfer: Transfer) async throws {
        try Task.checkCancellation()
        let localURL = localDir.appendingPathComponent(name)
        if isDirectory {
            try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
            for child in try await fs.list(remotePath) {
                try await downloadItem(remotePath: child.path, name: child.name, isDirectory: child.isDirectory,
                                       localDir: localURL, fs: fs, transfer: transfer)
            }
        } else {
            try await fs.download(remotePath, to: localURL) { transfer.add($0) }
        }
    }

    nonisolated static func sizeOfLocal(_ url: URL) -> UInt64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { UInt64($0) } ?? 0
        }
        var total: UInt64 = 0
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e {
                total += UInt64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }
}
