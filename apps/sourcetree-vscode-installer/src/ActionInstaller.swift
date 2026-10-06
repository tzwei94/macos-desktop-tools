import Foundation

struct InstallResult {
    let installed: Bool
    let backup: URL?
}

enum ActionInstaller {
    static func install(in directory: URL,
                        helperSource: URL? = Bundle.main.url(forResource: "RepositoryOpener", withExtension: nil),
                        sourceTreeRunning: @autoclosure () -> Bool) throws -> InstallResult {
        guard !sourceTreeRunning() else { throw InstallError.sourceTreeRunning }
        let manager = FileManager.default
        let destination = directory.appendingPathComponent("actions.plist")
        var actions: [[String: Any]] = []
        var original: Data?
        if manager.fileExists(atPath: destination.path) {
            let data = try Data(contentsOf: destination)
            // Validate the envelope before asking Foundation to decode it.
            guard let envelope = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  envelope["$archiver"] as? String == "NSKeyedArchiver" else {
                throw InstallError.unreadableActions
            }
            let classes: [AnyClass] = [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSDate.self, NSData.self, NSNull.self]
            guard let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) as? [[String: Any]],
                  decoded.allSatisfy({ $0["name"] is String }) else {
                throw InstallError.unreadableActions
            }
            actions = decoded
            original = data
        }

        guard let helperSource = helperSource else { throw InstallError.missingHelper }
        let helperData = try Data(contentsOf: helperSource)
        let helper = directory.appendingPathComponent("CustomActionHelpers/open-in-vscode")
        let helperNeedsUpdate = (try? Data(contentsOf: helper)) != helperData || !manager.isExecutableFile(atPath: helper.path)
        let action: [String: Any] = [
            "name": "Open in VS Code",
            "target": helper.path,
            "params": "$REPO",
            "repoAction": true,
            "fileAction": false,
            "logAction": false,
            "separateWindow": false,
            "showFullOutput": false,
            "shortcutKeyCode": -1,
            "shortcutKeyModifiers": 0,
            "shortcutKeyDisplay": ""
        ]
        var actionNeedsUpdate = true
        var matchedIndex: Int?
        for (index, existing) in actions.enumerated() {
            let name = (existing["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if name == "open in vs code" {
                if existing["target"] as? String == action["target"] as? String,
                   existing["params"] as? String == action["params"] as? String,
                   existing["repoAction"] as? Bool == true {
                    actionNeedsUpdate = false
                    matchedIndex = index
                    break
                }
                // Only migrate the exact configuration shipped by version 1.0.0.
                if existing["target"] as? String == "/usr/bin/open",
                   existing["params"] as? String == "-b com.microsoft.VSCode \"$REPO\"" {
                    matchedIndex = index
                    break
                }
                throw InstallError.nameConflict
            }
        }
        if !actionNeedsUpdate && !helperNeedsUpdate { return InstallResult(installed: false, backup: nil) }
        if actionNeedsUpdate {
            if let index = matchedIndex {
                var updated = actions[index]
                updated["target"] = helper.path
                updated["params"] = "$REPO"
                updated["repoAction"] = true
                actions[index] = updated
            } else {
                actions.append(action)
            }
        }
        let updated = try NSKeyedArchiver.archivedData(withRootObject: actions, requiringSecureCoding: false)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var backup: URL?
        if let original = original, actionNeedsUpdate {
            let backupDirectory = directory.appendingPathComponent("CustomActionBackups", isDirectory: true)
            try manager.createDirectory(at: backupDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backupURL = backupDirectory.appendingPathComponent("actions-\(timestamp)-\(UUID().uuidString).plist")
            try original.write(to: backupURL, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            backup = backupURL
        }
        guard !sourceTreeRunning() else { throw InstallError.sourceTreeRunning }
        // Abort if another process changed the file while it was being backed up.
        if let original = original {
            guard try Data(contentsOf: destination) == original else { throw InstallError.actionsChanged }
        } else if manager.fileExists(atPath: destination.path) {
            throw InstallError.actionsChanged
        }
        if helperNeedsUpdate {
            try manager.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
            try helperData.write(to: helper, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        }
        if actionNeedsUpdate { try updated.write(to: destination, options: .atomic) }
        return InstallResult(installed: true, backup: backup)
    }
}

enum InstallError: LocalizedError {
    case sourceTreeRunning, unreadableActions, nameConflict, actionsChanged, missingApps, missingHelper
    var errorDescription: String? {
        switch self {
        case .sourceTreeRunning:
            return "Quit SourceTree, then try again. The installer cannot update custom actions while SourceTree is running."
        case .unreadableActions:
            return "The existing custom actions file could not be read safely. It has been left unchanged."
        case .nameConflict:
            return "An action named “Open in VS Code” already exists with different settings. It has been left unchanged. Rename it in SourceTree’s Custom Actions settings, quit SourceTree, then try again."
        case .actionsChanged:
            return "The custom actions file changed during installation. Please quit SourceTree and try again."
        case .missingApps:
            return "Install SourceTree and Visual Studio Code before running this installer."
        case .missingHelper:
            return "The installer’s repository helper is missing. Extract a fresh copy of the installer app and try again."
        }
    }
}
