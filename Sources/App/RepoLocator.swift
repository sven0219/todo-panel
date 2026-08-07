import Foundation

/// Auto-locate the todo repo (walk up from the executable / CWD looking for AGENTS.md or .git).
enum RepoLocator {
    static func locate() -> String? {
        var roots: [URL] = []
        if let exe = Bundle.main.executableURL {
            roots.append(exe.deletingLastPathComponent())
        }
        roots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        for root in roots {
            var dir = root
            for _ in 0..<7 {
                let git = dir.appendingPathComponent(".git")
                let agents = dir.appendingPathComponent("AGENTS.md")
                if FileManager.default.fileExists(atPath: git.path) || FileManager.default.fileExists(atPath: agents.path) {
                    return dir.path
                }
                dir.deleteLastPathComponent()
            }
        }
        return nil
    }
}
