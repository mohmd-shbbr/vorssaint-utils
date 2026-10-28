// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum BitwardenIntegrationTests {
    static func run(_ suite: TestSuite) {
        let data = Data(#"[{"id":"test","name":"Example","type":1,"reprompt":1,"login":{"username":"demo","password":"synthetic-only","totp":"synthetic-seed"}},{"id":"note","name":"Note","type":2}]"#.utf8)
        let items = try? BitwardenLogin.decode(data)
        suite.expect(items?.count == 2 && items?.first?.requiresReprompt == true, "vault metadata preserves reprompt and includes secure notes")
        suite.expect(items?.last?.isSecureNote == true && items?.last?.primaryField == "notes", "secure notes use protected notes retrieval")
        suite.expect(items?.first?.primaryField == "password", "login default action remains password")
        suite.expect(items?.first?.login?.username == "demo", "login metadata decodes username")
        suite.expect(BitwardenSupport.output(Data("  example \n".utf8)) == "  example ", "password whitespace preserved")
        suite.expect(BitwardenSupport.output(Data("example\n\n".utf8)) == "example\n", "only one CLI terminator removed")
        suite.expect(BitwardenSupport.noteText(Data(#"{"notes":null,"fields":[{"name":"Account","value":"000123","type":0},{"name":"Branch","value":"Example","type":1}]}"#.utf8)) == "Account: 000123\nBranch: Example", "custom-field-only secure notes render without get notes")
        suite.expect(BitwardenSupport.noteText(Data(#"{"notes":"Note body","fields":[{"name":"Example","value":"Value"}]}"#.utf8)) == "Note body\n\nExample: Value", "note body and custom fields both preserved")
        suite.expect(BitwardenSupport.noteText(Data(#"{"notes":"  ","fields":[]}"#.utf8)) == nil, "empty note receives explicit empty handling")
        suite.expect(BitwardenSupport.noteText(Data("not JSON".utf8)) == nil, "invalid item response fails closed")
        let env = BitwardenSupport.environment(profile: URL(fileURLWithPath: "/tmp/test-vault"), session: "synthetic-session", password: "synthetic-password")
        suite.expect(env["BW_SESSION"] == "synthetic-session" && env["BW_PASSWORD"] == "synthetic-password", "credentials supplied only through child environment")
        suite.expect(env["BITWARDENCLI_APPDATA_DIR"] == "/tmp/test-vault" && env["BW_NOINTERACTION"] == "true", "explicit isolated profile and noninteractive child")
        suite.expect(BitwardenSupport.environment(profile: URL(fileURLWithPath: "/tmp/test-vault"))["BW_SESSION"] == nil, "session never inherited by default")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let fake = root.appendingPathComponent("fake-bw")
            try "#!/bin/sh\nprintf '%s' \"$BW_SESSION\"\n".write(to: fake, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
            let result = try BitwardenProcess().run(executable: fake.path, arguments: ["get", "password", "fixture"], environment: env)
            suite.expect(String(data: result, encoding: .utf8) == "synthetic-session", "process receives synthetic session without command-line secret")
            let cancelled = BitwardenProcess()
            cancelled.cancel()
            do {
                _ = try cancelled.run(executable: fake.path, arguments: [], environment: env)
                suite.expect(false, "cancel before launch must fail")
            } catch { suite.expect(true, "cancel before launch fails closed") }
            do {
                _ = try BitwardenProcess().run(executable: "/usr/bin/false", arguments: [], environment: env)
                suite.expect(false, "failed subprocess must not return success")
            } catch { suite.expect(true, "failed subprocess rejected") }
        } catch { suite.expect(false, "synthetic CLI fixture runs: \(type(of: error))") }
    }
}
