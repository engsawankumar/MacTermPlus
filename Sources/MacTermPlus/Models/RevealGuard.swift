import AppKit
import LocalAuthentication
import SwiftUI

/// Guards showing or copying saved passwords: Touch ID or the Mac login password every time it is locked.
/// After a successful check it stays unlocked for one minute, and locks at once when MacTerm+ goes to the background.
@MainActor
final class RevealGuard: ObservableObject {
    static let shared = RevealGuard()
    static let unlockSeconds: TimeInterval = 60
    static let clipboardSeconds: TimeInterval = 60

    @Published private(set) var unlockedUntil: Date?
    private var timer: Timer?

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { RevealGuard.shared.lock() }
        }
    }

    var isUnlocked: Bool { (unlockedUntil ?? .distantPast) > Date() }

    func lock() {
        unlockedUntil = nil
        timer?.invalidate()
        timer = nil
    }

    /// Asks for Touch ID / the Mac password unless already unlocked. Returns true when allowed.
    func unlock(reason: String) async -> Bool {
        if isUnlocked { return true }
        if Showcase.isOn { return false }   // screenshots never show real secrets
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        guard ok else { return false }
        unlockedUntil = Date().addingTimeInterval(Self.unlockSeconds)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.unlockSeconds, repeats: false) { _ in
            MainActor.assumeIsolated { RevealGuard.shared.lock() }
        }
        return true
    }

    /// Copies a secret and clears the clipboard after a minute (if it still holds that secret).
    static func copy(_ secret: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(secret, forType: .string)
        // Ask clipboard managers not to keep it.
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let count = pb.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + clipboardSeconds) {
            if NSPasteboard.general.changeCount == count { NSPasteboard.general.clearContents() }
        }
    }
}

/// A password field with an eye button. Showing a saved password needs Touch ID or the Mac password;
/// what you type yourself can be shown freely. Hidden again after 30 seconds.
struct RevealableSecretField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    /// The saved value: showing it needs authentication.
    var savedValue: String?
    @ViewState private var visible = false
    @ViewState private var hideTask: Task<Void, Never>?
    @ViewState private var denied = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if visible {
                    TextField(title, text: $text, prompt: Text(prompt)).font(.body.monospaced())
                        .autocorrectionDisabled()
                } else {
                    SecureField(title, text: $text, prompt: Text(prompt))
                }
            }
            Button { Task { await toggle() } } label: {
                Image(systemName: visible ? "eye.slash" : "eye").foregroundStyle(denied ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(text.isEmpty)
            .help(visible ? "Hide" : "Show (asks for Touch ID or your Mac password)")
        }
        .onDisappear { visible = false; hideTask?.cancel() }
    }

    private func toggle() async {
        if visible { visible = false; return }
        let isSaved = savedValue != nil && savedValue == text
        if isSaved {
            guard await RevealGuard.shared.unlock(reason: "show a saved password") else { flashDenied(); return }
        }
        visible = true
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled { visible = false }
        }
    }

    private func flashDenied() {
        denied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { denied = false }
    }
}
