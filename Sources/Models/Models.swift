import Foundation

/// Appearance mode: system / light / dark.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    var id: String { rawValue }
}

enum Location: String, CaseIterable, Identifiable, Codable {
    case pg = "PG"
    case marriott = "Marriott"
    case remote = "Remote"

    var id: String { rawValue }
}

struct TimeRecord: Codable, Equatable {
    var clockIn: String?
    /// Raw location text as stored in the file, e.g. "PG" or "PG → Marriott".
    var location: String?
    var clockOut: String?
    var duration: String?

    var isComplete: Bool {
        clockIn != nil && clockOut != nil
    }

    /// Last known location name, used by the UI picker.
    var lastLocationName: String? {
        guard let loc = location else { return nil }
        return loc.split(separator: "→").last.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

struct TodoItem: Identifiable, Hashable, Codable {
    let id: UUID
    var project: String
    var text: String
    var subItems: [String]

    init(id: UUID = UUID(), project: String, text: String, subItems: [String] = []) {
        self.id = id
        self.project = project
        self.text = text
        self.subItems = subItems
    }

    var display: String {
        text.isEmpty ? project : "\(project) - \(text)"
    }

    /// Whether a subtask is done (marked by wrapping in `~~`).
    func isSubDone(_ sub: String) -> Bool {
        sub.hasPrefix("~~") && sub.hasSuffix("~~")
    }

    /// Display text of a subtask with the done markers stripped.
    func subDisplay(_ sub: String) -> String {
        isSubDone(sub) ? String(sub.dropFirst(2).dropLast(2)) : sub
    }

    /// Toggle a single subtask's done state.
    func toggledSub(_ sub: String) -> String {
        if isSubDone(sub) { return subDisplay(sub) }
        return "~~\(sub)~~"
    }

    /// True when the item has no subtasks, or every subtask is marked done.
    var isFullyComplete: Bool {
        subItems.isEmpty || subItems.allSatisfy { isSubDone($0) }
    }
}

enum DaySection {
    case completed([TodoItem])
    case uncompleted([TodoItem])
    case followup([TodoItem])
    case timeRecord(TimeRecord)
}

struct DayRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    var completed: [TodoItem]
    var uncompleted: [TodoItem]
    var followup: [TodoItem]
    var time: TimeRecord

    init(date: Date) {
        self.id = UUID()
        self.date = date
        self.completed = []
        self.uncompleted = []
        self.followup = []
        self.time = TimeRecord()
    }
}

struct WeekFile {
    let year: Int
    let week: Int
    let startDate: Date
    let endDate: Date
    var days: [DayRecord]
}

struct ClockInResult {
    var scheduledTasksAdded: [TodoItem]
    var movedFromPrevious: [TodoItem]
    /// Previous ISO week file to save together with the current week (follow-up removal).
    var prevWeekToSave: WeekFile?
}

struct ClockOutResult {
    var record: TimeRecord
    /// Next ISO week file to save together with the current week (follow-up transfer).
    var nextWeekToSave: WeekFile?
}
