import AppKit
import SwiftUI

/// Right-hand "Host Details" panel: edit a saved session in place. Changes are saved as you type.
struct HostDetailsPanel: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var workspace: Workspace
    @ObservedObject private var identities = IdentityStore.shared
    @Environment(\.openWindow) private var openWindow
    let sessionID: UUID
    var connect: (SessionProfile) -> Void

    @ViewState private var draft = SessionProfile()
    @ViewState private var loadedID: UUID?
    /// The session as last loaded or saved; only real edits (draft ≠ baseline) are written.
    @ViewState private var baseline = SessionProfile()
    @ViewState private var secret = ""
    @ViewState private var storedSecret: String?
    @ViewState private var showMore = false
    @ViewState private var newTag = ""
    @ViewState private var saveTask: Task<Void, Never>?
    @ViewState private var secretTask: Task<Void, Never>?
    @ViewState private var confirmDelete = false
    @ViewState private var savedFlash = false

    private var identity: Identity? { identities.identity(draft.identityID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.sessions.contains(where: { $0.id == sessionID }) {
                ScrollView {
                    VStack(spacing: 12) {
                        addressCard
                        generalCard
                        connectionCard
                        credentialsCard
                        moreCard
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                }
                Divider()
                footer
            } else {
                Spacer()
                Text("This session was deleted.").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .background(.background)
        .onAppear { load(sessionID) }
        .onChange(of: sessionID) { old, new in commitNow(); load(new) }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onChange(of: draft.identityID) { _, _ in
            if let i = identity { draft.username = i.username; draft.auth = i.auth; draft.keyPath = i.keyPath }
        }
        .onChange(of: secret) { _, _ in scheduleSecretSave() }
        .onDisappear { commitNow() }
        .onReceive(NotificationCenter.default.publisher(for: SessionStore.changed)) { _ in
            // Changed elsewhere (sync, sidebar menu) while not being edited here: show the new values.
            if draft == baseline, let p = store.sessions.first(where: { $0.id == sessionID }), p != baseline {
                draft = p; baseline = p
            }
        }
        .confirmationDialog("Delete “\(draft.displayName)”?", isPresented: $confirmDelete) {
            Button("Delete Session", role: .destructive) {
                saveTask?.cancel(); secretTask?.cancel()
                store.delete(draft)
                workspace.inspectedID = nil
            }
        } message: { Text("Its saved password is removed too.") }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 8) {
            Text("Host Details").font(.headline)
            if savedFlash {
                Label("Saved", systemImage: "checkmark").font(.caption).foregroundStyle(.green).transition(.opacity)
            }
            Spacer()
            Menu {
                Button("Duplicate") { duplicate() }
                Button("Copy SSH Command") { copySSHCommand() }
                Button("Forget Host Key") { KnownHosts.shared.forget(host: draft.host, port: draft.port) }
                Divider()
                Button("Delete…", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Button { commitNow(); workspace.inspectedID = nil } label: { Image(systemName: "sidebar.trailing") }
                .buttonStyle(.borderless)
                .help("Close Host Details (⌘I)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var addressCard: some View {
        card("Address") {
            HStack(spacing: 10) {
                if !draft.osID.isEmpty {
                    DistroBadge(osID: draft.osID, size: 34)
                } else {
                    IconTile(symbol: draft.kind.icon, color: draft.color.color, size: 34)
                }
                TextField("Host", text: $draft.host, prompt: Text("example.com or 192.0.2.10"))
                    .textFieldStyle(.roundedBorder).labelsHidden()
            }
        }
    }

    private var generalCard: some View {
        card("General") {
            field("Name") { TextField("Name", text: $draft.name, prompt: Text(draft.displayName)).textFieldStyle(.roundedBorder).labelsHidden() }
            field("Folder") {
                HStack(spacing: 4) {
                    TextField("Folder", text: $draft.group, prompt: Text("None")).textFieldStyle(.roundedBorder).labelsHidden()
                    Menu {
                        Button("None") { draft.group = "" }
                        ForEach(store.groups.filter { !$0.isEmpty }, id: \.self) { g in Button(g) { draft.group = g } }
                    } label: { Image(systemName: "folder") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            field("Tags") { tagEditor }
            field("Color") {
                FlowLayout(spacing: 5) {
                    ForEach(SessionColor.allCases) { c in
                        ColorDot(color: c.color, selected: draft.color == c).onTapGesture { draft.color = c }.help(c.rawValue.capitalized)
                    }
                }
            }
            field("Theme") {
                Picker("Theme", selection: $draft.themeID) {
                    Text("Default").tag("")
                    Divider()
                    ForEach(TerminalTheme.all) { t in Text(t.name).tag(t.id) }
                }
                .labelsHidden()
            }
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !draft.tags.isEmpty {
                FlowTags(tags: draft.tags) { t in draft.tags.removeAll { $0 == t } }
            }
            HStack(spacing: 4) {
                TextField("Add tag", text: $newTag, prompt: Text("Add a tag")).textFieldStyle(.roundedBorder).labelsHidden()
                    .onSubmit(addTag)
                let suggestions = store.allTags.filter { !draft.tags.contains($0) }
                if !suggestions.isEmpty {
                    Menu {
                        ForEach(suggestions, id: \.self) { t in Button(t) { draft.tags.append(t) } }
                    } label: { Image(systemName: "tag") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Add an existing tag")
                }
            }
        }
    }

    private var connectionCard: some View {
        card("Connection") {
            Picker("Protocol", selection: $draft.kind) {
                ForEach(SessionKind.allCases) { k in Text(k.label).tag(k) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: draft.kind) { old, new in
                if draft.port == old.defaultPort { draft.port = new.defaultPort }
                if new.isFTP { draft.auth = .password }
            }
            field("Port") {
                TextField("Port", value: $draft.port, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).labelsHidden()
                    .frame(width: 90)
            }
            if draft.kind == .ftps {
                Toggle("Accept self-signed certificates", isOn: $draft.acceptInvalidCertificates)
            }
        }
    }

    private var credentialsCard: some View {
        card("Credentials") {
            field("Login") {
                Picker("Login", selection: $draft.identityID) {
                    Text("This session only").tag(UUID?.none)
                    let usable = identities.identities.filter { !draft.kind.isFTP || $0.auth == .password }
                    if !usable.isEmpty { Divider() }
                    ForEach(usable) { i in Text(i.displayName).tag(UUID?.some(i.id)) }
                }
                .labelsHidden()
            }
            if let identity {
                HStack(spacing: 8) {
                    IconTile(symbol: "person.text.rectangle.fill", color: .indigo, size: 24)
                    Text("\(identity.username) · \(identity.detail)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Manage…") { openWindow(id: "keychain") }.controlSize(.small)
                }
            } else {
                field("Username") {
                    TextField("Username", text: $draft.username, prompt: Text("root")).textFieldStyle(.roundedBorder).labelsHidden()
                }
                if !draft.kind.isFTP {
                    Picker("Method", selection: $draft.auth) {
                        ForEach(AuthMethod.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                if draft.auth == .privateKey && !draft.kind.isFTP {
                    field("Key") {
                        HStack(spacing: 4) {
                            TextField("Key", text: $draft.keyPath, prompt: Text("~/.ssh/id_ed25519")).textFieldStyle(.roundedBorder).labelsHidden()
                            Menu {
                                ForEach(Showcase.isOn ? [] : SSHKeys.scan()) { k in
                                    Button("\(k.name) (\(k.keyType))") { draft.keyPath = (k.path as NSString).abbreviatingWithTildeInPath }
                                }
                            } label: { Image(systemName: "key.horizontal") }
                            .menuStyle(.borderlessButton).fixedSize()
                        }
                    }
                }
                field(draft.auth == .privateKey && !draft.kind.isFTP ? "Passphrase" : "Password") {
                    RevealableSecretField(title: "Password", text: $secret, prompt: "Asked when connecting", savedValue: storedSecret)
                        .textFieldStyle(.roundedBorder).labelsHidden()
                }
            }
        }
    }

    private var moreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showMore.toggle() }
            } label: {
                HStack {
                    Text(showMore ? "Show less" : "Show more").font(.callout)
                    Image(systemName: "chevron.down").rotationEffect(.degrees(showMore ? 180 : 0))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            if showMore {
                field("Start folder") {
                    TextField("Start folder", text: $draft.initialRemotePath, prompt: Text("Home folder")).textFieldStyle(.roundedBorder).labelsHidden()
                }
                field("Backspace") {
                    Picker("Backspace", selection: $draft.backspaceCtrlH) {
                        Text("Default (DEL)").tag(false)
                        Text("Ctrl-H").tag(true)
                    }
                    .labelsHidden()
                }
                Toggle("Show the file browser when connected", isOn: $draft.openFilesPanel)
                Text("Notes").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft.notes)
                    .font(.callout)
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }

    private var footer: some View {
        HStack {
            Text(draft.endpoint).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button { commitNow(); connect(store.sessions.first { $0.id == draft.id } ?? draft) } label: {
                Label("Connect", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.host.isEmpty)
        }
        .padding(10)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.callout).foregroundStyle(.secondary).frame(width: 72, alignment: .leading).padding(.top, 3)
            content()
        }
    }

    // MARK: Saving

    private func load(_ id: UUID) {
        guard let p = store.sessions.first(where: { $0.id == id }) else { return }
        loadedID = id
        draft = p
        baseline = p
        newTag = ""
        if Showcase.isOn { secret = ""; storedSecret = nil; return }
        let s = p.identityID == nil ? Keychain.read(account: p.keychainAccount) : nil
        secret = s ?? ""
        storedSecret = s
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { commitProfile() }
        }
    }

    private func scheduleSecretSave() {
        guard secret != (storedSecret ?? "") else { return }
        secretTask?.cancel()
        secretTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            if !Task.isCancelled { commitSecret() }
        }
    }

    private func commitNow() {
        saveTask?.cancel(); secretTask?.cancel()
        commitProfile()
        commitSecret()
    }

    private func commitProfile() {
        guard loadedID == draft.id, draft != baseline, store.sessions.contains(where: { $0.id == draft.id }) else { return }
        var p = draft
        p.host = p.host.trimmingCharacters(in: .whitespaces)
        store.upsert(p)
        baseline = draft
        flashSaved()
    }

    private func commitSecret() {
        guard !Showcase.isOn, loadedID == draft.id, draft.identityID == nil, secret != (storedSecret ?? "") else { return }
        if secret.isEmpty { Keychain.delete(account: draft.keychainAccount) } else { Keychain.save(secret, account: draft.keychainAccount) }
        storedSecret = secret.isEmpty ? nil : secret
        flashSaved()
    }

    private func flashSaved() {
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { savedFlash = false } }
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        if !t.isEmpty && !draft.tags.contains(t) { draft.tags.append(t) }
        newTag = ""
    }

    private func duplicate() {
        commitNow()
        var copy = draft
        copy.id = UUID()
        copy.name = draft.displayName + " copy"
        store.upsert(copy)
        workspace.inspectedID = copy.id
    }

    private func copySSHCommand() {
        let p = draft.resolved()
        var cmd = "ssh "
        if p.port != 22 { cmd += "-p \(p.port) " }
        if p.auth == .privateKey, !p.keyPath.isEmpty { cmd += "-i \(p.keyPath) " }
        cmd += p.username.isEmpty ? p.host : "\(p.username)@\(p.host)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }
}

/// Tag chips that wrap onto new lines; click × to remove.
struct FlowTags: View {
    let tags: [String]
    var remove: ((String) -> Void)?

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(tags, id: \.self) { t in
                HStack(spacing: 3) {
                    Text(t).font(.caption)
                    if let remove {
                        Button { remove(t) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(TagColor.color(t).opacity(0.22)))
                .foregroundStyle(TagColor.color(t))
            }
        }
    }
}

/// Stable colour per tag name.
enum TagColor {
    static func color(_ tag: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .red, .indigo, .mint, .brown]
        let h = tag.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[abs(h) % palette.count]
    }
}

/// Simple wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
