import SwiftUI

/// Settings section: choose where session passwords are kept.
struct PasswordStorageSection: View {
    @EnvironmentObject var store: SessionStore
    @ViewState private var storage = Keychain.storage
    @ViewState private var sheet: Sheet?
    @ViewState private var message: String?
    @ViewState private var refresh = 0

    enum Sheet: Identifiable {
        case create, unlockToSwitchBack, change, unlock
        var id: Int { hashValue }
    }

    private var accounts: [String] { store.sessions.map(\.keychainAccount) + ["sync-passphrase"] }

    var body: some View {
        Section("Where passwords are saved") {
            Picker("Store passwords in", selection: Binding(get: { storage }, set: { choose($0) })) {
                ForEach(Keychain.Storage.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Text(storage == .keychain
                 ? "Passwords live in the macOS Keychain, in a single item that belongs to MacTerm+, so macOS doesn’t ask for permission."
                 : "Passwords live in an encrypted file only MacTerm+ reads (AES-256). You type your master password once each time MacTerm+ opens; there are no Keychain prompts. If you forget it, the saved passwords can’t be recovered.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if storage == .vault {
                HStack {
                    let v = PasswordVault.shared
                    Label(v.isUnlocked ? "Unlocked · \(v.count) saved" : "Locked",
                          systemImage: v.isUnlocked ? "lock.open.fill" : "lock.fill")
                        .foregroundStyle(v.isUnlocked ? .green : .orange)
                    Spacer()
                    if v.isUnlocked {
                        Button("Lock Now") { v.lockNow(); refresh += 1 }
                    } else {
                        Button("Unlock…") { sheet = .unlock }
                    }
                    Button("Change Master Password…") { sheet = .change }
                }
                .id(refresh)
            }
            if let message { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout) }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .create:
                MasterPasswordSheet(mode: .create) { pw in
                    try PasswordVault.shared.create(master: pw)
                    let n = Keychain.moveSecrets(to: .vault, accounts: accounts)
                    storage = .vault
                    message = "Moved \(n) password\(n == 1 ? "" : "s") into the MacTerm+ vault."
                }
            case .unlockToSwitchBack:
                MasterPasswordSheet(mode: .unlock) { pw in
                    try PasswordVault.shared.unlock(master: pw)
                    let n = Keychain.moveSecrets(to: .keychain, accounts: accounts)
                    if PasswordVault.shared.count == 0 { PasswordVault.shared.destroy() }
                    storage = .keychain
                    message = "Moved \(n) password\(n == 1 ? "" : "s") back to the macOS Keychain."
                }
            case .unlock:
                MasterPasswordSheet(mode: .unlock) { pw in
                    try PasswordVault.shared.unlock(master: pw)
                    refresh += 1
                }
            case .change:
                MasterPasswordSheet(mode: .change) { pw, old in
                    try PasswordVault.shared.changeMaster(from: old, to: pw)
                    message = "Master password changed."
                    refresh += 1
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: PasswordVault.changed)) { _ in refresh += 1 }
    }

    private func choose(_ target: Keychain.Storage) {
        guard target != storage else { return }
        message = nil
        if target == .vault {
            sheet = .create
        } else if PasswordVault.shared.isUnlocked {
            let n = Keychain.moveSecrets(to: .keychain, accounts: accounts)
            if PasswordVault.shared.count == 0 { PasswordVault.shared.destroy() }
            storage = .keychain
            message = "Moved \(n) password\(n == 1 ? "" : "s") back to the macOS Keychain."
        } else if PasswordVault.shared.exists {
            sheet = .unlockToSwitchBack
        } else {
            Keychain.storage = .keychain
            storage = .keychain
        }
    }
}

/// Create / unlock / change the master password.
struct MasterPasswordSheet: View {
    enum Mode { case create, unlock, change }
    let mode: Mode
    var onDone: ((String) throws -> Void)?
    var onChange: ((String, String) throws -> Void)?
    var onForgot: (() -> Void)?
    var onSkip: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @ViewState private var old = ""
    @ViewState private var first = ""
    @ViewState private var second = ""
    @ViewState private var error: String?
    @ViewState private var confirmForget = false

    init(mode: Mode, onSkip: (() -> Void)? = nil, onForgot: (() -> Void)? = nil, _ done: @escaping (String) throws -> Void) {
        self.mode = mode; self.onDone = done; self.onSkip = onSkip; self.onForgot = onForgot
    }

    init(mode: Mode, _ change: @escaping (String, String) throws -> Void) {
        self.mode = mode; self.onChange = change
    }

    private var valid: Bool {
        switch mode {
        case .unlock: return !first.isEmpty
        case .create: return first.count >= 8 && first == second
        case .change: return !old.isEmpty && first.count >= 8 && first == second
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(symbol: mode == .unlock ? "lock.fill" : "key.fill", color: .indigo, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode == .create ? "Create Master Password" : mode == .change ? "Change Master Password" : "Unlock Passwords")
                        .font(.title2.bold())
                    Text(mode == .unlock ? "Enter your MacTerm+ master password to use your saved server passwords."
                                         : "It protects all your saved server passwords. It can’t be recovered if you forget it.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if mode == .change {
                SecureField("Current master password", text: $old).textFieldStyle(.roundedBorder)
            }
            SecureField(mode == .unlock ? "Master password" : "New master password (8+ characters)", text: $first)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if valid { submit() } }
            if mode != .unlock {
                SecureField("Repeat it", text: $second).textFieldStyle(.roundedBorder).onSubmit { if valid { submit() } }
                if !second.isEmpty && first != second { Text("The two entries don’t match.").font(.caption).foregroundStyle(.orange) }
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout) }
            HStack {
                if mode == .unlock, onForgot != nil {
                    Button("Forgot Master Password…") { confirmForget = true }.buttonStyle(.link)
                }
                Spacer()
                if let onSkip {
                    Button("Not Now") { onSkip(); dismiss() }
                } else {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                Button(mode == .unlock ? "Unlock" : "Save") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
        }
        .padding(22)
        .frame(width: 440)
        .confirmationDialog("Erase all passwords saved in MacTerm+?", isPresented: $confirmForget) {
            Button("Erase Saved Passwords", role: .destructive) { onForgot?(); dismiss() }
        } message: {
            Text("Your sessions stay. You’ll be asked for each server’s password when you connect, and can save it again with a new master password.")
        }
    }

    private func submit() {
        do {
            if mode == .change { try onChange?(first, old) } else { try onDone?(first) }
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if mode == .unlock { first = "" }
        }
    }
}
