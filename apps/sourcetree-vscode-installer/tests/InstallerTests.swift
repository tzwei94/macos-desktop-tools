import Foundation

enum TestFailure: Error { case failed(String) }
func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw TestFailure.failed(message) }
}
func archived(_ actions: [[String: Any]]) throws -> Data {
    try NSKeyedArchiver.archivedData(withRootObject: actions, requiringSecureCoding: false)
}
func readActions(_ url: URL) throws -> [[String: Any]] {
    let data = try Data(contentsOf: url)
    let classes: [AnyClass] = [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSDate.self, NSData.self]
    return try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) as! [[String: Any]]
}
func withFixture(_ test: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SourceTree Installer Tests \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try test(dir)
}
func mustReject(_ block: () throws -> Void) throws {
    var rejected = false
    do { try block() } catch { rejected = true }
    try expect(rejected, "Expected installation to be rejected")
}

@main struct Tests {
    static func main() {
        let tests: [(String, (URL) throws -> Void)] = [
            ("fresh installation creates a usable repository action", { dir in
                let result = try ActionInstaller.install(in: dir, sourceTreeRunning: false)
                let actions = try readActions(dir.appendingPathComponent("actions.plist"))
                try expect(result.installed && result.backup == nil, "Fresh install result")
                try expect(actions.count == 1, "One action expected")
                let action = actions[0]
                try expect(action["name"] as? String == "Open in VS Code", "Missing action name")
                let helper = dir.appendingPathComponent("CustomActionHelpers/open-in-vscode")
                try expect(action["target"] as? String == helper.path, "Use the installed helper")
                try expect(action["params"] as? String == "$REPO", "Pass only the repository parameter")
                try expect(FileManager.default.isExecutableFile(atPath: helper.path), "Helper must be executable")
                try expect(action["repoAction"] as? Bool == true, "Repository menu visibility")
            }),
            ("quoted repository paths are forwarded as one clean path", { dir in
                let repo = dir.appendingPathComponent("Repo with spaces and 'quotes'", isDirectory: true)
                try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
                let args = try RepositoryLaunch.arguments(for: "\"\(repo.path)\"")
                try expect(args == ["-b", "com.microsoft.VSCode", repo.path], "SourceTree quotes must not reach open")
                let rawArgs = try RepositoryLaunch.arguments(for: repo.path)
                try expect(rawArgs == args, "Raw paths must work too")
            }),
            ("invalid repository input is rejected", { dir in
                try mustReject { _ = try RepositoryLaunch.arguments(for: "\"\(dir.path)/missing\"") }
            }),
            ("version one action is upgraded in place with backup", { dir in
                let url = dir.appendingPathComponent("actions.plist")
                let original = try archived([["name": "Open in VS Code", "target": "/usr/bin/open", "params": "-b com.microsoft.VSCode \"$REPO\"", "repoAction": true, "shortcutKeyCode": 42]])
                try original.write(to: url)
                let result = try ActionInstaller.install(in: dir, sourceTreeRunning: false)
                let actions = try readActions(url)
                try expect(result.installed && result.backup != nil, "Upgrade requires backup")
                try expect(actions.count == 1, "Upgrade must not add a duplicate")
                try expect(actions[0]["params"] as? String == "$REPO", "Upgrade old parameters")
                try expect(actions[0]["shortcutKeyCode"] as? Int == 42, "Preserve shortcuts")
            }),
            ("existing actions and backup bytes are preserved", { dir in
                let existing: [[String: Any]] = [["name": "My Action", "target": "/bin/echo", "params": "$REPO", "customMetadata": ["keep": "yes"]]]
                let original = try archived(existing)
                let url = dir.appendingPathComponent("actions.plist")
                try original.write(to: url)
                let result = try ActionInstaller.install(in: dir, sourceTreeRunning: false)
                let actions = try readActions(url)
                try expect(actions.count == 2, "Append, never replace")
                try expect(NSDictionary(dictionary: actions[0]).isEqual(to: existing[0]), "Existing action changed")
                guard let backup = result.backup else { throw TestFailure.failed("Missing backup") }
                let backupData = try Data(contentsOf: backup)
                try expect(backupData == original, "Backup is not byte-for-byte original")
            }),
            ("repeat installation neither duplicates nor rewrites", { dir in
                _ = try ActionInstaller.install(in: dir, sourceTreeRunning: false)
                let url = dir.appendingPathComponent("actions.plist")
                let before = try Data(contentsOf: url)
                let result = try ActionInstaller.install(in: dir, sourceTreeRunning: false)
                let after = try Data(contentsOf: url)
                let actions = try readActions(url)
                try expect(!result.installed && result.backup == nil, "Repeat should be a no-op")
                try expect(before == after && actions.count == 1, "Repeat changed actions")
            }),
            ("corrupted archives are rejected without changes", { dir in
                let url = dir.appendingPathComponent("actions.plist")
                let original = Data("broken archive".utf8)
                try original.write(to: url)
                try mustReject { _ = try ActionInstaller.install(in: dir, sourceTreeRunning: false) }
                let after = try Data(contentsOf: url)
                try expect(after == original, "Corrupted input was overwritten")
            }),
            ("unexpected archive structure is rejected without changes", { dir in
                let url = dir.appendingPathComponent("actions.plist")
                let original = try NSKeyedArchiver.archivedData(withRootObject: ["other": "data"], requiringSecureCoding: false)
                try original.write(to: url)
                try mustReject { _ = try ActionInstaller.install(in: dir, sourceTreeRunning: false) }
                let after = try Data(contentsOf: url)
                try expect(after == original, "Unexpected archive was overwritten")
            }),
            ("a conflicting named action is preserved", { dir in
                let url = dir.appendingPathComponent("actions.plist")
                let original = try archived([["name": "Open in VS Code", "target": "/my/custom/script", "params": "$REPO"]])
                try original.write(to: url)
                try mustReject { _ = try ActionInstaller.install(in: dir, sourceTreeRunning: false) }
                let after = try Data(contentsOf: url)
                try expect(after == original, "Conflicting action was overwritten")
            }),
            ("running SourceTree blocks all writes", { dir in
                let child = dir.appendingPathComponent("not-created")
                try mustReject { _ = try ActionInstaller.install(in: child, sourceTreeRunning: true) }
                try expect(!FileManager.default.fileExists(atPath: child.path), "Running app must block writes")
            }),
            ("unwritable backup location blocks config mutation", { dir in
                let url = dir.appendingPathComponent("actions.plist")
                let original = try archived([["name": "Keep me"]])
                try original.write(to: url)
                try Data("not a directory".utf8).write(to: dir.appendingPathComponent("CustomActionBackups"))
                try mustReject { _ = try ActionInstaller.install(in: dir, sourceTreeRunning: false) }
                let after = try Data(contentsOf: url)
                try expect(after == original, "Installation continued after backup failure")
            })
        ]
        var failures = 0
        for (name, test) in tests {
            do { try withFixture(test); print("PASS: \(name)") }
            catch { failures += 1; print("FAIL: \(name): \(error)") }
        }
        print("\(tests.count - failures)/\(tests.count) tests passed")
        exit(failures == 0 ? 0 : 1)
    }
}
