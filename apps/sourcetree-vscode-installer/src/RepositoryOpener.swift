import Foundation

@main struct RepositoryOpener {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else {
                throw NSError(domain: "RepositoryOpener", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "This action expects one repository path."])
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = try RepositoryLaunch.arguments(for: CommandLine.arguments[1])
            try task.run()
            task.waitUntilExit()
            exit(task.terminationStatus)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
