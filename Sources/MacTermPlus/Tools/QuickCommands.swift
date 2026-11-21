import Foundation
import SwiftUI

/// A ready-made or user-made command, filed in a folder, sent to the current terminal with one click.
struct QuickCommand: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var command: String
    var folder: String
    var starred = false
    var pressEnter = true
    /// Ask before sending (for commands that stop or kill things).
    var confirm = false
    /// Set for commands that ship with MacTerm+, so new built-ins can be added later without bringing back deleted ones.
    var builtinID: String?
    var updatedAt = Date()

    init(name: String, command: String, folder: String, starred: Bool = false, pressEnter: Bool = true,
         confirm: Bool = false, builtinID: String? = nil) {
        self.name = name; self.command = command; self.folder = folder; self.starred = starred
        self.pressEnter = pressEnter; self.confirm = confirm; self.builtinID = builtinID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        folder = try c.decodeIfPresent(String.self, forKey: .folder) ?? QuickFolders.common
        starred = try c.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        pressEnter = try c.decodeIfPresent(Bool.self, forKey: .pressEnter) ?? true
        confirm = try c.decodeIfPresent(Bool.self, forKey: .confirm) ?? false
        builtinID = try c.decodeIfPresent(String.self, forKey: .builtinID)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

/// Folder names, icons and colours.
enum QuickFolders {
    static let common = "Common"
    static let builtInOrder = [common, "System & Logs", "Apache", "LiteSpeed", "Nginx", "MySQL / MariaDB", "PHP",
                               "Docker", "Firewall & Network", "Updates"]

    static func icon(_ folder: String) -> String {
        switch folder {
        case common: return "terminal.fill"
        case "System & Logs": return "doc.text.magnifyingglass"
        case "Apache": return "leaf.fill"
        case "LiteSpeed": return "bolt.fill"
        case "Nginx": return "n.square.fill"
        case "MySQL / MariaDB": return "cylinder.split.1x2.fill"
        case "PHP": return "chevron.left.forwardslash.chevron.right"
        case "Docker": return "shippingbox.fill"
        case "Firewall & Network": return "shield.lefthalf.filled"
        case "Updates": return "arrow.down.circle.fill"
        default: return "folder.fill"
        }
    }

    static func color(_ folder: String) -> Color {
        switch folder {
        case common: return .gray
        case "System & Logs": return .brown
        case "Apache": return .red
        case "LiteSpeed": return .orange
        case "Nginx": return .green
        case "MySQL / MariaDB": return .teal
        case "PHP": return .indigo
        case "Docker": return .blue
        case "Firewall & Network": return .pink
        case "Updates": return .purple
        default: return .yellow
        }
    }
}

@MainActor
final class QuickCommandStore: ObservableObject {
    static let shared = QuickCommandStore()
    static let changed = Notification.Name("MacTermPlus.quickCommandsChanged")

    @Published private(set) var commands: [QuickCommand] = []
    /// Folder order (empty folders are kept too).
    @Published private(set) var folders: [String] = []
    private var knownBuiltins: Set<String> = []

    private struct File: Codable {
        var commands: [QuickCommand]
        var folders: [String]
        var knownBuiltins: [String]
    }

    private var url: URL { AppPaths.supportDirectory.appendingPathComponent("quickcommands.json") }

    private init() {
        if let data = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(File.self, from: data) {
            commands = f.commands
            folders = f.folders
            knownBuiltins = Set(f.knownBuiltins)
        }
        if addMissingBuiltins(includeKnown: false) > 0 || !FileManager.default.fileExists(atPath: url.path) {
            save(notify: false)
        }
    }

    // MARK: Queries

    var starred: [QuickCommand] { commands.filter(\.starred) }

    func commands(in folder: String) -> [QuickCommand] { commands.filter { $0.folder == folder } }

    func search(_ text: String) -> [QuickCommand] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return commands }
        return commands.filter { c in
            let hay = (c.name + " " + c.command + " " + c.folder).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    var lastChange: Date { commands.map(\.updatedAt).max() ?? .distantPast }

    // MARK: Changes

    func upsert(_ c: QuickCommand) {
        var c = c
        c.updatedAt = Date()
        c.folder = c.folder.trimmingCharacters(in: .whitespaces).isEmpty ? QuickFolders.common : c.folder.trimmingCharacters(in: .whitespaces)
        if !folders.contains(c.folder) { folders.append(c.folder) }
        if let i = commands.firstIndex(where: { $0.id == c.id }) { commands[i] = c } else { commands.append(c) }
        save()
    }

    func toggleStar(_ c: QuickCommand) {
        guard var x = commands.first(where: { $0.id == c.id }) else { return }
        x.starred.toggle()
        upsert(x)
    }

    func move(_ c: QuickCommand, to folder: String) {
        guard var x = commands.first(where: { $0.id == c.id }) else { return }
        x.folder = folder
        upsert(x)
    }

    func duplicate(_ c: QuickCommand) {
        var x = c
        x.id = UUID()
        x.builtinID = nil
        x.name += " copy"
        upsert(x)
    }

    func delete(_ c: QuickCommand) {
        commands.removeAll { $0.id == c.id }
        save()
    }

    func addFolder(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !folders.contains(n) else { return }
        folders.append(n)
        save()
    }

    func renameFolder(_ old: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != old else { return }
        for i in commands.indices where commands[i].folder == old {
            commands[i].folder = n
            commands[i].updatedAt = Date()
        }
        if let i = folders.firstIndex(of: old) {
            if folders.contains(n) { folders.remove(at: i) } else { folders[i] = n }
        }
        save()
    }

    /// Deletes a folder and the commands in it.
    func deleteFolder(_ folder: String) {
        commands.removeAll { $0.folder == folder }
        folders.removeAll { $0 == folder }
        save()
    }

    /// Brings back built-in commands that were deleted. Returns how many were added.
    @discardableResult
    func restoreBuiltins() -> Int {
        let n = addMissingBuiltins(includeKnown: true)
        save()
        return n
    }

    /// Replaces everything with what another Mac synced.
    func replaceAll(commands list: [QuickCommand], folders f: [String]) {
        commands = list
        folders = f
        for c in list where !folders.contains(c.folder) { folders.append(c.folder) }
        for c in list { if let b = c.builtinID { knownBuiltins.insert(b) } }
        save(notify: false)
    }

    private func addMissingBuiltins(includeKnown: Bool) -> Int {
        let present = Set(commands.compactMap(\.builtinID))
        var added = 0
        for b in Self.builtins where !present.contains(b.builtinID!) && (includeKnown || !knownBuiltins.contains(b.builtinID!)) {
            commands.append(b)
            added += 1
        }
        knownBuiltins.formUnion(Self.builtins.compactMap(\.builtinID))
        for f in QuickFolders.builtInOrder where !folders.contains(f) && commands.contains(where: { $0.folder == f }) {
            // Keep built-in folders in their natural order.
            let pos = folders.firstIndex { QuickFolders.builtInOrder.firstIndex(of: $0) ?? .max > QuickFolders.builtInOrder.firstIndex(of: f)! } ?? folders.count
            folders.insert(f, at: pos)
        }
        for c in commands where !folders.contains(c.folder) { folders.append(c.folder) }
        return added
    }

    private func save(notify: Bool = true) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let f = File(commands: commands, folders: folders, knownBuiltins: knownBuiltins.sorted())
        try? enc.encode(f).write(to: url, options: .atomic)
        if notify { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }

    // MARK: Built-in commands

    static let builtins: [QuickCommand] = {
        func c(_ id: String, _ folder: String, _ name: String, _ cmd: String, star: Bool = false, confirm: Bool = false) -> QuickCommand {
            QuickCommand(name: name, command: cmd, folder: folder, starred: star, confirm: confirm, builtinID: id)
        }
        let common = QuickFolders.common, sys = "System & Logs", apache = "Apache", ls = "LiteSpeed", nginx = "Nginx"
        let mysql = "MySQL / MariaDB", php = "PHP", docker = "Docker", net = "Firewall & Network", upd = "Updates"
        let mysqlUnit = "for s in mysql mariadb mysqld; do systemctl list-unit-files \"$s.service\" >/dev/null 2>&1 && break; done;"
        return [
            // Common
            c("top", common, "Top (top -c)", "top -c", star: true),
            c("htop", common, "htop", "htop", star: true),
            c("disk", common, "Disk check", "df -h -x tmpfs -x devtmpfs 2>/dev/null || df -h", star: true),
            c("memory", common, "Memory", "free -h", star: true),
            c("ports", common, "Listening ports", "sudo ss -tulpn", star: true),
            c("sysinfo", common, "System info", "uname -a; uptime; (. /etc/os-release 2>/dev/null && echo \"$PRETTY_NAME\")"),
            c("dirsizes", common, "Folder sizes here", "du -sh -- * .[!.]* 2>/dev/null | sort -h | tail -25"),
            c("bigfiles", common, "Biggest files (>100 MB)", "sudo find / -xdev -type f -size +100M -exec ls -lh {} + 2>/dev/null | sort -k5 -h | tail -20"),
            c("inodes", common, "Inode usage", "df -i -x tmpfs -x devtmpfs 2>/dev/null || df -i"),
            c("who", common, "Who is logged in", "w"),
            c("failed", common, "Failed services", "systemctl --failed --no-pager"),
            // System & logs
            c("syslog", sys, "Follow system log", "sudo journalctl -f", star: true),
            c("bootErrors", sys, "Errors since boot", "sudo journalctl -p err -b --no-pager | tail -50"),
            c("authlog", sys, "Login attempts log", "sudo tail -f /var/log/auth.log 2>/dev/null || sudo tail -f /var/log/secure"),
            c("dmesg", sys, "Kernel messages", "sudo dmesg -T | tail -40"),
            c("cron", sys, "My cron jobs", "crontab -l"),
            c("load", sys, "CPU load & uptime", "uptime; nproc"),
            // Apache
            c("apacheRestart", apache, "Restart Apache", "sudo systemctl restart apache2 2>/dev/null || sudo systemctl restart httpd", star: true),
            c("apacheReload", apache, "Reload Apache (graceful)", "sudo apachectl -k graceful"),
            c("apacheStatus", apache, "Apache status", "systemctl status apache2 --no-pager 2>/dev/null || systemctl status httpd --no-pager"),
            c("apacheTest", apache, "Test Apache config", "sudo apachectl configtest"),
            c("apacheVhosts", apache, "List virtual hosts", "sudo apachectl -S"),
            c("apacheErrors", apache, "Follow Apache error log", "sudo tail -f /var/log/apache2/error.log 2>/dev/null || sudo tail -f /var/log/httpd/error_log"),
            // LiteSpeed
            c("lsRestart", ls, "Restart LiteSpeed", "sudo /usr/local/lsws/bin/lswsctrl restart || sudo systemctl restart lsws", star: true),
            c("lsStatus", ls, "LiteSpeed status", "sudo /usr/local/lsws/bin/lswsctrl status"),
            c("lsStop", ls, "Stop LiteSpeed", "sudo /usr/local/lsws/bin/lswsctrl stop", confirm: true),
            c("lsStart", ls, "Start LiteSpeed", "sudo /usr/local/lsws/bin/lswsctrl start"),
            c("lsErrors", ls, "Follow LiteSpeed error log", "sudo tail -f /usr/local/lsws/logs/error.log"),
            c("lsKillPHP", ls, "Kill stuck lsphp processes", "sudo pkill -9 lsphp", confirm: true),
            // Nginx
            c("nginxRestart", nginx, "Restart Nginx", "sudo systemctl restart nginx", star: true),
            c("nginxReload", nginx, "Test & reload Nginx", "sudo nginx -t && sudo systemctl reload nginx"),
            c("nginxTest", nginx, "Test Nginx config", "sudo nginx -t"),
            c("nginxStatus", nginx, "Nginx status", "systemctl status nginx --no-pager"),
            c("nginxErrors", nginx, "Follow Nginx error log", "sudo tail -f /var/log/nginx/error.log"),
            c("nginxAccess", nginx, "Follow Nginx access log", "sudo tail -f /var/log/nginx/access.log"),
            // MySQL / MariaDB
            c("mysqlRestart", mysql, "Restart MySQL / MariaDB", mysqlUnit + " sudo systemctl restart \"$s\"", star: true),
            c("mysqlStatus", mysql, "MySQL status", mysqlUnit + " systemctl status \"$s\" --no-pager"),
            c("mysqlShell", mysql, "Open MySQL shell", "sudo mysql"),
            c("mysqlProcs", mysql, "Running queries", "sudo mysqladmin processlist"),
            c("mysqlSizes", mysql, "Database sizes", "sudo mysql -e \"SELECT table_schema AS db, ROUND(SUM(data_length+index_length)/1024/1024,1) AS size_mb FROM information_schema.tables GROUP BY table_schema ORDER BY size_mb DESC;\""),
            // PHP
            c("phpVersion", php, "PHP version", "php -v"),
            c("phpFpmRestart", php, "Restart PHP-FPM", "for u in $(systemctl list-units --type=service --no-legend 'php*-fpm*' | awk '{print $1}'); do echo \"restarting $u\"; sudo systemctl restart \"$u\"; done"),
            c("phpModules", php, "PHP modules", "php -m"),
            // Docker
            c("dockerPs", docker, "Running containers", "docker ps"),
            c("dockerAll", docker, "All containers", "docker ps -a"),
            c("dockerStats", docker, "Container usage", "docker stats --no-stream"),
            c("dockerDisk", docker, "Docker disk usage", "docker system df"),
            // Firewall & network
            c("ufw", net, "Firewall status (ufw)", "sudo ufw status verbose"),
            c("firewalld", net, "Firewall status (firewalld)", "sudo firewall-cmd --list-all"),
            c("ip", net, "IP addresses", "ip -br addr"),
            c("ping", net, "Internet check (ping)", "ping -c 4 1.1.1.1"),
            c("connections", net, "Connections per IP", "ss -tn state established | awk 'NR>1 {split($4,a,\":\"); print a[1]}' | sort | uniq -c | sort -rn | head -20"),
            // Updates
            c("aptCheck", upd, "Check updates (apt)", "sudo apt update && apt list --upgradable"),
            c("dnfCheck", upd, "Check updates (dnf/yum)", "sudo dnf check-update 2>/dev/null || sudo yum check-update"),
        ]
    }()
}
