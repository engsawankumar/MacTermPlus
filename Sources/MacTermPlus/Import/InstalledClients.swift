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
/// CrossOver, Wine or Whisky — and reads their saved sessions. Read-only: nothing is changed.
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
        let puttyDir = home.appendingPathComponent(".putty/sessions")
        if let files = try? fm.contentsOfDirectory(at: puttyDir, includingPropertiesForKeys: nil) {
            var r = ImportResult(detected: .putty)
            for f in files { if let t = text(f), let p = SessionImporter.puttyUnixSession(name: f.lastPathComponent, text: t) { r.sessions.append(p) } }
            add("PuTTY", "desktopcomputer", "blue", "~/.putty/sessions", puttyDir, r)
        }
        for path in [".config/filezilla/sitemanager.xml", "Library/Application Support/FileZilla/sitemanager.xml"] {
            let url = home.appendingPathComponent(path)
            if let data = try? Data(contentsOf: url) {
                add("FileZilla", "externaldrive.connected.to.line.below.fill", "red", "~/" + path, url, SessionImporter.filezilla(data))
                break
            }
        }
        for dir in ["Library/Group Containers/G69SCX94XU.duck/Library/Application Support/duck/Bookmarks",
                    "Library/Application Support/Cyberduck/Bookmarks"] {
            let url = home.appendingPathComponent(dir)
            if fm.fileExists(atPath: url.path) {
                add("Cyberduck / Mountain Duck", "externaldrive.badge.icloud", "yellow", "~/" + dir, url, cyberduck(url))
                break
            }
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.termius-dmg.mac") != nil
            || fm.fileExists(atPath: "/Applications/Termius.app") {
            found.append(DiscoveredSource(
                app: "Termius", icon: "tablecells.fill", colorName: "purple", location: "/Applications/Termius.app",
                url: URL(fileURLWithPath: "/Applications/Termius.app"), result: ImportResult(),
                note: "Termius keeps hosts in its own encrypted vault. Export them from Termius to a CSV or SSH config file, then use “Import from a file”."))
        }

        // MARK: macOS Keychain (servers saved by Finder, Transmit, Cyberduck, FileZilla…)

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

        // MARK: Windows apps in CrossOver / Wine / Whisky

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
            ("\(home)/Library/Application Support/CrossOver/Bottles", "CrossOver"),
            ("\(home)/Library/Containers/com.isaacmarovitz.Whisky/Bottles", "Whisky"),
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
            out.append(Prefix(url: wine, label: "Wine (~/.wine)"))
        }
        return out
    }

    private static func scanWindowsPrefix(_ prefix: URL, label: String, into found: inout [DiscoveredSource]) {
        let fm = FileManager.default

        // Registry: PuTTY + WinSCP sessions live in user.reg.
        let reg = prefix.appendingPathComponent("user.reg")
        if let t = SessionImporter.decodeText(try? Data(contentsOf: reg)), t.contains("SimonTatham") || t.contains("Martin Prikryl") {
            let r = SessionImporter.registry(t)
            let puttyCount = r.sessions.filter { $0.group == "PuTTY" }.count
            let app = puttyCount == r.sessions.count ? "PuTTY" : (puttyCount == 0 ? "WinSCP" : "PuTTY + WinSCP")
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
                    let r = SessionImporter.mobaxterm(t)
                    if !r.sessions.isEmpty || !r.skipped.isEmpty {
                        found.append(DiscoveredSource(app: "MobaXterm", icon: "rectangle.stack.fill", colorName: "orange",
                                                      location: shown, url: url, result: r))
                    }
                }
            } else if lower == "winscp.ini" {
                if let t = SessionImporter.decodeText(try? Data(contentsOf: url)) {
                    let r = SessionImporter.winscp(t)
                    if !r.sessions.isEmpty || !r.skipped.isEmpty {
                        found.append(DiscoveredSource(app: "WinSCP", icon: "arrow.left.arrow.right.square.fill", colorName: "green",
                                                      location: shown, url: url, result: r))
                    }
                }
            } else if lower == "sitemanager.xml", let data = try? Data(contentsOf: url) {
                let r = SessionImporter.filezilla(data)
                if !r.sessions.isEmpty || !r.skipped.isEmpty {
                    found.append(DiscoveredSource(app: "FileZilla", icon: "externaldrive.connected.to.line.below.fill", colorName: "red",
                                                  location: shown, url: url, result: r))
                }
            } else if lower == "addresses.cdb", let data = try? Data(contentsOf: url) {
                let r = SessionImporter.winbox(data)
                if !r.sessions.isEmpty {
                    found.append(DiscoveredSource(app: "WinBox", icon: "network", colorName: "indigo",
                                                  location: shown, url: url, result: r))
                }
            }
        }
    }

    /// Cyberduck / Mountain Duck bookmarks: one plist per bookmark.
    static func cyberduck(_ dir: URL) -> ImportResult {
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
            var p = SessionProfile(name: name, group: "Cyberduck", host: plist["Hostname"] as? String ?? "",
                                   port: Int(plist["Port"] as? String ?? "") ?? kind.defaultPort, username: plist["Username"] as? String ?? "")
            p.kind = kind
            if let path = plist["Path"] as? String { p.initialRemotePath = path }
            if !p.host.isEmpty { r.sessions.append(p) }
        }
        return r
    }
}
