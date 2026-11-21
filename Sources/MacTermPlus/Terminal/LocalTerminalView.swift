import AppKit
import SwiftTerm
import SwiftUI

/// A local shell tab (your Mac's own zsh), like MobaXterm's local terminal.
@MainActor
final class LocalTerminalController: NSObject, LocalProcessTerminalViewDelegate {
    let terminalView: LocalProcessTerminalView
    lazy var container = TerminalContainer(terminal: terminalView)
    private var contextMenu: TerminalMenu?
    private var started = false

    override init() {
        terminalView = MTPLocalTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        super.init()
        contextMenu = TerminalMenu(terminal: terminalView)
        Appearance.apply(to: terminalView)
        terminalView.processDelegate = self
        MultiExec.shared.register(terminalView)
        NotificationCenter.default.addObserver(forName: AppSettings.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let v = self?.terminalView { Appearance.apply(to: v) } }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("LANG=en_US.UTF-8")
        FileManager.default.changeCurrentDirectoryPath(NSHomeDirectory())
        terminalView.startProcess(executable: shell, args: ["-l"], environment: env, execName: "-" + (shell as NSString).lastPathComponent)
    }

    func sendText(_ text: String) {
        terminalView.send(txt: text)
    }

    func stop() {
        terminalView.terminate()
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            source.feed(text: "\r\n\u{1b}[33m[Process exited]\u{1b}[0m\r\n")
        }
    }
}

struct LocalTerminalRepresentable: NSViewRepresentable {
    let controller: LocalTerminalController

    func makeNSView(context: Context) -> TerminalContainer {
        controller.start()
        return controller.container
    }

    func updateNSView(_ nsView: TerminalContainer, context: Context) {}
}
