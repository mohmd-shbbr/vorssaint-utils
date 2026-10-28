// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI
import Carbon.HIToolbox

final class BitwardenVault: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = BitwardenVault()
    @Published var items: [BitwardenLogin] = []
    @Published var query = ""
    @Published var password = ""
    @Published var message = ""
    @Published var unlocked = false
    @Published var busy = false
    @Published var available = BitwardenSupport.executable() != nil
    @Published var verification = false
    @Published var focusRequest = UUID()
    @Published var sessionSaved = true
    @Published var displayedNote: String?
    private var session: String?
    private var panel: NSPanel?
    private var generation = UUID()
    private var currentRunner: BitwardenProcess?
    private let commands = DispatchQueue(label: "BitwardenVault.commands", qos: .userInitiated)
    private var copiedChangeCount: Int?
    static let shortcutKey = "bitwarden.shortcut"
    static let shortcutEnabledKey = "bitwarden.shortcutEnabled"
    static let defaultShortcut = GlobalShortcut(keyCode: Int64(kVK_ANSI_B), modifiers: [.control, .option])
    private let hotkey = QuickToolHotkey(id: 90)
    @Published var shortcutFailed = false
    private var pendingCopy: (String, String, Bool)?
    private var searchWork: DispatchWorkItem?
    override init() {
        super.init()
        hotkey.onPress = { [weak self] in self?.show() }

    }
    func syncShortcut() {
        let enabled = UserDefaults.standard.object(forKey: Self.shortcutEnabledKey) as? Bool ?? true
        shortcutFailed = !hotkey.sync(enabled: enabled,
            shortcut: GlobalShortcut.saved(for: Self.shortcutKey, fallback: Self.defaultShortcut), storageKey: Self.shortcutKey)
    }
    func show() {
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 510),
                                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Bitwarden Vault"
            window.minSize = NSSize(width: 500, height: 420)
            window.contentView = NSHostingView(rootView: BitwardenVaultView(model: self))
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.center()
            panel = window
        }
        available = BitwardenSupport.executable() != nil
        if session == nil, let saved = BitwardenSessionKeychain.read() {
            session = saved
            request(["status"]) { [weak self] data in
                guard let self else { return }
                let status = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                if status?["status"] as? String == "unlocked" {
                    self.unlocked = true
                    self.search()
                } else {
                    self.session = nil
                    if let value = status?["status"] as? String, ["locked", "unauthenticated"].contains(value) {
                        BitwardenSessionKeychain.clear()
                    }
                    self.message = "Could not restore the session. Try reopening search or unlock your vault."
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        focusRequest = UUID()
    }
    func windowWillClose(_ notification: Notification) { password = ""; displayedNote = nil; cancelVerification() }
    func chooseCLI() {
        let picker = NSOpenPanel()
        picker.title = "Choose the official Bitwarden CLI executable (bw)"
        picker.canChooseDirectories = false
        guard picker.runModal() == .OK, let url = picker.url,
              FileManager.default.isExecutableFile(atPath: url.path) else { return }
        lockVault()
        UserDefaults.standard.set(url.path, forKey: BitwardenSupport.executableKey)
        available = true
    }
    func signIn() {
        guard !unlocked, !busy, let cli = BitwardenSupport.executable() else { return }
        do {
            let profile = BitwardenSupport.profile
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let script = profile.appendingPathComponent("Sign in to Bitwarden.command")
            let body = "#!/bin/zsh\nunset BW_SESSION BW_PASSWORD BW_CLIENTID BW_CLIENTSECRET BW_NOINTERACTION\nexport BITWARDENCLI_APPDATA_DIR=" + BitwardenSupport.shellQuote(profile.path) + "\n" + BitwardenSupport.shellQuote(cli) + " login\n" + BitwardenSupport.shellQuote(cli) + " lock >/dev/null 2>&1\nprintf '\\nReturn to the vault window and unlock it.\\n'\n"
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
            message = "Complete sign-in in Terminal, then return here to unlock. This profile is separate from Raycast."
        } catch { message = "Could not open sign-in. Check the CLI path and try again." }
    }
    func unlock() {
        guard !password.isEmpty, !busy else { return }
        let secret = password
        password = ""
        request(["unlock", "--passwordenv", "BW_PASSWORD", "--raw"], password: secret) { [weak self] data in
            guard let self, let key = BitwardenSupport.output(data), !key.isEmpty else { return }
            self.session = key
            self.sessionSaved = BitwardenSessionKeychain.save(key)
            self.unlocked = true
            self.verification = false
            if let (id, field, reveal) = self.pendingCopy {
                self.pendingCopy = nil
                self.copyField(id: id, field: field, reveal: reveal)
            } else { self.search() }
        }
    }
    func lockVault() {
        BitwardenSessionKeychain.clear()
        let oldSession = session
        generation = UUID()
        currentRunner?.cancel()
        currentRunner = nil
        if let count = copiedChangeCount, NSPasteboard.general.changeCount == count { NSPasteboard.general.clearContents() }
        copiedChangeCount = nil
        searchWork?.cancel()
        session = nil
        items = []
        displayedNote = nil
        password = ""
        query = ""
        pendingCopy = nil
        verification = false
        unlocked = false
        busy = false
        message = "Vault locked."
        // Revoke only this app's separate CLI profile, never Raycast's session.
        if let oldSession, let cli = BitwardenSupport.executable() {
            let env = BitwardenSupport.environment(profile: BitwardenSupport.profile, session: oldSession)
            commands.async { _ = try? BitwardenProcess().run(executable: cli, arguments: ["lock"], environment: env) }
        }
    }
    func shutdown() {
        // Never timeout: retain the Keychain session for the next launch.
        generation = UUID()
        currentRunner?.cancel()
        searchWork?.cancel()
        password = ""
        displayedNote = nil
        session = nil
        items = []
        if let count = copiedChangeCount, NSPasteboard.general.changeCount == count { NSPasteboard.general.clearContents() }
    }
    func searchSoon() {
        searchWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.search() }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func search() {
        guard unlocked, !verification else { return }
        guard !busy else { searchSoon(); return }
        let requestedQuery = query
        request(["list", "items", "--search", requestedQuery]) { [weak self] data in
            guard let self, requestedQuery == self.query else { return }
            do { self.items = try BitwardenLogin.decode(data); self.message = self.items.isEmpty ? "No matching logins or secure notes." : "" }
            catch { self.items = []; self.message = "Could not read the vault response. Try syncing." }
        }
    }
    func sync() {
        guard unlocked, !busy else { return }
        request(["sync"]) { [weak self] _ in self?.search() }
    }
    func copy(_ item: BitwardenLogin, field: String, reveal: Bool = false) {
        guard unlocked, !busy else { return }
        // The policy may have changed since search. Re-read before every copy.
        request(["get", "item", item.id]) { [weak self] data in
            guard let self, let fresh = try? JSONDecoder().decode(BitwardenLogin.self, from: data), fresh.id == item.id else { return }
            if fresh.requiresReprompt {
                self.pendingCopy = (fresh.id, field, reveal)
                self.verification = true
                self.password = ""
                self.message = "This item requires your master password again."
            } else { self.copyField(id: fresh.id, field: field, reveal: reveal, noteData: field == "notes" ? data : nil) }
        }
    }
    func cancelVerification() { verification = false; pendingCopy = nil; password = ""; message = "" }
    private func copyField(id: String, field: String, reveal: Bool = false, noteData: Data? = nil) {
        if field == "notes", let noteData {
            guard let value = BitwardenSupport.noteText(noteData) else {
                message = "This note has no text or custom-field values. Try Sync if it was recently changed."
                return
            }
            present(value: value, reveal: reveal)
            return
        }
        request(field == "notes" ? ["get", "item", id] : ["get", field, id]) { [weak self] data in
            guard let self else { return }
            let value = field == "notes" ? BitwardenSupport.noteText(data) : BitwardenSupport.output(data)
            guard let value, !value.isEmpty else { self.message = "No text or custom-field values are available. Try Sync if this item was recently changed."; return }
            self.present(value: value, reveal: reveal)
        }
    }
    private func present(value: String, reveal: Bool) {
        if reveal { displayedNote = value; return }
        let item = NSPasteboardItem()
        item.setString(value, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let board = NSPasteboard.general
        board.clearContents()
        guard board.writeObjects([item]) else { message = "Could not copy this field."; return }
        let changeCount = board.changeCount
        copiedChangeCount = changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if board.changeCount == changeCount { board.clearContents() }
        }
        message = "Copied. Clipboard clears in 30 seconds unless you copy something else."
        panel?.orderOut(nil)
    }
    private func request(_ arguments: [String], password: String? = nil, completion: @escaping (Data) -> Void) {
        guard let cli = BitwardenSupport.executable(), !busy else { return }
        busy = true
        message = ""
        let token = generation
        let env = BitwardenSupport.environment(profile: BitwardenSupport.profile, session: arguments.first == "unlock" ? nil : session, password: password)
        let runner = BitwardenProcess()
        currentRunner = runner
        commands.async {
            let result = Result { try runner.run(executable: cli, arguments: arguments, environment: env) }
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.currentRunner = nil
                self.busy = false
                switch result {
                case .success(let data): completion(data)
                case .failure:
                    if arguments.first == "status" { self.session = nil }
                    self.message = "Bitwarden could not complete this request. Check your sign-in, master password, connection, and CLI path."
                }
            }
        }
    }
}

private struct BitwardenVaultView: View {
    @ObservedObject var model: BitwardenVault
    @State private var selected: String?
    @FocusState private var inputFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Bitwarden Vault", systemImage: "lock.shield") .font(.title2)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                if model.unlocked { Button("Sync", action: model.sync).disabled(model.busy); Button("Lock", action: model.lockVault) }
            }
            if !model.available {
                Text("Install the official Bitwarden CLI, or choose an existing executable. A Raycast-managed CLI is detected automatically when available.")
                Link("Bitwarden CLI installation", destination: URL(string: "https://bitwarden.com/help/cli/")!)
                Button("Choose CLI…", action: model.chooseCLI)
            } else if !model.unlocked || model.verification {
                Text(model.verification ? "Confirm your master password" : "Unlock your vault") .font(.headline)
                SecureField("Master password", text: $model.password).focused($inputFocused).onAppear { inputFocused = true }.onSubmit { model.unlock() }
                    .textFieldStyle(.roundedBorder).disabled(model.busy)
                HStack {
                    Button(model.verification ? "Confirm" : "Unlock", action: model.unlock).disabled(model.busy || model.password.isEmpty)
                    if model.verification { Button("Cancel", action: model.cancelVerification) }
                    else { Button("Sign in via Terminal", action: model.signIn).disabled(model.busy); Button("Choose CLI…", action: model.chooseCLI).disabled(model.busy) }
                }
                if !model.verification { Text("First use: sign in via Terminal, then unlock here.").font(.caption).foregroundStyle(.secondary) }
                Text("Your master password is never saved. Vault Timeout: Never. The unlock session is stored in macOS Keychain until you choose Lock, including across sleep and app restarts.").font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("Search logins and secure notes", text: $model.query)
                    .focused($inputFocused).onAppear { inputFocused = true }
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.query) { model.searchSoon() }
                    .onSubmit { if let item = selectedItem { model.copy(item, field: item.primaryField) } }
                List(model.items, selection: $selected) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Image(systemName: item.isSecureNote ? "note.text" : "key"); Text(item.name); if item.requiresReprompt { Image(systemName: "lock") } }
                        Text(item.isSecureNote ? "Secure note" : (item.login?.username ?? "")).font(.caption).foregroundStyle(.secondary)
                    }.tag(item.id)
                }
                .onChange(of: model.items.map(\.id)) { _, ids in if !ids.contains(selected ?? "") { selected = ids.first } }
                HStack {
                    Button(selectedItem?.isSecureNote == true ? "Copy note" : "Copy password") { if let item = selectedItem { model.copy(item, field: item.primaryField) } }
                        .keyboardShortcut(.return, modifiers: [])
                    if selectedItem?.isSecureNote == true {
                        Button("View note") { if let item = selectedItem { model.copy(item, field: "notes", reveal: true) } }
                    } else {
                        Button("Copy username") { if let item = selectedItem { model.copy(item, field: "username") } }
                        Button("Copy TOTP") { if let item = selectedItem { model.copy(item, field: "totp") } }
                    }
                }.disabled(selectedItem == nil || model.busy)
                Text("TOTP requires an eligible Bitwarden plan and a configured code. Copied fields are concealed from clipboard history.").font(.caption).foregroundStyle(.secondary)
            }
            if !model.sessionSaved { Text("Session could not be saved in Keychain. It will remain unlocked only until the app quits.").font(.caption).foregroundStyle(.orange) }
            if !model.message.isEmpty { Text(model.message).font(.callout).foregroundStyle(.secondary).textSelection(.disabled) }
            Spacer(minLength: 0)
        }.padding(20).frame(minWidth: 460, minHeight: 380)
            .onChange(of: model.focusRequest) { inputFocused = true }
            .sheet(isPresented: Binding(get: { model.displayedNote != nil }, set: { if !$0 { model.displayedNote = nil } })) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Secure note").font(.headline)
                    ScrollView { Text(model.displayedNote ?? "").frame(maxWidth: .infinity, alignment: .leading).textSelection(.disabled) }
                    HStack { Text("Use Copy note in the vault to copy with clipboard protection.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Close") { model.displayedNote = nil }.keyboardShortcut(.cancelAction) }
                }.padding(20).frame(width: 560, height: 400)
            }
    }
    private var selectedItem: BitwardenLogin? { model.items.first { $0.id == selected } }
}
