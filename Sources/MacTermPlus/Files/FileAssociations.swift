import AppKit
import SwiftUI

/// "Always open .xml with Sublime Text": extension → app, used when a remote or local file is opened
/// without choosing an app. Kept in UserDefaults and synced with the other settings.
enum FileAssociations {
    static let key = "fileAssociations"
    static let changed = Notification.Name("MacTermPlus.fileAssociationsChanged")

    static func normalize(_ ext: String) -> String {
        ext.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    }

    static var all: [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    /// The chosen app for this file name, if it is still installed.
    static func app(for fileName: String) -> URL? {
        let name = fileName.lowercased()
        let ext = (name as NSString).pathExtension
        // Whole-name match first (e.g. "nginx.conf"), then the extension.
        let path = all[name] ?? (ext.isEmpty ? nil : all[ext])
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    @MainActor
    static func set(_ ext: String, app: URL?) {
        let e = normalize(ext)
        guard !e.isEmpty else { return }
        var d = all
        d[e] = app?.path
        UserDefaults.standard.set(d, forKey: key)
        AppSettings.shared.objectWillChange.send()   // counts as a settings change for sync
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

/// Settings → Files: the extension → app table.
struct FileAssociationsSection: View {
    @ViewState private var rows: [(String, String)] = []
    @ViewState private var newExt = ""

    var body: some View {
        Section {
            if rows.isEmpty {
                Text("No file types yet. Files open in the app macOS normally uses for them.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.0) { r in row(ext: r.0, path: r.1) }
            HStack {
                TextField("Extension", text: $newExt, prompt: Text(".xml, .log, nginx.conf"))
                    .textFieldStyle(.roundedBorder).labelsHidden().frame(width: 200)
                    .onSubmit(add)
                Button("Choose App…", action: add).disabled(FileAssociations.normalize(newExt).isEmpty)
                Spacer()
            }
        } header: {
            Text("Open file types with")
        } footer: {
            Text("Used when you double-click a file. “Open With” in the right-click menu still lets you pick any app.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: FileAssociations.changed)) { _ in reload() }
    }

    private func row(ext: String, path: String) -> some View {
        let exists = FileManager.default.fileExists(atPath: path)
        let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        let label: String = ext.contains(".") ? ext : "." + ext
        return HStack(spacing: 10) {
            Text(label).font(.body.monospaced()).frame(width: 110, alignment: .leading)
            Image(nsImage: icon(path)).resizable().frame(width: 18, height: 18)
            Text(name).foregroundStyle(exists ? Color.primary : Color.red)
            Spacer()
            Button { choose(ext) } label: { Image(systemName: "pencil") }
                .help("Choose another app")
            Button { FileAssociations.set(ext, app: nil) } label: { Image(systemName: "trash").foregroundStyle(.red) }
                .help("Remove")
        }
        .buttonStyle(.borderless)
        .help(path)
    }

    private func choose(_ ext: String) {
        if let app = OpenWith.chooseApp() { FileAssociations.set(ext, app: app) }
    }

    private func add() {
        let e = FileAssociations.normalize(newExt)
        guard !e.isEmpty, let app = OpenWith.chooseApp() else { return }
        FileAssociations.set(e, app: app)
        newExt = ""
    }

    private func reload() { rows = FileAssociations.all.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }

    private func icon(_ path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }
}
