import CCurlShim
import Foundation

enum FTPError: LocalizedError {
    case curl(code: Int, message: String, serverReply: Int)
    case cannotInit

    var errorDescription: String? {
        switch self {
        case .cannotInit: return "Couldn’t start the FTP engine."
        case .curl(let code, let message, let reply):
            switch code {
            case 67: return "Login failed — check the username and password."
            case 6: return "Server not found — check the host name."
            case 7: return "Couldn’t connect — is FTP running on that port?"
            case 28: return "The connection timed out."
            case 35, 60: return "Secure connection (TLS) failed. If the server uses a self-signed certificate, enable “Accept invalid certificates” in the session."
            case 64: return "This server doesn’t support FTP over TLS. Use plain FTP for this session."
            case 9, 78: return "Access denied or file not found\(reply > 0 ? " (server code \(reply))" : "")."
            case 21: return "The server refused the command\(reply > 0 ? " (code \(reply))" : "")."
            default: return "\(message)\(reply > 0 ? " (server code \(reply))" : "")"
            }
        }
    }
}

/// FTP and FTPS (explicit AUTH TLS, or implicit on port 990) via the libcurl that ships with macOS.
/// All calls run one at a time on a private queue and reuse one connection where possible.
final class FTPFileSystem: RemoteFileSystem, @unchecked Sendable {
    struct Config: Sendable {
        var host: String
        var port: Int
        var username: String
        var password: String
        var secure: Bool
        var acceptInvalidCertificates: Bool
        var initialPath: String
    }

    private let config: Config
    private let queue = DispatchQueue(label: "MacTermPlus.ftp")
    private var handle: UnsafeMutableRawPointer?   // CURL*
    private var mlsdUnsupported = false

    init(config: Config) {
        self.config = config
        _ = FTPFileSystem.globalInit
    }

    deinit {
        if let handle { curl_easy_cleanup(handle) }
    }

    private static let globalInit: Void = { curl_global_init(Int(CURL_GLOBAL_DEFAULT)) }()

    // MARK: URL helpers

    private var baseURL: String {
        let scheme = (config.secure && config.port == 990) ? "ftps" : "ftp"
        let host = config.host.contains(":") ? "[\(config.host)]" : config.host
        return "\(scheme)://\(host):\(config.port)"
    }

    /// Absolute remote path → URL. curl treats the URL path as relative to the login dir, so
    /// absolute paths are written with a leading "%2F".
    private func url(for path: String, directory: Bool = false) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/;?#%")
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
        var u = baseURL + "/" + (path.hasPrefix("/") ? "%2F" : "") + segments.joined(separator: "/")
        if directory && !u.hasSuffix("/") { u += "/" }
        return u
    }

    // MARK: Engine

    private final class Box: @unchecked Sendable {
        var data = Data()
        var file: FileHandle?
        var progress: (@Sendable (UInt64) -> Void)?
        var error: Error?
    }

    /// Runs one libcurl request on the private queue.
    private func perform(_ configure: @escaping (UnsafeMutableRawPointer, Box) throws -> Void,
                         after: ((UnsafeMutableRawPointer) -> Void)? = nil) async throws -> Box {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Box, Error>) in
            queue.async { [self] in
                if handle == nil { handle = curl_easy_init() }
                guard let h = handle else { cont.resume(throwing: FTPError.cannotInit); return }
                curl_easy_reset(h)
                let box = Box()
                mtp_setopt_str(h, CURLOPT_USERNAME, config.username.isEmpty ? "anonymous" : config.username)
                mtp_setopt_str(h, CURLOPT_PASSWORD, config.username.isEmpty && config.password.isEmpty ? "anonymous@" : config.password)
                mtp_setopt_long(h, CURLOPT_CONNECTTIMEOUT, 20)
                mtp_setopt_long(h, CURLOPT_FTP_USE_EPSV, 1)
                mtp_setopt_long(h, CURLOPT_FTP_FILEMETHOD, Int(CURLFTPMETHOD_NOCWD.rawValue))
                mtp_setopt_long(h, CURLOPT_NOSIGNAL, 1)
                if config.secure {
                    mtp_setopt_long(h, CURLOPT_USE_SSL, Int(CURLUSESSL_ALL.rawValue))
                    if config.acceptInvalidCertificates {
                        mtp_setopt_long(h, CURLOPT_SSL_VERIFYPEER, 0)
                        mtp_setopt_long(h, CURLOPT_SSL_VERIFYHOST, 0)
                    }
                }
                let unmanaged = Unmanaged.passRetained(box)
                defer { unmanaged.release() }
                mtp_setopt_writefn(h, { ptr, size, n, ud in
                    let box = Unmanaged<Box>.fromOpaque(ud!).takeUnretainedValue()
                    let count = size * n
                    guard let ptr else { return count }
                    if let file = box.file {
                        do { try file.write(contentsOf: Data(bytes: ptr, count: count)) } catch { box.error = error; return 0 }
                        box.progress?(UInt64(count))
                    } else {
                        box.data.append(UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt8.self), count: count)
                    }
                    return count
                }, unmanaged.toOpaque())
                do {
                    try configure(h, box)
                } catch {
                    cont.resume(throwing: error); return
                }
                let rc = curl_easy_perform(h)
                after?(h)
                if let e = box.error { cont.resume(throwing: e); return }
                if rc != CURLE_OK {
                    var reply = 0
                    mtp_getinfo_long(h, CURLINFO_RESPONSE_CODE, &reply)
                    let msg = String(cString: curl_easy_strerror(rc))
                    cont.resume(throwing: FTPError.curl(code: Int(rc.rawValue), message: msg, serverReply: reply))
                    return
                }
                cont.resume(returning: box)
            }
        }
    }

    /// Sends raw FTP commands (MKD, DELE, RMD, RNFR/RNTO) without transferring data.
    private func quote(_ commands: [String]) async throws {
        _ = try await perform { [self] h, _ in
            var list: UnsafeMutablePointer<curl_slist>?
            for c in commands { list = curl_slist_append(list, c) }
            mtp_setopt_str(h, CURLOPT_URL, baseURL + "/")
            mtp_setopt_slist(h, CURLOPT_QUOTE, list)
            mtp_setopt_long(h, CURLOPT_NOBODY, 1)
            // The list must outlive the request; it is freed by the `after` hook below via the box.
            QuoteLists.shared.hold(list, for: h)
        } after: { h in
            QuoteLists.shared.release(for: h)
        }
    }

    // MARK: RemoteFileSystem

    func home() async throws -> String {
        if !config.initialPath.isEmpty { return config.initialPath }
        var entry = "/"
        _ = try await perform { [self] h, _ in
            mtp_setopt_str(h, CURLOPT_URL, baseURL + "/")
            mtp_setopt_long(h, CURLOPT_NOBODY, 1)
        } after: { h in
            var p: UnsafePointer<CChar>?
            if mtp_getinfo_str(h, CURLINFO_FTP_ENTRY_PATH, &p) == CURLE_OK, let p { entry = String(cString: p) }
        }
        return entry.isEmpty ? "/" : entry
    }

    func list(_ path: String) async throws -> [FileItem] {
        if !mlsdUnsupported {
            do {
                let box = try await perform { [self] h, _ in
                    mtp_setopt_str(h, CURLOPT_URL, url(for: path, directory: true))
                    mtp_setopt_str(h, CURLOPT_CUSTOMREQUEST, "MLSD")
                }
                let items = FTPListing.parseMLSD(String(decoding: box.data, as: UTF8.self), in: path)
                if !items.isEmpty || box.data.isEmpty { return items }
            } catch FTPError.curl(let code, _, _) where ![6, 7, 28, 35, 60, 64, 67].contains(code) {
                mlsdUnsupported = true   // server doesn't know MLSD (or the folder is odd); use LIST from now on
            }
        }
        let box = try await perform { [self] h, _ in
            mtp_setopt_str(h, CURLOPT_URL, url(for: path, directory: true))
        }
        return FTPListing.parseLIST(String(decoding: box.data, as: UTF8.self), in: path)
    }

    func download(_ remotePath: String, to local: URL, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        FileManager.default.createFile(atPath: local.path, contents: nil)
        let file = try FileHandle(forWritingTo: local)
        defer { try? file.close() }
        _ = try await perform { [self] h, box in
            box.file = file
            box.progress = progress
            mtp_setopt_str(h, CURLOPT_URL, url(for: remotePath))
        }
    }

    func upload(_ local: URL, to remotePath: String, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        let file = try FileHandle(forReadingFrom: local)
        defer { try? file.close() }
        let size = (try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let reader = Reader(file: file, progress: progress)
        let unmanaged = Unmanaged.passRetained(reader)
        defer { unmanaged.release() }
        _ = try await perform { [self] h, _ in
            mtp_setopt_str(h, CURLOPT_URL, url(for: remotePath))
            mtp_setopt_long(h, CURLOPT_UPLOAD, 1)
            mtp_setopt_off(h, CURLOPT_INFILESIZE_LARGE, curl_off_t(size))
            mtp_setopt_readfn(h, { ptr, size, n, ud in
                let reader = Unmanaged<Reader>.fromOpaque(ud!).takeUnretainedValue()
                guard let ptr else { return 0 }
                let data = (try? reader.file.read(upToCount: size * n)) ?? Data()
                data.copyBytes(to: UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: UInt8.self), count: data.count)
                reader.progress(UInt64(data.count))
                return data.count
            }, unmanaged.toOpaque())
        }
    }

    private final class Reader: @unchecked Sendable {
        let file: FileHandle
        let progress: @Sendable (UInt64) -> Void
        init(file: FileHandle, progress: @escaping @Sendable (UInt64) -> Void) { self.file = file; self.progress = progress }
    }

    func makeDirectory(_ path: String) async throws { try await quote(["MKD \(path)"]) }
    func removeFile(_ path: String) async throws { try await quote(["DELE \(path)"]) }
    func removeDirectory(_ path: String) async throws { try await quote(["RMD \(path)"]) }
    func rename(_ from: String, to: String) async throws { try await quote(["RNFR \(from)", "RNTO \(to)"]) }

    func setPermissions(_ path: String, mode: UInt32) async throws {
        try await quote([String(format: "SITE CHMOD %o %@", mode & 0o7777, path)])
    }

    func isDirectory(_ path: String) async -> Bool {
        (try? await list(path)) != nil
    }

    func close() {
        queue.async { [self] in
            if let h = handle { curl_easy_cleanup(h); handle = nil }
        }
    }
}

/// Keeps curl_slist objects alive for the duration of a request.
private final class QuoteLists: @unchecked Sendable {
    static let shared = QuoteLists()
    private var lists: [UnsafeMutableRawPointer: UnsafeMutablePointer<curl_slist>] = [:]
    private let lock = NSLock()

    func hold(_ list: UnsafeMutablePointer<curl_slist>?, for handle: UnsafeMutableRawPointer) {
        lock.lock(); defer { lock.unlock() }
        if let list { lists[handle] = list }
    }

    func release(for handle: UnsafeMutableRawPointer) {
        lock.lock(); defer { lock.unlock() }
        if let list = lists.removeValue(forKey: handle) { curl_slist_free_all(list) }
    }
}

/// Parses FTP directory listings.
enum FTPListing {
    /// MLSD: "type=dir;size=0;modify=20240101120000;UNIX.mode=0755; name"
    static func parseMLSD(_ text: String, in dir: String) -> [FileItem] {
        var out: [FileItem] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard let space = line.firstIndex(of: " ") else { continue }
            let name = String(line[line.index(after: space)...])
            guard name != ".", name != ".." else { continue }
            var facts: [String: String] = [:]
            for f in line[..<space].split(separator: ";") {
                let kv = f.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { facts[kv[0].lowercased()] = String(kv[1]) }
            }
            let type = facts["type"]?.lowercased() ?? "file"
            guard type != "cdir", type != "pdir" else { continue }
            var modified: Date?
            if let m = facts["modify"] {
                let f = DateFormatter()
                f.dateFormat = "yyyyMMddHHmmss"
                f.timeZone = TimeZone(identifier: "UTC")
                modified = f.date(from: String(m.prefix(14)))
            }
            let mode = facts["unix.mode"].flatMap { UInt32($0, radix: 8) }
            let isDir = type == "dir"
            out.append(FileItem(name: name, path: RemotePath.join(dir, name), isDirectory: isDir,
                                isSymlink: type.contains("slink"), size: facts["size"].flatMap { UInt64($0) },
                                modified: modified,
                                permissions: FileItem.permissionString(mode.map { $0 | (isDir ? 0o040000 : 0o100000) })))
        }
        return out
    }

    /// LIST in Unix ("drwxr-xr-x 2 u g 4096 Jan 01 12:00 name") or DOS ("01-02-24 10:00AM <DIR> name") style.
    static func parseLIST(_ text: String, in dir: String) -> [FileItem] {
        var out: [FileItem] = []
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.hasPrefix("total ") { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if let first = line.first, "dl-cbps".contains(first), parts.count >= 9 {
                // Unix: perms links owner group size month day time/year name...
                var name = parts[8...].joined(separator: " ")
                // Keep original spacing in names where possible.
                if let r = line.range(of: " \(parts[5]) +\(parts[6]) +\(parts[7]) ", options: .regularExpression) {
                    name = String(line[r.upperBound...])
                }
                let isLink = first == "l"
                if isLink, let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
                guard name != ".", name != ".." else { continue }
                var date: Date?
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                if parts[7].contains(":") {
                    f.dateFormat = "MMM d HH:mm yyyy"
                    let year = cal.component(.year, from: now)
                    date = f.date(from: "\(parts[5]) \(parts[6]) \(parts[7]) \(year)")
                    if let d = date, d > now.addingTimeInterval(86400) { date = cal.date(byAdding: .year, value: -1, to: d) }
                } else {
                    f.dateFormat = "MMM d yyyy"
                    date = f.date(from: "\(parts[5]) \(parts[6]) \(parts[7])")
                }
                var item = FileItem(name: name, path: RemotePath.join(dir, name), isDirectory: first == "d", isSymlink: isLink,
                                    size: UInt64(parts[4]), modified: date, permissions: String(parts[0].prefix(10)))
                item.owner = parts[2]
                item.group = parts[3]
                out.append(item)
            } else if parts.count >= 4, parts[0].contains("-"), parts[1].uppercased().hasSuffix("M") {
                // DOS / IIS
                let isDir = parts[2].uppercased() == "<DIR>"
                let name = parts[3...].joined(separator: " ")
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "MM-dd-yy hh:mma"
                out.append(FileItem(name: name, path: RemotePath.join(dir, name), isDirectory: isDir, isSymlink: false,
                                    size: isDir ? nil : UInt64(parts[2]), modified: f.date(from: "\(parts[0]) \(parts[1])"),
                                    permissions: ""))
            }
        }
        return out
    }
}
