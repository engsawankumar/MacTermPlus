import AppKit
import SwiftUI

/// One message for the Welcome window, published in announcements.json in the GitHub repo.
/// Edit that file on GitHub to show news, tips or sponsored messages — no app update needed.
struct Announcement: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var body: String?
    /// "info" (default), "news", "tip", "warning" or "ad" (shown with a "Sponsored" label).
    var style: String?
    /// https image shown above the text (optional).
    var imageURL: String?
    var buttonTitle: String?
    /// https link opened in the browser by the button.
    var buttonURL: String?
    /// Show only from / until these dates ("yyyy-MM-dd", optional).
    var start: String?
    var end: String?
    /// Show only to these app versions (inclusive, optional).
    var minVersion: String?
    var maxVersion: String?
    /// After the user has seen it once, don't open the window for it again (still listed).
    var showOnce: Bool?
    /// Higher first.
    var priority: Int?

    func isActive(on date: Date = Date(), version: String) -> Bool {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        if let s = start.flatMap(f.date(from:)), date < s { return false }
        if let e = end.flatMap(f.date(from:)), date > e.addingTimeInterval(86400) { return false }
        if let min = minVersion, !min.isEmpty, Updater.isNewer(min, than: version) { return false }
        if let max = maxVersion, !max.isEmpty, Updater.isNewer(version, than: max) { return false }
        return !title.isEmpty
    }

    var isAd: Bool { style == "ad" }

    var tint: Color {
        switch style {
        case "ad": return .orange
        case "news": return .blue
        case "tip": return .green
        case "warning": return .red
        default: return .teal
        }
    }

    var icon: String {
        switch style {
        case "ad": return "megaphone.fill"
        case "news": return "newspaper.fill"
        case "tip": return "lightbulb.fill"
        case "warning": return "exclamationmark.triangle.fill"
        default: return "info.circle.fill"
        }
    }

    /// Only https links/images are used.
    static func safeURL(_ s: String?) -> URL? {
        guard let s, let u = URL(string: s), u.scheme?.lowercased() == "https" else { return nil }
        return u
    }
}

struct AnnouncementFeed: Codable {
    var version: Int?
    var messages: [Announcement]
}

/// Downloads and caches announcements, and decides when the Welcome window opens.
@MainActor
final class AnnouncementCenter: ObservableObject {
    static let shared = AnnouncementCenter()
    static let showWindow = Notification.Name("MacTermPlus.showWelcome")

    @Published private(set) var messages: [Announcement] = []
    @Published private(set) var loading = false
    @Published var showAtLaunch: Bool { didSet { UserDefaults.standard.set(showAtLaunch, forKey: "welcome.atLaunch") } }

    private let cacheURL = AppPaths.supportDirectory.appendingPathComponent("announcements-cache.json")
    private var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "welcome.seen") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "welcome.seen") }
    }

    private init() {
        showAtLaunch = UserDefaults.standard.object(forKey: "welcome.atLaunch") as? Bool ?? true
        if let data = try? Data(contentsOf: cacheURL), let feed = try? JSONDecoder().decode(AnnouncementFeed.self, from: data) {
            apply(feed)
        }
    }

    /// announcements.json next to the code on GitHub (main branch), or the URL baked into Info.plist.
    var feedURL: URL? {
        if let s = ProcessInfo.processInfo.environment["MTP_ANNOUNCEMENTS_URL"], let u = URL(string: s) { return u }  // tests
        if let s = Bundle.main.object(forInfoDictionaryKey: "MTPAnnouncementsURL") as? String, let u = URL(string: s), !s.isEmpty { return u }
        let repo = Updater.shared.repo
        guard Updater.shared.isConfigured else { return nil }
        return URL(string: "https://raw.githubusercontent.com/\(repo)/main/announcements.json")
    }

    func refresh() async {
        guard let url = feedURL else { return }
        loading = true
        defer { loading = false }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("MacTermPlus", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let feed = try? JSONDecoder().decode(AnnouncementFeed.self, from: data) else { return }
        try? data.write(to: cacheURL, options: .atomic)
        apply(feed)
    }

    private func apply(_ feed: AnnouncementFeed) {
        messages = feed.messages
            .filter { $0.isActive(version: AppInfo.version) }
            .sorted { ($0.priority ?? 0) > ($1.priority ?? 0) }
    }

    /// At launch: open on first run, after an update, or when there's a message the user hasn't seen.
    func checkAtLaunch() {
        let lastVersion = UserDefaults.standard.string(forKey: "welcome.lastVersion")
        let newVersion = lastVersion != AppInfo.version
        Task {
            await refresh()
            let unseen = messages.contains { !seen.contains($0.id) }
            if newVersion || (showAtLaunch && unseen) {
                NotificationCenter.default.post(name: Self.showWindow, object: nil)
            }
        }
    }

    /// Called when the window is shown.
    func markShown() {
        UserDefaults.standard.set(AppInfo.version, forKey: "welcome.lastVersion")
        seen.formUnion(messages.map(\.id))
    }
}

// MARK: - Window

struct WelcomeWindowView: View {
    @ObservedObject var center = AnnouncementCenter.shared
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if !center.messages.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(center.messages) { AnnouncementCard(message: $0) }
                        }
                    }
                    quickStart
                }
                .padding(24)
            }
            Divider()
            HStack {
                Toggle("Show this window when MacTerm+ opens", isOn: $center.showAtLaunch)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                Spacer()
                if center.loading { ProgressView().controlSize(.small) }
                Button("Get Started") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 600, height: 620)
        .tint(settings.accent.color)
        .preferredColorScheme(settings.appearance.colorScheme)
        .task {
            center.markShown()
            await center.refresh()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().frame(width: 84, height: 84)
            } else {
                IconTile(symbol: "terminal.fill", color: .teal, size: 72)
            }
            Text("Welcome to MacTerm+").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Version \(AppInfo.version)").font(.callout).foregroundStyle(.secondary)
            BuiltByBadge()
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get started").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                QuickTile(icon: "plus.rectangle.on.rectangle", color: .teal, title: "Add a server",
                          detail: "SSH, SFTP, FTP or FTPS") {
                    NotificationCenter.default.post(name: .newSession, object: nil); dismiss()
                }
                QuickTile(icon: "square.and.arrow.down.fill", color: .orange, title: "Import sessions",
                          detail: "From other apps on this Mac") {
                    NotificationCenter.default.post(name: .importSessions, object: nil); dismiss()
                }
                QuickTile(icon: "icloud.fill", color: .blue, title: "Sync your Macs",
                          detail: "iCloud Drive or Google Drive") {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                    NotificationCenter.default.post(name: .showSyncSettings, object: nil); dismiss()
                }
                QuickTile(icon: "questionmark.circle.fill", color: .purple, title: "Read the guide",
                          detail: "Everything MacTerm+ can do") {
                    openWindow(id: "help"); dismiss()
                }
            }
        }
    }
}

private struct AnnouncementCard: View {
    let message: Announcement

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let img = Announcement.safeURL(message.imageURL) {
                AsyncImage(url: img) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(alignment: .top, spacing: 10) {
                IconTile(symbol: message.icon, color: message.tint, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(message.title).font(.headline)
                        if message.isAd {
                            Text("Sponsored").font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.2), in: Capsule())
                        }
                    }
                    if let body = message.body, !body.isEmpty {
                        Text((try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(body))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if let url = Announcement.safeURL(message.buttonURL) {
                        Button(message.buttonTitle ?? "Learn More") { NSWorkspace.shared.open(url) }
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(message.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(message.tint.opacity(0.3)))
    }
}

private struct QuickTile: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconTile(symbol: icon, color: color, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(hovering ? 0.9 : 0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
