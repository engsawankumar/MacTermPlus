import AppKit
import SwiftUI

/// Export sessions to a file.
struct ExportSessionsView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var format: ExportFormat = .json
    @ViewState private var done: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up.on.square.fill").font(.title).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Export Sessions").font(.title2.bold())
                    Text("\(store.sessions.count) saved session\(store.sessions.count == 1 ? "" : "s"). Passwords and passphrases are never exported.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Picker("Format", selection: $format) {
                ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            if format == .applePasswords {
                VStack(alignment: .leading, spacing: 4) {
                    Label("This file contains your passwords in plain text.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout.weight(.semibold))
                    Text("Next: open the Passwords app → File → Import Passwords… → choose this file. Your servers then sync to all your Apple devices with iCloud Keychain. Delete the CSV afterwards (move it to the Bin and empty it).")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            if let done {
                Label(done, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            HStack {
                Spacer()
                Button(done == nil ? "Cancel" : "Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Export…") { export() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.sessions.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = format.fileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SessionExporter.export(store.sessions, as: format).write(to: url, options: .atomic)
            done = "Saved \(url.lastPathComponent)"
        } catch {
            done = nil
            NSAlert(error: error).runModal()
        }
    }
}
