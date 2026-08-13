import Foundation

/// A single scheduled-task config.
/// `weekday`: 1=Sunday ... 7=Saturday; `monthDay`: day of month. At least one must be set.
struct ScheduledTaskConfig: Codable, Equatable, Identifiable {
    var project: String
    var text: String
    var weekday: Int?
    var monthDay: Int?

    var id: String { "\(project)|\(text)|\(weekday ?? 0)|\(monthDay ?? 0)" }

    /// One-line task title for the UI.
    var displayTitle: String {
        text.isEmpty ? project : "\(project) - \(text)"
    }

    /// When this task triggers (weekday name or day-of-month).
    var scheduleLabel: String {
        if let w = weekday {
            return Self.weekdayLabel(w)
        }
        if let d = monthDay {
            return I18n.t("每月\(d)日", "Day \(d)")
        }
        return "—"
    }

    private static func weekdayLabel(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return "?" }
        if I18n.isZH {
            return ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekday]
        }
        return ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday]
    }

    static var weekdayOptions: [(value: Int, label: String)] {
        (1...7).map { ($0, weekdayLabel($0)) }
    }
}

/// todo.config.json structure (missing fields fall back to defaults).
struct TodoConfig: Codable, Equatable {
    var appName = "TodoPanel"
    var locations: [String] = ["PG", "Marriott", "Remote"]
    var scheduledTasks: [ScheduledTaskConfig] = TodoConfig.defaultTasks
    var commitMessagePrefix = "update:"
    var defaultLanguage = "system" // system | zh | en

    static let defaultTasks: [ScheduledTaskConfig] = [
        ScheduledTaskConfig(project: "Report", text: "Send weekly report", weekday: 2, monthDay: nil),
        ScheduledTaskConfig(project: "Ops", text: "Check cloud costs", weekday: 4, monthDay: nil),
        ScheduledTaskConfig(project: "Finance", text: "Renew subscription", weekday: nil, monthDay: 1),
        ScheduledTaskConfig(project: "Finance", text: "Send invoice", weekday: nil, monthDay: 3),
        ScheduledTaskConfig(project: "Report", text: "Log expenses", weekday: nil, monthDay: 5),
        ScheduledTaskConfig(project: "Ops", text: "Top up balance", weekday: nil, monthDay: 20),
    ]

    static let `default` = TodoConfig()
}

extension TodoConfig {
    private enum CodingKeys: String, CodingKey {
        case appName, locations, scheduledTasks, commitMessagePrefix, defaultLanguage
    }

    /// Decode each field independently so a config file missing any key still loads,
    /// using the built-in default for that key only. Empty `locations`/`scheduledTasks`
    /// arrays are preserved (a user can genuinely want zero).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let def = TodoConfig.default
        appName = (try c.decodeIfPresent(String.self, forKey: .appName)).flatMap { $0.isEmpty ? nil : $0 } ?? def.appName
        locations = try c.decodeIfPresent([String].self, forKey: .locations) ?? def.locations
        scheduledTasks = try c.decodeIfPresent([ScheduledTaskConfig].self, forKey: .scheduledTasks) ?? def.scheduledTasks
        commitMessagePrefix = (try c.decodeIfPresent(String.self, forKey: .commitMessagePrefix)).flatMap { $0.isEmpty ? nil : $0 } ?? def.commitMessagePrefix
        defaultLanguage = (try c.decodeIfPresent(String.self, forKey: .defaultLanguage)).flatMap { $0.isEmpty ? nil : $0 } ?? def.defaultLanguage
    }
}

/// Global config loaded from `todo.config.json`; defaults when absent.
enum AppConfig {
    static var shared = TodoConfig.default

    static func configURL(repoPath: String, configPath: String?) -> URL {
        if let configPath, !configPath.isEmpty {
            return URL(fileURLWithPath: configPath)
        }
        return URL(fileURLWithPath: repoPath).appendingPathComponent("todo.config.json")
    }

    /// Repo-relative path when the config file lives inside the repo; nil if outside.
    static func relativePathInRepo(repoPath: String, configPath: String?) -> String? {
        let repo = URL(fileURLWithPath: repoPath).standardized.path
        let cfg = configURL(repoPath: repoPath, configPath: configPath).standardized.path
        guard cfg.hasPrefix(repo + "/") else { return nil }
        return String(cfg.dropFirst(repo.count + 1))
    }

    /// Load config. If `configPath` is given it is used as-is;
    /// otherwise `<repoPath>/todo.config.json` is used.
    static func load(repoPath: String, configPath: String? = nil) {
        let url = configURL(repoPath: repoPath, configPath: configPath)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TodoConfig.self, from: data) else {
            shared = .default
            return
        }
        shared = decoded
    }

    /// Write the given config to disk (no reliance on the global, so it is safe to call off-main).
    static func save(_ config: TodoConfig, repoPath: String, configPath: String?) throws {
        let url = configURL(repoPath: repoPath, configPath: configPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func commitMessage(_ text: String) -> String {
        "\(shared.commitMessagePrefix) \(text)"
    }
}
