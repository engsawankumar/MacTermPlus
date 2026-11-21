import AppKit
import SwiftTerm

/// MultiExec: when on, keys typed in one terminal are also sent to every other open terminal.
@MainActor
final class MultiExec: ObservableObject {
    static let shared = MultiExec()

    @Published var enabled = false

    private final class Weak { weak var view: TerminalView?; init(_ v: TerminalView) { view = v } }
    private var views: [Weak] = []
    private var broadcasting = false

    func register(_ view: TerminalView) {
        views.removeAll { $0.view == nil }
        views.append(Weak(view))
    }

    /// Mirror input typed in `source` to the other terminals.
    func mirror(_ data: ArraySlice<UInt8>, from source: TerminalView) {
        guard enabled, !broadcasting else { return }
        broadcasting = true
        defer { broadcasting = false }
        for w in views {
            guard let v = w.view, v !== source, v.window != nil || v.superview != nil else { continue }
            v.send(data: data)
        }
    }

    var terminalCount: Int { views.filter { $0.view != nil }.count }
}
