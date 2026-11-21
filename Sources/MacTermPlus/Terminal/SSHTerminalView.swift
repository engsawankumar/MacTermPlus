import AppKit
import Citadel
import NIOCore
import NIOSSH
import SwiftTerm
import SwiftUI

/// Drives one interactive shell over SSH and renders it with SwiftTerm.
@MainActor
final class SSHTerminalController: NSObject, ObservableObject, TerminalViewDelegate {
    let terminalView: TerminalView
    lazy var container = TerminalContainer(terminal: terminalView)
    private var contextMenu: TerminalMenu?
    private let connection: SSHConnection
    private var writer: TTYStdinWriter?
    private var sessionTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<ByteBuffer>.Continuation?
    private var cols = 80
    private var rows = 24
    @Published private(set) var isRunning = false
    /// True once a shell session has ended (exit, error or drop) — drives the Reconnect button.
    @Published private(set) var hasEnded = false
    /// True once the remote shell channel is open (other channels can safely be opened after this).
    @Published private(set) var ptyReady = false
    /// Called with the shell's working directory when it changes (OSC 7), for "Follow terminal folder".
    var onDirectoryChange: ((String) -> Void)?

    init(connection: SSHConnection) {
        self.connection = connection
        terminalView = MTPTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        super.init()
        contextMenu = TerminalMenu(terminal: terminalView)
        let themeID = connection.profile.themeID
        Appearance.apply(to: terminalView, themeID: themeID)
        terminalView.backspaceSendsControlH = connection.profile.backspaceCtrlH
        terminalView.terminalDelegate = self
        MultiExec.shared.register(terminalView)
        NotificationCenter.default.addObserver(forName: AppSettings.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let v = self?.terminalView { Appearance.apply(to: v, themeID: themeID) } }
        }
    }

    func start() {
        if Showcase.isOn {   // README screenshots: demo output, no connection
            printBanner()
            terminalView.feed(text: Showcase.terminalText())
            return
        }
        guard !isRunning else { return }
        isRunning = true
        hasEnded = false
        // A fresh input stream per session: a cancelled consumer permanently finishes an AsyncStream.
        let (input, continuation) = AsyncStream<ByteBuffer>.makeStream()
        inputContinuation = continuation
        printBanner()

        sessionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try await connection.connectedClient()
                let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: cols,
                    terminalRowHeight: rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: SSHTerminalModes([:])
                )
                try await SSHConnection.ignoringRemoteClose { try await client.withPTY(request) { inbound, outbound in
                    await MainActor.run { self.writer = outbound; self.ptyReady = true }
                    // The view may have been resized while connecting.
                    let (c, r) = await MainActor.run { (self.cols, self.rows) }
                    try? await outbound.changeSize(cols: c, rows: r, pixelWidth: 0, pixelHeight: 0)
                    if await MainActor.run(body: { AppSettings.shared.followTerminalFolder }) {
                        // Let the login banner and prompt arrive first, then install the folder reporter.
                        try? await Task.sleep(for: .milliseconds(1200))
                        let snippet = await MainActor.run { self.followFolderSnippet() }
                        try? await outbound.write(ByteBuffer(string: snippet))
                    }
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await chunk in input { try await outbound.write(chunk) }
                        }
                        group.addTask {
                            for try await output in inbound {
                                switch output {
                                case .stdout(let buffer), .stderr(let buffer):
                                    let bytes = Array(buffer.readableBytesView)
                                    await MainActor.run { self.terminalView.feed(byteArray: bytes[...]) }
                                }
                            }
                        }
                        // The shell ending (inbound finishes) ends the session.
                        try await group.next()
                        group.cancelAll()
                    }
                } }
                feedLine("\r\n\u{1b}[33m[Session closed]\u{1b}[0m")
            } catch is CancellationError {
                // tab closed
            } catch {
                feedLine("\r\n\u{1b}[31m[Error] \(SSHConnection.describe(error))\u{1b}[0m")
            }
            writer = nil
            inputContinuation?.finish()
            inputContinuation = nil
            isRunning = false
            hasEnded = true
        }
    }

    func stop() {
        sessionTask?.cancel()
        inputContinuation?.finish()
    }

    private func feedLine(_ text: String) {
        terminalView.feed(text: text + "\r\n")
    }

    /// Sends text (a macro, a pasted command) as if typed.
    func sendText(_ text: String) {
        terminalView.send(txt: text)
    }

    /// Info box shown at the top of each SSH session.
    private func printBanner() {
        let p = connection.profile
        let s = AppSettings.shared
        let check = "\u{1b}[32m✔\u{1b}[0m", cross = "\u{1b}[90m–\u{1b}[0m"
        let lines: [(String, Int)] = [
            ("\u{1b}[1;36m• MacTerm+ \(AppInfo.version) •\u{1b}[0m", 13 + AppInfo.version.count),
            ("\u{1b}[33m(SSH client, SFTP/FTP browser and tools)\u{1b}[0m", 40),
            ("\u{1b}[90m\(AppInfo.credit)\u{1b}[0m", AppInfo.credit.count),
            ("", 0),
            ("➤ SSH session to \u{1b}[1;35m\(p.username)@\(p.host)\u{1b}[0m\(p.port == 22 ? "" : ":\(p.port)")",
             17 + p.username.count + 1 + p.host.count + (p.port == 22 ? 0 : String(p.port).count + 1)),
            ("  • SFTP browser       : \(check)", 26),
            ("  • Remote monitoring  : \(s.showStatusBar ? check : cross)", 26),
            ("  • Follow folder      : \(s.followTerminalFolder ? check : cross)", 26),
            ("  • MultiExec          : \(MultiExec.shared.enabled ? check : cross)", 26),
            ("", 0),
            ("➤ Help: ⌘?   Macros: sidebar   Settings: ⌘,", 43),
        ]
        let width = max(54, (lines.map(\.1).max() ?? 0) + 4)
        let bar = String(repeating: "─", count: width)
        var out = "\u{1b}[90m┌\(bar)┐\u{1b}[0m\r\n"
        for (i, (text, len)) in lines.enumerated() {
            let centered = i < 3
            let pad = max(0, width - len - 2)
            let left = centered ? pad / 2 : 0
            out += "\u{1b}[90m│\u{1b}[0m " + String(repeating: " ", count: left) + text
                + String(repeating: " ", count: pad - left) + " \u{1b}[90m│\u{1b}[0m\r\n"
        }
        out += "\u{1b}[90m└\(bar)┘\u{1b}[0m\r\n\r\n"
        terminalView.feed(text: out)
    }

    /// Shell snippet that reports the working directory after every command (OSC 7), then erases
    /// its own echoed line so the terminal stays clean. Works in bash and zsh; harmless elsewhere.
    private func followFolderSnippet() -> String {
        let cmd = #" __mtp_cwd(){ printf '\033]7;file://%s%s\007' "${HOSTNAME:-}" "$PWD"; }; if [ -n "$ZSH_VERSION" ]; then precmd_functions+=(__mtp_cwd); else PROMPT_COMMAND="__mtp_cwd${PROMPT_COMMAND:+;$PROMPT_COMMAND}"; fi; __mtp_cwd"#
        let echoedLines = max(1, Int((Double(cmd.count + 40) / Double(max(cols, 20))).rounded(.up)))
        let erase = String(repeating: #"\033[1A\033[2K"#, count: echoedLines)
        return cmd + #"; printf '"# + erase + #"\r'"# + "\n"
    }

    // MARK: TerminalViewDelegate

    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let buffer = ByteBuffer(bytes: data)
        MainActor.assumeIsolated {
            _ = inputContinuation?.yield(buffer)
            if source.window?.firstResponder === source { MultiExec.shared.mirror(data, from: source) }
        }
    }

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        MainActor.assumeIsolated {
            cols = newCols
            rows = newRows
            guard let writer else { return }
            Task { try? await writer.changeSize(cols: newCols, rows: newRows, pixelWidth: 0, pixelHeight: 0) }
        }
    }

    nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        // OSC 7 gives "file://host/path"; plain paths are accepted too.
        let path = URL(string: directory)?.path.removingPercentEncoding ?? directory
        guard path.hasPrefix("/") else { return }
        MainActor.assumeIsolated { onDirectoryChange?(path) }
    }
    nonisolated func scrolled(source: TerminalView, position: Double) {}
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        if let text = String(data: content, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

struct SSHTerminalRepresentable: NSViewRepresentable {
    let controller: SSHTerminalController

    func makeNSView(context: Context) -> TerminalContainer {
        controller.start()
        return controller.container
    }

    func updateNSView(_ nsView: TerminalContainer, context: Context) {}
}
