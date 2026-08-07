import Foundation

struct StoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Reads/writes week files and the weekly summary, committing & pushing via git.
final class WeekStore: @unchecked Sendable {
    let repoPath: String
    let weeksDir: URL
    let git: GitManager
    private let fileManager = FileManager.default
    /// When false, saves skip git commit/push (used for tests/dry-run).
    var pushEnabled: Bool = true

    init(repoPath: String) throws {
        self.repoPath = repoPath
        self.weeksDir = URL(fileURLWithPath: repoPath).appendingPathComponent("weeks")
        self.git = GitManager(repoPath: repoPath)
        if !git.isRepo() {
            throw StoreError(message: "\(repoPath) 不是 git 仓库")
        }
    }

    func url(for file: WeekFile) -> URL {
        let yearDir = weeksDir.appendingPathComponent("\(file.year)")
        return yearDir.appendingPathComponent(ISOWeek.fileName(year: file.year, week: file.week, start: file.startDate, end: file.endDate))
    }

    /// Load (or create) the week file containing `date`.
    func loadWeek(containing date: Date) throws -> WeekFile {
        let (year, weekNum, start, end) = ISOWeek.components(for: date)
        let dir = weeksDir.appendingPathComponent("\(year)")
        let url = dir.appendingPathComponent(ISOWeek.fileName(year: year, week: weekNum, start: start, end: end))
        if fileManager.fileExists(atPath: url.path) {
            let text = try String(contentsOf: url, encoding: .utf8)
            return try MarkdownCodec.parse(text, week: year, weekNumber: weekNum, start: start, end: end)
        }
        return WeekFile(year: year, week: weekNum, startDate: start, endDate: end, days: [])
    }

    /// Get or create the DayRecord for `date` inside `week`.
    func day(in week: inout WeekFile, for date: Date) -> DayRecord {
        if let existing = week.days.first(where: { DateMath.isSameDay($0.date, date) }) {
            return existing
        }
        let record = DayRecord(date: date)
        week.days.append(record)
        week.days.sort { $0.date > $1.date }
        return record
    }

    /// Overwrite a specific day inside the week.
    func replace(_ day: DayRecord, in week: inout WeekFile) {
        if let idx = week.days.firstIndex(where: { DateMath.isSameDay($0.date, day.date) }) {
            week.days[idx] = day
        } else {
            week.days.append(day)
        }
        week.days.sort { $0.date > $1.date }
    }

    /// Write file, always commit locally. Push only when enabled (`push ?? pushEnabled`).
    /// Pass `push: false` for batch mode (commit only, flush later).
    func save(_ file: WeekFile, message: String, push: Bool? = nil) throws {
        let url = self.url(for: file)
        let content = MarkdownCodec.serialize(file)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        if push ?? pushEnabled {
            try git.commitAndPush(message: message)
        } else {
            try git.commit(message: message)
        }
    }

    /// Pull + push any locally committed (but not yet pushed) changes.
    func flushPush() throws {
        try git.push()
    }

    /// Number of local commits not yet pushed.
    func pendingPushCount() -> Int {
        git.countPendingCommits()
    }

    /// Scan all week files for `**Project**` and return historical project names by frequency.
    func knownProjects() -> [String] {
        var counts: [String: Int] = [:]
        guard let enumerator = fileManager.enumerator(at: weeksDir, includingPropertiesForKeys: nil) else {
            return []
        }
        for case let url as URL in enumerator where url.pathExtension == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let nsRange = NSRange(text.startIndex..., in: text)
            for match in Self.projectRegex.matches(in: text, range: nsRange) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let name = String(text[range]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { counts[name, default: 0] += 1 }
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    private static let projectRegex = try! NSRegularExpression(pattern: #"\*\*([^*]+?)\*\*"#)

    /// Load the previous ISO week's file (relative to `date`) if it exists.
    func loadPreviousWeek(before date: Date) throws -> WeekFile? {
        guard let prevStart = Calendar.current.date(byAdding: .day, value: -7, to: ISOWeek.components(for: date).start) else { return nil }
        let (year, weekNum, start, end) = ISOWeek.components(for: prevStart)
        let dir = weeksDir.appendingPathComponent("\(year)")
        let url = dir.appendingPathComponent(ISOWeek.fileName(year: year, week: weekNum, start: start, end: end))
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try MarkdownCodec.parse(text, week: year, weekNumber: weekNum, start: start, end: end)
    }

    // MARK: - Weekly summary (README.md)

    func loadSummary() -> String? {
        let url = URL(fileURLWithPath: repoPath).appendingPathComponent("README.md")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func saveSummary(_ text: String, message: String, push: Bool? = nil) throws {
        let url = URL(fileURLWithPath: repoPath).appendingPathComponent("README.md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        if push ?? pushEnabled {
            try git.commitAndPush(message: message)
        } else {
            try git.commit(message: message)
        }
    }
}
