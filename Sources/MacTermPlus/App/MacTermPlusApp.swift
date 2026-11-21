import AppKit
import Logging
import SwiftUI

@main
struct MacTermPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = SessionStore()
    @StateObject private var workspace = Workspace()

    init() {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .warning
            return handler
        }
        SelfTest.runIfRequested()
    }

    var body: some Scene {
        Window("MacTerm+", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(workspace)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)

        Settings {
            SettingsView()
                .environmentObject(store)
        }

        Window("About MacTerm+", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window("Welcome to MacTerm+", id: "welcome") {
            WelcomeWindowView()
        }
        .windowResizability(.contentSize)

        Window("Software Update", id: "update") {
            UpdateView()
        }
        .windowResizability(.contentSize)

        Window("Keychain", id: "keychain") {
            KeychainWindow()
                .environmentObject(store)
        }
        .defaultSize(width: 980, height: 640)

        Window("Set Up Sync", id: "sync-setup") {
            SyncSetupView()
        }
        .windowResizability(.contentSize)

        Window("MacTerm+ Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session…") {
                    NotificationCenter.default.post(name: .newSession, object: nil)
                }
                .keyboardShortcut("n")
                Button("New Local Shell") { workspace.openLocal() }
                    .keyboardShortcut("t")
                Divider()
                Button("Import Sessions…") { NotificationCenter.default.post(name: .importSessions, object: nil) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Export Sessions…") { NotificationCenter.default.post(name: .exportSessions, object: nil) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Close Tab") { workspace.closeSelected() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(workspace.selected == nil)
            }
            CommandGroup(replacing: .appInfo) {
                AboutMenuItem()
            }
            CommandGroup(replacing: .help) {
                HelpMenuItems()
            }
            CommandGroup(after: .sidebar) {
                Button("Quick Commands") { AppSettings.shared.showQuickCommands.toggle() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                KeychainMenuButton()
                Button("Search Quick Commands") {
                    AppSettings.shared.showQuickCommands = true
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .focusQuickCommandSearch, object: nil) }
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                Divider()
            }
            CommandMenu("Tabs") {
                Button("Next Tab") { workspace.selectNext(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { workspace.selectNext(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (swift run) so the window gets focus and a Dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private struct HelpMenuItems: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("MacTerm+ Help") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
        Button("Welcome to MacTerm+") { openWindow(id: "welcome") }
        Button("Keyboard Shortcuts") { openWindow(id: "help") }
        Divider()
        Button("Show Data Folder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory]) }
        Button("Third-Party Licenses") {
            if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

private struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("About MacTerm+") { openWindow(id: "about") }
        Button("Check for Updates…") { openWindow(id: "update") }
    }
}

/// "Built by Bairagi" pill used on the Home screen and in About.
struct BuiltByBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hammer.fill")
                .foregroundStyle(LinearGradient(colors: [Color(hex: "12C2E9"), Color(hex: "C471ED"), Color(hex: "F64F59")],
                                                startPoint: .leading, endPoint: .trailing))
            Text("Built by ").foregroundStyle(.secondary) + Text(AppInfo.developer).fontWeight(.semibold)
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

struct AboutView: View {
    @ObservedObject var settings = AppSettings.shared
    var body: some View {
        VStack(spacing: 12) {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().frame(width: 110, height: 110)
            } else {
                IconTile(symbol: "terminal.fill", color: .teal, size: 90)
            }
            Text("MacTerm+").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Version \(AppInfo.version)").font(.callout).foregroundStyle(.secondary)
            BuiltByBadge()
            Text("SSH terminal, SFTP & FTP file manager, tunnels, macros and sync for macOS.")
                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button("Third-Party Licenses") {
                    if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link)
            }
            Text("© \(Calendar.current.component(.year, from: Date())) \(AppInfo.developer). All rights reserved.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 380)
        .tint(settings.accent.color)
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

/// View ▸ Keychain… (keys, identities, known hosts, passwords).
private struct KeychainMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Keychain…") { openWindow(id: "keychain") }
            .keyboardShortcut("k", modifiers: [.command, .option])
    }
}
