import Foundation

/// A saved command (snippet) that can be sent to the active terminal.
struct Macro: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var command: String
    var pressEnter = true
    var updatedAt = Date()
}

@MainActor
final class MacroStore: ObservableObject {
    static let shared = MacroStore()
    static let changed = Notification.Name("MacTermPlus.macrosChanged")

    @Published private(set) var macros: [Macro] = []
    private let url = AppPaths.supportDirectory.appendingPathComponent("macros.json")

    private init() {
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Macro].self, from: data) {
            macros = list
        } else {
            macros = [
                Macro(name: "System info", command: "uname -a && uptime"),
                Macro(name: "Disk usage", command: "df -h"),
                Macro(name: "Memory", command: "free -h"),
                Macro(name: "Top processes", command: "ps aux --sort=-%cpu | head -15"),
                Macro(name: "Listening ports", command: "ss -tulpn"),
                Macro(name: "Follow syslog", command: "sudo journalctl -f"),
            ]
            save(notify: false)
        }
    }

    func upsert(_ m: Macro) {
        var m = m
        m.updatedAt = Date()
        if let i = macros.firstIndex(where: { $0.id == m.id }) { macros[i] = m } else { macros.append(m) }
        save()
    }

    func delete(_ m: Macro) {
        macros.removeAll { $0.id == m.id }
        save()
    }

    func replaceAll(_ list: [Macro]) {
        macros = list
        save(notify: false)
    }

    var lastChange: Date { macros.map(\.updatedAt).max() ?? .distantPast }

    private func save(notify: Bool = true) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(macros).write(to: url, options: .atomic)
        if notify { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }
}
