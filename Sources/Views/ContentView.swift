import SwiftUI

struct ContentView: View {
    @ObservedObject var service: TodoService

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )

            VStack(spacing: 0) {
                HeaderBar(service: service)
                ClockBar(service: service)
                Divider().opacity(0.4)

                ScrollView {
                    if service.weekMode {
                        WeekView(service: service)
                            .padding(14)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                                }
                            )
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                        TodoSection(
                            title: I18n.t("待办", "Todo"),
                            icon: "circle.dotted",
                            color: Palette.primary,
                            items: service.day.followup,
                            addPlaceholderProject: I18n.t("项目", "Project"),
                            addPlaceholderText: I18n.t("事项", "Task"),
                            service: service,
                            toCompleted: true
                        )
                        if !service.day.uncompleted.isEmpty {
                            TodoSection(
                                title: I18n.t("今日未完成", "Unfinished"),
                                icon: "circle.slash",
                                color: Palette.uncompleted,
                                items: service.day.uncompleted,
                                addPlaceholderProject: "",
                                addPlaceholderText: "",
                                service: service,
                                toCompleted: true,
                                showAdd: false
                            )
                        }
                        TodoSection(
                            title: I18n.t("已完成", "Done"),
                            icon: "checkmark.circle.fill",
                            color: Palette.completed,
                            items: service.day.completed,
                            addPlaceholderProject: I18n.t("项目", "Project"),
                            addPlaceholderText: I18n.t("事项", "Task"),
                            service: service,
                            toCompleted: false,
                            initiallyCollapsed: true
                        )
                    }
                    .padding(14)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                        }
                    )
                    }
                }
                .scrollIndicators(.never)
                .onPreferenceChange(ContentHeightKey.self) { height in
                    NotificationCenter.default.post(
                        name: .panelContentHeightChanged,
                        object: nil,
                        userInfo: ["height": height]
                    )
                }

                if let notice = service.lastNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
                if let error = service.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                            .lineLimit(2)
                        Spacer()
                        Button(I18n.t("重试", "Retry")) {
                            service.lastError = nil
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 360)
        .onAppear { service.lastError = nil }
    }
}

struct HeaderBar: View {
    @ObservedObject var service: TodoService
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                service.selectPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(I18n.t("前一天", "Previous day"))

            Text(DayName.heading(service.viewDate))
                .font(.headline)
                .fontDesign(.rounded)
                .frame(minWidth: 96, maxWidth: 120)

            Button {
                service.selectNextDay()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(I18n.t("后一天", "Next day"))

            if !DateMath.isSameDay(service.viewDate, service.today) {
                Button(I18n.t("回到今天", "Today")) {
                    service.goToday()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Palette.primary)
                .fixedSize()
            }
            Spacer()
            Button {
                service.flushPush()
            } label: {
                HStack(spacing: 4) {
                    if service.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                        Text(I18n.t("同步中", "Syncing"))
                    } else if service.pendingPushCount > 0 {
                        Image(systemName: "arrow.up.circle")
                        Text(I18n.t("未同步 \(service.pendingPushCount)", "Unsynced \(service.pendingPushCount)"))
                    } else {
                        Image(systemName: "checkmark.circle")
                        Text(I18n.t("已同步", "Synced"))
                    }
                }
                .font(.caption2.bold())
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(syncColor))
                .fixedSize()
            }
            .buttonStyle(.plain)
            .disabled(service.isSyncing)
            .help(I18n.t("点击同步到远端", "Sync now"))

            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingSettings) {
                SettingsPopover(service: service)
            }
            .help(I18n.t("设置", "Settings"))
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(I18n.t("退出", "Quit"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var syncColor: Color {
        if service.isSyncing { return .gray }
        if service.pendingPushCount > 0 { return Palette.unsynced }
        return Palette.synced
    }
}

struct SettingsPopover: View {
    @ObservedObject var service: TodoService
    @State private var repoPathInput = ""
    @State private var configPathInput = ""

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(I18n.t("外观", "Appearance"))
                    .font(.caption.bold())
                Spacer()
                Picker("", selection: Binding(
                    get: { service.appearanceMode },
                    set: { service.setAppearanceMode($0) }
                )) {
                    Text(I18n.t("跟随系统", "System")).tag(AppearanceMode.system)
                    Text(I18n.t("浅色", "Light")).tag(AppearanceMode.light)
                    Text(I18n.t("深色", "Dark")).tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            HStack {
                Text(I18n.t("语言", "Language"))
                    .font(.caption.bold())
                Spacer()
                Picker("", selection: Binding(
                    get: { service.languageMode },
                    set: { service.setLanguageMode($0) }
                )) {
                    Text(I18n.t("跟随系统", "System")).tag(I18n.Language.system)
                    Text("中文").tag(I18n.Language.zh)
                    Text("English").tag(I18n.Language.en)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Divider()
            Toggle(I18n.t("每次操作立即推送", "Push on every action"), isOn: Binding(
                get: { service.immediatePush },
                set: { service.setImmediatePush($0) }
            ))
            Text(I18n.t("关闭时：操作先本地提交，每 10 分钟统一推送，退出时自动推送。",
                        "When off: changes commit locally, pushed together every 10 minutes, and flushed on quit."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle(I18n.t("窗口置顶", "Always on top"), isOn: Binding(
                get: { service.alwaysOnTop },
                set: { service.setAlwaysOnTop($0) }
            ))
            Text(I18n.t("关闭后窗口可以被其他应用遮挡。", "The panel can be covered by other apps when off."))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Divider()
            Toggle(I18n.t("开机自启", "Launch at login"), isOn: Binding(
                get: { service.launchAtLogin },
                set: { service.setLaunchAtLogin($0) }
            ))
            Text(I18n.t("登录 macOS 时自动启动。需将 App 放入「应用程序」，首次开启可能需在系统设置里允许。",
                        "Auto-start when you log in. Move the app to Applications; first time may need approval in System Settings."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(I18n.t("仓库路径", "Repo path"))
                .font(.caption.bold())
            HStack(spacing: 6) {
                TextField(I18n.t("例如 ~/work/todo", "e.g. ~/work/todo"), text: $repoPathInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onAppear { repoPathInput = service.repoPathOverride }
                Button {
                    if let p = PathPicker.chooseDirectory() {
                        repoPathInput = p
                    }
                } label: {
                    Label(I18n.t("选择…", "Choose…"), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(I18n.t("应用", "Apply")) {
                    if !service.setRepoPathOverride(repoPathInput) {
                        repoPathInput = service.repoPathOverride
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(I18n.t("留空则自动检测（打包脚本所在仓库）；修改后即时生效。",
                        "Leave empty to auto-detect (the repo where the app lives); takes effect immediately."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let effective = service.effectiveRepoPath {
                Text(I18n.t("当前使用：", "Using: ") + effective)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Divider()
            Text(I18n.t("配置文件路径", "Config file path"))
                .font(.caption.bold())
            HStack(spacing: 6) {
                TextField(I18n.t("留空 = 仓库根目录 todo.config.json", "Empty = <repo>/todo.config.json"), text: $configPathInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onAppear { configPathInput = service.configPathOverride }
                Button {
                    if let p = PathPicker.chooseFile() {
                        configPathInput = p
                    }
                } label: {
                    Label(I18n.t("选择…", "Choose…"), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(I18n.t("应用", "Apply")) {
                    service.setConfigPathOverride(configPathInput)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(I18n.t("也可启动时传入：TodoPanel --config <路径>。", "Or at launch: TodoPanel --config <path>."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            ScheduledTasksSection(service: service)
        }
        }
        .padding(12)
        .frame(width: 320)
        .frame(maxHeight: 520)
    }
}

struct ClockBar: View {
    @ObservedObject var service: TodoService
    @State private var now = Date()
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if DateMath.isSameDay(service.viewDate, service.today) {
                    if !service.isWorking {
                        ClockInButton(service: service)
                    } else {
                        ClockOutButton(service: service)
                    }
                } else {
                    Label(I18n.t("仅今天可打卡", "Clock-in only today"), systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            if !service.weekMode {
                HStack(spacing: 14) {
                    Label(service.clockInTime ?? "--:--", systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(service.clockInTime == nil ? Color.secondary : Palette.completed)
                    Label(service.clockOutTime ?? "--:--", systemImage: "arrow.left.circle")
                        .font(.caption)
                        .foregroundStyle(service.clockOutTime == nil ? Color.secondary : Palette.clockOut)
                    Spacer()
                    LocationPicker(service: service)
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Palette.primary)
                if service.weekMode {
                    Text(I18n.t("本周已工作 \(service.weekTotalText)", "This week: \(service.weekTotalText)"))
                } else if DateMath.isSameDay(service.viewDate, service.today) {
                    Text(I18n.t("今日已工作 \(service.workedHoursText)", "Worked today: \(service.workedHoursText)"))
                } else {
                    Text(I18n.t("该日已工作 \(service.workedHoursText)", "Worked that day: \(service.workedHoursText)"))
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { service.weekMode ? 1 : 0 },
                    set: { service.setWeekMode($0 == 1) }
                )) {
                    Text(I18n.t("日", "Day")).tag(0)
                    Text(I18n.t("周", "Week")).tag(1)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                if !service.weekMode && service.clockOutTime != nil {
                    Text(I18n.t("已下班", "Clocked out"))
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.clockOut))
                }
            }
            .onReceive(refreshTimer) { _ in
                now = Date()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

struct ClockInButton: View {
    @ObservedObject var service: TodoService
    @State private var showingLocation = false

    var body: some View {
        Button {
            showingLocation = true
        } label: {
            Label(I18n.t("上班打卡", "Clock In"), systemImage: "figure.walk")
                .font(.body.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.primary)
        .controlSize(.large)
        .disabled(service.isSyncing)
        .confirmationDialog(I18n.t("选择办公地点", "Select location"), isPresented: $showingLocation, titleVisibility: .visible) {
            ForEach(service.locations, id: \.self) { loc in
                Button(loc) {
                    service.clockIn(location: loc)
                }
            }
        } message: {
            Text(I18n.t("今天在哪办公？", "Where are you working today?"))
        }
    }
}

struct ClockOutButton: View {
    @ObservedObject var service: TodoService

    var body: some View {
        Button {
            service.clockOut()
        } label: {
            Label(I18n.t("下班打卡", "Clock Out"), systemImage: "figure.walk.departure")
                .font(.body.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.clockOut)
        .controlSize(.large)
        .disabled(service.isSyncing)
    }
}

struct LocationPicker: View {
    @ObservedObject var service: TodoService
    @State private var selection: String?

    var body: some View {
        Picker(I18n.t("地点", "Location"), selection: Binding(
            get: { selection ?? service.locationName ?? (service.locations.first ?? "") },
            set: { newValue in
                selection = newValue
                service.setLocation(newValue)
            }
        )) {
            ForEach(service.locations, id: \.self) { loc in
                Text(loc).tag(loc)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(!service.isWorking || service.isSyncing || !DateMath.isSameDay(service.viewDate, service.today))
    }
}
