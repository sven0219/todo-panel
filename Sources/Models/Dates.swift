import Foundation

enum DayName {
    static func weekdays() -> [String] {
        ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    }

    static func weekdayName(from date: Date) -> String {
        if I18n.isZH {
            let comps = Calendar.current.dateComponents([.weekday], from: date)
            let index = ((comps.weekday ?? 1) + 5) % 7
            return weekdays()[index]
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = "EEE"
            return fmt.string(from: date)
        }
    }

    static func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    static func heading(_ date: Date) -> String {
        "\(dateString(date)) \(weekdayName(from: date))"
    }
}

enum DateMath {
    /// Next workday (Mon-Fri) strictly after `date`.
    static func nextWorkday(after date: Date) -> Date {
        var d = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        while isWeekend(d) {
            d = Calendar.current.date(byAdding: .day, value: 1, to: d)!
        }
        return d
    }

    /// The most recent workday strictly before `date`.
    static func previousWorkday(before date: Date) -> Date? {
        var d = Calendar.current.date(byAdding: .day, value: -1, to: date)!
        var guardCount = 0
        while isWeekend(d) && guardCount < 10 {
            d = Calendar.current.date(byAdding: .day, value: -1, to: d)!
            guardCount += 1
        }
        return isWeekend(d) ? nil : d
    }

    static func isWeekend(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// Next occurrence of the given weekday (1=Sun ... 7=Sat), strictly after date, or date itself if matches today.
    static func sameOrNext(_ date: Date, weekday target: Int, orToday: Bool = true) -> Date {
        let cur = Calendar.current.component(.weekday, from: date)
        if orToday && cur == target { return date }
        var diff = (target - cur + 7) % 7
        if diff == 0 { diff = 7 }
        return Calendar.current.date(byAdding: .day, value: diff, to: date)!
    }

    static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, inSameDayAs: b)
    }
}

enum ISOWeek {
    static func components(for date: Date) -> (year: Int, week: Int, start: Date, end: Date) {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let week = cal.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        let weekNum = week.weekOfYear ?? 1
        let year = week.yearForWeekOfYear ?? Calendar.current.component(.year, from: date)
        let start = cal.date(from: DateComponents(weekday: 2, weekOfYear: weekNum, yearForWeekOfYear: year))!
        let end = cal.date(byAdding: .day, value: 6, to: start)!
        return (year, weekNum, start, end)
    }

    static func fileName(year: Int, week: Int, start: Date, end: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMdd"
        return "\(year)-W\(week)-\(fmt.string(from: start))-\(fmt.string(from: end)).md"
    }

    static func isInSameWeek(_ d1: Date, _ d2: Date) -> Bool {
        let a = components(for: d1)
        let b = components(for: d2)
        return a.year == b.year && a.week == b.week
    }
}
