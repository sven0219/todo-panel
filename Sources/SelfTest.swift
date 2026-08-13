import Foundation
import SwiftUI
import AppKit

enum SelfTest {
    /// Render off-screen screenshots of the main UI states for documentation.
    /// Usage: TodoPanel --screenshot <outDir> --repo <path-to-demo-repo>
    /// Writes English PNGs to `<outDir>/` and Chinese PNGs to `<outDir>/zh/`.
    @MainActor
    static func renderScreenshots(outDir: String) {
        let repo = argValue("--repo") ?? FileManager.default.currentDirectoryPath
        guard let store = try? WeekStore(repoPath: repo),
              let svc = try? TodoService(store: store) else {
            print("screenshot: bad repo \(repo)")
            exit(1)
        }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let zhDir = (outDir as NSString).appendingPathComponent("zh")
        try? fm.createDirectory(atPath: zhDir, withIntermediateDirectories: true)

        renderScreenshotSet(outDir: outDir, service: svc, language: .en)
        renderScreenshotSet(outDir: zhDir, service: svc, language: .zh)
    }

    @MainActor
    private static func renderScreenshotSet(outDir: String, service: TodoService, language: I18n.Language) {
        service.setLanguageMode(language)
        service.setWeekMode(false)
        service.setMiniFloatEnabled(false)
        service.setPanelExpanded(true)

        let demoDay = DateComponents(calendar: .current, year: 2026, month: 6, day: 10).date!
        service.goToDay(demoDay)
        render(ContentView(service: service), size: CGSize(width: 360, height: 640), to: "\(outDir)/todo-day.png")
        service.setWeekMode(true)
        render(ContentView(service: service), size: CGSize(width: 360, height: 640), to: "\(outDir)/todo-week.png")
        render(SettingsPopover(service: service), size: CGSize(width: 340, height: 520), to: "\(outDir)/todo-settings.png")
        service.setWeekMode(false)
        service.setMiniFloatEnabled(true)
        service.setPanelExpanded(false)
        render(ContentView(service: service), size: CGSize(width: 96, height: 48), to: "\(outDir)/todo-mini.png")
    }

    @MainActor
    private static func render<V: View>(_ view: V, size: CGSize, to path: String) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("screenshot: failed to create bitmap for \(path)")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }

    private static func argValue(_ name: String) -> String? {
        guard let idx = CommandLine.arguments.firstIndex(of: name),
              idx + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[idx + 1]
    }
    /// End-to-end: run clock-in → add todo → clock-out against a real repo, with real git push.
    /// Use on a test branch only.
    static func e2e() -> Never {
        let repo = CommandLine.arguments.first { $0.hasPrefix("--repo=") }?
            .replacingOccurrences(of: "--repo=", with: "")
            ?? FileManager.default.currentDirectoryPath
        do {
            let store = try WeekStore(repoPath: repo)
            let today = Date()
            var week = try store.loadWeek(containing: today)
            let result = try TodoRules.clockIn(today: today, location: "PG", store: store, week: &week)
            print("clockIn: scheduled=\(result.scheduledTasksAdded.map { $0.text }) moved=\(result.movedFromPrevious.count)")
            try store.save(week, message: "test: e2e clock in", push: true)

            var w2 = try store.loadWeek(containing: today)
            var day = store.day(in: &w2, for: today)
            day.completed.append(TodoItem(project: "E2E", text: "自动化测试条目"))
            store.replace(day, in: &w2)
            try store.save(w2, message: "test: e2e add todo", push: true)

            var w3 = try store.loadWeek(containing: today)
            let outResult = try TodoRules.clockOut(today: today, store: store, week: &w3)
            print("clockOut: in=\(outResult.record.clockIn ?? "-") out=\(outResult.record.clockOut ?? "-") loc=\(outResult.record.location ?? "-") dur=\(outResult.record.duration ?? "-")")
            var weeks3 = [w3]
            if let next = outResult.nextWeekToSave { weeks3.append(next) }
            try store.save(weeks3, message: "test: e2e clock out", push: true)

            print("E2E OK")
            exit(0)
        } catch {
            print("E2E FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func run() -> Never {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            if condition {
                print("PASS  \(name)")
            } else {
                failures += 1
                print("FAIL  \(name)")
            }
        }

        do {
            // Group 1: markdown round-trip
            let store1 = try makeRepo()
            store1.pushEnabled = false
            let mon = DateComponents(calendar: .current, year: 2026, month: 8, day: 10).date!
            var week = try store1.loadWeek(containing: mon)
            var monDay = store1.day(in: &week, for: mon)
            monDay.completed.append(TodoItem(project: "Marriott", text: "payment vault 集成", subItems: ["MIC-67324"]))
            monDay.completed.append(TodoItem(project: "Hilton Survey", text: "发送报告"))
            monDay.followup.append(TodoItem(project: "wiredcraft", text: "检查阿里云费用"))
            monDay.time.clockIn = "09:45"
            monDay.time.location = "PG → Marriott"
            monDay.time.clockOut = "18:17"
            monDay.time.duration = "8h 32m"
            store1.replace(monDay, in: &week)
            try store1.save(week, message: "t")

            let reloaded = try store1.loadWeek(containing: mon)
            check(reloaded.days.count == 1, "round-trip: 1 day")
            let d = reloaded.days.first!
            check(d.completed.count == 2, "round-trip: 2 completed")
            check(d.completed[0].project == "Marriott" && d.completed[0].subItems == ["MIC-67324"], "round-trip: sub items")
            check(d.time.clockIn == "09:45" && d.time.location == "PG → Marriott" && d.time.clockOut == "18:17" && d.time.duration == "8h 32m", "round-trip: time record")
            check(d.time.lastLocationName == "Marriott", "round-trip: lastLocationName from multi-location text")

            // Group 2: scheduled tasks
            let monday = DateComponents(calendar: .current, year: 2026, month: 8, day: 10).date!
            let mondayTasks = TodoRules.scheduledTasks(on: monday)
            check(mondayTasks.contains { $0.project == "Report" }, "scheduled: Monday report")
            let wednesday = DateComponents(calendar: .current, year: 2026, month: 8, day: 12).date!
            check(TodoRules.scheduledTasks(on: wednesday).contains { $0.text.contains("Check cloud costs") }, "scheduled: Wednesday cloud")
            let aug3 = DateComponents(calendar: .current, year: 2026, month: 8, day: 3).date!
            let aug3Tasks = TodoRules.scheduledTasks(on: aug3)
            check(aug3Tasks.contains { $0.text.contains("Renew subscription") }, "scheduled: Aug 1 (Sat) deferred to Aug 3")
            let aug5 = DateComponents(calendar: .current, year: 2026, month: 8, day: 5).date!
            check(TodoRules.scheduledTasks(on: aug5).contains { $0.project == "Report" }, "scheduled: Aug 5 expenses")
            let aug20 = DateComponents(calendar: .current, year: 2026, month: 8, day: 20).date!
            check(TodoRules.scheduledTasks(on: aug20).contains { $0.text.contains("Top up balance") }, "scheduled: Aug 20 topup")

            // Group 3: clock-in on a fresh repo
            let store3 = try makeRepo()
            store3.pushEnabled = false
            var w3 = try store3.loadWeek(containing: monday)
            let result = try TodoRules.clockIn(today: monday, location: "PG", store: store3, week: &w3)
            check(result.scheduledTasksAdded.count == 1 && result.scheduledTasksAdded.first?.project == "Report", "clock-in: scheduled added")
            try store3.save(w3, message: "t")
            let md = w3.days.first(where: { $0.date == monday })!
            check(md.time.clockIn != nil && md.time.location == "PG", "clock-in: time & location recorded")
            check(md.followup.count == 1 && md.followup.first?.project == "Report", "clock-in: followup has scheduled item")
            let fileAfterClockIn = try store3.loadWeek(containing: monday)
            let dayAfter = fileAfterClockIn.days.first(where: { $0.date == monday })!
            check(dayAfter.time.location == "PG", "clock-in: location persisted to file")

            // Group 4: previous workday followup moved on clock-in
            let store4 = try makeRepo()
            store4.pushEnabled = false
            let friday = DateComponents(calendar: .current, year: 2026, month: 8, day: 7).date!
            var w4f = try store4.loadWeek(containing: friday)
            var fd4 = store4.day(in: &w4f, for: friday)
            fd4.followup.append(TodoItem(project: "Marriott", text: "上周待办"))
            store4.replace(fd4, in: &w4f)
            try store4.save(w4f, message: "t")
            var w4m = try store4.loadWeek(containing: monday)
            let r4 = try TodoRules.clockIn(today: monday, location: "Remote", store: store4, week: &w4m)
            check(r4.movedFromPrevious.contains { $0.text == "上周待办" }, "clock-in: prev workday followup moved")
            var weeks4 = [w4m]
            if let prev = r4.prevWeekToSave { weeks4.append(prev) }
            try store4.save(weeks4, message: "t")
            let mondayDay4 = try store4.loadWeek(containing: monday)
            check(mondayDay4.days.first(where: { $0.date == monday })!.followup.contains { $0.text == "上周待办" }, "clock-in: moved item present on Monday")
            let fridayAfter4 = try store4.loadWeek(containing: friday)
            check(fridayAfter4.days.first(where: { $0.date == friday })!.followup.isEmpty, "clock-in: removed from Friday")

            // Group 4b: clock-out on Monday moves follow-ups to Tuesday within the same week file
            let store4b = try makeRepo()
            store4b.pushEnabled = false
            let monday4b = DateComponents(calendar: .current, year: 2026, month: 8, day: 10).date!
            let tuesday4b = DateComponents(calendar: .current, year: 2026, month: 8, day: 11).date!
            var w4b = try store4b.loadWeek(containing: monday4b)
            var d4b = store4b.day(in: &w4b, for: monday4b)
            d4b.followup.append(TodoItem(project: "Marriott", text: "同周待办"))
            d4b.time.clockIn = "09:00"
            store4b.replace(d4b, in: &w4b)
            try store4b.save(w4b, message: "t")
            var w4b2 = try store4b.loadWeek(containing: monday4b)
            let out4b = try TodoRules.clockOut(today: monday4b, store: store4b, week: &w4b2)
            check(out4b.nextWeekToSave == nil, "clock-out same week: no extra week file")
            var weeks4b = [w4b2]
            if let next = out4b.nextWeekToSave { weeks4b.append(next) }
            try store4b.save(weeks4b, message: "t")
            let after4b = try store4b.loadWeek(containing: monday4b)
            check(after4b.days.first(where: { $0.date == monday4b })?.followup.isEmpty == true, "clock-out same week: Monday cleared")
            check(after4b.days.first(where: { $0.date == tuesday4b })?.followup.contains { $0.text == "同周待办" } == true, "clock-out same week: Tuesday has item")
            check(after4b.days.first(where: { $0.date == monday4b })?.time.clockOut != nil, "clock-out same week: Monday clock-out saved")

            // Group 5: clock-out on Friday moves follow-ups to next Monday (new week auto-created)
            let store5 = try makeRepo()
            store5.pushEnabled = false
            var w5 = try store5.loadWeek(containing: friday)
            var d5 = store5.day(in: &w5, for: friday)
            d5.followup.append(TodoItem(project: "Marriott", text: "待办A"))
            d5.time.clockIn = "09:00"
            store5.replace(d5, in: &w5)
            try store5.save(w5, message: "t")
            var w5b = try store5.loadWeek(containing: friday)
            let outResult5 = try TodoRules.clockOut(today: friday, store: store5, week: &w5b)
            check(outResult5.record.clockOut != nil, "clock-out: time recorded")
            var weeks5 = [w5b]
            if let next = outResult5.nextWeekToSave { weeks5.append(next) }
            try store5.save(weeks5, message: "t")
            let mondayNext = DateComponents(calendar: .current, year: 2026, month: 8, day: 10).date!
            let nextWeek = try store5.loadWeek(containing: mondayNext)
            check(nextWeek.days.first(where: { $0.date == mondayNext })?.followup.contains { $0.text == "待办A" } == true, "clock-out: 待跟进 moved to next Monday")
            let fridayAfter5 = try store5.loadWeek(containing: friday)
            check(fridayAfter5.days.first(where: { $0.date == friday })?.followup.isEmpty == true, "clock-out: today 待跟进 cleared")

            // Group 5c: partial subtask completion stays open and moves on clock-out
            let store5c = try makeRepo()
            store5c.pushEnabled = false
            let mon5c = DateComponents(calendar: .current, year: 2026, month: 8, day: 10).date!
            let tue5c = DateComponents(calendar: .current, year: 2026, month: 8, day: 11).date!
            var w5c = try store5c.loadWeek(containing: mon5c)
            var d5c = store5c.day(in: &w5c, for: mon5c)
            let partial = TodoItem(project: "Marriott", text: "pipeline", subItems: ["~~A~~", "B"])
            check(!partial.isFullyComplete, "subtask: partial item not fully complete")
            d5c.completed.append(partial)
            d5c.time.clockIn = "09:00"
            store5c.replace(d5c, in: &w5c)
            try store5c.save(w5c, message: "t")
            var w5c2 = try store5c.loadWeek(containing: mon5c)
            _ = try TodoRules.clockOut(today: mon5c, store: store5c, week: &w5c2)
            try store5c.save(w5c2, message: "t")
            let after5c = try store5c.loadWeek(containing: mon5c)
            check(after5c.days.first(where: { $0.date == mon5c })?.completed.isEmpty == true, "clock-out partial: Monday completed cleared")
            let tueDay5c = after5c.days.first(where: { $0.date == tue5c })
            check(tueDay5c?.followup.contains { $0.text == "pipeline" } == true, "clock-out partial: moved to Tuesday")
            check(tueDay5c?.followup.first(where: { $0.text == "pipeline" })?.subItems == ["~~A~~", "B"], "clock-out partial: subtasks preserved")

            // Group 5b: day lookups with non-midnight dates must reuse the same day
            let store6 = try makeRepo()
            store6.pushEnabled = false
            // Friday afternoon — next workday is Monday (different week file).
            let now = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 15, minute: 30))!
            var w6a = try store6.loadWeek(containing: now)
            _ = try TodoRules.clockIn(today: now, location: "Remote", store: store6, week: &w6a)
            try store6.save(w6a, message: "t")
            var w6b = try store6.loadWeek(containing: now)
            var d6b = store6.day(in: &w6b, for: now)
            check(d6b.time.clockIn != nil && d6b.time.location == "Remote", "non-midnight: clock-in preserved on reload")
            d6b.followup.append(TodoItem(project: "X", text: "y"))
            store6.replace(d6b, in: &w6b)
            try store6.save(w6b, message: "t")
            var w6c = try store6.loadWeek(containing: now)
            check(w6c.days.count == 1, "non-midnight: no duplicate day sections")
            let outResult6 = try TodoRules.clockOut(today: now, store: store6, week: &w6c)
            check(outResult6.record.clockIn != nil, "non-midnight: clock-out sees clock-in")
            var weeks6 = [w6c]
            if let next = outResult6.nextWeekToSave { weeks6.append(next) }
            try store6.save(weeks6, message: "t")
            let final6 = try store6.loadWeek(containing: now)
            check(final6.days.count == 1, "non-midnight: single day after clock out")

            // Group 6: duration + weekly summary
            check(TodoRules.duration(from: "09:45", to: "18:17") == "8h 32m", "duration: normal")
            check(TodoRules.duration(from: "23:00", to: "01:00") == "2h 0m", "duration: overnight")
            check(TodoRules.parseDuration("45h 22min") == 45 * 60 + 22, "parseDuration: min suffix")
            let summary = WeeklySummary.buildSummary(week: reloaded)
            check(summary.contains("总时长: 8h 32m"), "summary: total duration")
            check(summary.contains("**Marriott**"), "summary: project grouped")

            // Group 6b: English time labels round-trip
            let prevLang = I18n.mode
            I18n.mode = .en
            let enWeek = WeekFile(year: 2026, week: 33, startDate: mon, endDate: mon, days: [d])
            let enText = MarkdownCodec.serialize(enWeek)
            check(enText.contains("Clock-in:") && enText.contains("Clock-out:"), "i18n: English time labels on serialize")
            let enParsed = try MarkdownCodec.parse(enText, week: 2026, weekNumber: 33, start: mon, end: mon)
            check(enParsed.days.first?.time.clockIn == "09:45", "i18n: English time labels parse")
            I18n.mode = prevLang

            // Group 6c: duplicate day headings merge on parse
            let dupMd = """
            # 2026-W33 Weekly Log

            ## 2026-08-10 Mon

            ### Follow-up
            - **A** - first

            ## 2026-08-10 Mon

            ### Follow-up
            - **B** - second
            """
            let dupParsed = try MarkdownCodec.parse(dupMd, week: 2026, weekNumber: 33, start: mon, end: mon)
            check(dupParsed.days.count == 1, "dedupe: one day after merge")
            check(dupParsed.days.first?.followup.count == 2, "dedupe: items merged")

            // Group 6d: todo.config.json scheduled task CRUD
            let cfgStore = try makeRepo()
            cfgStore.pushEnabled = false
            let cfgURL = cfgStore.repoPath + "/todo.config.json"
            AppConfig.load(repoPath: cfgStore.repoPath, configPath: cfgURL)
            var cfg = AppConfig.shared
            cfg.scheduledTasks = [
                ScheduledTaskConfig(project: "A", text: "one", weekday: 2, monthDay: nil)
            ]
            AppConfig.shared = cfg
            try AppConfig.save(cfg, repoPath: cfgStore.repoPath, configPath: cfgURL)
            AppConfig.load(repoPath: cfgStore.repoPath, configPath: cfgURL)
            check(AppConfig.shared.scheduledTasks.count == 1, "config: save/load tasks")
            AppConfig.shared.scheduledTasks.append(
                ScheduledTaskConfig(project: "B", text: "two", weekday: nil, monthDay: 15)
            )
            try AppConfig.save(AppConfig.shared, repoPath: cfgStore.repoPath, configPath: cfgURL)
            AppConfig.load(repoPath: cfgStore.repoPath, configPath: cfgURL)
            check(AppConfig.shared.scheduledTasks.count == 2, "config: append task")
            AppConfig.shared.scheduledTasks.removeAll { $0.project == "A" }
            try AppConfig.save(AppConfig.shared, repoPath: cfgStore.repoPath, configPath: cfgURL)
            AppConfig.load(repoPath: cfgStore.repoPath, configPath: cfgURL)
            check(AppConfig.shared.scheduledTasks.count == 1 && AppConfig.shared.scheduledTasks[0].project == "B",
                  "config: delete task")

            // Group 7: serialize real sample stays parseable
            if let sample = try? String(contentsOfFile: samplePath, encoding: .utf8) {
                let parsed = try MarkdownCodec.parse(sample, week: 2026, weekNumber: 32,
                                                     start: DateComponents(calendar: .current, year: 2026, month: 8, day: 3).date!,
                                                     end: DateComponents(calendar: .current, year: 2026, month: 8, day: 9).date!)
                check(parsed.days.count > 0, "sample: parses days")
                let reserialized = MarkdownCodec.serialize(parsed)
                let parsedAgain = try MarkdownCodec.parse(reserialized, week: 2026, weekNumber: 32,
                                                          start: parsed.startDate, end: parsed.endDate)
                check(parsedAgain.days.count == parsed.days.count, "sample: re-parse stable")
                check(parsedAgain.days.first?.completed.count == parsed.days.first?.completed.count, "sample: item counts stable")
            } else {
                check(true, "sample: skip (not found)")
            }
        } catch {
            failures += 1
            print("FAIL  unexpected error: \(error)")
        }

        print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) TEST(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    /// Create a fresh temp git repo with an AGENTS.md.
    private static func makeRepo() throws -> WeekStore {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("todopanel-selftest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try shell("-C", tmp.path, "init", "-q")
        try "".write(to: tmp.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try shell("-C", tmp.path, "add", "-A")
        try shell("-C", tmp.path, "commit", "-q", "-m", "init")
        try shell("-C", tmp.path, "branch", "-M", "main")
        return try WeekStore(repoPath: tmp.path)
    }

    private static var samplePath: String {
        CommandLine.arguments.first { $0.hasPrefix("--sample=") }?.replacingOccurrences(of: "--sample=", with: "") ?? ""
    }

    @discardableResult
    private static func shell(_ args: String...) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
