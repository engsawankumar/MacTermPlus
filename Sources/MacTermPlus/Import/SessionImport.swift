import Foundation

/// Where sessions can be imported from.
enum ImportSource: String, CaseIterable, Identifiable {
    case auto, mobaxterm, putty, winscp, filezilla, winbox, termius, applePasswords, sshConfig, macterm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto-detect"
        case .mobaxterm: return "MobaXterm"
        case .putty: return "PuTTY"
        case .winscp: return "WinSCP"
        case .filezilla: return "FileZilla (FTP/SFTP)"
        case .winbox: return "WinBox"
        case .termius: return "Termius / CSV"
        case .applePasswords: return "Passwords app"
        case .sshConfig: return "OpenSSH config"
        case .macterm: return "MacTerm+ export"
        }
    }

    var icon: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .mobaxterm: return "rectangle.stack.fill"
        case .putty: return "desktopcomputer"
        case .winscp: return "arrow.left.arrow.right.square.fill"
        case .filezilla: return "externaldrive.connected.to.line.below.fill"
        case .winbox: return "network"
        case .termius: return "tablecells.fill"
        case .applePasswords: return "key.icloud.fill"
        case .sshConfig: return "terminal.fill"
        case .macterm: return "shippingbox.fill"
        }
    }

    var colorName: String {
        switch self {
        case .auto: return "teal"
        case .mobaxterm: return "orange"
        case .putty: return "blue"
        case .winscp: return "green"
        case .filezilla: return "red"
        case .winbox: return "indigo"
        case .termius: return "purple"
        case .applePasswords: return "gray"
        case .sshConfig: return "gray"
        case .macterm: return "pink"
        }
    }

    /// Where the user finds the file to import.
    var hint: String {
        switch self {
        case .auto:
            return "Pick any supported file or folder (including a CrossOver/Wine bottle’s user.reg); the format is detected automatically."
        case .mobaxterm:
            return "In MobaXterm: right-click “User sessions” → Export all sessions to file (.mxtsessions). The MobaXterm.ini file also works."
        case .putty:
            return "A .reg export (on Windows: reg export HKCU\\Software\\SimonTatham\\PuTTY\\Sessions putty.reg), a CrossOver/Wine bottle’s user.reg, or the ~/.putty/sessions folder."
        case .winscp:
            return "In WinSCP: Tools → Export/Backup Configuration (WinSCP.ini), or use the portable WinSCP.ini."
        case .filezilla:
            return "In FileZilla: File → Export… (or copy sitemanager.xml from %APPDATA%\\FileZilla). SFTP, FTP and FTPS sites are imported."
        case .winbox:
            return "Copy Addresses.cdb from %APPDATA%\\Mikrotik\\Winbox. Addresses are imported as SSH sessions on port 22 (best effort — WinBox’s file format is undocumented)."
        case .termius:
            return "A CSV file with a header row, e.g. Label, Group, Hostname, Port, Username. Works for Termius exports, spreadsheets and most other apps."
        case .applePasswords:
            return "A CSV exported from Apple’s Passwords app (iCloud Keychain): Passwords → File → Export All Passwords. Entries whose URL starts with ssh://, sftp://, ftp:// or ftps:// become sessions, with their passwords. Delete the CSV afterwards — it contains passwords in plain text."
        case .sshConfig:
            return "Your ~/.ssh/config (Host, HostName, User, Port, IdentityFile). Wildcard hosts are skipped."
        case .macterm:
            return "A .json file made with Export Sessions in MacTerm+."
        }
    }
}

struct ImportResult {
    var sessions: [SessionProfile] = []
    var skipped: [String] = []
    var detected: ImportSource = .auto
    /// Passwords that came with the import (Apple Passwords CSV), keyed by session id.
    var secrets: [UUID: String] = [:]
    /// Sessions found in the macOS keychain; their passwords can be fetched on import.
    var keychainEntries: [UUID: Keychain.ServerEntry] = [:]
}

enum ImportError: LocalizedError {
    case unreadable, unknownFormat, nothingFound
    var errorDescription: String? {
        switch self {
        case .unreadable: return "The file couldn’t be read."
        case .unknownFormat: return "This file wasn’t recognized. Pick the source app explicitly and try again."
        case .nothingFound: return "No SSH or SFTP sessions were found in this file."
        }
    }
}

enum SessionImporter {
    static func importFile(at url: URL, as source: ImportSource) throws -> ImportResult {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            // ~/.putty/sessions folder
            var result = ImportResult(detected: .putty)
            let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for f in files {
                guard let text = decodeText(try? Data(contentsOf: f)) else { continue }
                if let p = puttyUnixSession(name: f.lastPathComponent, text: text) { result.sessions.append(p) }
            }
            guard !result.sessions.isEmpty else { throw ImportError.nothingFound }
            return result
        }

        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        let resolved = source == .auto ? detect(url: url, data: data) : source
        guard let resolved else { throw ImportError.unknownFormat }

        var result: ImportResult
        switch resolved {
        case .winbox:
            result = winbox(data)
        case .filezilla:
            result = filezilla(data)
        case .macterm:
            result = try json(data)
        default:
            guard let text = decodeText(data) else { throw ImportError.unreadable }
            switch resolved {
            case .mobaxterm: result = mobaxterm(text)
            case .putty:
                result = text.contains("SimonTatham") || text.contains("Martin Prikryl") ? registry(text)
                    : ImportResult(sessions: [puttyUnixSession(name: url.lastPathComponent, text: text)].compactMap { $0 })
            case .winscp: result = winscp(text)
            case .termius: result = csv(text)
            case .applePasswords: result = applePasswords(text)
            case .sshConfig: result = sshConfig(text)
            default: throw ImportError.unknownFormat
            }
        }
        result.detected = resolved
        guard !result.sessions.isEmpty else {
            if !result.skipped.isEmpty { return result }
            throw ImportError.nothingFound
        }
        return result
    }

    // MARK: Detection

    static func detect(url: URL, data: Data) -> ImportSource? {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        if ext == "cdb" || data.starts(with: [0x0D, 0xF0, 0x1D, 0xC0]) { return .winbox }
        if ext == "mxtsessions" || name == "mobaxterm.ini" { return .mobaxterm }
        if ext == "csv" {
            if let head = decodeText(data)?.split(separator: "\n").first?.lowercased(),
               head.contains("title"), head.contains("url"), head.contains("password") { return .applePasswords }
            return .termius
        }
        if ext == "json" { return .macterm }
        guard let text = decodeText(data) else { return nil }
        if text.contains("<FileZilla3") || text.contains("<Servers>") { return .filezilla }
        if text.contains("SimonTatham\\PuTTY") || text.contains("SimonTatham\\\\PuTTY") || text.contains("Martin Prikryl") { return .putty }
        if text.contains("[Sessions\\") { return .winscp }
        if text.contains("[Bookmarks") { return .mobaxterm }
        if text.range(of: #"(?im)^\s*host\s+\S+"#, options: .regularExpression) != nil,
           text.range(of: #"(?im)^\s*hostname\s+\S+"#, options: .regularExpression) != nil { return .sshConfig }
        if name == "config" { return .sshConfig }
        if text.trimmingCharacters(in: .whitespaces).hasPrefix("{") || text.hasPrefix("[") { return .macterm }
        if text.contains("HostName=") && text.contains("Protocol=") { return .putty }
        if let first = text.split(separator: "\n").first, first.contains(","), first.lowercased().contains("host") { return .termius }
        return nil
    }

    static func decodeText(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        if data.starts(with: [0xFF, 0xFE]) { return String(data: data, encoding: .utf16LittleEndian).map { String($0.dropFirst()) } }
        if data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16BigEndian).map { String($0.dropFirst()) } }
        // UTF-16LE without BOM: every other byte is zero.
        if data.count > 4, data[1] == 0, data[3] == 0 { return String(data: data, encoding: .utf16LittleEndian) }
        if let s = String(data: data, encoding: .utf8) { return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s }
        return String(data: data, encoding: .isoLatin1)
    }

    // MARK: Helpers

    private static func make(name: String, group: String, host: String, port: Int, user: String,
                             keyPath: String = "", kind: SessionKind = .ssh) -> SessionProfile? {
        var host = host.trimmingCharacters(in: .whitespaces)
        var user = user.trimmingCharacters(in: .whitespaces)
        if let at = host.lastIndex(of: "@") {
            if user.isEmpty { user = String(host[..<at]) }
            host = String(host[host.index(after: at)...])
        }
        guard !host.isEmpty else { return nil }
        var p = SessionProfile(name: name.trimmingCharacters(in: .whitespaces), group: group, host: host,
                               port: port > 0 ? port : kind.defaultPort, username: user)
        p.kind = kind
        if !keyPath.isEmpty {
            p.auth = .privateKey
            p.keyPath = keyPath
        }
        return p
    }

    private static func iniSections(_ text: String) -> [(name: String, values: [String: String])] {
        var out: [(String, [String: String])] = []
        var current: (String, [String: String])?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), let close = line.lastIndex(of: "]") {
                if let c = current { out.append(c) }
                let name = String(line[line.index(after: line.startIndex)..<close]).replacingOccurrences(of: "\\\\", with: "\\")
                current = (name, [:])
            } else if let eq = line.firstIndex(of: "="), current != nil {
                current!.1[String(line[..<eq]).trimmingCharacters(in: .whitespaces)] = String(line[line.index(after: eq)...])
            }
        }
        if let c = current { out.append(c) }
        return out
    }

    // MARK: MobaXterm (.mxtsessions / MobaXterm.ini)

    static func mobaxterm(_ text: String) -> ImportResult {
        var result = ImportResult()
        let sections = iniSections(text)
        // Sessions may reference a stored credential as "[Name]"; its value is "username:encrypted-password".
        // Only the username is used — the password part is never read.
        var credentialUsers: [String: String] = [:]
        for (k, v) in sections.first(where: { $0.name == "Credentials" })?.values ?? [:] {
            if let colon = v.firstIndex(of: ":") { credentialUsers[k] = String(v[..<colon]) }
        }
        func resolveUser(_ u: String) -> String {
            guard u.hasPrefix("["), u.hasSuffix("]") else { return u }
            return credentialUsers[String(u.dropFirst().dropLast())] ?? ""
        }
        for section in sections where section.name.lowercased().hasPrefix("bookmarks") {
            let group = (section.values["SubRep"] ?? "").replacingOccurrences(of: "\\", with: "/")
            for (key, value) in section.values where key != "SubRep" && key != "ImgNum" {
                let parts = value.components(separatedBy: "#")
                guard parts.count > 2 else { continue }
                let fields = parts[2].components(separatedBy: "%")
                guard fields.count > 3 else { continue }
                switch fields[0] {
                case "0", "7", "6": // 0 = SSH, 7 = SFTP, 6 = FTP
                    let kind: SessionKind = fields[0] == "0" ? .ssh : (fields[0] == "7" ? .sftp : .ftp)
                    if let p = make(name: key, group: group, host: fields[1], port: Int(fields[2]) ?? kind.defaultPort,
                                    user: resolveUser(fields[3]), kind: kind) {
                        result.sessions.append(p)
                    }
                default:
                    let kinds = ["1": "Telnet", "4": "RDP", "5": "VNC", "6": "FTP", "8": "Serial", "3": "XDMCP"]
                    result.skipped.append("\(key) (\(kinds[fields[0]] ?? "unsupported type"))")
                }
            }
        }
        return result
    }

    // MARK: PuTTY

    /// Windows registry text: a .reg export, or a Wine/CrossOver/Whisky user.reg. Reads PuTTY and WinSCP sessions.
    static func registry(_ text: String) -> ImportResult {
        var result = puttyReg(text)
        for section in iniSections(text) {
            guard let r = section.name.range(of: "Martin Prikryl\\WinSCP 2\\Sessions\\") else { continue }
            let full = String(section.name[r.upperBound...]).removingPercentEncoding ?? ""
            guard full != "Default Settings" else { continue }
            func str(_ k: String) -> String {
                ((section.values["\"\(k)\""] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    .removingPercentEncoding ?? "")
            }
            func dword(_ k: String) -> Int? {
                guard let v = section.values["\"\(k)\""], v.hasPrefix("dword:") else { return nil }
                return Int(v.dropFirst(6), radix: 16)
            }
            let pieces = full.split(separator: "/").map(String.init)
            let proto = dword("FSProtocol") ?? 2
            guard let kind = winscpKind(proto, ftps: dword("Ftps") ?? 0) else {
                result.skipped.append("\(pieces.last ?? full) (\(proto == 6 ? "WebDAV" : proto == 7 ? "S3" : "other"))"); continue
            }
            if let p = make(name: pieces.last ?? full, group: pieces.count > 1 ? pieces.dropLast().joined(separator: "/") : "WinSCP",
                            host: str("HostName"), port: dword("PortNumber") ?? kind.defaultPort, user: str("UserName"), kind: kind) {
                result.sessions.append(p)
            }
        }
        return result
    }

    static func puttyReg(_ text: String) -> ImportResult {
        var result = ImportResult()
        for section in iniSections(text) {
            guard section.name.contains("SimonTatham\\PuTTY"), let r = section.name.range(of: "\\Sessions\\") else { continue }
            let name = String(section.name[r.upperBound...]).removingPercentEncoding ?? ""
            guard name != "Default Settings" else { continue }
            func str(_ k: String) -> String {
                (section.values["\"\(k)\""] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
            func dword(_ k: String) -> Int? {
                guard let v = section.values["\"\(k)\""], v.hasPrefix("dword:") else { return nil }
                return Int(v.dropFirst(6), radix: 16)
            }
            let proto = str("Protocol")
            if !proto.isEmpty && proto != "ssh" { result.skipped.append("\(name) (\(proto))"); continue }
            if let p = make(name: name, group: "PuTTY", host: str("HostName"), port: dword("PortNumber") ?? 22, user: str("UserName")) {
                result.sessions.append(p)
            }
        }
        return result
    }

    static func puttyUnixSession(name: String, text: String) -> SessionProfile? {
        var v: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            if let eq = line.firstIndex(of: "=") { v[String(line[..<eq])] = String(line[line.index(after: eq)...]) }
        }
        let proto = v["Protocol"] ?? "ssh"
        guard proto == "ssh" else { return nil }
        let decoded = name.removingPercentEncoding ?? name
        guard decoded != "Default Settings" else { return nil }
        return make(name: decoded, group: "PuTTY", host: v["HostName"] ?? "", port: Int(v["PortNumber"] ?? "") ?? 22,
                    user: v["UserName"] ?? "", keyPath: v["PublicKeyFile"] ?? "")
    }

    // MARK: WinSCP (WinSCP.ini)

    static func winscp(_ text: String) -> ImportResult {
        var result = ImportResult()
        for section in iniSections(text) where section.name.hasPrefix("Sessions\\") {
            let full = String(section.name.dropFirst("Sessions\\".count)).removingPercentEncoding ?? ""
            guard full != "Default Settings" else { continue }
            let pieces = full.split(separator: "/").map(String.init)
            let name = pieces.last ?? full
            let group = pieces.dropLast().joined(separator: "/")
            let proto = Int(section.values["FSProtocol"] ?? "2") ?? 2
            guard let kind = winscpKind(proto, ftps: Int(section.values["Ftps"] ?? "0") ?? 0) else {
                result.skipped.append("\(name) (\(proto == 6 ? "WebDAV" : proto == 7 ? "S3" : "unsupported"))")
                continue
            }
            let key = (section.values["PublicKeyFile"] ?? "").removingPercentEncoding ?? ""
            if let p = make(name: name, group: group.isEmpty ? "WinSCP" : group, host: section.values["HostName"] ?? "",
                            port: Int(section.values["PortNumber"] ?? "") ?? kind.defaultPort, user: section.values["UserName"] ?? "",
                            keyPath: key.hasPrefix("/") || key.hasPrefix("~") ? key : "", kind: kind) {
                result.sessions.append(p)
            }
        }
        return result
    }

    /// WinSCP FSProtocol: 0 SCP, 1 SFTP→SCP, 2 SFTP, 5 FTP (Ftps: 0 none, 1 implicit, 2/3 explicit).
    private static func winscpKind(_ proto: Int, ftps: Int) -> SessionKind? {
        switch proto {
        case 0, 1, 2: return .sftp
        case 5: return ftps == 0 ? .ftp : .ftps
        default: return nil
        }
    }

    // MARK: FileZilla (sitemanager.xml / export)

    static func filezilla(_ data: Data) -> ImportResult {
        let delegate = FileZillaParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        var result = ImportResult()
        for s in delegate.servers {
            let proto = Int(s["Protocol"] ?? "0") ?? 0
            let name = s["Name"] ?? s["Host"] ?? "?"
            // 0 FTP (TLS if available), 1 SFTP, 3 FTPS implicit, 4 FTPES explicit, 6 plain FTP
            let kind: SessionKind
            switch proto {
            case 1: kind = .sftp
            case 3, 4: kind = .ftps
            case 0, 6: kind = .ftp
            default:
                result.skipped.append("\(name) (protocol \(proto))")
                continue
            }
            let key = s["Keyfile"] ?? ""
            if let p = make(name: name, group: s["_folder"] ?? "FileZilla", host: s["Host"] ?? "",
                            port: Int(s["Port"] ?? "") ?? kind.defaultPort, user: s["User"] ?? "",
                            keyPath: key.hasPrefix("/") ? key : "", kind: kind) {
                result.sessions.append(p)
            }
        }
        return result
    }

    private final class FileZillaParser: NSObject, XMLParserDelegate {
        var servers: [[String: String]] = []
        private var stack: [String] = []
        private var folders: [String] = []
        private var folderNamePending = false
        private var current: [String: String]?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if folderNamePending { folders.append(text.trimmingCharacters(in: .whitespacesAndNewlines)); folderNamePending = false }
            stack.append(name)
            text = ""
            if name == "Folder" { folderNamePending = true }
            if name == "Server" {
                current = [:]
                if !folders.isEmpty { current?["_folder"] = folders.filter { !$0.isEmpty }.joined(separator: "/") }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "Folder" {
                if folderNamePending { folderNamePending = false } else if !folders.isEmpty { folders.removeLast() }
            } else if name == "Server", let c = current {
                servers.append(c)
                current = nil
            } else if current != nil, stack.count >= 2, stack[stack.count - 2] == "Server" {
                current?[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            stack.removeLast()
            text = ""
        }
    }

    // MARK: WinBox (Addresses.cdb) — best effort

    /// The file is a sequence of records with length-prefixed key/value strings. We scan for the
    /// known keys and read the length-prefixed value that follows each one.
    static func winbox(_ data: Data) -> ImportResult {
        let bytes = [UInt8](data)
        var records: [[String: String]] = []
        var current: [String: String] = [:]
        let keys = ["host", "login", "group", "note", "type"]

        func printable(_ b: UInt8) -> Bool { b >= 0x20 && b < 0x7F }

        var i = 0
        while i < bytes.count {
            var matched = false
            for key in keys {
                let k = Array(key.utf8)
                guard i + k.count < bytes.count, Array(bytes[i..<(i + k.count)]) == k,
                      i == 0 || !printable(bytes[i - 1]) else { continue }
                // Value: within the next 4 bytes, a length byte followed by that many printable bytes.
                var j = i + k.count
                var value: String?
                for skip in 0..<4 where j + skip < bytes.count {
                    let len = Int(bytes[j + skip])
                    let start = j + skip + 1
                    if len == 0, skip > 0 { value = ""; j = start; break } // empty value
                    guard len > 0, start + len <= bytes.count else { continue }
                    let slice = bytes[start..<(start + len)]
                    if slice.allSatisfy(printable) {
                        value = String(decoding: slice, as: UTF8.self)
                        j = start + len
                        break
                    }
                }
                if let value {
                    // A key we've already seen means the next record has started.
                    if current[key] != nil {
                        if current["host"] != nil { records.append(current) }
                        current = [:]
                    }
                    current[key] = value
                    i = j
                    matched = true
                }
                break
            }
            if !matched { i += 1 }
        }
        if current["host"] != nil { records.append(current) }

        var result = ImportResult()
        for r in records {
            var host = r["host"] ?? ""
            // WinBox addresses may carry the WinBox port (8291); SSH uses 22.
            if let colon = host.lastIndex(of: ":"), !host.contains("::") { host = String(host[..<colon]) }
            let label = (r["note"]?.isEmpty == false ? r["note"]! : host)
            if let p = make(name: label, group: r["group"]?.isEmpty == false ? r["group"]! : "WinBox",
                            host: host, port: 22, user: r["login"] ?? "admin") {
                result.sessions.append(p)
            }
        }
        return result
    }

    // MARK: CSV (Termius, spreadsheets)

    static func csv(_ text: String) -> ImportResult {
        var rows = parseCSV(text)
        guard !rows.isEmpty else { return ImportResult() }
        let header = rows.removeFirst().map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func col(_ names: [String]) -> Int? {
            for n in names { if let i = header.firstIndex(of: n) { return i } }
            for n in names { if let i = header.firstIndex(where: { $0.contains(n) }) { return i } }
            return nil
        }
        let cHost = col(["hostname", "host", "address", "ip"])
        let cName = col(["label", "name", "alias", "title"])
        let cGroup = col(["group", "folder", "tags"])
        let cPort = col(["port"])
        let cUser = col(["username", "user", "login"])
        var result = ImportResult()
        for row in rows {
            func v(_ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            if let p = make(name: v(cName), group: v(cGroup), host: v(cHost), port: Int(v(cPort)) ?? 22, user: v(cUser)) {
                result.sessions.append(p)
            }
        }
        return result
    }

    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let delimiter: Character = (text.split(separator: "\n").first?.filter { $0 == ";" }.count ?? 0) >
            (text.split(separator: "\n").first?.filter { $0 == "," }.count ?? 0) ? ";" : ","
        var it = Array(text).makeIterator()
        var pending: Character?
        while let ch = pending ?? it.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = it.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else { inQuotes = false }
                } else { field.append(ch) }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == delimiter {
                row.append(field); field = ""
            } else if ch == "\n" || ch == "\r\n" || ch == "\r" {
                row.append(field); field = ""
                if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(ch)
            }
        }
        row.append(field)
        if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
        return rows
    }

    // MARK: Apple Passwords app (iCloud Keychain) CSV

    /// Columns: Title, URL, Username, Password, Notes, OTPAuth. Only ssh/sftp/ftp/ftps URLs become sessions.
    static func applePasswords(_ text: String) -> ImportResult {
        var rows = parseCSV(text)
        guard !rows.isEmpty else { return ImportResult() }
        let header = rows.removeFirst().map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func col(_ n: String) -> Int? { header.firstIndex(of: n) }
        let cTitle = col("title"), cURL = col("url"), cUser = col("username"), cPass = col("password"), cNotes = col("notes")
        var result = ImportResult()
        var websites = 0
        for row in rows {
            func v(_ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            guard let url = URLComponents(string: v(cURL).trimmingCharacters(in: .whitespaces)),
                  let scheme = url.scheme?.lowercased(), let kind = SessionKind(rawValue: scheme) else {
                websites += 1
                continue
            }
            guard var p = make(name: v(cTitle), group: "Passwords app", host: url.host ?? "", port: url.port ?? kind.defaultPort,
                               user: v(cUser).isEmpty ? (url.user ?? "") : v(cUser), kind: kind) else { continue }
            p.notes = v(cNotes)
            if !url.path.isEmpty, url.path != "/" { p.initialRemotePath = url.path }
            result.sessions.append(p)
            if !v(cPass).isEmpty { result.secrets[p.id] = v(cPass) }
        }
        if websites > 0 { result.skipped.append("\(websites) website logins") }
        return result
    }

    // MARK: OpenSSH config

    static func sshConfig(_ text: String) -> ImportResult {
        var result = ImportResult()
        var aliases: [String] = []
        var opts: [String: String] = [:]
        let home = NSHomeDirectory()
        let defaultKey = ["id_ed25519", "id_rsa"].map { "\(home)/.ssh/\($0)" }
            .first { FileManager.default.fileExists(atPath: $0) }

        func flush() {
            for alias in aliases where !alias.contains("*") && !alias.contains("?") && !alias.hasPrefix("!") {
                let key = (opts["identityfile"] ?? defaultKey ?? "").replacingOccurrences(of: "~", with: home)
                if let p = make(name: alias, group: "SSH config", host: opts["hostname"] ?? alias,
                                port: Int(opts["port"] ?? "") ?? 22, user: opts["user"] ?? NSUserName(), keyPath: key) {
                    result.sessions.append(p)
                }
            }
            aliases = []
            opts = [:]
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" })
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \t=\""))
            if key == "host" {
                flush()
                aliases = value.split(separator: " ").map(String.init)
            } else if key == "match" {
                flush()
            } else if !aliases.isEmpty, opts[key] == nil {
                opts[key] = value
            }
        }
        flush()
        return result
    }

    // MARK: JSON (MacTerm+ export, or a generic list)

    static func json(_ data: Data) throws -> ImportResult {
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        if let export = try? isoDecoder.decode(SessionExport.self, from: data) {
            return ImportResult(sessions: export.sessions)
        }
        if let list = try? JSONDecoder().decode([SessionProfile].self, from: data), list.contains(where: { !$0.host.isEmpty }) {
            return ImportResult(sessions: list)
        }
        guard let any = try? JSONSerialization.jsonObject(with: data) else { throw ImportError.unknownFormat }
        let items = (any as? [[String: Any]]) ?? ((any as? [String: Any])?.values.compactMap { $0 as? [[String: Any]] }.first ?? [])
        var result = ImportResult()
        for d in items {
            func s(_ keys: [String]) -> String {
                for k in keys { if let v = d[k] { return "\(v)" } }
                return ""
            }
            if let p = make(name: s(["label", "name", "alias"]), group: s(["group", "folder"]),
                            host: s(["hostname", "host", "address"]), port: Int(s(["port"])) ?? 22,
                            user: s(["username", "user", "login"])) {
                result.sessions.append(p)
            }
        }
        return result
    }
}

// MARK: - Export

struct SessionExport: Codable {
    var app = "MacTerm+"
    var version = 1
    var exported = Date()
    var sessions: [SessionProfile]
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case json, sshConfig, csv, applePasswords
    var id: String { rawValue }
    var title: String {
        switch self {
        case .json: return "MacTerm+ (.json) — full, re-importable"
        case .sshConfig: return "OpenSSH config — for ssh, Termius, VS Code"
        case .csv: return "CSV — spreadsheets, Termius"
        case .applePasswords: return "Passwords app (iCloud Keychain) — includes passwords"
        }
    }
    var fileName: String {
        switch self {
        case .json: return "MacTermPlus-sessions.json"
        case .sshConfig: return "macterm-plus.ssh-config"
        case .csv: return "MacTermPlus-sessions.csv"
        case .applePasswords: return "MacTermPlus-for-Passwords-app.csv"
        }
    }
}

enum SessionExporter {
    static func export(_ sessions: [SessionProfile], as format: ExportFormat) throws -> Data {
        switch format {
        case .json:
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            return try enc.encode(SessionExport(sessions: sessions))
        case .sshConfig:
            var out = "# Exported from MacTerm+ on \(Date().formatted(date: .abbreviated, time: .shortened))\n"
            var used = Set<String>()
            for p in sessions {
                var alias = p.displayName.replacingOccurrences(of: " ", with: "-")
                while used.contains(alias) { alias += "-2" }
                used.insert(alias)
                out += "\nHost \(alias)\n    HostName \(p.host)\n"
                if !p.username.isEmpty { out += "    User \(p.username)\n" }
                if p.port != 22 { out += "    Port \(p.port)\n" }
                if p.auth == .privateKey, !p.keyPath.isEmpty { out += "    IdentityFile \(p.keyPath)\n" }
            }
            return Data(out.utf8)
        case .csv:
            func q(_ s: String) -> String { s.contains(where: { ",\"\n".contains($0) }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s }
            var out = "Label,Group,Hostname,Port,Username,Auth,KeyFile\n"
            for p in sessions {
                out += [p.displayName, p.group, p.host, String(p.port), p.username, p.auth.rawValue, p.keyPath].map(q).joined(separator: ",") + "\n"
            }
            return Data(out.utf8)
        case .applePasswords:
            // Format accepted by Passwords → File → Import Passwords.
            func q(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            var out = "Title,URL,Username,Password,Notes,OTPAuth\n"
            for p in sessions {
                let url = "\(p.kind.rawValue)://\(p.host)\(p.port == p.kind.defaultPort ? "" : ":\(p.port)")"
                let secret = p.auth == .password ? (Keychain.read(account: p.keychainAccount) ?? "") : ""
                let notes = ([p.group.isEmpty ? nil : "Folder: \(p.group)", p.notes.isEmpty ? nil : p.notes,
                              p.auth == .privateKey ? "Key: \(p.keyPath)" : nil].compactMap { $0 }).joined(separator: " — ")
                out += [p.displayName, url, p.username, secret, notes, ""].map(q).joined(separator: ",") + "\n"
            }
            return Data(out.utf8)
        }
    }
}
