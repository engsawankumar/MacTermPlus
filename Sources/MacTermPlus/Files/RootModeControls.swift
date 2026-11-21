import SwiftUI

/// "Browse as root (sudo)" switch, with a password prompt when sudo needs one.
struct RootModeToggle: View {
    @ObservedObject var browser: RemoteFileBrowser
    var label = "Browse as root (sudo)"
    var asButton = false
    @ViewState private var askPassword = false
    @ViewState private var password = ""
    @ViewState private var working = false
    @ViewState private var error: String?

    var body: some View {
        Group {
            if asButton {
                Button { start() } label: { Label(label, systemImage: "lock.open.fill") }
                    .disabled(working)
            } else {
                Toggle(isOn: Binding(get: { browser.isRoot }, set: { on in if on { start() } else { Task { await browser.disableRoot() } } })) {
                    Label(label, systemImage: "bolt.shield.fill")
                }
                .disabled(working)
            }
        }
        .alert("sudo password", isPresented: $askPassword) {
            SecureField("Password", text: $password)
            Button("Continue") { let pw = password; password = ""; run(pw) }
            Button("Cancel", role: .cancel) { password = "" }
        } message: {
            Text(error ?? "Enter the sudo password for this server (usually your login password). It’s kept only in memory for this tab.")
        }
    }

    private func start() { run(nil) }

    private func run(_ pw: String?) {
        working = true
        Task {
            defer { working = false }
            do {
                try await browser.enableRoot(password: pw)
                error = nil
            } catch SudoError.needsPassword {
                error = nil; askPassword = true
            } catch SudoError.wrongPassword {
                error = "That password isn’t correct. Try again."; askPassword = true
            } catch {
                browser.errorMessage = SSHConnection.describe(error)
            }
        }
    }
}

/// Red badge shown while browsing as root.
struct RootBadge: View {
    var body: some View {
        Text("ROOT")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.red, in: Capsule())
            .help("Browsing as root with sudo — changes affect system files")
    }
}
