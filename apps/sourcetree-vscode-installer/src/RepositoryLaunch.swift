import Foundation

enum RepositoryLaunch {
    static func arguments(for input: String) throws -> [String] {
        func isDirectory(_ path: String) -> Bool {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
        }
        var path = input
        if !isDirectory(path), path.count >= 2,
           (path.first == "\"" && path.last == "\"" || path.first == "'" && path.last == "'") {
            path = String(path.dropFirst().dropLast())
        }
        guard isDirectory(path) else {
            throw NSError(domain: "RepositoryOpener", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The repository directory could not be found: \(input)"])
        }
        return ["-b", "com.microsoft.VSCode", URL(fileURLWithPath: path).standardizedFileURL.path]
    }
}
