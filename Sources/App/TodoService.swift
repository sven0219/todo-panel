import Foundation
import SwiftUI
import AppKit

@MainActor
final class TodoService: ObservableObject {
    /// Real current date (anchor for "back to today").
    @Published var today: Date
    /// Date currently shown in the UI; navigable via ◀ ▶.
    @Published var viewDate: Date
    /// Week view mode: browse each day's duration/completion counts by week.
    @Published private(set) var weekMode = false
    /// Week view: day records of the currently viewed week (incl. empty days).
    @Published private(set) var weekDays: [DayRecord] = []
    @Published var day: DayRecord
    @Published var lastError: String?
    @Published var lastNotice: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var pendingPushCount = 0
    @Published private(set) var knownProjects: [String] = []
    @Published var alwaysOnTop = true
    @Published private(set) var launchAtLogin = false
    /// UI language: system / zh / en.
    @Published private(set) var languageMode: I18n.Language = .system
    /// Appearance: system / light / dark.
    @Published private(set) var appearanceMode: AppearanceMode = .system
    /// Manually specified repo path; empty = auto-detect.
    @Published private(set) var repoPathOverride = ""

    /// Effective repo path (override first, otherwise auto-detect).
    var effectiveRepoPath: String? {
        repoPathOverride.isEmpty ? RepoLocator.locate() : repoPathOverride
    }
    @Published var immediatePush: Bool {
        didSet {
            UserDefaults.standard.set(immediatePush, forKey: "immediatePush")
            store.pushEnabled = immediatePush
        }
    }

    let store: WeekStore
    private var week: WeekFile
    private let syncQueue = DispatchQueue(label: "com.todopanel.sync", qos: .userInitiated)

    init(store: WeekStore) throws {
        self.store = store
        AppConfig.load(from: store.repoPath)
        let today = Date()
        self.today = today
        self.viewDate = today
        self.immediatePush = UserDefaults.standard.bool(forKey: "immediatePush")
        self.alwaysOnTop = UserDefaults.standard.object(forKey: "alwaysOnTop") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "alwaysOnTop")
        self.repoPathOverride = UserDefaults.standard.string(forKey: "repoPathOverride") ?? ""
        self.launchAtLogin = LoginItem.isEnabled
        let savedLang = UserDefaults.standard.string(forKey: "languageMode")
        let langMode: I18n.Language
        if let savedLang, !savedLang.isEmpty {
            langMode = I18n.Language(rawValue: savedLang) ?? .system
        } else if AppConfig.shared.defaultLanguage == "zh" {
            langMode = .zh
        } else if AppConfig.shared.defaultLanguage == "en" {
            langMode = .en
        } else {
            langMode = .system
        }
        let appMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system
        var week = try store.loadWeek(containing: today)
        let day = store.day(in: &week, for: today)
        self.day = day
        self.week = week
        self.languageMode = langMode
        I18n.mode = langMode
        self.appearanceMode = appMode
        store.pushEnabled = self.immediatePush
        pendingPushCount = store.pendingPushCount()
        loadKnownProjects()
    }

    /// Scan historical project names in the background.
    private func loadKnownProjects() {
        let store = store
        syncQueue.async { [weak self] in
            let projects = store.knownProjects()
            DispatchQueue.main.async { [weak self] in
                self?.knownProjects = projects
            }
        }
    }

    var isWorking: Bool { day.time.clockIn != nil }
    var clockInTime: String? { day.time.clockIn }
    var clockOutTime: String? { day.time.clockOut }
    var duration: String? { day.time.duration }
    var locationName: String? { day.time.lastLocationName }
    var locations: [String] { AppConfig.shared.locations }
    var appName: String { AppConfig.shared.appName }

    /// Today's worked time: recorded duration if clocked out, else live elapsed since clock-in.
    var workedHoursText: String {
        if let dur = day.time.duration, !dur.isEmpty {
            return dur
        }
        if let inTime = day.time.clockIn {
            return TodoRules.duration(from: inTime, to: TodoRules.timeNow())
        }
        return "0h 0m"
    }

    func setAlwaysOnTop(_ value: Bool) {
        alwaysOnTop = value
        UserDefaults.standard.set(value, forKey: "alwaysOnTop")
    }

    func setRepoPathOverride(_ value: String) {
        repoPathOverride = value.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(repoPathOverride, forKey: "repoPathOverride")
    }

    func setLaunchAtLogin(_ value: Bool) {
        do {
            try LoginItem.setEnabled(value)
            launchAtLogin = value
            lastError = nil
        } catch {
            lastError = "开机自启设置失败：\(error.localizedDescription)"
        }
    }

    func setLanguageMode(_ value: I18n.Language) {
        I18n.mode = value
        languageMode = value
        UserDefaults.standard.set(value.rawValue, forKey: "languageMode")
    }

    func setAppearanceMode(_ value: AppearanceMode) {
        appearanceMode = value
        UserDefaults.standard.set(value.rawValue, forKey: "appearanceMode")
    }

    // MARK: - Date navigation

    func selectPreviousDay() {
        guard !isSyncing else { return }
        let delta = weekMode ? -7 : -1
        setViewDate(Calendar.current.date(byAdding: .day, value: delta, to: viewDate)!)
    }

    func selectNextDay() {
        guard !isSyncing else { return }
        let delta = weekMode ? 7 : 1
        setViewDate(Calendar.current.date(byAdding: .day, value: delta, to: viewDate)!)
    }

    func goToday() {
        guard !isSyncing else { return }
        setViewDate(today)
    }

    func setWeekMode(_ value: Bool) {
        weekMode = value
        if value { refreshWeek() }
    }

    func toggleWeekMode() {
        setWeekMode(!weekMode)
    }

    /// Click a day in week view → switch back to day view.
    func goToDay(_ date: Date) {
        weekMode = false
        setViewDate(date)
    }

    /// Total duration of the currently viewed week.
    var weekTotalText: String {
        var minutes = 0
        for day in weekDays {
            if let dur = day.time.duration, let m = TodoRules.parseDuration(dur) {
                minutes += m
            }
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func setViewDate(_ date: Date) {
        viewDate = date
        loadDay()
        if weekMode { refreshWeek() }
    }

    private func refreshWeek() {
        do {
            let week = try store.loadWeek(containing: viewDate)
            let (_, _, start, end) = ISOWeek.components(for: viewDate)
            var result: [DayRecord] = []
            var d = start
            while d <= end {
                let rec = week.days.first(where: { DateMath.isSameDay($0.date, d) })
                    ?? DayRecord(date: d)
                result.append(rec)
                d = Calendar.current.date(byAdding: .day, value: 1, to: d)!
            }
            result.sort { $0.date > $1.date }
            weekDays = result
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func loadDay() {
        do {
            var w = try store.loadWeek(containing: viewDate)
            let d = store.day(in: &w, for: viewDate)
            week = w
            day = d
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Clock

    func clockIn(location: String) {
        guard !isSyncing else { return }
        beginSync()
        let store = store
        let date = viewDate

        syncQueue.async { [weak self] in
            do {
                var week = try store.loadWeek(containing: date)
                let result = try TodoRules.clockIn(
                    today: date,
                    location: location,
                    store: store,
                    week: &week
                )
                try store.save(week, message: AppConfig.commitMessage("上班打卡 \(TodoRules.timeNow()) 地点 \(location)"))
                _ = try? WeeklySummary.ensure(forToday: date, store: store)

                var notices: [String] = []
                if !result.scheduledTasksAdded.isEmpty {
                    notices.append("已添加定时任务：\(result.scheduledTasksAdded.map { $0.project }.joined(separator: "、"))")
                }
                if !result.movedFromPrevious.isEmpty {
                    notices.append("已转移昨日待跟进 \(result.movedFromPrevious.count) 条")
                }
                self?.finishSync(store: store, date: date, notice: notices.isEmpty ? "上班记录已同步" : notices.joined(separator: "；"))
            } catch {
                Logger.log("clockIn error: \(error.localizedDescription)")
                self?.finishSync(store: store, date: date, error: error)
            }
        }
    }

    func clockOut() {
        guard !isSyncing else { return }
        beginSync()
        let store = store
        let date = viewDate

        syncQueue.async { [weak self] in
            do {
                var week = try store.loadWeek(containing: date)
                let record = try TodoRules.clockOut(today: date, store: store, week: &week)
                try store.save(week, message: AppConfig.commitMessage("下班打卡 \(record.clockOut ?? "") 时长 \(record.duration ?? "")"))
                _ = try? WeeklySummary.ensure(forToday: date, store: store)
                // Clock-out must push immediately so the follow-up transfer, weekly summary, etc. are all synced.
                try store.flushPush()
                self?.finishSync(
                    store: store,
                    date: date,
                    notice: "已下班 \(record.clockOut ?? "")，时长 \(record.duration ?? "")，已同步到远端"
                )
            } catch {
                Logger.log("clockOut error: \(error.localizedDescription)")
                self?.finishSync(store: store, date: date, error: error)
            }
        }
    }

    // MARK: - List operations

    func setLocation(_ loc: String) {
        guard !isSyncing else { return }
        day.time.location = loc
        persist("更新地点为 \(loc)")
    }

    func addTodo(project: String, text: String, toCompleted: Bool = false) {
        guard !isSyncing else { return }
        guard !project.trimmingCharacters(in: .whitespaces).isEmpty else {
            lastError = "项目名不能为空"
            return
        }
        let item = TodoItem(
            project: project.trimmingCharacters(in: .whitespaces),
            text: text.trimmingCharacters(in: .whitespaces)
        )
        if toCompleted {
            day.completed.append(item)
        } else {
            day.followup.append(item)
        }
        persist("添加待办 \(item.display)")
    }

    func deleteTodo(_ item: TodoItem, fromCompleted: Bool = false) {
        guard !isSyncing else { return }
        if fromCompleted {
            day.completed.removeAll { $0.id == item.id }
        } else {
            day.followup.removeAll { $0.id == item.id }
        }
        persist("删除待办 \(item.display)")
    }

    func updateTodo(_ item: TodoItem, project: String, text: String, subItems: [String]) {
        guard !isSyncing else { return }
        guard !project.trimmingCharacters(in: .whitespaces).isEmpty else {
            lastError = "项目名不能为空"
            return
        }
        var updated = item
        updated.project = project.trimmingCharacters(in: .whitespaces)
        updated.text = text.trimmingCharacters(in: .whitespaces)
        updated.subItems = subItems.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let idx = day.followup.firstIndex(where: { $0.id == item.id }) {
            day.followup[idx] = updated
        } else if let idx = day.completed.firstIndex(where: { $0.id == item.id }) {
            day.completed[idx] = updated
        }
        persist("修改待办 \(updated.display)")
    }

    func moveTodo(_ item: TodoItem, toCompleted: Bool) {
        guard !isSyncing else { return }
        let action = toCompleted ? "标记完成" : "移回待办"
        if toCompleted {
            day.followup.removeAll { $0.id == item.id }
            if !day.completed.contains(where: { $0.id == item.id }) {
                day.completed.append(item)
            }
        } else {
            day.completed.removeAll { $0.id == item.id }
            if !day.followup.contains(where: { $0.id == item.id }) {
                day.followup.append(item)
            }
        }
        persist("\(action) \(item.display)")
    }

    /// Toggle a subtask's done state: completing moves the whole item to Done;
    /// cancelling in Done moves it back to Todo if no other subtask is done.
    func toggleSubItem(_ item: TodoItem, sub: String) {
        guard !isSyncing else { return }
        var updated = item
        let wasDone = item.isSubDone(sub)
        updated.subItems = updated.subItems.map { $0 == sub ? item.toggledSub(sub) : $0 }
        let anyDone = updated.subItems.contains { updated.isSubDone($0) }

        let inFollowup = day.followup.contains { $0.id == item.id }
        let inCompleted = day.completed.contains { $0.id == item.id }

        if inFollowup {
            day.followup.removeAll { $0.id == item.id }
            if !day.completed.contains(where: { $0.id == item.id }) {
                day.completed.append(updated)
            }
        } else if inCompleted {
            day.completed.removeAll { $0.id == item.id }
            if anyDone {
                if !day.completed.contains(where: { $0.id == item.id }) {
                    day.completed.append(updated)
                }
            } else {
                if !day.followup.contains(where: { $0.id == item.id }) {
                    day.followup.append(updated)
                }
            }
        }
        persist("子事项\(wasDone ? "恢复" : "完成") \(updated.display)")
    }

    func moveTodos(_ items: [TodoItem], toCompleted: Bool) {
        guard !isSyncing else { return }
        let action = toCompleted ? "标记完成" : "移回待办"
        for item in items {
            if toCompleted {
                day.followup.removeAll { $0.id == item.id }
                if !day.completed.contains(where: { $0.id == item.id }) { day.completed.append(item) }
            } else {
                day.completed.removeAll { $0.id == item.id }
                if !day.followup.contains(where: { $0.id == item.id }) { day.followup.append(item) }
            }
        }
        persist("\(action) \(items.map { $0.display }.joined(separator: "、"))")
    }

    func move(_ item: TodoItem, offset: Int) {
        guard !isSyncing else { return }
        func reorder(_ arr: inout [TodoItem]) {
            guard let idx = arr.firstIndex(where: { $0.id == item.id }) else { return }
            let target = idx + offset
            guard target >= 0 && target < arr.count else { return }
            arr.swapAt(idx, target)
        }
        if day.followup.contains(where: { $0.id == item.id }) {
            reorder(&day.followup)
        } else if day.completed.contains(where: { $0.id == item.id }) {
            reorder(&day.completed)
        }
        persist("调整待办顺序 \(item.display)")
    }

    // MARK: - Background sync

    private func persist(_ label: String) {
        store.replace(day, in: &week)
        let snapshot = week
        let store = store
        let date = viewDate
        beginSync()

        syncQueue.async { [weak self] in
            do {
                try store.save(snapshot, message: AppConfig.commitMessage(label))
                _ = try? WeeklySummary.ensure(forToday: date, store: store)
                self?.finishSync(store: store, date: date, notice: "已保存")
            } catch {
                Logger.log("persist(\(label)) error: \(error.localizedDescription)")
                self?.finishSync(store: store, date: date, error: error)
            }
        }
    }

    /// Pull + push all locally committed changes. Runs in the background.
    func flushPush() {
        guard !isSyncing else { return }
        beginSync()
        let store = store
        let date = viewDate
        syncQueue.async { [weak self] in
            do {
                try store.flushPush()
                self?.finishSync(store: store, date: date, notice: "已同步到远端")
            } catch {
                Logger.log("flushPush error: \(error.localizedDescription)")
                self?.finishSync(store: store, date: date, error: error)
            }
        }
    }

    /// Best-effort push on quit (async, non-blocking; data is already committed locally).
    func shutdown() {
        let store = store
        syncQueue.async {
            try? store.flushPush()
        }
    }

    private func beginSync() {
        isSyncing = true
        lastError = nil
        lastNotice = nil
    }

    nonisolated private func finishSync(
        store: WeekStore,
        date: Date,
        notice: String? = nil,
        error: Error? = nil
    ) {
        let pending = store.pendingPushCount()
        do {
            var refreshedWeek = try store.loadWeek(containing: date)
            let refreshedDay = store.day(in: &refreshedWeek, for: date)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.week = refreshedWeek
                self.day = refreshedDay
                self.pendingPushCount = pending
                self.lastNotice = notice
                self.lastError = error?.localizedDescription
                self.isSyncing = false
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.pendingPushCount = pending
                self?.lastError = error.localizedDescription
                self?.isSyncing = false
            }
        }
    }

    /// Refresh the unsynced count from git (runs in background).
    func refreshPendingCount() {
        let store = store
        syncQueue.async { [weak self] in
            let count = store.pendingPushCount()
            DispatchQueue.main.async { [weak self] in
                self?.pendingPushCount = count
            }
        }
    }
}
