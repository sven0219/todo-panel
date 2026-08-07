import Foundation

/// A single scheduled-task config.
/// `weekday`: 1=Sunday ... 7=Saturday; `monthDay`: day of month. At least one must be set.
struct ScheduledTaskConfig: Codable, Equatable {
    var project: String
    var text: String
    var weekday: Int?
    var monthDay: Int?
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

/// Global config loaded from `todo.config.json`; defaults when absent.
enum AppConfig {
    static var shared = TodoConfig.default

    /// Load config. If `configPath` is given it is used as-is;
    /// otherwise `<repoPath>/todo.config.json` is used.
    static func load(repoPath: String, configPath: String? = nil) {
        let url: URL
        if let configPath, !configPath.isEmpty {
            url = URL(fileURLWithPath: configPath)
        } else {
            url = URL(fileURLWithPath: repoPath).appendingPathComponent("todo.config.json")
        }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TodoConfig.self, from: data) else {
            shared = .default
            return
        }
        let def = TodoConfig.default
        shared = TodoConfig(
            appName: decoded.appName.isEmpty ? def.appName : decoded.appName,
            locations: decoded.locations.isEmpty ? def.locations : decoded.locations,
            scheduledTasks: decoded.scheduledTasks.isEmpty ? def.scheduledTasks : decoded.scheduledTasks,
            commitMessagePrefix: decoded.commitMessagePrefix.isEmpty ? def.commitMessagePrefix : decoded.commitMessagePrefix,
            defaultLanguage: decoded.defaultLanguage.isEmpty ? def.defaultLanguage : decoded.defaultLanguage
        )
    }

    static func commitMessage(_ text: String) -> String {
        "\(shared.commitMessagePrefix) \(text)"
    }
}
