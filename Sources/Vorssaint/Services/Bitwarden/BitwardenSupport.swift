// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Security

/// Decode only searchable metadata; passwords, notes and TOTP seeds are discarded.
struct BitwardenLogin: Decodable, Identifiable {
    struct Login: Decodable { let username: String? }
    let id: String
    let name: String
    let type: Int
    let reprompt: Int?
    let login: Login?
    var isSecureNote: Bool { type == 2 }
    var primaryField: String { isSecureNote ? "notes" : "password" }
    var requiresReprompt: Bool { (reprompt ?? 0) != 0 }
    static func decode(_ data: Data) throws -> [BitwardenLogin] {
        try JSONDecoder().decode([BitwardenLogin].self, from: data).filter { $0.type == 1 || $0.type == 2 }
    }
}

enum BitwardenSupport {
    static let executableKey = "bitwarden.executablePath"
    static func executable() -> String? {
        let saved = UserDefaults.standard.string(forKey: executableKey)
        var candidates = [saved, "/opt/homebrew/bin/bw", "/usr/local/bin/bw"].compactMap { $0 }
        let extensions = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.raycast.macos/extensions")
        if let folders = try? FileManager.default.contentsOfDirectory(at: extensions, includingPropertiesForKeys: nil) {
            for folder in folders {
                if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                    candidates += files.filter { $0.lastPathComponent.hasPrefix("bw-") }.map(\.path)
                }
            }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0)
            && (try? URL(fileURLWithPath: $0).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
    static var profile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "NotchCraft")
            .appendingPathComponent("BitwardenCLI", isDirectory: true)
    }
    static func environment(profile: URL, session: String? = nil, password: String? = nil) -> [String: String] {
        var env = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": NSHomeDirectory(),
                   "BITWARDENCLI_APPDATA_DIR": profile.path, "BW_NOINTERACTION": "true"]
        if let session { env["BW_SESSION"] = session }
        if let password { env["BW_PASSWORD"] = password }
        return env
    }
    /// Secure notes can hold their content entirely in custom fields. `bw get
    /// notes` rejects these as not found, so render the complete item instead.
    static func noteText(_ data: Data) -> String? {
        guard let item = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var sections: [String] = []
        if let text = item["notes"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sections.append(text) }
        let fields = (item["fields"] as? [[String: Any]] ?? []).compactMap { field -> String? in
            guard let value = field["value"] as? String, !value.isEmpty else { return nil }
            let name = field["name"] as? String ?? "Field"
            return name + ": " + value
        }
        if !fields.isEmpty { sections.append(fields.joined(separator: "\n")) }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    /// Strip the CLI's one output terminator, never whitespace inside a password.
    static func output(_ data: Data) -> String? {
        guard var value = String(data: data, encoding: .utf8) else { return nil }
        if value.hasSuffix("\n") { value.removeLast(); if value.hasSuffix("\r") { value.removeLast() } }
        return value
    }
}

/// No shell, secret command-line arguments, output logs, or temporary secret files.
final class BitwardenProcess {
    enum Failure: Error { case unavailable, failed, tooLarge }
    private let lock = NSLock()
    private var active: Process?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let process = active; lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }
    func run(executable: String, arguments: [String], environment: [String: String]) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        lock.lock()
        guard !cancelled else { lock.unlock(); throw Failure.failed }
        do { try process.run() } catch { lock.unlock(); throw error }
        active = process
        lock.unlock()
        defer { lock.lock(); if active === process { active = nil }; lock.unlock() }
        let timeout = DispatchWorkItem { [weak process] in if process?.isRunning == true { process?.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: timeout)
        defer { timeout.cancel() }
        var result = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
            if result.count + chunk.count > 16 * 1024 * 1024 { process.terminate(); throw Failure.tooLarge }
            result.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.failed }
        return result
    }
}

/// A saved unlock session is a decryption key. Keep it in the macOS Keychain,
/// never preferences, settings exports, files, or Raycast's storage.
enum BitwardenSessionKeychain {
    private static var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "NotchCraft") + ".bitwarden",
         kSecAttrAccount as String: "vault-session"]
    }
    static func read() -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ session: String) -> Bool {
        let data = Data(session.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = identity
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    static func clear() { SecItemDelete(identity as CFDictionary) }
}
