import AppKit
import CryptoKit
import Security
import Foundation
import SwiftUI

/// A release on GitHub (from the Releases API).
struct ReleaseInfo: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let size: Int
    }
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: URL
    let published_at: Date?
    let draft: Bool?
    let prerelease: Bool?
    let assets: [Asset]

    var version: String { tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) }
    /// The app zip ("MacTerm+-1.0.1.zip"; GitHub may show "+" differently, so match loosely).
    var zipAsset: Asset? { assets.first { $0.name.lowercased().hasSuffix(".zip") && $0.name.lowercased().contains("macterm") } }
    var checksumAsset: Asset? {
        guard let zip = zipAsset else { return nil }
        return assets.first { $0.name == zip.name + ".sha256" } ?? assets.first { $0.name.lowercased().hasSuffix(".zip.sha256") }
    }
}

enum UpdateError: LocalizedError {
    case notConfigured, noRelease, noAsset, checksumMismatch, badBundle(String), notWritable(URL), http(Int)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Updates aren’t set up yet: no GitHub repository is configured for this build."
        case .noRelease: return "No published release was found on GitHub."
        case .noAsset: return "The latest release has no MacTerm+ .zip attached."
        case .checksumMismatch: return "The download doesn’t match its published checksum, so it wasn’t installed."
        case .badBundle(let why): return "The downloaded app isn’t valid: \(why)"
        case .notWritable(let url): return "MacTerm+ can’t replace itself in \(url.deletingLastPathComponent().path). The new version was opened in Finder — drag it to Applications."
        case .http(let code): return code == 404 ? "Repository or release not found on GitHub (404)." : "GitHub answered with HTTP \(code)."
        }
    }
}

/// Checks GitHub Releases for a newer MacTerm+ and installs it in place.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let showWindow = Notification.Name("MacTermPlus.showUpdate")

    enum State: Equatable {
        case idle, checking, upToDate, available, downloading(Double), installing, failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latest: ReleaseInfo?
    @Published var autoCheck: Bool { didSet { UserDefaults.standard.set(autoCheck, forKey: "update.auto") } }
    @Published var repoOverride: String { didSet { UserDefaults.standard.set(repoOverride, forKey: "update.repo") } }

    private init() {
        autoCheck = UserDefaults.standard.object(forKey: "update.auto") as? Bool ?? true
        repoOverride = UserDefaults.standard.string(forKey: "update.repo") ?? ""
    }

    /// "owner/name" — from Settings, else baked into Info.plist by build-app.sh (release.config).
    var repo: String {
        let r = repoOverride.trimmingCharacters(in: .whitespaces)
        if !r.isEmpty { return r }
        return Bundle.main.object(forInfoDictionaryKey: "MTPUpdateRepo") as? String ?? ""
    }

    var isConfigured: Bool {
        let parts = repo.split(separator: "/")
        return parts.count == 2 && !repo.hasPrefix("OWNER/") && !repo.contains(" ")
    }

    var currentVersion: String { AppInfo.version }
    var canInstallInPlace: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    var releasesPage: URL? { isConfigured ? URL(string: "https://github.com/\(repo)/releases") : nil }

    // MARK: Checking

    /// Silent daily check at launch.
    func checkAtLaunchIfDue() {
        guard autoCheck, isConfigured else { return }
        let last = UserDefaults.standard.object(forKey: "update.lastCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 3600 else { return }
        Task {
            await check(userInitiated: false)
            if state == .available, let v = latest?.version, UserDefaults.standard.string(forKey: "update.skip") != v {
                NotificationCenter.default.post(name: Self.showWindow, object: nil)
            }
        }
    }

    func check(userInitiated: Bool) async {
        guard isConfigured else {
            state = .failed(UpdateError.notConfigured.errorDescription!)
            return
        }
        state = .checking
        do {
            let api = ProcessInfo.processInfo.environment["MTP_UPDATE_API"] ?? "https://api.github.com"   // tests only
            var req = URLRequest(url: URL(string: "\(api)/repos/\(repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("MacTermPlus-Updater", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 20
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.http(http.statusCode) }
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let release = try dec.decode(ReleaseInfo.self, from: data)
            latest = release
            UserDefaults.standard.set(Date(), forKey: "update.lastCheck")
            state = Self.isNewer(release.version, than: currentVersion) ? .available : .upToDate
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func skipThisVersion() {
        if let v = latest?.version { UserDefaults.standard.set(v, forKey: "update.skip") }
    }

    /// Semantic-ish comparison: 0.10.0 > 0.9.2; "dev" builds are always older.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        if b == "dev" { return true }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: Installing

    func downloadAndInstall() async {
        guard let release = latest else { return }
        do {
            guard let zip = release.zipAsset else { throw UpdateError.noAsset }
            state = .downloading(0)
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("MacTermPlus-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zipURL = work.appendingPathComponent(zip.name)
            try await download(zip.browser_download_url, to: zipURL, expected: zip.size)

            // Integrity: compare with the published SHA-256.
            if let sumAsset = release.checksumAsset {
                let (sumData, _) = try await URLSession.shared.data(from: sumAsset.browser_download_url)
                let expected = String(decoding: sumData, as: UTF8.self).split(whereSeparator: { $0 == " " || $0.isNewline }).first.map(String.init)?.lowercased() ?? ""
                let actual = SHA256.hash(data: try Data(contentsOf: zipURL)).map { String(format: "%02x", $0) }.joined()
                guard expected == actual else { throw UpdateError.checksumMismatch }
            }

            state = .installing
            let unzipDir = work.appendingPathComponent("unzipped")
            try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, unzipDir.path])
            guard let newApp = (try FileManager.default.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil))
                .first(where: { $0.pathExtension == "app" }) else { throw UpdateError.badBundle("no .app inside the zip") }
            guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
                  info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
                throw UpdateError.badBundle("it isn’t MacTerm+ (different bundle identifier)")
            }
            let newVersion = info["CFBundleShortVersionString"] as? String ?? ""
            guard Self.isNewer(newVersion, than: currentVersion) else { throw UpdateError.badBundle("version \(newVersion) isn’t newer") }
            try run("/usr/bin/codesign", ["--verify", "--deep", newApp.path])
            try Self.checkSameSigner(newApp)

            let current = Bundle.main.bundleURL
            guard canInstallInPlace, FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
                NSWorkspace.shared.activateFileViewerSelecting([newApp])
                throw UpdateError.notWritable(current)
            }
            try relaunch(replacing: current, with: newApp)
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func download(_ url: URL, to dest: URL, expected: Int) async throws {
        var observation: NSKeyValueObservation?
        defer { observation?.invalidate() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: url) { tmp, resp, error in
                if let error { cont.resume(throwing: error); return }
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    cont.resume(throwing: UpdateError.http(http.statusCode)); return
                }
                guard let tmp else { cont.resume(throwing: UpdateError.noAsset); return }
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    cont.resume()
                } catch { cont.resume(throwing: error) }
            }
            observation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
                let f = p.fractionCompleted
                Task { @MainActor in self?.state = .downloading(f) }
            }
            task.resume()
        }
    }

    /// The update must be signed by the same identity as the running app (when the running app has a
    /// permanent identity). This blocks look-alike downloads and keeps macOS permissions valid.
    private static func checkSameSigner(_ newApp: URL) throws {
        var selfCode: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyDesignatedRequirement(selfCode as! SecStaticCode, [], &requirement) == errSecSuccess,
              let requirement else { return }
        var text: CFString?
        SecRequirementCopyString(requirement, [], &text)
        // Ad-hoc builds (requirement is just a cdhash) can't pin a signer; accept any valid signature.
        guard let t = text as String?, t.contains("certificate") else { return }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(newApp as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError.badBundle("its signature can’t be read")
        }
        let status = SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
        guard status == errSecSuccess else {
            throw UpdateError.badBundle("it isn’t signed by the MacTerm+ developer (code \(status))")
        }
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw UpdateError.badBundle("\((tool as NSString).lastPathComponent) failed (\(p.terminationStatus))")
        }
    }

    /// A tiny helper script waits for this process to quit, swaps the app bundle (keeping a backup
    /// until the copy succeeds), and opens the new version.
    private static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private func relaunch(replacing current: URL, with newApp: URL) throws {
        let script = """
        #!/bin/sh
        while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
        OLD=\(Self.shellQuote(current.path)); NEW=\(Self.shellQuote(newApp.path)); BAK="$OLD.updating-backup"
        rm -rf "$BAK"
        if mv "$OLD" "$BAK" && /usr/bin/ditto "$NEW" "$OLD"; then
          rm -rf "$BAK"
        else
          rm -rf "$OLD"; mv "$BAK" "$OLD"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
        /usr/bin/open "$OLD"
        """
        let scriptURL = newApp.deletingLastPathComponent().appendingPathComponent("install.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [scriptURL.path]
        try p.run()
        if NSApplication.shared.isRunning { NSApp.terminate(nil) } else { exit(0) }
    }
}

// MARK: - UI

struct UpdateView: View {
    @ObservedObject var updater = Updater.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let img = NSImage(contentsOf: url) {
                    Image(nsImage: img).resizable().frame(width: 56, height: 56)
                } else {
                    IconTile(symbol: "arrow.down.app.fill", color: .teal, size: 50)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title2.bold())
                    Text("You have MacTerm+ \(updater.currentVersion)\(updater.latest.map { " · latest is \($0.version)" } ?? "")")
                        .foregroundStyle(.secondary)
                }
            }
            switch updater.state {
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("Checking GitHub for updates…") }
            case .downloading(let p):
                VStack(alignment: .leading) {
                    Text("Downloading \(updater.latest?.zipAsset?.name ?? "update")…")
                    ProgressView(value: p)
                }
            case .installing:
                HStack { ProgressView().controlSize(.small); Text("Verifying and installing… MacTerm+ will restart.") }
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case .upToDate:
                Label("MacTerm+ is up to date.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            default:
                EmptyView()
            }
            if updater.state == .available || isBusy, let notes = updater.latest?.body, !notes.isEmpty {
                Text("What’s new").font(.headline)
                ScrollView {
                    Text((try? AttributedString(markdown: notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(notes))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(height: 180)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                if let page = updater.latest?.html_url ?? updater.releasesPage {
                    Button("Release Page") { NSWorkspace.shared.open(page) }.buttonStyle(.link)
                }
                Spacer()
                if updater.state == .available {
                    Button("Skip This Version") { updater.skipThisVersion(); dismiss() }
                    Button("Later") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(updater.canInstallInPlace ? "Install & Relaunch" : "Download") {
                        if updater.canInstallInPlace {
                            Task { await updater.downloadAndInstall() }
                        } else if let page = updater.latest?.html_url { NSWorkspace.shared.open(page) }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Check Again") { Task { await updater.check(userInitiated: true) } }.disabled(isBusy)
                    Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { if updater.state == .idle || updater.state == .upToDate { await updater.check(userInitiated: true) } }
    }

    private var isBusy: Bool {
        switch updater.state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private var title: String {
        switch updater.state {
        case .available: return "MacTerm+ \(updater.latest?.version ?? "") is available"
        case .upToDate: return "You’re up to date"
        default: return "Software Update"
        }
    }
}
