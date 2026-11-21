import AppKit
import Foundation

/// A set of sessions found on this Mac, from one app in one place.
struct DiscoveredSource: Identifiable {
    var id: String { url.path + "|" + app }
    let app: String
    let icon: String
    let colorName: String
    let location: String
    let url: URL
    let result: ImportResult
    /// When set, the app was found but its sessions can't be read automatically; this explains what to do.
    var note: String?

    var count: Int { result.sessions.count }
}

/// Looks for SSH/SFTP clients installed on this Mac — natively, or Windows apps running in
/// Windows compatibility bottles — and reads their saved sessions. Read-only: nothing is changed.
enum InstalledClientScanner {
    static func scan() -> [DiscoveredSource] {
        var found: [DiscoveredSource] = []
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())

        func add(_ app: String, _ icon: String, _ color: String, _ location: String, _ url: URL, _ result: ImportResult) {
            guard !result.sessions.isEmpty || !result.skipped.isEmpty else { return }
            found.append(DiscoveredSource(app: app, icon: icon, colorName: color, location: location, url: url, result: result))
        }
        func text(_ url: URL) -> String? { SessionImporter.decodeText(try? Data(contentsOf: url)) }

        // MARK: Native macOS

        let sshConfig = home.appendingPathComponent(".ssh/config")
        if let t = text(sshConfig) {
            add("OpenSSH", "terminal.fill", "gray", "~/.ssh/config", sshConfig, SessionImporter.sshConfig(t))
        }
        let sessionsDir = home.appendingPathComponent(".putty/sessions")
        if let files = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) {
            var r = ImportResult(detected: .registry)
            for f in files { if let t = text(f), let p = SessionImporter.unixSessionFile(name: f.lastPathComponent, text: t) { r.sessions.append(p) } }
            add("Saved SSH sessions", "desktopcomputer", "blue", "~/.putty/sessions", sessionsDir, r)
        }
        for path in [".config/filezilla/sitemanager.xml", "Library/Application Support/FileZilla/sitemanager.xml"] {
            let url = home.appendingPathComponent(path)
            if let data = try? Data(contentsOf: url) {
                add("FTP/SFTP site list", "externaldrive.connected.to.line.below.fill", "red", "~/" + path, url, SessionImporter.siteManager(data))
                break
            }
        }
        for dir in ["Library/Group Containers/G69SCX94XU.duck/Library/Application Support/duck/Bookmarks",
                    "Library/Application Support/Cyberduck/Bookmarks"] {
            let url = home.appendingPathComponent(dir)
            if fm.fileExists(atPath: url.path) {
                add("File transfer bookmarks", "externaldrive.badge.icloud", "yellow", "~/" + dir, url, bookmarkPlists(url))
                break
            }
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.csvFile-dmg.mac") != nil
            || fm.fileExists(atPath: "/Applications/Termius.app") {
            found.append(DiscoveredSource(
                app: "Encrypted host vault", icon: "tablecells.fill", colorName: "purple", location: "/Applications/Termius.app",
                url: URL(fileURLWithPath: "/Applications/Termius.app"), result: ImportResult(),
                note: "This app keeps its hosts in an encrypted vault that other apps can’t read. Export them from the app to a CSV or SSH config file, then use “Import from a file”."))
        }

        // MARK: macOS Keychain (server logins saved by Finder and other apps)

        let entries = Keychain.serverEntries()
        if !entries.isEmpty {
            var r = ImportResult()
            for e in entries {
                var p = SessionProfile(name: e.label == e.server ? "" : e.label, group: "Keychain", host: e.server,
                                       port: e.port, username: e.account)
                p.kind = e.kind
                r.sessions.append(p)
                r.keychainEntries[p.id] = e
            }
            let icloudCount = entries.filter(\.synchronizable).count
            found.append(DiscoveredSource(app: "macOS Keychain", icon: "key.fill", colorName: "gray",
                                          location: "Servers saved by other apps\(icloudCount > 0 ? " · \(icloudCount) in iCloud Keychain" : "")",
                                          url: URL(fileURLWithPath: "/"), result: r))
        }
        if let data = Keychain.readSessionList(),
           let list = try? JSONDecoder().decode([SessionProfile].self, from: data), !list.isEmpty {
            found.append(DiscoveredSource(app: "iCloud Keychain", icon: "key.icloud.fill", colorName: "blue",
                                          location: "MacTerm+ session list saved from another Mac",
                                          url: URL(fileURLWithPath: "/"), result: ImportResult(sessions: list)))
        }

        // MARK: Windows apps in compatibility bottles

        for prefix in windowsPrefixes() {
            scanWindowsPrefix(prefix.url, label: prefix.label, into: &found)
        }
        return found
    }

    struct Prefix { let url: URL; let label: String }

    static func windowsPrefixes() -> [Prefix] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var out: [Prefix] = []
        let bottleRoots: [(String, String)] = [
            ("\(home)/Library/Application Support/CrossOver/Bottles", "Windows"),
            ("\(home)/Library/Containers/com.isaacmarovitz.Whisky/Bottles", "Windows"),
        ]
        for (root, product) in bottleRoots {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where !name.hasPrefix(".") {
                let url = URL(fileURLWithPath: root).appendingPathComponent(name)
                if fm.fileExists(atPath: url.appendingPathComponent("drive_c").path) {
                    out.append(Prefix(url: url, label: "\(product) bottle “\(name)”"))
                }
            }
        }
        let wine = URL(fileURLWithPath: "\(home)/.wine")
        if fm.fileExists(atPath: wine.appendingPathComponent("drive_c").path) {
            out.append(Prefix(url: wine, label: "Windows prefix (~/.wine)"))
        }
        return out
    }

    private static func scanWindowsPrefix(_ prefix: URL, label: String, into found: inout [DiscoveredSource]) {
        let fm = FileManager.default

        // Registry: some Windows SSH/SFTP clients keep sessions in user.reg.
        let reg = prefix.appendingPathComponent("user.reg")
        if let t = SessionImporter.decodeText(try? Data(contentsOf: reg)), t.contains("SimonTatham") || t.contains("Martin Prikryl") {
            let r = SessionImporter.registry(t)
                        let app = "Saved sessions (registry)"
            if !r.sessions.isEmpty || !r.skipped.isEmpty {
                found.append(DiscoveredSource(app: app, icon: "desktopcomputer", colorName: "blue", location: label + " · registry",
                                              url: reg, result: r))
            }
        }

        // Session files anywhere in the usual places (depth-limited, skipping the Windows folder).
        let driveC = prefix.appendingPathComponent("drive_c")
        guard let e = fm.enumerator(at: driveC, includingPropertiesForKeys: [.isDirectoryKey],
                                    options: [.skipsPackageDescendants]) else { return }
        var seen = Set<String>()
        for case let url as URL in e {
            let name = url.lastPathComponent
            let lower = name.lowercased()
            if e.level > 6 { e.skipDescendants(); continue }
            if e.level == 1 && ["windows", "programdata"].contains(lower) { e.skipDescendants(); continue }
            if ["cache", "temp", "tmp", "inetcache", "microsoft", "packages", "node_modules"].contains(lower) { e.skipDescendants(); continue }

            let shown = label + " · " + url.path.replacingOccurrences(of: driveC.path, with: "C:").replacingOccurrences(of: "/", with: "\\")
            guard seen.insert(url.resolvingSymlinksInPath().path).inserted else { continue }
            if lower == "mobaxterm.ini" || lower.hasSuffix(".mxtsessions") {
                if let t = SessionImporter.decodeText(try? Data(contentsOf: url)) {
                    let r = SessionImporter.bookmarksIni(t)
                    if !r.sessions.isEmpty || !r.skipped.isEmpty {
                        found.append(DiscoveredSource(app: "Session bookmarks", icon: "rectangle.stack.fill", colorName: "orange",
                                                      location: shown, url: url, result: r))
                    }
                }
            } else if lower == "winscp.ini" {
                if let t = SessionImporter.decodeText(try? Data(contentsOf: url)) {
                    let r = SessionImporter.sessionsIni(t)
                    if !r.sessions.isEmpty || !r.skipped.isEmpty {
                        found.append(DiscoveredSource(app: "Session list", icon: "arrow.left.arrow.right.square.fill", colorName: "green",
                                                      location: shown, url: url, result: r))
                    }
                }
            } else if lower == "sitemanager.xml", let data = try? Data(contentsOf: url) {
                let r = SessionImporter.siteManager(data)
                if !r.sessions.isEmpty || !r.skipped.isEmpty {
                    found.append(DiscoveredSource(app: "FTP/SFTP site list", icon: "externaldrive.connected.to.line.below.fill", colorName: "red",
                                                  location: shown, url: url, result: r))
                }
            } else if lower == "addresses.cdb", let data = try? Data(contentsOf: url) {
                let r = SessionImporter.addressBook(data)
                if !r.sessions.isEmpty {
                    found.append(DiscoveredSource(app: "Router address book", icon: "network", colorName: "indigo",
                                                  location: shown, url: url, result: r))
                }
            }
        }
    }

    /// File-transfer bookmarks stored as one plist per bookmark (.duck).
    static func bookmarkPlists(_ dir: URL) -> ImportResult {
        var r = ImportResult()
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "duck" {
            guard let data = try? Data(contentsOf: f),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            let proto = (plist["Protocol"] as? String ?? "").lowercased()
            let name = plist["Nickname"] as? String ?? plist["Hostname"] as? String ?? f.deletingPathExtension().lastPathComponent
            let kind: SessionKind
            switch proto {
            case "sftp": kind = .sftp
            case "ftp": kind = .ftp
            case "ftps": kind = .ftps
            default: r.skipped.append("\(name) (\(proto.uppercased()))"); continue
            }
            var p = SessionProfile(name: name, group: "Imported", host: plist["Hostname"] as? String ?? "",
                                   port: Int(plist["Port"] as? String ?? "") ?? kind.defaultPort, username: plist["Username"] as? String ?? "")
            p.kind = kind
            if let path = plist["Path"] as? String { p.initialRemotePath = path }
            if !p.host.isEmpty { r.sessions.append(p) }
        }
        return r
    }
}
