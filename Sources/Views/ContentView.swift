import SwiftUI

struct ContentView: View {
    @ObservedObject var service: TodoService

    var body: some View {
        Group {
            if service.miniFloatEnabled && !service.panelExpanded {
                MiniFloatView(service: service)
            } else {
                fullPanel
            }
        }
        .onAppear { service.lastError = nil }
    }

    private var fullPanel: some View {
        VStack(spacing: 0) {
            HeaderBar(service: service)

            Divider()

            ClockBar(service: service)

            Divider()

            ScrollView {
                if service.weekMode {
                    WeekView(service: service)
                        .padding(12)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                            }
                        )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        TodoSection(
                            title: I18n.t("待办", "Todo"),
                            icon: "circle",
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
                                icon: "circle.dashed",
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
                            icon: "checkmark.circle",
                            color: Palette.completed,
                            items: service.day.completed,
                            addPlaceholderProject: I18n.t("项目", "Project"),
                            addPlaceholderText: I18n.t("事项", "Task"),
                            service: service,
                            toCompleted: false,
                            initiallyCollapsed: true
                        )
                    }
                    .padding(12)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                        }
                    )
                }
            }
            .scrollIndicators(.automatic)
            .onPreferenceChange(ContentHeightKey.self) { height in
                NotificationCenter.default.post(
                    name: .panelContentHeightChanged,
                    object: nil,
                    userInfo: ["height": height]
                )
            }

            if let notice = service.lastNotice {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(notice)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Palette.controlBackground)
            }

            if let error = service.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .lineLimit(2)
                    Spacer()
                    Button(I18n.t("关闭", "Dismiss")) {
                        service.lastError = nil
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.08))
            }
        }
        .background(Palette.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.separator, lineWidth: 0.5)
        )
        .frame(minWidth: 320, minHeight: 360)
    }
}

struct MiniFloatView: View {
    @ObservedObject var service: TodoService

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor)
            if service.isWorking || service.clockOutTime != nil {
                Text(service.workedHoursText)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: 0.5))
        .frame(width: MiniFloatLayout.size.width, height: MiniFloatLayout.size.height)
        .help(I18n.t("点击展开面板", "Click to expand panel"))
    }

    private var statusColor: Color {
        if service.isWorking { return Palette.completed }
        if service.clockOutTime != nil { return Palette.followup }
        return .secondary
    }
}

struct HeaderBar: View {
    @ObservedObject var service: TodoService
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { service.selectPreviousDay() }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help(I18n.t("前一天", "Previous day"))

            Text(DayName.heading(service.viewDate))
                .font(.headline)
                .frame(minWidth: 110)

            Button(action: { service.selectNextDay() }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help(I18n.t("后一天", "Next day"))

            if !DateMath.isSameDay(service.viewDate, service.today) {
                Button(I18n.t("今天", "Today")) { service.goToday() }
                    .buttonStyle(.link)
                    .font(.caption)
            }

            Spacer()

            Button(action: { service.flushPush() }) {
                if service.isSyncing {
                    Label(I18n.t("同步中", "Syncing"), systemImage: "arrow.triangle.2.circlepath")
                } else if service.pendingPushCount > 0 {
                    Label(I18n.t("未同步 \(service.pendingPushCount)", "Unsynced \(service.pendingPushCount)"),
                          systemImage: "arrow.up.circle")
                } else {
                    Label(I18n.t("已同步", "Synced"), systemImage: "checkmark.circle")
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(syncColor)
            .monospacedDigit()
            .disabled(service.isSyncing)
            .help(I18n.t("点击同步到远端", "Sync now"))

            Button(action: { showingSettings.toggle() }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(I18n.t("设置", "Settings"))
            .popover(isPresented: $showingSettings) {
                SettingsPopover(service: service)
            }

            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(I18n.t("退出", "Quit"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.controlBackground.opacity(0.5))
    }

    private var syncColor: Color {
        if service.isSyncing { return .secondary }
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
            Form {
                Section(I18n.t("外观", "Appearance")) {
                    Picker(I18n.t("外观", "Appearance"), selection: Binding(
                        get: { service.appearanceMode },
                        set: { service.setAppearanceMode($0) }
                    )) {
                        Text(I18n.t("跟随系统", "System")).tag(AppearanceMode.system)
                        Text(I18n.t("浅色", "Light")).tag(AppearanceMode.light)
                        Text(I18n.t("深色", "Dark")).tag(AppearanceMode.dark)
                    }
                    .labelsHidden()

                    Picker(I18n.t("语言", "Language"), selection: Binding(
                        get: { service.languageMode },
                        set: { service.setLanguageMode($0) }
                    )) {
                        Text(I18n.t("跟随系统", "System")).tag(I18n.Language.system)
                        Text("中文").tag(I18n.Language.zh)
                        Text("English").tag(I18n.Language.en)
                    }
                    .labelsHidden()
                }

                Section(I18n.t("同步", "Sync")) {
                    Toggle(I18n.t("每次操作立即推送", "Push on every action"), isOn: Binding(
                        get: { service.immediatePush },
                        set: { service.setImmediatePush($0) }
                    ))
                    Text(I18n.t("关闭时：操作先本地提交，每 10 分钟统一推送，退出时自动推送。",
                                "When off: changes commit locally, pushed together every 10 minutes, and flushed on quit."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(I18n.t("窗口", "Window")) {
                    Toggle(I18n.t("窗口置顶", "Always on top"), isOn: Binding(
                        get: { service.alwaysOnTop },
                        set: { service.setAlwaysOnTop($0) }
                    ))
                    Toggle(I18n.t("迷你悬浮", "Mini float"), isOn: Binding(
                        get: { service.miniFloatEnabled },
                        set: { service.setMiniFloatEnabled($0) }
                    ))
                    Text(I18n.t("收起为小胶囊悬浮在屏幕上，点击展开，移开自动收起（仅本次运行有效，重启后恢复完整面板）。",
                                "Collapse to a small pill on screen; click to expand, move away to collapse (this session only; restarts open the full panel)."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(I18n.t("启动", "Startup")) {
                    Toggle(I18n.t("开机自启", "Launch at login"), isOn: Binding(
                        get: { service.launchAtLogin },
                        set: { service.setLaunchAtLogin($0) }
                    ))
                }

                Section(I18n.t("仓库路径", "Repo path")) {
                    TextField(I18n.t("例如 ~/work/todo", "e.g. ~/work/todo"), text: $repoPathInput)
                        .onAppear { repoPathInput = service.repoPathOverride }
                    HStack {
                        Button {
                            if let p = PathPicker.chooseDirectory() { repoPathInput = p }
                        } label: {
                            Label(I18n.t("选择…", "Choose…"), systemImage: "folder")
                        }
                        Button(I18n.t("应用", "Apply")) {
                            if !service.setRepoPathOverride(repoPathInput) {
                                repoPathInput = service.repoPathOverride
                            }
                        }
                    }
                    if let effective = service.effectiveRepoPath {
                        Text(effective)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Section(I18n.t("配置文件路径", "Config file path")) {
                    TextField(I18n.t("留空 = 仓库根目录 todo.config.json", "Empty = <repo>/todo.config.json"),
                             text: $configPathInput)
                        .onAppear { configPathInput = service.configPathOverride }
                    HStack {
                        Button {
                            if let p = PathPicker.chooseFile() { configPathInput = p }
                        } label: {
                            Label(I18n.t("选择…", "Choose…"), systemImage: "folder")
                        }
                        Button(I18n.t("应用", "Apply")) {
                            service.setConfigPathOverride(configPathInput)
                        }
                    }
                }

                Section {
                    ScheduledTasksSection(service: service)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 340)
        .frame(maxHeight: 520)
    }
}

struct ClockBar: View {
    @ObservedObject var service: TodoService
    @State private var now = Date()
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
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
                HStack(spacing: 16) {
                    Label(service.clockInTime ?? "--:--", systemImage: "arrow.right.to.line")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(service.clockInTime == nil ? .secondary : Palette.completed)
                    Label(service.clockOutTime ?? "--:--", systemImage: "arrow.left.to.line")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(service.clockOutTime == nil ? .secondary : Palette.clockOut)
                    Spacer()
                    LocationPicker(service: service)
                }
            }

            HStack(spacing: 8) {
                Label {
                    Group {
                        if service.weekMode {
                            Text(I18n.t("本周 \(service.weekTotalText)", "This week: \(service.weekTotalText)"))
                        } else if DateMath.isSameDay(service.viewDate, service.today) {
                            Text(I18n.t("今日 \(service.workedHoursText)", "Today: \(service.workedHoursText)"))
                        } else {
                            Text(I18n.t("该日 \(service.workedHoursText)", "That day: \(service.workedHoursText)"))
                        }
                    }
                    .monospacedDigit()
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Picker("", selection: Binding(
                    get: { service.weekMode ? 1 : 0 },
                    set: { service.setWeekMode($0 == 1) }
                )) {
                    Text(I18n.t("日", "Day")).tag(0)
                    Text(I18n.t("周", "Week")).tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                if !service.weekMode && service.clockOutTime != nil {
                    Text(I18n.t("已下班", "Clocked out"))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.clockOut.opacity(0.12), in: Capsule())
                        .foregroundStyle(Palette.clockOut)
                }
            }
            .onReceive(refreshTimer) { _ in now = Date() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(service.isSyncing)
        .confirmationDialog(I18n.t("选择办公地点", "Select location"), isPresented: $showingLocation, titleVisibility: .visible) {
            ForEach(service.locations, id: \.self) { loc in
                Button(loc) { service.clockIn(location: loc) }
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
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Palette.clockOut)
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
