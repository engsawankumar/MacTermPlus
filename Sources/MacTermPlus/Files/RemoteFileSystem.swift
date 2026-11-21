import Citadel
import Foundation
import NIOCore

/// What the file browser, Files view, transfers and remote editing need from a server.
/// Implemented by SFTP (over the tab's SSH connection) and FTP/FTPS (libcurl).
protocol RemoteFileSystem: AnyObject, Sendable {
    /// Folder to show first (the login/home directory).
    func home() async throws -> String
    func list(_ path: String) async throws -> [FileItem]
    func download(_ remotePath: String, to local: URL, progress: @escaping @Sendable (UInt64) -> Void) async throws
    func upload(_ local: URL, to remotePath: String, progress: @escaping @Sendable (UInt64) -> Void) async throws
    func makeDirectory(_ path: String) async throws
    func removeFile(_ path: String) async throws
    func removeDirectory(_ path: String) async throws
    func rename(_ from: String, to: String) async throws
    /// True if this path is a directory (used for symlinks).
    func isDirectory(_ path: String) async -> Bool
    /// chmod: sets permission bits (e.g. 0o755).
    func setPermissions(_ path: String, mode: UInt32) async throws
    func close()
}

extension RemoteFileSystem {
    /// Recursive delete.
    func removeRecursively(_ item: FileItem) async throws {
        if item.isDirectory {
            for child in try await list(item.path) {
                try await removeRecursively(child)
            }
            try await removeDirectory(item.path)
        } else {
            try await removeFile(item.path)
        }
    }
}

// MARK: - SFTP

/// SFTP over the tab's SSH connection (one extra channel on the same connection).
final class SFTPFileSystem: RemoteFileSystem, @unchecked Sendable {
    private let connection: SSHConnection

    init(connection: SSHConnection) {
        self.connection = connection
    }

    private func sftp() async throws -> SFTPClient {
        try await connection.sftp()
    }

    func home() async throws -> String {
        let start = await MainActor.run { connection.profile.initialRemotePath }
        return try await sftp().getRealPath(atPath: start.isEmpty ? "." : start)
    }

    func list(_ path: String) async throws -> [FileItem] {
        let names = try await sftp().listDirectory(atPath: path)
        var result: [FileItem] = []
        for name in names {
            for component in name.components where component.filename != "." && component.filename != ".." {
                let attrs = component.attributes
                let mode = attrs.permissions
                let typeBits = (mode ?? 0) & 0o170000
                // longname is "ls -l" style: perms links owner group size …
                let cols = component.longname.split(separator: " ", omittingEmptySubsequences: true)
                var item = FileItem(
                    name: component.filename,
                    path: RemotePath.join(path, component.filename),
                    isDirectory: typeBits == 0o040000 || (mode == nil && component.longname.hasPrefix("d")),
                    isSymlink: typeBits == 0o120000,
                    size: attrs.size,
                    modified: attrs.accessModificationTime?.modificationTime,
                    permissions: FileItem.permissionString(mode)
                )
                if cols.count >= 4 { item.owner = String(cols[2]); item.group = String(cols[3]) }
                else if let ug = attrs.uidgid { item.owner = String(ug.userId); item.group = String(ug.groupId) }
                result.append(item)
            }
        }
        return result
    }

    func download(_ remotePath: String, to local: URL, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        FileManager.default.createFile(atPath: local.path, contents: nil)
        let handle = try FileHandle(forWritingTo: local)
        defer { try? handle.close() }
        try await sftp().withFile(filePath: remotePath, flags: .read) { file in
            var offset: UInt64 = 0
            while true {
                let buffer = try await file.read(from: offset, length: UInt32(TransferQueue.chunkSize))
                if buffer.readableBytes == 0 { break }
                try handle.write(contentsOf: Data(buffer.readableBytesView))
                offset += UInt64(buffer.readableBytes)
                progress(UInt64(buffer.readableBytes))
            }
        }
    }

    func upload(_ local: URL, to remotePath: String, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        let handle = try FileHandle(forReadingFrom: local)
        defer { try? handle.close() }
        try await sftp().withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
            var offset: UInt64 = 0
            while let data = try handle.read(upToCount: TransferQueue.chunkSize), !data.isEmpty {
                try await file.write(ByteBuffer(bytes: data), at: offset)
                offset += UInt64(data.count)
                progress(UInt64(data.count))
            }
        }
    }

    func makeDirectory(_ path: String) async throws { try await sftp().createDirectory(atPath: path) }
    func removeFile(_ path: String) async throws { try await sftp().remove(at: path) }
    func removeDirectory(_ path: String) async throws { try await sftp().rmdir(at: path) }
    func rename(_ from: String, to: String) async throws { try await sftp().rename(at: from, to: to) }

    func isDirectory(_ path: String) async -> Bool {
        (try? await sftp().listDirectory(atPath: path)) != nil
    }

    func setPermissions(_ path: String, mode: UInt32) async throws {
        var attrs = SFTPFileAttributes()
        attrs.permissions = mode & 0o7777
        try await sftp().setAttributes(at: path, to: attrs)
    }

    func close() {}
}
