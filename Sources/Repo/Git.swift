import Foundation

struct GitError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class GitManager {
    let repoPath: String

    init(repoPath: String) {
        self.repoPath = repoPath
    }

    /// Run a git command, returning output and exit status without throwing.
    /// Non-interactive SSH (BatchMode) prevents passphrase prompts from hanging;
    /// a timeout guarantees the call returns instead of blocking forever.
    private func run(_ args: [String], timeout: TimeInterval = 60) -> (output: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath] + args
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ("", 127)
        }

        // Wait for exit; terminate on timeout to avoid SSH/network hangs.
        var status: Int32 = 0
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            status = process.terminationStatus
            group.leave()
        }
        let result = group.wait(timeout: .now() + timeout)
        if result == .timedOut {
            process.terminate()
            group.wait()
            return ("命令超时（\(Int(timeout))s），已终止", 124)
        }

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (out.trimmingCharacters(in: .whitespacesAndNewlines)
                    + (err.isEmpty ? "" : "\n" + err.trimmingCharacters(in: .whitespacesAndNewlines)),
                status)
    }

    @discardableResult
    private func runOrThrow(_ args: [String]) throws -> String {
        let result = run(args)
        if result.status != 0 {
            throw GitError(message: "git \(args.joined(separator: " ")) failed: \(result.output)")
        }
        return result.output
    }

    /// Stage the given repo-relative paths and commit locally. No remote interaction.
    func commit(message: String, paths: [String]) throws {
        guard !paths.isEmpty else { return }
        _ = try runOrThrow(["add", "--"] + paths)
        let commit = run(["commit", "-m", message])
        if commit.status != 0
            && !commit.output.contains("nothing to commit")
            && !commit.output.contains("no changes added")
            && !commit.output.contains("nothing added to commit") {
            throw GitError(message: "git commit failed: \(commit.output)")
        }
    }

    /// Pull with rebase, then push pending commits. Transient failures are retried up to 3
    /// times; conflicts raise a clear, actionable error.
    func push() throws {
        var lastMessage = ""
        for attempt in 0..<3 {
            let pull = run(["pull", "--rebase"])
            if pull.status != 0 {
                if Self.isConflict(pull.output) {
                    throw GitError(message: "本地与远端存在冲突，请手动解决后重试：\n\(Self.summarize(pull.output))")
                }
                lastMessage = pull.output
                if attempt < 2 { Thread.sleep(forTimeInterval: 2) }
                continue
            }

            let push = run(["push"])
            if push.status == 0 { return }

            if Self.isConflict(push.output) {
                throw GitError(message: "推送被远端拒绝（远端可能有更新），请手动处理：\n\(Self.summarize(push.output))")
            }

            let hasUpstream = run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]).status == 0
            if !hasUpstream {
                let retry = run(["push", "-u", "origin", "HEAD"])
                if retry.status == 0 { return }
                throw GitError(message: "git push -u 失败：\n\(Self.summarize(retry.output))")
            }

            lastMessage = push.output
            if attempt < 2 { Thread.sleep(forTimeInterval: 2) }
        }
        throw GitError(message: "多次重试推送仍失败（可能是网络问题）：\n\(Self.summarize(lastMessage))")
    }

    private static func isConflict(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("conflict")
            || lower.contains("could not rebase")
            || lower.contains("non-fast-forward")
            || lower.contains("fetch first")
            || lower.contains("rebase in progress")
    }

    private static func summarize(_ output: String) -> String {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.suffix(6).joined(separator: "\n")
    }

    func commitAndPush(message: String, paths: [String]) throws {
        try commit(message: message, paths: paths)
        try push()
    }

    /// Number of local commits not yet pushed to the upstream branch.
    func countPendingCommits() -> Int {
        let upstream = run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
        guard upstream.status == 0 else { return 0 }
        let count = run(["rev-list", "--count", "@{u}..HEAD"])
        return Int(count.output) ?? 0
    }

    func isRepo() -> Bool {
        run(["rev-parse", "--is-inside-work-tree"]).status == 0
    }
}
