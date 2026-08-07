import Foundation

struct TodoRules {

    // MARK: - Scheduled tasks

    /// Tasks that should trigger on `date`. Fixed-date tasks on weekends defer to the next workday.
    /// Tasks come from `todo.config.json` (AppConfig.shared.scheduledTasks).
    static func scheduledTasks(on date: Date) -> [TodoItem] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        return AppConfig.shared.scheduledTasks.compactMap { task -> TodoItem? in
            if let w = task.weekday {
                return weekday == w ? TodoItem(project: task.project, text: task.text) : nil
            }
            if let d = task.monthDay {
                var comps = cal.dateComponents([.year, .month], from: date)
                comps.day = d
                var candidate = cal.date(from: comps)!
                if DateMath.isWeekend(candidate) {
                    candidate = DateMath.nextWorkday(after: candidate)
                }
                return cal.startOfDay(for: candidate) == cal.startOfDay(for: date)
                    ? TodoItem(project: task.project, text: task.text)
                    : nil
            }
            return nil
        }
    }

    // MARK: - Clock in

    /// Record clock-in time & location, add scheduled tasks on first clock-in,
    /// and move the previous workday's follow-ups to today.
    static func clockIn(today: Date, location: String,
                        store: WeekStore,
                        week: inout WeekFile) throws -> ClockInResult {
        var day = store.day(in: &week, for: today)
        let firstClockInToday = day.time.clockIn == nil
        let dayHadFollowup = !day.followup.isEmpty

        var scheduledAdded: [TodoItem] = []
        if firstClockInToday {
            scheduledAdded = scheduledTasks(on: today)
            day.followup.append(contentsOf: scheduledAdded)
        }
        day.time.clockIn = day.time.clockIn ?? Self.timeNow()
        day.time.location = location
        store.replace(day, in: &week)

        var moved: [TodoItem] = []
        if let prev = try previousWorkdayFollowup(before: today, store: store), !prev.items.isEmpty, !dayHadFollowup {
            var prevWeek = prev.week
            var prevDay = prev.day
            prevDay.followup.removeAll { item in prev.items.contains { $0.id == item.id } }
            prevWeek.days = prevWeek.days.map { DateMath.isSameDay($0.date, prevDay.date) ? prevDay : $0 }
            try store.save(prevWeek, message: AppConfig.commitMessage("move 待跟进 to next workday"))

            day.followup.append(contentsOf: prev.items)
            moved = prev.items
            store.replace(day, in: &week)
        }
        return ClockInResult(scheduledTasksAdded: scheduledAdded, movedFromPrevious: moved)
    }

    // MARK: - Clock out

    static func clockOut(today: Date, store: WeekStore, week: inout WeekFile) throws -> TimeRecord {
        var day = store.day(in: &week, for: today)
        day.time.clockOut = Self.timeNow()
        if let start = day.time.clockIn {
            day.time.duration = Self.duration(from: start, to: day.time.clockOut!)
        }
        store.replace(day, in: &week)

        // Move today's follow-ups to the next workday.
        if !day.followup.isEmpty {
            let next = DateMath.nextWorkday(after: today)
            var nextWeek = try store.loadWeek(containing: next)
            var nextDay = store.day(in: &nextWeek, for: next)
            nextDay.followup.append(contentsOf: day.followup)
            store.replace(nextDay, in: &nextWeek)
            day.followup.removeAll()
            store.replace(day, in: &week)
            try store.save(nextWeek, message: AppConfig.commitMessage("move todos to next workday"))
        }
        return day.time
    }

    // MARK: - Previous workday follow-ups

    private struct PrevDay {
        let week: WeekFile
        let date: Date
        let day: DayRecord
        let items: [TodoItem]
    }

    private static func previousWorkdayFollowup(before date: Date, store: WeekStore) throws -> PrevDay? {
        guard let prev = DateMath.previousWorkday(before: date) else { return nil }
        let week = try store.loadWeek(containing: prev)
        if let day = week.days.first(where: { DateMath.isSameDay($0.date, prev) }), !day.followup.isEmpty {
            return PrevDay(week: week, date: prev, day: day, items: day.followup)
        }
        return nil
    }

    // MARK: - Helpers

    static func timeNow() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: Date())
    }

    static func duration(from start: String, to end: String) -> String {
        func minutes(_ s: String) -> Int? {
            let parts = s.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return parts[0] * 60 + parts[1]
        }
        guard let s = minutes(start), let e = minutes(end) else { return "" }
        let total = e >= s ? e - s : (24 * 60 - s + e)
        let h = total / 60
        let m = total % 60
        return "\(h)h \(m)m"
    }

    static func parseDuration(_ s: String) -> Int? {
        var minutes = 0
        let tokens = s.replacingOccurrences(of: "min", with: "m")
            .split(separator: " ")
        for token in tokens {
            let t = token.trimmingCharacters(in: .whitespaces)
            if t.hasSuffix("h"), let v = Int(t.dropLast()) { minutes += v * 60 }
            if t.hasSuffix("m"), let v = Int(t.dropLast()) { minutes += v }
        }
        return minutes == 0 && s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : minutes
    }
}
