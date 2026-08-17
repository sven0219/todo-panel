import Foundation

enum ParseError: LocalizedError {
    case noHeader
    var errorDescription: String? { "无法识别的周记录文件" }
}

enum MarkdownCodec {

    /// Parse markdown text into a WeekFile.
    static func parse(_ text: String, week year: Int, weekNumber: Int, start: Date, end: Date) throws -> WeekFile {
        var file = WeekFile(year: year, week: weekNumber, startDate: start, endDate: end, days: [])

        var currentDay: DayRecord?
        var currentCategory: Category?
        var lineBuffer: [String] = []

        func flushBuffer(into day: inout DayRecord) {
            guard let cat = currentCategory else {
                lineBuffer.removeAll()
                return
            }
            let items = parseTodoLines(lineBuffer)
            switch cat {
            case .completed:
                for item in items {
                    if let leave = Self.leaveType(from: item) {
                        if day.time.leave == nil { day.time.leave = leave }
                    } else {
                        day.completed.append(item)
                    }
                }
            case .uncompleted: day.uncompleted.append(contentsOf: items)
            case .followup: day.followup.append(contentsOf: items)
            case .timeRecord: day.time = parseTimeRecord(lineBuffer)
            }
            lineBuffer.removeAll()
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\r", with: "")
            if line.hasPrefix("## ") {
                if var day = currentDay {
                    flushBuffer(into: &day)
                    file.days.append(day)
                }
                let dateStr = line.dropFirst(3).split(separator: " ").first.map(String.init) ?? ""
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                let date = fmt.date(from: dateStr) ?? start
                let day = DayRecord(date: date)
                currentCategory = nil
                currentDay = day
            } else if line.hasPrefix("### ") {
                if currentDay != nil {
                    flushBuffer(into: &currentDay!)
                }
                let title = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                currentCategory = Category(title: title)
            } else if line.hasPrefix("# ") {
                continue
            } else if line.isEmpty {
                if let day = currentDay {
                    _ = day // buffer flush on next category; ignore blank
                }
            } else {
                if currentDay != nil {
                    lineBuffer.append(line)
                }
            }
        }
        if var day = currentDay {
            flushBuffer(into: &day)
            file.days.append(day)
        }
        file.days = deduplicateDays(file.days)
        file.days.sort { $0.date > $1.date }
        return file
    }

    /// Merge duplicate day sections (same calendar date) from hand-edited files.
    private static func deduplicateDays(_ days: [DayRecord]) -> [DayRecord] {
        var byDay: [Date: DayRecord] = [:]
        for day in days {
            let key = DateMath.startOfDay(day.date)
            if var existing = byDay[key] {
                existing.completed.append(contentsOf: day.completed)
                existing.uncompleted.append(contentsOf: day.uncompleted)
                existing.followup.append(contentsOf: day.followup)
                if day.time.clockIn != nil { existing.time.clockIn = day.time.clockIn }
                if day.time.location != nil { existing.time.location = day.time.location }
                if day.time.clockOut != nil { existing.time.clockOut = day.time.clockOut }
                if day.time.duration != nil { existing.time.duration = day.time.duration }
                if day.time.leave != nil { existing.time.leave = day.time.leave }
                byDay[key] = existing
            } else {
                byDay[key] = day
            }
        }
        return Array(byDay.values)
    }

    private enum Category {
        case completed
        case uncompleted
        case followup
        case timeRecord

        /// Both Chinese and English section titles are recognized when parsing.
        init?(title: String) {
            switch title {
            case "今日完成", "Completed": self = .completed
            case "今日未完成", "Unfinished": self = .uncompleted
            case "待跟进", "Follow-up": self = .followup
            case "时间记录", "Time Record": self = .timeRecord
            default: return nil
            }
        }

        /// Outputs the title in the current language when writing.
        var title: String {
            switch self {
            case .completed: return I18n.t("今日完成", "Completed")
            case .uncompleted: return I18n.t("今日未完成", "Unfinished")
            case .followup: return I18n.t("待跟进", "Follow-up")
            case .timeRecord: return I18n.t("时间记录", "Time Record")
            }
        }
    }

    /// Detect whether a completed item is actually a leave record (legacy data stored
    /// leave as a plain completed line, e.g. `- 年假`, `- 休假`, or `- **病假**`).
    /// Returns a normalized leave type string, or nil for a normal todo item.
    private static func leaveType(from item: TodoItem) -> String? {
        if item.project.isEmpty {
            return normalizeLeave(item.text)
        }
        if item.text.isEmpty {
            return normalizeLeave(item.project)
        }
        return nil
    }

    /// Normalize free-form leave text (e.g. `状态: 休病假`, `公共假期，端午节`,
    /// `Sick Leave`, `Public Holiday`) into a canonical leave type matching the
    /// configured `leaveTypes` where possible. Bilingual: matches zh and en keywords.
    private static func normalizeLeave(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        for prefix in ["状态:", "状态：", "Status:", "Status："] {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard !s.isEmpty else { return nil }
        let configured = AppConfig.shared.leaveTypes
        if configured.contains(s) { return s }
        let lower = s.lowercased()
        // Ordered from most specific to least specific.
        let categories: [(keywords: [String], fallback: String)] = [
            (["病假", "sick"], "病假"),
            (["年假", "annual"], "年假"),
            (["法定", "公共假期", "节假日", "public holiday", "statutory"], "法定假期"),
            (["假期", "休假", "leave", "假", "休"], "年假"),
        ]
        for cat in categories {
            if cat.keywords.contains(where: { lower.contains($0.lowercased()) }) {
                return pickLeave(cat.fallback, from: configured)
            }
        }
        return nil
    }

    private static func pickLeave(_ keyword: String, from configured: [String]) -> String {
        configured.first(where: { $0.localizedCaseInsensitiveContains(keyword) }) ?? keyword
    }

    private static func parseTodoLines(_ lines: [String]) -> [TodoItem] {
        var items: [TodoItem] = []
        for line in lines {
            if line.hasPrefix("- ") {
                let rest = line.dropFirst(2)
                if let project = extractProject(from: String(rest)) {
                    items.append(TodoItem(project: project.project, text: project.text, subItems: []))
                } else {
                    items.append(TodoItem(project: "", text: String(rest)))
                }
            } else if line.hasPrefix("  - ") {
                if !items.isEmpty {
                    items[items.count - 1].subItems.append(String(line.dropFirst(4)))
                }
            } else {
                // stray line, attach to last item's text area
                if !items.isEmpty {
                    items[items.count - 1].subItems.append(line)
                }
            }
        }
        return items
    }

    /// Extract `**Project**` and optional `- text`.
    private static func extractProject(from rest: String) -> (project: String, text: String)? {
        guard rest.hasPrefix("**") else { return nil }
        let body = rest.dropFirst(2)
        guard let idx = body.range(of: "**") else { return nil }
        let project = String(body[body.startIndex..<idx.lowerBound])
        var text = ""
        let remainder = body[idx.upperBound...]
        var trimmed = remainder.drop { $0 == " " || $0 == "-" }
        trimmed = trimmed.drop { $0 == " " }
        text = String(trimmed)
        return (project, text)
    }

    private static func parseTimeRecord(_ lines: [String]) -> TimeRecord {
        var record = TimeRecord()
        for line in lines {
            let stripped = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
            let parts = stripped.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let value = parts[1]
            switch parts[0] {
            case "上班", "Clock-in": record.clockIn = value
            case "下班", "Clock-out": record.clockOut = value
            case "时长", "Duration": record.duration = value
            case "地点", "Location": record.location = value
            case "休假", "Leave": record.leave = value
            case "状态", "Status":
                if let leave = Self.normalizeLeave(value) { record.leave = leave }
            default: break
            }
        }
        return record
    }

    /// Serialize a WeekFile back to markdown.
    static func serialize(_ file: WeekFile) -> String {
        var out: [String] = []
        out.append("# \(file.year)-W\(file.week) \(I18n.t("本周记录", "Weekly Log"))")
        out.append("")
        let daysDesc = file.days.sorted { $0.date > $1.date }
        for day in daysDesc {
            let heading = DayName.heading(day.date)
            out.append("- [\(heading)](#\(anchor(of: heading)))")
        }
        out.append("")
        for day in daysDesc {
            out.append("## \(DayName.heading(day.date))")
            out.append("")
            if !day.completed.isEmpty {
                out.append("### \(Category.completed.title)")
                for item in day.completed { out.append(contentsOf: serializeItem(item)) }
                out.append("")
            }
            if !day.uncompleted.isEmpty {
                out.append("### \(Category.uncompleted.title)")
                for item in day.uncompleted { out.append(contentsOf: serializeItem(item)) }
                out.append("")
            }
            if !day.followup.isEmpty {
                out.append("### \(Category.followup.title)")
                for item in day.followup { out.append(contentsOf: serializeItem(item)) }
                out.append("")
            }
            if let time = serializeTime(day.time) {
                out.append("### \(Category.timeRecord.title)")
                out.append("")
                out.append(contentsOf: time)
                out.append("")
            }
        }
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n") + "\n"
    }

    private static func serializeItem(_ item: TodoItem) -> [String] {
        var lines: [String] = []
        let bullet: String
        if item.project.isEmpty {
            bullet = "- \(item.text)"
        } else if item.text.isEmpty {
            bullet = "- **\(item.project)**"
        } else {
            bullet = "- **\(item.project)** - \(item.text)"
        }
        lines.append(bullet)
        for sub in item.subItems { lines.append("  - \(sub)") }
        return lines
    }

    private static func serializeTime(_ time: TimeRecord) -> [String]? {
        var lines: [String] = []
        if let leave = time.leave { lines.append("- \(I18n.t("休假", "Leave")): \(leave)") }
        if let inTime = time.clockIn { lines.append("- \(I18n.t("上班", "Clock-in")): \(inTime)") }
        if let loc = time.location { lines.append("- \(I18n.t("地点", "Location")): \(loc)") }
        if let out = time.clockOut { lines.append("- \(I18n.t("下班", "Clock-out")): \(out)") }
        if let dur = time.duration { lines.append("- \(I18n.t("时长", "Duration")): \(dur)") }
        return lines.isEmpty ? nil : lines
    }

    static func anchor(of heading: String) -> String {
        heading.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
