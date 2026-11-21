import AppKit
import SwiftUI

/// Step-by-step sync setup: 1 where, 2 what, 3 allow access, then done.
struct SyncSetupView: View {
    @ObservedObject var sync = SyncManager.shared
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable { case place, items, access, done
        var title: String { ["Where", "What", "Allow", "Done"][rawValue] }
    }

    @ViewState private var step: Step = .place
    @ViewState private var locations: [SyncLocation] = Self.detect()
    @ViewState private var chosen: SyncLocation?
    @ViewState private var sessions = true
    @ViewState private var passwords = true
    @ViewState private var settings = true
    @ViewState private var macros = true
    @ViewState private var tunnels = true
    @ViewState private var pass1 = ""
    @ViewState private var pass2 = ""
    @ViewState private var changePassphrase = false
    @ViewState private var working = false
    @ViewState private var accessError: String?

    private var hasSavedPassphrase: Bool { !Showcase.isOn && sync.passphrase != nil }
    private var needsNewPassphrase: Bool { passwords && sessions && (!hasSavedPassphrase || changePassphrase) }
    private var passphraseOK: Bool { !needsNewPassphrase || (pass1.count >= 8 && pass1 == pass2) }
    private var allOn: Bool { sessions && passwords && settings && macros && tunnels }
    private var anyOn: Bool { sessions || settings || macros || tunnels }

    var body: some View {
        VStack(spacing: 0) {
            stepper
            Divider()
            Group {
                switch step {
                case .place: placeStep
                case .items: itemsStep
                case .access: accessStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(22)
            Divider()
            buttons
        }
        .frame(width: 600, height: 560)
        .onAppear(perform: loadCurrent)
    }

    // MARK: Header

    private var stepper: some View {
        HStack(spacing: 0) {
            ForEach(Step.allCases, id: \.self) { s in
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 24, height: 24)
                        if s.rawValue < step.rawValue {
                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                        } else {
                            Text("\(s.rawValue + 1)").font(.caption.bold()).foregroundStyle(s == step ? .white : .secondary)
                        }
                    }
                    Text(s.title).font(.callout.weight(s == step ? .semibold : .regular))
                        .foregroundStyle(s == step ? .primary : .secondary)
                }
                if s != .done {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1).padding(.horizontal, 10)
                }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    // MARK: Step 1 — where

    private var placeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Where should MacTerm+ keep your sync file?",
                  "Pick the cloud drive this Mac already uses. Every Mac that picks the same drive stays in sync.")
            let icloud = locations.first { $0.provider == .iCloud }
            let googles = locations.filter { $0.provider == .google }
            placeCard(icon: "icloud.fill", color: .blue, name: "iCloud Drive",
                      detail: icloud != nil ? "Uses your Apple ID’s iCloud Drive" : "iCloud Drive is off on this Mac",
                      location: icloud,
                      fix: icloud == nil ? ("Open iCloud Settings", { open("x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") }) : nil)
            if googles.isEmpty {
                placeCard(icon: "g.circle.fill", color: .red, name: "Google Drive",
                          detail: "Install Google Drive for desktop and sign in, then click Look Again",
                          location: nil, fix: ("Get Google Drive", { open("https://www.google.com/drive/download/") }))
            } else {
                ForEach(googles) { g in
                    placeCard(icon: "g.circle.fill", color: .red, name: g.name, detail: "Your Google Drive (My Drive)", location: g, fix: nil)
                }
            }
            let others = locations.filter { $0.provider != .iCloud && $0.provider != .google }
            ForEach(others) { o in
                placeCard(icon: o.icon, color: .indigo, name: o.name, detail: "Cloud folder found on this Mac", location: o, fix: nil)
            }
            HStack {
                Button("Look Again") { locations = Self.detect() }
                Button("Choose Another Folder…") { chooseFolder() }
                Spacer()
            }
            .buttonStyle(.link)
            if let chosen, chosen.provider == .custom {
                Label((chosen.url.path as NSString).abbreviatingWithTildeInPath, systemImage: "folder.fill")
                    .font(.callout).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private func placeCard(icon: String, color: Color, name: String, detail: String, location: SyncLocation?,
                           fix: (String, () -> Void)?) -> some View {
        let selected = location != nil && chosen?.url == location?.url
        return HStack(spacing: 12) {
            IconTile(symbol: icon, color: location == nil ? .gray : color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).foregroundStyle(location == nil ? .secondary : .primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let fix {
                Button(fix.0, action: fix.1)
            } else {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(selected ? Color.accentColor : .secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { if let location { chosen = location } }
    }

    // MARK: Step 2 — what

    private var itemsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("What should be synced?", "Everything is selected. Untick what should stay on this Mac only.")
            Toggle(isOn: Binding(get: { allOn }, set: { v in sessions = v; passwords = v; settings = v; macros = v; tunnels = v })) {
                Text("Select all").font(.headline)
            }
            .toggleStyle(.checkbox)
            Divider()
            item($sessions, "server.rack", .teal, "Sessions", "Servers, groups, colours, notes and folders")
            item($passwords, "key.fill", .orange, "Passwords", "Encrypted on this Mac with your sync passphrase before upload")
                .disabled(!sessions)
            if passwords && sessions { passphraseFields.padding(.leading, 30) }
            item($settings, "gearshape.fill", .gray, "Settings", "Theme, fonts, appearance, toolbar, files and status bar options")
            item($macros, "bolt.horizontal.fill", .mint, "Macros & Quick Commands", "Your saved commands, stars and folders")
            item($tunnels, "point.3.connected.trianglepath.dotted", .green, "Tunnels", "Saved SSH port forwards")
        }
    }

    private func item(_ on: Binding<Bool>, _ icon: String, _ color: Color, _ name: String, _ detail: String) -> some View {
        Toggle(isOn: on) {
            HStack(spacing: 10) {
                IconTile(symbol: icon, color: color, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    @ViewBuilder private var passphraseFields: some View {
        if hasSavedPassphrase && !changePassphrase {
            HStack {
                Label("Using the sync passphrase saved on this Mac", systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(.green)
                Button("Change") { changePassphrase = true }.buttonStyle(.link).font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    SecureField("Sync passphrase (8+ characters)", text: $pass1)
                    SecureField("Repeat it", text: $pass2)
                }
                .textFieldStyle(.roundedBorder)
                Text(!pass2.isEmpty && pass1 != pass2 ? "The two entries don’t match."
                     : "Use the same passphrase on all your Macs. It stays in this Mac’s Keychain and is never uploaded.")
                    .font(.caption).foregroundStyle(!pass2.isEmpty && pass1 != pass2 ? .orange : .secondary)
            }
        }
    }

    // MARK: Step 3 — allow

    private var accessStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Allow MacTerm+ to use \(chosen?.name ?? "the folder")",
                  "macOS protects your cloud drives. When you continue, macOS asks whether MacTerm+ may access files there. Click Allow.")
            HStack(spacing: 14) {
                IconTile(symbol: chosen?.icon ?? "folder.fill", color: .blue, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MacTerm+ only uses one folder:").font(.callout)
                    Text(((chosen?.url.appendingPathComponent("MacTermPlus").path ?? "") as NSString).abbreviatingWithTildeInPath)
                        .font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Text("Nothing is sent anywhere else.").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("You chose to sync:").font(.callout.weight(.semibold))
                Text(summaryOfChoices).font(.callout).foregroundStyle(.secondary)
            }
            if working { HStack { ProgressView().controlSize(.small); Text("Waiting for permission and syncing…") } }
            if let accessError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(accessError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Privacy Settings") {
                        open("x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
                    }
                }
            }
        }
    }

    private var summaryOfChoices: String {
        var parts: [String] = []
        if sessions { parts.append("Sessions") }
        if sessions && passwords { parts.append("Passwords (encrypted)") }
        if settings { parts.append("Settings") }
        if macros { parts.append("Macros & Quick Commands") }
        if tunnels { parts.append("Tunnels") }
        return parts.joined(separator: " · ")
    }

    // MARK: Step 4 — done

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let e = sync.lastError {
                title("Almost there", "Sync is on, but the first sync reported a problem.")
                Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if e == SyncError.wrongPassphrase.errorDescription {
                    Button("Enter the Passphrase Again") { changePassphrase = true; pass1 = ""; pass2 = ""; step = .items }
                }
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 46)).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sync is on").font(.title2.bold())
                        Text(sync.lastSummary).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Syncing:  \(summaryOfChoices)").font(.callout)
            Text("To add another Mac: install MacTerm+ there, open Sync → Set Up Sync, and choose the same drive\(passwords && sessions ? " and passphrase" : "").")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !sync.devices.isEmpty {
                Text("Macs using this sync").font(.callout.weight(.semibold))
                ForEach(sync.devices) { d in
                    Label(d.name + (d.id == sync.deviceID ? " (this Mac)" : ""), systemImage: "laptopcomputer").font(.callout)
                }
            }
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack {
            if step == .place || step == .done {
                Button(step == .done ? "Sync Settings…" : "Cancel") {
                    if step == .done { NotificationCenter.default.post(name: .showSettings, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NotificationCenter.default.post(name: .showSyncSettings, object: nil) } }
                    dismiss()
                }
                .keyboardShortcut(step == .place ? .cancelAction : nil)
            } else {
                Button("Back") { accessError = nil; step = Step(rawValue: step.rawValue - 1)! }.disabled(working)
            }
            Spacer()
            switch step {
            case .place:
                Button("Continue") { step = .items }.keyboardShortcut(.defaultAction).disabled(chosen == nil)
            case .items:
                Button("Continue") { step = .access }.keyboardShortcut(.defaultAction).disabled(!anyOn || !passphraseOK)
            case .access:
                Button(accessError == nil ? "Allow Access & Start Sync" : "Try Again") { start() }
                    .keyboardShortcut(.defaultAction).disabled(working)
            case .done:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    // MARK: Actions

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.title2.bold())
            Text(sub).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    /// Showcase screenshots use made-up drives (no real account names, no file access).
    private static func detect() -> [SyncLocation] {
        guard Showcase.isOn else { return SyncLocation.detect() }
        return [SyncLocation(provider: .iCloud, name: "iCloud Drive", url: URL(fileURLWithPath: "/tmp/showcase-icloud")),
                SyncLocation(provider: .google, name: "Google Drive (you@example.com)", url: URL(fileURLWithPath: "/tmp/showcase-gdrive"))]
    }

    private func loadCurrent() {
        if let n = ProcessInfo.processInfo.environment["MTP_SYNC_STEP"].flatMap(Int.init), let s = Step(rawValue: n) { step = s }
        if !sync.folderPath.isEmpty {
            chosen = locations.first { $0.url.path == sync.folderPath }
                ?? SyncLocation(provider: .custom, name: (sync.folderPath as NSString).lastPathComponent, url: URL(fileURLWithPath: sync.folderPath))
            sessions = sync.syncSessions; settings = sync.syncSettings; macros = sync.syncMacros; tunnels = sync.syncTunnels
            passwords = sync.syncPasswords || !sync.enabled
        } else {
            chosen = locations.first { $0.provider == .iCloud } ?? locations.first { $0.provider == .google }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose a folder that your cloud app syncs."
        if panel.runModal() == .OK, let url = panel.url {
            chosen = SyncLocation(provider: .custom, name: url.lastPathComponent, url: url)
        }
    }

    private func start() {
        guard let folder = chosen?.url else { return }
        working = true
        accessError = nil
        Task {
            do {
                try await Task.detached { try SyncManager.requestAccess(to: folder) }.value
                await sync.finishSetup(folder: folder, sessions: sessions, passwords: passwords,
                                       passphrase: needsNewPassphrase ? pass1 : nil, settings: settings,
                                       macros: macros, tunnels: tunnels)
                pass1 = ""; pass2 = ""; changePassphrase = false
                working = false
                step = .done
            } catch {
                working = false
                accessError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func open(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }
}
