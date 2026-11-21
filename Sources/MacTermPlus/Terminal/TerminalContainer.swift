import AppKit
import SwiftTerm

/// Hosts a terminal view with padding around it, painted in the theme's background color.
final class TerminalContainer: NSView {
    let terminal: TerminalView
    private var observer: NSObjectProtocol?

    init(terminal: TerminalView) {
        self.terminal = terminal
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        wantsLayer = true
        addSubview(terminal)
        applyTheme()
        observer = NotificationCenter.default.addObserver(forName: AppSettings.changed, object: nil, queue: .main) { [weak self] _ in
            // Run after the terminal itself re-applied its theme.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.applyTheme()
                    self?.needsLayout = true
                }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override var isFlipped: Bool { true }

    @MainActor private func applyTheme() {
        // Match whatever theme the terminal uses (the app default or the session's own theme).
        layer?.backgroundColor = terminal.nativeBackgroundColor.cgColor
    }

    override func layout() {
        super.layout()
        let pad = CGFloat(MainActor.assumeIsolated { AppSettings.shared.terminalPadding })
        let frame = bounds.insetBy(dx: pad, dy: pad * 0.75)
        if terminal.frame != frame { terminal.frame = frame }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Give the terminal keyboard focus when its tab appears.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self.terminal)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(terminal)
    }
}
