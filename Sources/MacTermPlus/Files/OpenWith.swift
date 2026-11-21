import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Finds apps that can open a file, for the "Open With" menu.
enum OpenWith {
    struct App: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
        var name: String { FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
        var icon: NSImage {
            let img = NSWorkspace.shared.icon(forFile: url.path)
            img.size = NSSize(width: 16, height: 16)
            return img
        }
    }

    /// Editors offered for every file, when installed (handy for config files with odd extensions).
    private static let editorBundleIDs = [
        "com.apple.TextEdit", "com.microsoft.VSCode", "com.sublimetext.4", "com.sublimetext.3",
        "com.barebones.bbedit", "com.coteditor.CotEditor", "com.panic.Nova", "dev.zed.Zed", "com.apple.dt.Xcode",
    ]

    static func type(for fileName: String) -> UTType {
        let ext = (fileName as NSString).pathExtension
        return (ext.isEmpty ? nil : UTType(filenameExtension: ext)) ?? .plainText
    }

    static func defaultApp(for fileName: String) -> App? {
        NSWorkspace.shared.urlForApplication(toOpen: type(for: fileName)).map(App.init(url:))
    }

    /// Apps registered for this file type, plus installed text editors. Default app first, no duplicates.
    static func apps(for fileName: String) -> (suggested: [App], editors: [App]) {
        let t = type(for: fileName)
        let def = NSWorkspace.shared.urlForApplication(toOpen: t)
        var seen = Set<String>()
        var suggested: [App] = []
        for url in ([def].compactMap { $0 } + NSWorkspace.shared.urlsForApplications(toOpen: t)) {
            let key = url.resolvingSymlinksInPath().path
            if seen.insert(key).inserted { suggested.append(App(url: url)) }
        }
        var editors: [App] = []
        for id in editorBundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            if seen.insert(url.resolvingSymlinksInPath().path).inserted { editors.append(App(url: url)) }
        }
        let suggestedSorted = suggested.prefix(1) + suggested.dropFirst().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (Array(suggestedSorted.prefix(15)), editors)
    }

    static func open(_ file: URL, with app: URL?) {
        guard let app else {
            NSWorkspace.shared.open(file)
            return
        }
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Lets the user pick any app from /Applications.
    @MainActor
    static func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Open"
        panel.message = "Choose an app to open this file with"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// "Open With ▸" submenu used in file context menus.
struct OpenWithMenu: View {
    let fileName: String
    let action: (URL?) -> Void

    var body: some View {
        Menu("Open With") {
            let (suggested, editors) = OpenWith.apps(for: fileName)
            ForEach(Array(suggested.enumerated()), id: \.element) { index, app in
                Button { action(app.url) } label: {
                    Label { Text(index == 0 ? "\(app.name) (default)" : app.name) } icon: { Image(nsImage: app.icon) }
                }
            }
            if !editors.isEmpty {
                Divider()
                ForEach(editors) { app in
                    Button { action(app.url) } label: {
                        Label { Text(app.name) } icon: { Image(nsImage: app.icon) }
                    }
                }
            }
            Divider()
            Button("Other…") { if let app = OpenWith.chooseApp() { action(app) } }
        }
    }
}
