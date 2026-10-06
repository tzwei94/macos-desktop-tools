import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sourceTreeRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.torusknot.SourceTreeNotMAS" ||
            $0.bundleIdentifier == "com.torusknot.SourceTree" ||
            $0.localizedName?.lowercased() == "sourcetree"
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { self.showInstaller() }
    }

    private func showInstaller() {
        let prompt = NSAlert()
        prompt.messageText = "Install Open in VS Code"
        prompt.informativeText = "Add a SourceTree custom action that opens the current repository in Visual Studio Code.\n\nQuit SourceTree before installing. Existing custom actions will be preserved and backed up."
        prompt.alertStyle = .informational
        prompt.addButton(withTitle: "Install")
        prompt.addButton(withTitle: "Cancel")
        guard prompt.runModal() == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return
        }

        while true {
            do {
                let workspace = NSWorkspace.shared
                let hasSourceTree = workspace.urlForApplication(withBundleIdentifier: "com.torusknot.SourceTreeNotMAS") != nil ||
                    workspace.urlForApplication(withBundleIdentifier: "com.torusknot.SourceTree") != nil
                guard hasSourceTree, workspace.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil else {
                    throw InstallError.missingApps
                }
                let directory = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/SourceTree", isDirectory: true)
                let result = try ActionInstaller.install(in: directory, sourceTreeRunning: self.sourceTreeRunning)
                let success = NSAlert()
                success.messageText = result.installed ? "Open in VS Code is ready" : "Already installed"
                success.informativeText = "Open SourceTree, select a repository, then choose:\n\nActions → Custom Actions → Open in VS Code"
                if result.backup != nil {
                    success.informativeText += "\n\nA backup was saved in:\n~/Library/Application Support/SourceTree/CustomActionBackups"
                }
                success.addButton(withTitle: "Done")
                success.runModal()
                break
            } catch {
                let failure = NSAlert()
                failure.alertStyle = .warning
                failure.messageText = "Installation could not finish"
                failure.informativeText = error.localizedDescription
                failure.addButton(withTitle: "Try Again")
                failure.addButton(withTitle: "Quit")
                if failure.runModal() != .alertFirstButtonReturn { break }
            }
        }
        NSApp.terminate(nil)
    }
}

@main struct InstallerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Open in VS Code Installer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        app.mainMenu = menu
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
