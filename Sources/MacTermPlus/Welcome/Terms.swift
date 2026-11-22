import AppKit
import SwiftUI

/// License and terms of use, accepted once before MacTerm+ is used (and again if the terms change).
enum Terms {
    /// Bump when the license or terms change in a way users must accept again.
    static let version = 1
    private static let key = "terms.acceptedVersion"
    private static let dateKey = "terms.acceptedDate"
    static let accepted = Notification.Name("MacTermPlus.termsAccepted")
    /// Set when the user chose Quit on the agreement (so it isn't shown again while quitting).
    @MainActor static var quitting = false

    /// Quit from the agreement sheet. AppKit won't quit while a sheet is open, so close it first.
    @MainActor static func quit(dismiss: DismissAction) {
        quitting = true
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    static var isAccepted: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["MTP_SHOW_TERMS"] != nil { return false }   // screenshots of the agreement
        if Showcase.isOn || env["MTP_DEMO"] != nil { return true }
        return UserDefaults.standard.integer(forKey: key) >= version
    }

    static var acceptedDate: Date? { UserDefaults.standard.object(forKey: dateKey) as? Date }

    static func accept() {
        guard !Showcase.isOn else { return }
        UserDefaults.standard.set(version, forKey: key)
        UserDefaults.standard.set(Date(), forKey: dateKey)
        NotificationCenter.default.post(name: accepted, object: nil)
    }

    /// The full license shipped inside the app.
    static var licenseText: String {
        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        return "The full license is at https://github.com/engsawankumar/MacTermPlus/blob/main/LICENSE"
    }

    static let issuesURL = URL(string: "https://github.com/engsawankumar/MacTermPlus/issues/new/choose")!

    /// The key points, in plain words.
    static let points: [(icon: String, color: Color, title: String, text: String)] = [
        ("person.fill.checkmark", .green, "Free for personal and non-commercial use",
         "Use, copy and modify MacTerm+ for yourself, learning, teaching and non-profit work. Keep the license and the “Built by Bairagi” credit."),
        ("nosign", .red, "No commercial use without permission",
         "Don’t sell it or use it or its code in paid products, services or client projects without written permission."),
        ("exclamationmark.shield.fill", .orange, "Use it responsibly",
         "Only on servers, networks and accounts you own or are allowed to access, and within the law."),
        ("hand.raised.fill", .purple, "No warranty, no liability",
         "MacTerm+ is provided as is. The developer is not liable for any unethical, unauthorized or illegal use, or for data loss, downtime or other damage."),
        ("person.crop.circle.badge.exclamationmark", .blue, "You are responsible",
         "By using MacTerm+ you agree that all responsibility and liability for its use lies with you, the user, and not with the developer."),
        ("envelope.fill", .teal, "Copyright or complaints",
         "Believe something infringes your rights, or have a complaint? Reach us through the project’s GitHub page and we’ll respond promptly."),
    ]
}

/// First-launch agreement. MacTerm+ can’t be used until it is accepted; declining quits.
struct TermsSheet: View {
    /// Tests only: press "Quit MacTerm+".
    static let testQuit = Notification.Name("MacTermPlus.termsTestQuit")
    @Environment(\.dismiss) private var dismiss
    @ViewState private var agreed = false
    @ViewState private var showFull = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Before you start").font(.title.bold())
                    Text("Please read and accept the MacTerm+ license and terms of use.").foregroundStyle(.secondary)
                }
            }
            TermsPoints()
            DisclosureGroup("Read the full license", isExpanded: $showFull) {
                ScrollView {
                    Text(Terms.licenseText).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                .frame(height: 180)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
            }
            Toggle(isOn: $agreed) {
                Text("I have read and accept the license and terms of use, and I agree that I alone am responsible for how I use MacTerm+.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)
            HStack {
                Button("Quit MacTerm+") { Terms.quit(dismiss: dismiss) }
                Spacer()
                Button("Accept & Continue") { Terms.accept(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!agreed)
            }
        }
        .padding(24)
        .frame(width: 600)
        .interactiveDismissDisabled()
        .onReceive(NotificationCenter.default.publisher(for: Self.testQuit)) { _ in Terms.quit(dismiss: dismiss) }
    }
}

/// The six key points (used on first launch and in Help → License & Terms).
struct TermsPoints: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Terms.points, id: \.title) { p in
                HStack(alignment: .top, spacing: 12) {
                    IconTile(symbol: p.icon, color: p.color, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).font(.headline)
                        Text(p.text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Help → License & Terms: read-only view with the acceptance date.
struct TermsWindow: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("License & Terms of Use").font(.title.bold())
                if let d = Terms.acceptedDate {
                    Label("You accepted these terms on \(d.formatted(date: .long, time: .shortened)).", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                TermsPoints()
                HStack {
                    Button("Report a Copyright Concern or Complaint…") { NSWorkspace.shared.open(Terms.issuesURL) }
                    Button("Third-Party Licenses") {
                        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") { NSWorkspace.shared.open(url) }
                    }
                }
                Divider()
                Text("Full license").font(.headline)
                Text(Terms.licenseText).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            .padding(24)
        }
        .frame(width: 640, height: 640)
    }
}
