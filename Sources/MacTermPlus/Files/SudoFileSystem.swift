import Citadel
import Foundation
import NIOCore

enum SudoError: LocalizedError {
    case needsPassword, wrongPassword, notAllowed(String), failed(String)
    var errorDescription: String? {
        switch self {
        case .needsPassword: return "sudo needs your password."
        case .wrongPassword: return "That sudo password isn’t correct."
        case .notAllowed(let user): return "“\(user)” isn’t allowed to use sudo on this server."
        case .failed(let m): return m
        }
    }
}

/// Browse files as root: runs small `sudo` commands over the tab's SSH connection.
/// Reads stream through `sudo cat`; writes upload to a private temp file with SFTP, then `sudo mv`.
/// The sudo password (if any) is sent on the command's input, never on the command line.
final class SudoFileSystem: RemoteFileSystem, @unchecked Sendable {
    private let connection: SSHConnection
    private let sftp: SFTPFileSystem
    private let password: String?
    private let user: String
    /// Tests can replace "sudo" with a stand-in.
    private let sudo = ProcessInfo.processInfo.environment["MTP_SUDO_COMMAND"] ?? "sudo"

    init(connection: SSHConnection, password: String?, user: String) {
        self.connection = connection
        self.sftp = SFTPFileSystem(connection: connection)
        self.password = password?.isEmpty == false ? password : nil
        self.user = user
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Checks that sudo works with this password (or without one).
    static func verify(connection: SSHConnection, password: String?, user: String) async throws {
        let fs = SudoFileSystem(connection: connection, password: password, user: user)
        _ = try await fs.run("true")
    }

    /// Runs `sudo <command>`; returns stdout. `sink` receives stdout chunks instead (for downloads).
    @discardableResult
    private func run(_ command: String, sink: ((ByteBuffer) throws -> Void)? = nil) async throws -> Data {
        let client = try await connection.connectedClient()
        let full = password == nil ? "\(sudo) -n -- \(command)" : "\(sudo) -S -p '' -- \(command)"
        var out = Data()
        var err = ""
        let pw = password
        try await SSHConnection.ignoringRemoteClose {
            try await client.withExec("LC_ALL=C " + full) { inbound, outbound in
                if let pw { try await outbound.write(ByteBuffer(string: pw + "\n")) }
                for try await chunk in inbound {
                    switch chunk {
                    case .stdout(let b):
                        if let sink { try sink(b) } else { out.append(contentsOf: b.readableBytesView) }
                    case .stderr(let b):
                        err += String(buffer: b)
                    }
                }
            }
        }
        let e = err.trimmingCharacters(in: .whitespacesAndNewlines)
        if !e.isEmpty {
            let low = e.lowercased()
            if low.contains("a password is required") || low.contains("a terminal is required") { throw SudoError.needsPassword }
            if low.contains("incorrect password") || low.contains("sorry, try again") || low.contains("authentication failure") { throw SudoError.wrongPassword }
            if low.contains("not in the sudoers") || low.contains("is not allowed to") || low.contains("may not run sudo") { throw SudoError.notAllowed(user) }
            if out.isEmpty && sink == nil { throw SudoError.failed(e) }
        }
        return out
    }

    /// root's home folder as the server reports it (/root on Linux, /var/root on macOS); "/" if unknown.
    func home() async throws -> String {
        let out = String(decoding: try await run("sh -c " + Self.quote("cd ~root 2>/dev/null && pwd")), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.hasPrefix("/") ? out : "/"
    }

    func list(_ path: String) async throws -> [FileItem] {
        // GNU find gives exact, tab-separated fields; fall back to ls on systems without -printf.
        let q = Self.quote(path)
        let script = "sh -c " + Self.quote("find \(q) -mindepth 1 -maxdepth 1 -printf '%M\\t%u\\t%g\\t%s\\t%T@\\t%f\\n' 2>/dev/null || ls -lan \(q)")
        let text = String(decoding: try await run(script), as: UTF8.self)
        if text.contains("\t") {
            return text.split(separator: "\n").compactMap { line in
                let f = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
                guard f.count == 6 else { return nil }
                var item = FileItem(name: f[5], path: RemotePath.join(path, f[5]), isDirectory: f[0].hasPrefix("d"),
                                    isSymlink: f[0].hasPrefix("l"), size: UInt64(f[3]),
                                    modified: Double(f[4]).map { Date(timeIntervalSince1970: $0) }, permissions: f[0])
                item.owner = f[1]; item.group = f[2]
                return item
            }
        }
        return FTPListing.parseLIST(text, in: path)
    }

    func download(_ remotePath: String, to local: URL, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        FileManager.default.createFile(atPath: local.path, contents: nil)
        let handle = try FileHandle(forWritingTo: local)
        defer { try? handle.close() }
        try await run("cat -- " + Self.quote(remotePath)) { buffer in
            try handle.write(contentsOf: Data(buffer.readableBytesView))
            progress(UInt64(buffer.readableBytes))
        }
    }

    func upload(_ local: URL, to remotePath: String, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        let tmp = "/tmp/.macterm-upload-\(UUID().uuidString)"
        // Readable only by you while it waits to be moved into place (other server users can't peek).
        try await sftp.upload(local, to: tmp, createMode: 0o600, progress: progress)
        do {
            // Keep an existing file's owner and mode; new files get root's defaults.
            try await run("sh -c " + Self.quote(
                "if [ -e \(Self.quote(remotePath)) ]; then chown --reference=\(Self.quote(remotePath)) \(Self.quote(tmp)) 2>/dev/null; chmod --reference=\(Self.quote(remotePath)) \(Self.quote(tmp)) 2>/dev/null; else chown root: \(Self.quote(tmp)) 2>/dev/null; fi; mv -f \(Self.quote(tmp)) \(Self.quote(remotePath))"))
        } catch {
            try? await sftp.removeFile(tmp)
            throw error
        }
    }

    func makeDirectory(_ path: String) async throws { try await run("mkdir -- " + Self.quote(path)) }
    func removeFile(_ path: String) async throws { try await run("rm -f -- " + Self.quote(path)) }
    func removeDirectory(_ path: String) async throws { try await run("rmdir -- " + Self.quote(path)) }
    func rename(_ from: String, to: String) async throws { try await run("mv -- \(Self.quote(from)) \(Self.quote(to))") }
    func setPermissions(_ path: String, mode: UInt32) async throws {
        try await run("chmod -- \(String(mode & 0o7777, radix: 8)) " + Self.quote(path))   // "--" first: GNU and BSD
    }

    func isDirectory(_ path: String) async -> Bool {
        (try? await run("test -d " + Self.quote(path) + " && echo yes")).map { String(decoding: $0, as: UTF8.self).contains("yes") } ?? false
    }

    func close() {}
}
