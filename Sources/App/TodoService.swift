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
    /// Mini float: collapsed pill on screen; click to expand.
    @Published private(set) var miniFloatEnabled = false
    /// Runtime expanded state when mini float is on (not persisted).
    @Published private(set) var panelExpanded = true
    @Published private(set) var launchAtLogin = false
    /// UI language: system / zh / en.
    @Published private(set) var languageMode: I18n.Language = .system
    /// Appearance: system / light / dark.
    @Published private(set) var appearanceMode: AppearanceMode = .system
    /// Manually specified repo path; empty = auto-detect.
    @Published private(set) var repoPathOverride = ""
    /// Manually specified config file path; empty = use `<repoPath>/todo.config.json`.
    @Published private(set) var configPathOverride = ""
    @Published private(set) var scheduledTasks: [ScheduledTaskConfig] = []

    /// Effective repo path (override first, otherwise auto-detect).
    var effectiveRepoPath: String? {
        WeekStore.resolveRepoPath(override: repoPathOverride)
    }
    @Published private(set) var immediatePush: Bool

    let store: WeekStore
    private var week: WeekFile
    private let syncQueue = DispatchQueue(label: "com.todopanel.sync", qos: .userInitiated)
    private var syncWatchdog: DispatchWorkItem?

    init(store: WeekStore) throws {
        self.store = store
        let configOverride = UserDefaults.standard.string(forKey: "configPathOverride") ?? ""
        self.configPathOverride = configOverride
        AppConfig.load(repoPath: store.repoPath, configPath: configOverride)
        let today = Date()
        self.today = today
        self.viewDate = today
        self.immediatePush = UserDefaults.standard.bool(forKey: "immediatePush")
        self.alwaysOnTop = UserDefaults.standard.object(forKey: "alwaysOnTop") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "alwaysOnTop")
        // Mini float is session-only; always start expanded with the setting off.
        self.miniFloatEnabled = false
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
        reloadScheduledTasks()
        pendingPushCount = store.pendingPushCount()
        loadKnownProjects()
    }

    /// Scan historical project names in the background.
    private func loadKnownProjects() {
        let store = store
        syncQueue.async { [weak self] in
            let projects = store.knownProjects()
            Task { @MainActor [weak self] in
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

    /// Advance the today anchor when the calendar day rolls over (menu-bar apps stay open overnight).
    func refreshTodayIfNeeded() {
        let now = Date()
        guard !DateMath.isSameDay(today, now) else { return }
        today = now
    }

    func setImmediatePush(_ value: Bool) {
        immediatePush = value
        UserDefaults.standard.set(value, forKey: "immediatePush")
        store.pushEnabled = value
    }

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

    func setMiniFloatEnabled(_ value: Bool) {
        miniFloatEnabled = value
        if !value {
            panelExpanded = true
        }
    }

    func setPanelExpanded(_ value: Bool) {
        guard miniFloatEnabled else {
            panelExpanded = true
            return
        }
        panelExpanded = value
    }

    func setRepoPathOverride(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard WeekStore.resolveRepoPath(override: trimmed) != nil else {
            lastError = I18n.t("无法打开该仓库路径", "Cannot open that repo path")
            return false
        }
        repoPathOverride = trimmed
        UserDefaults.standard.set(trimmed, forKey: "repoPathOverride")
        lastError = nil
        return true
    }

    /// Set an explicit config file path (empty = use `<repoPath>/todo.config.json`).
    /// Reloads the config immediately.
    func setConfigPathOverride(_ value: String) {
        configPathOverride = value.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(configPathOverride, forKey: "configPathOverride")
        AppConfig.load(repoPath: store.repoPath, configPath: configPathOverride)
        reloadScheduledTasks()
    }

    private func reloadScheduledTasks() {
        scheduledTasks = AppConfig.shared.scheduledTasks
    }

    func addScheduledTask(project: String, text: String, weekday: Int?, monthDay: Int?) {
        guard let task = validatedScheduledTask(project: project, text: text, weekday: weekday, monthDay: monthDay) else { return }
        persistScheduledTasks(label: "add scheduled task \(task.displayTitle)") { config in
            config.scheduledTasks.append(task)
        }
    }

    func updateScheduledTask(replacingId id: String, project: String, text: String, weekday: Int?, monthDay: Int?) {
        guard let task = validatedScheduledTask(project: project, text: text, weekday: weekday, monthDay: monthDay) else { return }
        guard AppConfig.shared.scheduledTasks.contains(where: { $0.id == id }) else {
            lastError = I18n.t("找不到该任务", "Task not found")
            return
        }
        persistScheduledTasks(label: "edit scheduled task \(task.displayTitle)") { config in
            guard let idx = config.scheduledTasks.firstIndex(where: { $0.id == id }) else { return }
            config.scheduledTasks[idx] = task
        }
    }

    func deleteScheduledTask(_ task: ScheduledTaskConfig) {
        persistScheduledTasks(label: "delete scheduled task \(task.displayTitle)") { config in
            config.scheduledTasks.removeAll { $0.id == task.id }
        }
    }

    private func validatedScheduledTask(project: String, text: String, weekday: Int?, monthDay: Int?) -> ScheduledTaskConfig? {
        let p = project.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else {
            lastError = I18n.t("项目名不能为空", "Project name cannot be empty")
            return nil
        }
        guard weekday != nil || monthDay != nil else {
            lastError = I18n.t("请选择重复周期", "Choose a schedule")
            return nil
        }
        if let d = monthDay, !(1...31).contains(d) {
            lastError = I18n.t("日期需在 1–31 之间", "Day must be 1–31")
            return nil
        }
        lastError = nil
        return ScheduledTaskConfig(
            project: p,
            text: text.trimmingCharacters(in: .whitespaces),
            weekday: weekday,
            monthDay: monthDay
        )
    }

    private func persistScheduledTasks(label: String, mutate: (inout TodoConfig) -> Void) {
        guard !isSyncing else { return }
        let backup = AppConfig.shared
        var config = AppConfig.shared
        mutate(&config)
        AppConfig.shared = config
        scheduledTasks = config.scheduledTasks
        beginSync()

        let store = store
        let configPath = configPathOverride
        let push = store.pushEnabled
        let message = AppConfig.commitMessage(label)

        syncQueue.async { [weak self] in
            do {
                try AppConfig.save(repoPath: store.repoPath, configPath: configPath)
                if let rel = AppConfig.relativePathInRepo(repoPath: store.repoPath, configPath: configPath) {
                    try store.commit(paths: [rel], message: message, push: push)
                }
                Task { @MainActor [weak self] in
                    self?.completeSync(
                        notice: I18n.t("定时任务已保存", "Scheduled tasks saved"),
                        refreshPending: true
                    )
                }
            } catch {
                AppConfig.shared = backup
                Task { @MainActor [weak self] in
                    self?.scheduledTasks = backup.scheduledTasks
                    self?.completeSync(error: error, refreshPending: false)
                }
            }
        }
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
        refreshTodayIfNeeded()
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
        refreshTodayIfNeeded()
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
                var weeks = [week]
                if let prev = result.prevWeekToSave { weeks.append(prev) }
                try store.save(weeks, message: AppConfig.commitMessage("clock in \(TodoRules.timeNow()) at \(location)"))
                _ = try? WeeklySummary.ensure(forToday: date, store: store)

                var notices: [String] = []
                if !result.scheduledTasksAdded.isEmpty {
                    notices.append(I18n.t("已添加定时任务：\(result.scheduledTasksAdded.map { $0.project }.joined(separator: "、"))",
                                          "Scheduled tasks added: \(result.scheduledTasksAdded.map { $0.project }.joined(separator: ", "))"))
                }
                if !result.movedFromPrevious.isEmpty {
                    notices.append(I18n.t("已转移昨日待跟进 \(result.movedFromPrevious.count) 条",
                                          "Moved \(result.movedFromPrevious.count) follow-ups from yesterday"))
                }
                self?.finishSync(store: store, date: date, notice: notices.isEmpty
                    ? I18n.t("上班记录已同步", "Clock-in synced")
                    : notices.joined(separator: I18n.t("；", "; ")))
            } catch {
                Logger.log("clockIn error: \(error.localizedDescription)")
                self?.finishSync(store: store, date: date, error: error)
            }
        }
    }

    func clockOut() {
        guard !isSyncing else { return }
        refreshTodayIfNeeded()
        beginSync()
        let store = store
        let date = viewDate

        syncQueue.async { [weak self] in
            do {
                var week = try store.loadWeek(containing: date)
                let outResult = try TodoRules.clockOut(today: date, store: store, week: &week)
                var weeks = [week]
                if let next = outResult.nextWeekToSave { weeks.append(next) }
                try store.save(weeks, message: AppConfig.commitMessage("clock out \(outResult.record.clockOut ?? "") duration \(outResult.record.duration ?? "")"))
                _ = try? WeeklySummary.ensure(forToday: date, store: store)
                // Clock-out must push immediately so the follow-up transfer, weekly summary, etc. are all synced.
                try store.flushPush()
                self?.finishSync(
                    store: store,
                    date: date,
                    notice: I18n.t("已下班 \(outResult.record.clockOut ?? "")，时长 \(outResult.record.duration ?? "")，已同步到远端",
                                    "Clocked out \(outResult.record.clockOut ?? ""), duration \(outResult.record.duration ?? ""), synced")
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
        persist("update location to \(loc)")
    }

    func addTodo(project: String, text: String, toCompleted: Bool = false) {
        guard !isSyncing else { return }
        guard !project.trimmingCharacters(in: .whitespaces).isEmpty else {
            lastError = I18n.t("项目名不能为空", "Project name cannot be empty")
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
        persist("add todo \(item.display)")
    }

    func deleteTodo(_ item: TodoItem, fromCompleted: Bool = false) {
        guard !isSyncing else { return }
        if fromCompleted {
            day.completed.removeAll { $0.id == item.id }
        } else {
            day.followup.removeAll { $0.id == item.id }
        }
        persist("delete todo \(item.display)")
    }

    func updateTodo(_ item: TodoItem, project: String, text: String, subItems: [String]) {
        guard !isSyncing else { return }
        guard !project.trimmingCharacters(in: .whitespaces).isEmpty else {
            lastError = I18n.t("项目名不能为空", "Project name cannot be empty")
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
        persist("edit todo \(updated.display)")
    }

    func moveTodo(_ item: TodoItem, toCompleted: Bool) {
        guard !isSyncing else { return }
        let action = toCompleted ? "mark done" : "move to todo"
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

    /// Toggle a subtask's done state. The parent moves to Done only when every subtask is done.
    func toggleSubItem(_ item: TodoItem, sub: String) {
        guard !isSyncing else { return }
        var updated = item
        let wasDone = item.isSubDone(sub)
        updated.subItems = updated.subItems.map { $0 == sub ? item.toggledSub(sub) : $0 }

        let inFollowup = day.followup.contains { $0.id == item.id }
        let inCompleted = day.completed.contains { $0.id == item.id }

        if inFollowup {
            day.followup.removeAll { $0.id == item.id }
            if updated.isFullyComplete {
                if !day.completed.contains(where: { $0.id == item.id }) {
                    day.completed.append(updated)
                }
            } else {
                day.followup.append(updated)
            }
        } else if inCompleted {
            day.completed.removeAll { $0.id == item.id }
            if updated.isFullyComplete {
                day.completed.append(updated)
            } else {
                day.followup.append(updated)
            }
        }
        persist("subtask \(wasDone ? "restore" : "done") \(updated.display)")
    }

    func moveTodos(_ items: [TodoItem], toCompleted: Bool) {
        guard !isSyncing else { return }
        let action = toCompleted ? "mark done" : "move to todo"
        for item in items {
            if toCompleted {
                day.followup.removeAll { $0.id == item.id }
                if !day.completed.contains(where: { $0.id == item.id }) { day.completed.append(item) }
            } else {
                day.completed.removeAll { $0.id == item.id }
                if !day.followup.contains(where: { $0.id == item.id }) { day.followup.append(item) }
            }
        }
        persist("\(action) \(items.map { $0.display }.joined(separator: ", "))")
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
        persist("reorder todo \(item.display)")
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
                self?.finishSync(store: store, date: date, notice: I18n.t("已保存", "Saved"))
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
                self?.finishSync(store: store, date: date, notice: I18n.t("已同步到远端", "Synced to remote"))
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
        syncWatchdog?.cancel()
        isSyncing = true
        lastError = nil
        lastNotice = nil

        let watchdog = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isSyncing else { return }
                Logger.log("sync watchdog: timed out")
                self.completeSync(
                    error: StoreError(message: I18n.t("同步超时，请稍后重试", "Sync timed out; try again later")),
                    refreshPending: true
                )
            }
        }
        syncWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: watchdog)
    }

    /// Apply sync completion on the main actor (always clears `isSyncing`).
    private func completeSync(
        week refreshedWeek: WeekFile? = nil,
        day refreshedDay: DayRecord? = nil,
        pending: Int? = nil,
        notice: String? = nil,
        error: Error? = nil,
        refreshPending: Bool = false
    ) {
        syncWatchdog?.cancel()
        if let refreshedWeek, let refreshedDay {
            week = refreshedWeek
            day = refreshedDay
        }
        if let pending {
            pendingPushCount = pending
        } else if refreshPending {
            refreshPendingCount()
        }
        lastNotice = notice
        lastError = error?.localizedDescription
        isSyncing = false
        if weekMode { refreshWeek() }
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
            Task { @MainActor [weak self] in
                self?.completeSync(
                    week: refreshedWeek,
                    day: refreshedDay,
                    pending: pending,
                    notice: notice,
                    error: error
                )
            }
        } catch let loadError {
            Task { @MainActor [weak self] in
                self?.completeSync(
                    pending: pending,
                    notice: notice,
                    error: error ?? loadError
                )
            }
        }
    }

    /// Refresh the unsynced count from git (runs in background).
    func refreshPendingCount() {
        let store = store
        syncQueue.async {
            let count = store.pendingPushCount()
            Task { @MainActor [weak self] in
                self?.pendingPushCount = count
            }
        }
    }
}
