import Foundation

struct WeeklySummary {

    /// On Monday, if last week's summary is missing, generate and prepend it.
    /// Returns the summary text if one was written.
    static func ensure(forToday today: Date, store: WeekStore, push: Bool? = nil, messagePrefix: String) throws -> String? {
        let cal = Calendar.current
        guard cal.component(.weekday, from: today) == 2 else { return nil }

        let (_, _, start, _) = ISOWeek.components(for: today)
        guard let prevStart = cal.date(byAdding: .day, value: -7, to: start) else { return nil }
        let (py, pw, pstart, pend) = ISOWeek.components(for: prevStart)

        guard let prevWeek = try store.loadPreviousWeek(before: today) else { return nil }

        let heading = "[\(py)-W\(pw)](weeks/\(py)/\(ISOWeek.fileName(year: py, week: pw, start: pstart, end: pend)))"
        if let existing = store.loadSummary(), existing.contains(heading) {
            return nil
        }

        let summary = buildSummary(week: prevWeek)
        var text = "# Weekly Summary\n\n"
        if let existing = store.loadSummary(), !existing.isEmpty {
            var body = existing
            body = body.trimmingCharacters(in: .newlines)
            body = body.replacingOccurrences(of: "# Weekly Summary", with: "")
            body = body.trimmingCharacters(in: .newlines)
            text += "## \(heading)\n\n" + summary + "\n\n" + body + "\n"
        } else {
            text += "## \(heading)\n\n" + summary + "\n"
        }
        try store.saveSummary(text, message: "\(messagePrefix) add README summary for \(py)-W\(pw)", push: push)
        return summary
    }

    static func buildSummary(week: WeekFile) -> String {
        var lines: [String] = []
        var projectTexts: [String: [String]] = [:]
        var totalMinutes = 0

        for day in week.days.sorted(by: { $0.date < $1.date }) {
            if let dur = day.time.duration, let mins = TodoRules.parseDuration(dur) {
                totalMinutes += mins
            }
            for item in day.completed {
                let key = item.project.isEmpty ? "其他" : item.project
                var texts = projectTexts[key] ?? []
                var t = item.text
                if !item.subItems.isEmpty {
                    t += "（" + item.subItems.joined(separator: "、") + "）"
                }
                if !t.isEmpty { texts.append(t) }
                projectTexts[key] = texts
            }
        }

        for (project, texts) in projectTexts.sorted(by: { $0.key < $1.key }) {
            let detail = texts.joined(separator: "、")
            lines.append("- **\(project)**\(detail.isEmpty ? "" : " - \(detail)")")
        }

        let h = totalMinutes / 60
        let m = totalMinutes % 60
        lines.append("- 总时长: \(h)h \(m)m")
        return lines.joined(separator: "\n")
    }
}
