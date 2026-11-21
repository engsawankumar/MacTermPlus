import AppKit
import SwiftTerm

/// Shows what is about to be pasted and asks before sending several lines (each line runs as a command).
@MainActor
enum PasteGuard {
    static func confirm(_ text: String, in window: NSWindow?) -> Bool {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let lineCount = lines.count - (text.hasSuffix("\n") ? 1 : 0)
        guard AppSettings.shared.confirmMultilinePaste, lineCount > 1 else { return true }

        let alert = NSAlert()
        alert.messageText = "Paste \(lineCount) lines into the terminal?"
        alert.informativeText = "Each line is sent to the shell, so it may run as a command. Check the text below."
        alert.addButton(withTitle: "Paste")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask again"

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 170))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.string = text
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        alert.accessoryView = scroll

        let ok = alert.runModal() == .alertFirstButtonReturn
        if alert.suppressionButton?.state == .on { AppSettings.shared.confirmMultilinePaste = false }
        return ok
    }

    /// Short description of the clipboard for the context menu.
    static func preview(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let first = lines.first else { return "" }
        var snippet = String(first).trimmingCharacters(in: .whitespaces)
        if snippet.count > 38 { snippet = String(snippet.prefix(38)) + "…" }
        return lines.count > 1 ? "\(lines.count) lines: “\(snippet)”" : "“\(snippet)”"
    }
}

/// SSH terminal view with the paste preview.
final class MTPTerminalView: TerminalView {
    override func paste(_ sender: Any) {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard MainActor.assumeIsolated({ PasteGuard.confirm(text, in: window) }) else { return }
        super.paste(sender)
    }
}

/// Local shell view with the paste preview.
final class MTPLocalTerminalView: LocalProcessTerminalView {
    override func paste(_ sender: Any) {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard MainActor.assumeIsolated({ PasteGuard.confirm(text, in: window) }) else { return }
        super.paste(sender)
    }
}

/// Right-click menu for terminals: copy, paste (with a preview of the clipboard), macros and more.
@MainActor
final class TerminalMenu: NSObject, NSMenuDelegate {
    private weak var terminal: TerminalView?
    private let menu = NSMenu()

    init(terminal: TerminalView) {
        self.terminal = terminal
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        terminal.menu = menu
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { rebuild() }
    }

    private func item(_ title: String, _ action: Selector, key: String = "", symbol: String? = nil, enabled: Bool = true) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.isEnabled = enabled
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    private func rebuild() {
        menu.removeAllItems()
        guard let terminal else { return }
        let selection = terminal.getSelection() ?? ""
        let clip = NSPasteboard.general.string(forType: .string) ?? ""

        menu.addItem(item("Copy", #selector(copyText), key: "c", symbol: "doc.on.doc", enabled: !selection.isEmpty))
        let paste = item(clip.isEmpty ? "Paste" : "Paste \(PasteGuard.preview(clip))", #selector(pasteText), key: "v",
                         symbol: "doc.on.clipboard", enabled: !clip.isEmpty)
        if !clip.isEmpty { paste.toolTip = String(clip.prefix(600)) }
        menu.addItem(paste)
        if !selection.isEmpty {
            menu.addItem(item("Paste Selection", #selector(pasteSelection), symbol: "text.insert"))
        }
        menu.addItem(item("Select All", #selector(selectAllText), key: "a", symbol: "selection.pin.in.out"))
        menu.addItem(.separator())
        menu.addItem(item("Clear Scrollback", #selector(clearScrollback), symbol: "eraser"))
        menu.addItem(item("Send Ctrl-C (interrupt)", #selector(sendInterrupt), symbol: "stop.circle"))
        menu.addItem(.separator())

        let macros = MacroStore.shared.macros
        if !macros.isEmpty {
            let sub = NSMenu()
            for m in macros {
                let mi = item(m.name, #selector(runMacro(_:)), symbol: "paperplane")
                mi.representedObject = m.id
                mi.toolTip = m.command
                sub.addItem(mi)
            }
            let parent = NSMenuItem(title: "Run Macro", action: nil, keyEquivalent: "")
            parent.image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil)
            parent.submenu = sub
            menu.addItem(parent)
        }
        menu.addItem(item("Bigger Text", #selector(biggerText), symbol: "textformat.size.larger"))
        menu.addItem(item("Smaller Text", #selector(smallerText), symbol: "textformat.size.smaller"))
        menu.addItem(.separator())
        menu.addItem(item("Terminal Settings…", #selector(openSettings), symbol: "gearshape"))
    }

    @objc private func copyText() { terminal?.copy(self) }
    @objc private func pasteText() { terminal?.paste(self) }
    @objc private func selectAllText() { terminal?.selectAll(nil) }
    @objc private func clearScrollback() { terminal?.clearScrollback() }
    @objc private func sendInterrupt() { terminal?.send([0x03]) }

    @objc private func pasteSelection() {
        guard let terminal, let text = terminal.getSelection(), !text.isEmpty else { return }
        if PasteGuard.confirm(text, in: terminal.window) { terminal.send(txt: text) }
    }

    @objc private func runMacro(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let m = MacroStore.shared.macros.first(where: { $0.id == id }) else { return }
        terminal?.send(txt: m.command + (m.pressEnter ? "\r" : ""))
    }

    @objc private func biggerText() { AppSettings.shared.fontSize = min(28, AppSettings.shared.fontSize + 1) }
    @objc private func smallerText() { AppSettings.shared.fontSize = max(9, AppSettings.shared.fontSize - 1) }
    @objc private func openSettings() { NotificationCenter.default.post(name: .showSettings, object: nil) }
}
