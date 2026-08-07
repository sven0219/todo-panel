import Foundation

enum Logger {
    private static let fileURL: URL = {
        let base = FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("Library/Logs", isDirectory: true)
        return dir.appendingPathComponent("todopanel.log")
    }()

    private static let lock = NSLock()

    static func log(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
