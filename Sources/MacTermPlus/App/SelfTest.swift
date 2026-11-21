import AppKit
import Citadel
import SwiftTerm
import Foundation
import NIOCore
import NIOSSH

/// Headless connection check, usable without the UI:
///   MacTermPlus --selftest <host> <port> <user> <keyPath | password:SECRET>
/// Exercises the same code paths as the app: key/password auth, PTY shell, SFTP list/upload/download/delete.
enum SelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let h = args.firstIndex(of: "--export-help"), args.count > h + 1 {
            try? HelpContent.markdown().write(toFile: args[h + 1], atomically: true, encoding: .utf8)
            exit(0)
        }
        if let k = args.firstIndex(of: "--sync-once"), args.count > k + 1 {
            // Tests: MTP_DATA_DIR=<device dir> MacTermPlus --sync-once <folder> [add:<name>] [delete:<name>]
            let done = DispatchSemaphore(value: 0)
            Task { @MainActor in
                let store = SessionStore()
                for a in args where a.hasPrefix("add:") {
                    store.upsert(SessionProfile(name: String(a.dropFirst(4)), host: String(a.dropFirst(4)) + ".example", username: "u"))
                }
                for a in args where a.hasPrefix("delete:") {
                    if let p = store.sessions.first(where: { $0.name == String(a.dropFirst(7)) }) { store.delete(p) }
                }
                let m = SyncManager.shared
                m.folderPath = args[k + 1]
                m.attach(store: store)
                m.enabled = true
                await m.syncNow()
                print("SYNC \(m.lastError ?? "ok") | \(m.lastSummary) | sessions=\(store.sessions.map(\.name).sorted().joined(separator: ","))")
                done.signal()
            }
            while done.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            exit(0)
        }
        if let k = args.firstIndex(of: "--tunnel-test"), args.count > k + 6 {
            // Tests: MTP_DATA_DIR=… MacTermPlus --tunnel-test host sshPort user keyPath localPort targetPort
            let done = DispatchSemaphore(value: 0)
            Task { @MainActor in
                let store = SessionStore()
                var p = SessionProfile(name: "tunnel-test", host: args[k + 1], port: Int(args[k + 2]) ?? 22, username: args[k + 3])
                p.auth = .privateKey; p.keyPath = args[k + 4]
                store.upsert(p)
                var t = TunnelConfig()
                t.sessionID = p.id; t.localPort = Int(args[k + 5]) ?? 18080; t.remoteHost = "127.0.0.1"; t.remotePort = Int(args[k + 6]) ?? 8000
                TunnelManager.shared.upsert(t)
                TunnelManager.shared.start(t, store: store)
                for _ in 0..<100 {
                    if case .running = TunnelManager.shared.state(t) { break }
                    if case .failed = TunnelManager.shared.state(t) { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                print("TUNNEL STATE \(TunnelManager.shared.state(t))")
                // Fetch through the tunnel twice (two separate connections).
                for i in 1...2 {
                    let url = URL(string: "http://127.0.0.1:\(t.localPort)/hello.txt")!
                    if let (data, _) = try? await URLSession.shared.data(from: url) {
                        print("FETCH \(i): \(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))")
                    } else { print("FETCH \(i): failed") }
                }
                TunnelManager.shared.stop(t)
                done.signal()
            }
            while done.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            exit(0)
        }
        if args.contains("--icloud-keychain-test") {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.macterm-plus.probe",
                                    kSecAttrAccount as String: "probe", kSecAttrSynchronizable as String: true,
                                    kSecValueData as String: Data("x".utf8)]
            let add = SecItemAdd(q as CFDictionary, nil)
            print("SYNC ADD status=\(add) \(SecCopyErrorMessageString(add, nil) as String? ?? "")")
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.macterm-plus.probe",
                           kSecAttrSynchronizable as String: kSecAttrSynchronizableAny] as CFDictionary)
            let q2: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.macterm-plus.probe",
                                     kSecAttrAccount as String: "probe", kSecUseDataProtectionKeychain as String: true,
                                     kSecValueData as String: Data("x".utf8)]
            let add2 = SecItemAdd(q2 as CFDictionary, nil)
            print("DATA-PROTECTION ADD status=\(add2) \(SecCopyErrorMessageString(add2, nil) as String? ?? "")")
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.macterm-plus.probe",
                           kSecUseDataProtectionKeychain as String: true] as CFDictionary)
            exit(0)
        }
        if args.contains("--distro-test") {
            let cases: [(String, String, String)] = [
                ("ubuntu", "debian", "Ubuntu 22.04.4 LTS"), ("debian", "", "Debian GNU/Linux 12 (bookworm)"),
                ("raspbian", "debian", "Raspbian GNU/Linux 11"), ("debian", "", "Raspberry Pi OS (64-bit)"),
                ("rocky", "rhel centos fedora", "Rocky Linux 9.3"), ("almalinux", "rhel centos fedora", "AlmaLinux 9"),
                ("centos", "rhel fedora", "CentOS Stream 9"), ("opensuse-leap", "suse opensuse", "openSUSE Leap 15.5"),
                ("linuxmint", "ubuntu debian", "Linux Mint 21"), ("pop", "ubuntu debian", "Pop!_OS 22.04"),
                ("amzn", "centos rhel fedora", "Amazon Linux 2023"), ("arch", "", "Arch Linux"),
                ("alpine", "", "Alpine Linux v3.19"), ("darwin", "", "Darwin 27.2.0"), ("myos", "ubuntu", "MyOS 1"),
                ("weird", "", "Something"),
            ]
            for (id, like, pretty) in cases {
                let r = Distro.resolve(id: id, like: like, pretty: pretty)
                print("\(pretty) -> \(r) (\(Distro.named(r)?.name ?? "?"))")
            }
            exit(0)
        }
        if args.contains("--update-test") {
            let done = DispatchSemaphore(value: 0)
            Task { @MainActor in
                let u = Updater.shared
                print("current \(u.currentVersion), repo \(u.repo)")
                await u.check(userInitiated: true)
                print("check → \(u.state) latest=\(u.latest?.version ?? "-")")
                if u.state == .available { await u.downloadAndInstall() }
                print("install → \(u.state)")
                done.signal()
            }
            while done.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            exit(0)
        }
        if args.contains("--keychain-noprompt-check") {
            // Reads the real passwords item but forbids any dialog: succeeds only if macOS would NOT prompt.
            // Prints counts only, never passwords.
            var r: AnyObject?
            let st = SecItemCopyMatching([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.macterm-plus.secrets",
                                          kSecAttrAccount as String: "all", kSecReturnData as String: true,
                                          kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail] as CFDictionary, &r)
            let n = (r as? Data).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }?.count ?? 0
            print(st == errSecSuccess ? "NO PROMPT NEEDED — read \(n) saved passwords silently"
                                      : "WOULD PROMPT (status \(st): \(SecCopyErrorMessageString(st, nil) as String? ?? ""))")
            exit(0)
        }
        if args.contains("--keychain-bundle-test") {
            // Run with MTP_KEYCHAIN_PREFIX=com.macterm-plus-test so real items are never touched.
            let prefix = ProcessInfo.processInfo.environment["MTP_KEYCHAIN_PREFIX"] ?? ""
            guard prefix.hasSuffix("-test") else { print("refusing: set MTP_KEYCHAIN_PREFIX=…-test"); exit(1) }
            func check(_ ok: Bool, _ what: String) { print((ok ? "✓ " : "✗ ") + what); if !ok { exit(1) } }
            func legacyCount() -> Int {
                var r: AnyObject?
                let st = SecItemCopyMatching([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: prefix + ".session",
                                              kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll] as CFDictionary, &r)
                return st == errSecSuccess ? ((r as? [[String: Any]])?.count ?? 0) : 0
            }
            // Old-style items, one per password (what versions up to 1.0.5 created).
            for (a, p) in [("acct-1", "one"), ("acct-2", "twö"), ("sync-passphrase", "phrase")] {
                SecItemAdd([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: prefix + ".session",
                            kSecAttrAccount as String: a, kSecValueData as String: Data(p.utf8)] as CFDictionary, nil)
            }
            Keychain.storage = .keychain
            check(legacyCount() == 3, "3 old per-password items before")
            check(Keychain.read(account: "acct-2") == "twö", "first read returns the right password")
            check(legacyCount() == 0, "old items moved and removed after one read")
            check(Keychain.read(account: "acct-1") == "one" && Keychain.read(account: "sync-passphrase") == "phrase", "all passwords in the single item")
            Keychain.save("new", account: "acct-3"); Keychain.delete(account: "acct-1")
            var r: AnyObject?
            SecItemCopyMatching([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: prefix + ".secrets",
                                 kSecAttrAccount as String: "all", kSecReturnData as String: true] as CFDictionary, &r)
            let stored = (r as? Data).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            check(stored == ["acct-2": "twö", "acct-3": "new", "sync-passphrase": "phrase"], "save/delete persisted in one item: \(stored.keys.sorted())")
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: prefix + ".secrets"] as CFDictionary)
            print("BUNDLETEST PASS")
            exit(0)
        }
        if args.contains("--vault-test") {
            // Tests (use MTP_DATA_DIR): vault create/save/read/lock/unlock/change, and moving secrets to and from the Keychain.
            let v = PasswordVault.shared
            func check(_ ok: Bool, _ what: String) { print((ok ? "✓ " : "✗ ") + what); if !ok { exit(1) } }
            v.destroy()
            do {
                try v.create(master: "correct horse")
                v.save("s3cret-A", account: "acct-A"); v.save("pässwörd-B ✓", account: "acct-B")
                check(v.read(account: "acct-A") == "s3cret-A" && v.read(account: "acct-B") == "pässwörd-B ✓", "save + read")
                let raw = (try? String(contentsOf: AppPaths.supportDirectory.appendingPathComponent("passwords.vault"), encoding: .utf8)) ?? ""
                check(!raw.contains("s3cret") && !raw.contains("pässwörd"), "file contains no plain-text passwords")
                v.lockNow(); check(v.read(account: "acct-A") == nil, "locked vault reveals nothing")
                check((try? v.unlock(master: "wrong one")) == nil, "wrong master password rejected")
                try v.unlock(master: "correct horse"); check(v.read(account: "acct-A") == "s3cret-A", "unlock with correct password")
                try v.changeMaster(from: "correct horse", to: "new battery staple"); v.lockNow()
                check((try? v.unlock(master: "correct horse")) == nil, "old master password no longer works")
                try v.unlock(master: "new battery staple"); check(v.read(account: "acct-B") == "pässwörd-B ✓", "items kept after master change")
                // Keychain ⇄ vault migration with throwaway accounts
                let ids = ["mtp-test-\(UUID().uuidString)", "mtp-test-\(UUID().uuidString)"]
                Keychain.storage = .keychain
                Keychain.save("kc-one", account: ids[0]); Keychain.save("kc-two", account: ids[1])
                let moved = Keychain.moveSecrets(to: .vault, accounts: ids)
                check(moved == 2 && Keychain.storage == .vault && Keychain.read(account: ids[0]) == "kc-one", "Keychain → vault moved \(moved)")
                Keychain.storage = .keychain
                check(Keychain.read(account: ids[0]) == nil, "removed from Keychain after the move")
                Keychain.storage = .vault
                let back = Keychain.moveSecrets(to: .keychain, accounts: ids)
                check(back == 2 && Keychain.read(account: ids[1]) == "kc-two", "vault → Keychain moved \(back)")
                Keychain.storage = .vault
                check(Keychain.read(account: ids[1]) == nil, "removed from vault after the move")
                ids.forEach { Keychain.delete(account: $0) }
                Keychain.storage = .keychain
                v.destroy(); check(!v.exists, "vault erased")
                print("VAULTTEST PASS")
            } catch { print("VAULTTEST FAIL: \(error)"); exit(1) }
            exit(0)
        }
        if args.contains("--scan-test") {
            let t0 = Date()
            for src in InstalledClientScanner.scan() {
                print("FOUND \(src.app) | \(src.location) | sessions=\(src.count) skipped=\(src.result.skipped.count)\(src.note != nil ? " | note" : "")")
            }
            print(String(format: "scan took %.2fs", Date().timeIntervalSince(t0)))
            exit(0)
        }
        if let k = args.firstIndex(of: "--import-test"), args.count > k + 1 {
            do {
                let r = try SessionImporter.importFile(at: URL(fileURLWithPath: args[k + 1]), as: .auto)
                print("DETECTED \(r.detected.rawValue) sessions=\(r.sessions.count) skipped=\(r.skipped.count)")
                for p in r.sessions { print("  [\(p.group)] \(p.displayName) -> \(p.username)@\(p.host):\(p.port) \(p.auth.rawValue) \(p.keyPath)") }
                for s in r.skipped { print("  skipped: \(s)") }
            } catch { print("IMPORT ERROR: \(error.localizedDescription)") }
            exit(0)
        }
        if let f = args.firstIndex(of: "--ftptest"), args.count >= f + 6 {
            // --ftptest host port user password ftp|ftps [insecure]
            let cfg = FTPFileSystem.Config(host: args[f + 1], port: Int(args[f + 2]) ?? 21, username: args[f + 3],
                                           password: args[f + 4], secure: args[f + 5] == "ftps",
                                           acceptInvalidCertificates: args.contains("insecure"), initialPath: "")
            let done = DispatchSemaphore(value: 0)
            var failed = false
            Task { @MainActor in
                do {
                    try await testFileSystem(FTPFileSystem(config: cfg), label: args[f + 5].uppercased(), remoteBase: nil)
                    print("FTPTEST PASS")
                } catch {
                    print("FTPTEST FAIL: \(SSHConnection.describe(error))")
                    failed = true
                }
                done.signal()
            }
            while done.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            exit(failed ? 1 : 0)
        }
        guard let i = args.firstIndex(of: "--selftest"), args.count >= i + 5 else { return }
        let host = args[i + 1], port = Int(args[i + 2]) ?? 22, user = args[i + 3], cred = args[i + 4]

        var profile = SessionProfile(name: "selftest", host: host, port: port, username: user)
        var secret: String?
        if cred.hasPrefix("password:") {
            profile.auth = .password
            secret = String(cred.dropFirst("password:".count))
        } else {
            profile.auth = .privateKey
            profile.keyPath = cred
        }

        let done = DispatchSemaphore(value: 0)
        var failed = false
        Task { @MainActor in
            do {
                try await run(profile: profile, secret: secret)
                print("SELFTEST PASS")
            } catch {
                print("SELFTEST FAIL: \(SSHConnection.describe(error))")
                failed = true
            }
            done.signal()
        }
        while done.wait(timeout: .now() + 0.05) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        exit(failed ? 1 : 0)
    }

    @MainActor
    private static func run(profile: SessionProfile, secret: String?) async throws {
        let conn = SSHConnection(profile: profile, secret: secret)
        let client = try await conn.connectedClient()
        print("✓ connected + authenticated (\(profile.auth.rawValue))")

        // PTY shell round trip
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true, term: "xterm-256color", terminalCharacterWidth: 100, terminalRowHeight: 30,
            terminalPixelWidth: 0, terminalPixelHeight: 0, terminalModes: SSHTerminalModes([:]))
        var output = ""
        try await SSHConnection.ignoringRemoteClose { try await client.withPTY(request) { inbound, outbound in
            try await outbound.write(ByteBuffer(string: "echo MTP_$((40+2))_OK; exit\n"))
            for try await chunk in inbound {
                switch chunk {
                case .stdout(let b), .stderr(let b): output += String(buffer: b)
                }
            }
        } }
        guard output.contains("MTP_42_OK") else { throw TestError("PTY output missing marker:\n\(output)") }
        print("✓ interactive PTY shell")

        try await testFileSystem(SFTPFileSystem(connection: conn), label: "SFTP", remoteBase: "/tmp")
        conn.disconnect()
    }

    /// list → mkdir → upload (folder) → list → download → compare → rename → delete, on any RemoteFileSystem.
    @MainActor
    static func testFileSystem(_ fs: RemoteFileSystem, label: String, remoteBase: String?) async throws {
        let home = try await fs.home()
        let listing = try await fs.list(home)
        print("✓ \(label) home \(home): \(listing.count) entries")

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mtp-selftest-\(UUID().uuidString)")
        let srcDir = tmp.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        var bytes = [UInt8](repeating: 0, count: 300_000) // several chunks
        for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
        try Data(bytes).write(to: srcDir.appendingPathComponent("payload.bin"))
        try Data("hello ftp/sftp\n".utf8).write(to: srcDir.appendingPathComponent("sub/notes with space.txt"))

        let remoteDir = RemotePath.join(remoteBase ?? home, "mtp-selftest-\(UUID().uuidString.prefix(8))")
        try await fs.makeDirectory(remoteDir)
        let up = Transfer(name: "folder", direction: .upload)
        try await TransferQueue.upload(local: srcDir, toRemoteDir: remoteDir, fs: fs, transfer: up)
        try await Task.sleep(for: .milliseconds(200))
        print("✓ \(label) upload folder (\(up.bytesDone) bytes)")

        let remoteFolder = RemotePath.join(remoteDir, "folder")
        let items = try await fs.list(remoteFolder)
        guard let file = items.first(where: { $0.name == "payload.bin" }), items.contains(where: { $0.name == "sub" && $0.isDirectory }) else {
            throw TestError("uploaded items not listed: \(items.map(\.name))")
        }
        print("✓ \(label) list shows file (\(file.size ?? 0) bytes) and sub-folder")

        let back = tmp.appendingPathComponent("back", isDirectory: true)
        try FileManager.default.createDirectory(at: back, withIntermediateDirectories: true)
        let down = Transfer(name: "folder", direction: .download)
        try await TransferQueue.download(remote: FileItem(name: "folder", path: remoteFolder, isDirectory: true, isSymlink: false,
                                                          size: nil, modified: nil, permissions: ""),
                                         toLocalDir: back, fs: fs, transfer: down)
        let roundTrip = try Data(contentsOf: back.appendingPathComponent("folder/payload.bin"))
        let note = try String(contentsOf: back.appendingPathComponent("folder/sub/notes with space.txt"), encoding: .utf8)
        guard roundTrip == Data(bytes), note == "hello ftp/sftp\n" else { throw TestError("downloaded content differs") }
        print("✓ \(label) download folder matches byte-for-byte")

        try await fs.rename(RemotePath.join(remoteFolder, "payload.bin"), to: RemotePath.join(remoteFolder, "renamed.bin"))
        guard try await fs.list(remoteFolder).contains(where: { $0.name == "renamed.bin" }) else { throw TestError("rename failed") }
        print("✓ \(label) rename")

        try await fs.setPermissions(RemotePath.join(remoteFolder, "renamed.bin"), mode: 0o600)
        let perms = try await fs.list(remoteFolder).first { $0.name == "renamed.bin" }?.permissions ?? "?"
        guard perms.hasSuffix("rw-------") else { throw TestError("chmod 600 gave \(perms)") }
        try await fs.setPermissions(RemotePath.join(remoteFolder, "sub"), mode: 0o750)
        let subPerms = try await fs.list(remoteFolder).first { $0.name == "sub" }?.permissions ?? "?"
        guard subPerms.hasSuffix("rwxr-x---") else { throw TestError("chmod 750 gave \(subPerms)") }
        print("✓ \(label) chmod (file \(perms), folder \(subPerms))")

        try await fs.removeRecursively(FileItem(name: "x", path: remoteDir, isDirectory: true, isSymlink: false,
                                                size: nil, modified: nil, permissions: ""))
        guard !(try await fs.list(remoteBase ?? home)).contains(where: { $0.path == remoteDir }) else { throw TestError("delete failed") }
        try? FileManager.default.removeItem(at: tmp)
        print("✓ \(label) recursive delete")
        fs.close()
    }

    struct TestError: LocalizedError {
        let message: String
        init(_ m: String) { message = m }
        var errorDescription: String? { message }
    }
}

/// Debug-only hooks for automated UI checks (no Screen Recording permission needed):
///   MTP_DEMO="host,port,user,keyPath"  opens that session in a tab at launch
///   MTP_SNAPSHOT="/path/out.png"       saves the main window as PNG after a few seconds
///   MTP_MODE="files"                   switches the demo tab to the two-pane Files view
enum DebugHooks {
    @MainActor
    static func run(workspace: Workspace) {
        let env = ProcessInfo.processInfo.environment
        if let demo = env["MTP_DEMO"] {
            let p = demo.split(separator: ",").map(String.init)
            if p.count == 4 {
                var profile = SessionProfile(name: "Demo server", host: p[0], port: Int(p[1]) ?? 22, username: p[2])
                profile.auth = .privateKey
                profile.keyPath = p[3]
                workspace.open(profile, secret: nil)
                if env["MTP_MODE"] == "files", case .ssh(let tab) = workspace.tabs.last { tab.mode = .commander }
            }
        }
        if env["MTP_OPEN"] == "help" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NotificationCenter.default.post(name: .showHelp, object: nil) }
        } else if env["MTP_OPEN"] == "settings" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NotificationCenter.default.post(name: .showSettings, object: nil) }
        } else if env["MTP_OPEN"] == "welcome" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NotificationCenter.default.post(name: AnnouncementCenter.showWindow, object: nil) }
        } else if env["MTP_OPEN"] == "import" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NotificationCenter.default.post(name: .importSessions, object: nil) }
        }
        if let size = env["MTP_WINDOW_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                for w in NSApp.windows where w.isVisible && w.frame.width > 400 {
                    w.setContentSize(NSSize(width: size[0], height: size[1])); w.center()
                }
            }
        }
        if let panel = env["MTP_PANEL"].flatMap(SidebarPanel.init(rawValue:)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { workspace.sidebarRequest = panel }
        }
        if env["MTP_MODE"] == "files" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if case .ssh(let t) = workspace.tabs.last { t.mode = .commander } }
        }
        if let tab = env["MTP_SETTINGS_TAB"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { NotificationCenter.default.post(name: .showSettingsTab, object: tab) }
        }
        if Showcase.isOn, env["MTP_SHOWCASE_OPEN"] != nil {
            if let p = Showcase.sessions().first { workspace.open(p, secret: nil) }
        }
        if let text = env["MTP_SEND"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { workspace.selected?.sendText(text + "\r") }
        }
        if let out = env["MTP_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(env["MTP_DELAY"] ?? "") ?? 4)) {
                let wantTitle = env["MTP_WINDOW"]
                guard let window = NSApp.windows.first(where: { w in
                          w.isVisible && w.frame.width > 300 && (wantTitle == nil || w.title.contains(wantTitle!))
                      }) ?? NSApp.keyWindow,
                      let view = (env["MTP_SHEET"] == "1" ? (window.attachedSheet ?? window) : window).contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                if env["MTP_REPORT"] != nil, case .ssh(let t) = workspace.selected {
                    t.terminal.terminalView.selectAll()
                    print("TERMINAL<<\n\(t.terminal.terminalView.getSelection() ?? "")\n>>")
                    print("BROWSER PATH \(t.remote.path) follow=\(t.remote.followTerminal)")
                }
                // Force terminals to redraw everything (they normally draw only changed lines).
                func resizeKick(_ v: NSView) {
                    if v is TerminalView { let f = v.frame; v.setFrameSize(NSSize(width: f.width - 1, height: f.height)); v.setFrameSize(f.size) }
                    v.subviews.forEach(resizeKick)
                }
                resizeKick(view)
                func invalidate(_ v: NSView) { v.needsDisplay = true; v.subviews.forEach(invalidate) }
                invalidate(view)
                view.displayIfNeeded()
                view.cacheDisplay(in: view.bounds, to: rep)
                // Terminals draw into layers that cacheDisplay skips: render those layers and paste them in.
                func terminals(_ v: NSView) -> [NSView] { (v is TerminalView ? [v] : []) + v.subviews.flatMap(terminals) }
                if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                    for t in terminals(view) {
                        guard let layer = t.layer else { continue }
                        if env["MTP_LAYERDEBUG"] != nil {
                            func dump(_ l: CALayer, _ depth: Int) {
                                print(String(repeating: "  ", count: depth) + "\(type(of: l)) bg=\(l.backgroundColor.map { "\($0.components ?? [])" } ?? "nil") opaque=\(l.isOpaque) contents=\(l.contents != nil) frame=\(l.frame)")
                                l.sublayers?.forEach { dump($0, depth + 1) }
                            }
                            dump(layer, 0)
                            print("nativeBg", (t as? TerminalView)?.nativeBackgroundColor ?? "-")
                        }
                        let r = t.convert(t.bounds, to: view)          // in view coordinates (bottom-left origin)
                        let cg = ctx.cgContext
                        if let tv = t as? TerminalView, let box = t.superview {   // padded container background
                            cg.setFillColor(tv.nativeBackgroundColor.cgColor)
                            cg.fill(box.convert(box.bounds, to: view))
                        }
                        // Render the terminal layer into its own bitmap, turn its white backing into the
                        // theme background, then paste it in place.
                        guard let tv = t as? TerminalView else { continue }
                        let px = Int(r.width * 2), py = Int(r.height * 2)
                        guard let tmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py, bitsPerSample: 8,
                                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                         bytesPerRow: px * 4, bitsPerPixel: 32),
                              let tctx = NSGraphicsContext(bitmapImageRep: tmp) else { continue }
                        let tcg = tctx.cgContext
                        tcg.scaleBy(x: 2, y: 2)
                        if t.isFlipped { tcg.translateBy(x: 0, y: r.height); tcg.scaleBy(x: 1, y: -1) }
                        layer.render(in: tcg)
                        tcg.flush()
                        let bg = tv.nativeBackgroundColor.usingColorSpace(.deviceRGB) ?? .black
                        let br = UInt8(bg.redComponent * 255), bgc = UInt8(bg.greenComponent * 255), bb = UInt8(bg.blueComponent * 255)
                        if let data = tmp.bitmapData {
                            for i in stride(from: 0, to: px * py * 4, by: 4) {
                                let a = data[i + 3]
                                if a < 10 || (data[i] > 244 && data[i + 1] > 244 && data[i + 2] > 244) {
                                    data[i] = br; data[i + 1] = bgc; data[i + 2] = bb; data[i + 3] = 255
                                }
                            }
                        }
                        tmp.size = r.size
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = ctx
                        tmp.draw(in: r)
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                if env["MTP_QUIT"] == "1" { NSApp.terminate(nil) }
            }
        }
    }
}
