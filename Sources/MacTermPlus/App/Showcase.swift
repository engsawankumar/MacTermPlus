import Foundation

/// Demo content for README screenshots (MTP_SHOWCASE=1). Uses made-up servers and files and makes
/// no network connections. Never active in normal use.
enum Showcase {
    /// Only with a separate data folder (MTP_DATA_DIR), so the user's real data is never involved.
    static var isOn: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["MTP_SHOWCASE"] != nil && env["MTP_DATA_DIR"] != nil
    }

    /// What the demo terminal shows: a short, realistic admin session (ANSI colors).
    static func terminalText() -> String {
        let g = "\u{1b}[1;32m", b = "\u{1b}[1;34m", c = "\u{1b}[36m", y = "\u{1b}[33m", r = "\u{1b}[0m", d = "\u{1b}[90m", m = "\u{1b}[35m"
        let prompt = "\(g)deploy@web-01\(r):\(b)~/app\(r)$ "
        return [
            "Welcome to Ubuntu 24.04.1 LTS (GNU/Linux 6.8.0-45-generic x86_64)",
            "",
            "  System load:  0.18               Processes:             142",
            "  Usage of /:   41.6% of 78.17GB   Users logged in:       1",
            "  Memory usage: 37%                IPv4 address for eth0: 10.0.1.21",
            "",
            "\(prompt)git pull --ff-only",
            "Updating 3f2c1ab..9d4e7f0",
            "Fast-forward",
            " src/server.js        | 12 \(g)++++++++\(r)\(y)----\(r)",
            " public/index.html    |  4 \(g)++\(r)\(y)--\(r)",
            " 2 files changed, 10 insertions(+), 6 deletions(-)",
            "\(prompt)docker compose ps",
            "\(d)NAME          IMAGE              STATUS          PORTS\(r)",
            "app-web-1     node:20-alpine     \(g)Up 3 days\(r)       0.0.0.0:3000->3000/tcp",
            "app-db-1      postgres:16        \(g)Up 3 days\(r)       5432/tcp",
            "app-cache-1   redis:7            \(g)Up 3 days\(r)       6379/tcp",
            "\(prompt)systemctl status nginx --no-pager | head -3",
            "\(g)●\(r) nginx.service - A high performance web server and a reverse proxy server",
            "     Loaded: loaded (/lib/systemd/system/nginx.service; \(g)enabled\(r))",
            "     Active: \(g)active (running)\(r) since Mon 2026-11-16 09:12:44 UTC; 5 days ago",
            "\(prompt)ls -la",
            "\(d)total 48\(r)",
            "drwxr-xr-x  6 deploy deploy 4096 Nov 21 10:02 \(b).\(r)",
            "-rw-r--r--  1 deploy deploy  312 Nov 21 09:58 \(y).env\(r)",
            "-rw-r--r--  1 deploy deploy  861 Nov 20 17:31 docker-compose.yml",
            "drwxr-xr-x  2 deploy deploy 4096 Nov 21 10:02 \(b)logs\(r)",
            "-rw-r--r--  1 deploy deploy 1530 Nov 19 12:04 package.json",
            "drwxr-xr-x  8 deploy deploy 4096 Nov 21 10:02 \(b)public\(r)",
            "-rwxr-xr-x  1 deploy deploy  402 Nov 18 08:45 \(g)deploy.sh\(r)",
            "drwxr-xr-x  5 deploy deploy 4096 Nov 21 10:02 \(b)src\(r)",
            "\(prompt)\(c)./deploy.sh\(r) \(m)--production\(r)",
            "\(g)✔\(r) Build finished in 14.2s",
            "\(g)✔\(r) Restarted app-web-1",
            "\(prompt)",
        ].joined(separator: "\r\n")
    }

    static func sessions() -> [SessionProfile] {
        func p(_ name: String, _ group: String, _ host: String, _ user: String, _ color: SessionColor, _ os: String,
               kind: SessionKind = .ssh, key: Bool = true) -> SessionProfile {
            var s = SessionProfile(name: name, group: group, host: host, username: user)
            s.color = color; s.osID = os; s.kind = kind
            if key { s.auth = .privateKey; s.keyPath = "~/.ssh/id_ed25519" }
            if kind.isFTP { s.port = 21; s.auth = .password }
            return s
        }
        return [
            p("web-01", "Production", "web-01.example.com", "deploy", .red, "ubuntu"),
            p("web-02", "Production", "web-02.example.com", "deploy", .red, "ubuntu"),
            p("db-01", "Production", "db-01.example.com", "admin", .orange, "debian"),
            p("api-staging", "Staging", "staging.example.com", "deploy", .yellow, "rocky"),
            p("ci-runner", "Staging", "ci.example.com", "runner", .blue, "fedora"),
            p("Raspberry Pi", "Home Lab", "pi.local", "pi", .pink, "raspbian"),
            p("NAS", "Home Lab", "nas.local", "admin", .indigo, "truenas"),
            p("Router", "Home Lab", "192.168.1.1", "admin", .gray, "openwrt", key: false),
            p("Media files", "Home Lab", "files.example.com", "media", .teal, "", kind: .ftps, key: false),
        ]
    }
}

/// Made-up server files for the showcase.
final class ShowcaseFileSystem: RemoteFileSystem, @unchecked Sendable {
    private func item(_ name: String, _ dir: String, folder: Bool = false, size: UInt64 = 0, perms: String? = nil, daysAgo: Double = 1) -> FileItem {
        var i = FileItem(name: name, path: RemotePath.join(dir, name), isDirectory: folder, isSymlink: false,
                         size: folder ? nil : size, modified: Date().addingTimeInterval(-daysAgo * 86400),
                         permissions: perms ?? (folder ? "drwxr-xr-x" : "-rw-r--r--"))
        i.owner = "deploy"; i.group = "deploy"
        return i
    }

    func home() async throws -> String { "/home/deploy/app" }

    func list(_ path: String) async throws -> [FileItem] {
        [
            item("logs", path, folder: true, daysAgo: 0.1),
            item("public", path, folder: true, daysAgo: 0.2),
            item("src", path, folder: true, daysAgo: 0.2),
            item("node_modules", path, folder: true, daysAgo: 3),
            item(".env", path, size: 312, perms: "-rw-------", daysAgo: 0.3),
            item("deploy.sh", path, size: 402, perms: "-rwxr-xr-x", daysAgo: 3),
            item("docker-compose.yml", path, size: 861, daysAgo: 1),
            item("nginx.conf", path, size: 2_214, daysAgo: 6),
            item("package.json", path, size: 1_530, daysAgo: 2),
            item("README.md", path, size: 4_096, daysAgo: 9),
            item("backup-2026-11-20.tar.gz", path, size: 48_234_112, daysAgo: 1),
            item("schema.sql", path, size: 18_820, daysAgo: 4),
            item("logo.png", path, size: 52_440, daysAgo: 12),
        ]
    }

    func download(_ remotePath: String, to local: URL, progress: @escaping @Sendable (UInt64) -> Void) async throws {}
    func upload(_ local: URL, to remotePath: String, progress: @escaping @Sendable (UInt64) -> Void) async throws {}
    func makeDirectory(_ path: String) async throws {}
    func removeFile(_ path: String) async throws {}
    func removeDirectory(_ path: String) async throws {}
    func rename(_ from: String, to: String) async throws {}
    func isDirectory(_ path: String) async -> Bool { true }
    func setPermissions(_ path: String, mode: UInt32) async throws {}
    func close() {}
}
