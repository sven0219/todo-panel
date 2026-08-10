import SwiftUI

struct ScheduledTasksSection: View {
    @ObservedObject var service: TodoService
    @State private var editingTask: ScheduledTaskConfig?
    @State private var editingOriginalId: String?
    @State private var showingAdd = false
    @State private var taskToDelete: ScheduledTaskConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(I18n.t("定时任务", "Scheduled tasks"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    editingTask = nil
                    editingOriginalId = nil
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(service.isSyncing)
            }

            Text(I18n.t("首次上班打卡时自动加入「待跟进」",
                        "Added to Follow-up on the first clock-in of the day"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if service.scheduledTasks.isEmpty {
                Text(I18n.t("暂无", "None"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(service.scheduledTasks.enumerated()), id: \.element.id) { index, task in
                        HStack(alignment: .center, spacing: 8) {
                            Text(task.scheduleLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.followup)
                                .frame(width: 56, alignment: .leading)
                            Text(task.displayTitle)
                                .font(.caption)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                editingTask = task
                                editingOriginalId = task.id
                                showingAdd = true
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .buttonStyle(.borderless)
                            .disabled(service.isSyncing)
                            Button {
                                taskToDelete = task
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .disabled(service.isSyncing)
                        }
                        .padding(.vertical, 6)
                        if index < service.scheduledTasks.count - 1 {
                            Divider()
                        }
                    }
                }
            }

            Text(I18n.t("保存至 todo.config.json；月内固定日遇周末顺延至下一工作日。",
                        "Saved to todo.config.json; fixed month days on weekends move to the next workday."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .sheet(isPresented: $showingAdd) {
            ScheduledTaskEditorSheet(
                service: service,
                task: editingTask,
                originalId: editingOriginalId
            ) {
                showingAdd = false
                editingTask = nil
                editingOriginalId = nil
            }
        }
        .confirmationDialog(
            I18n.t("删除定时任务？", "Delete scheduled task?"),
            isPresented: Binding(
                get: { taskToDelete != nil },
                set: { if !$0 { taskToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(I18n.t("删除", "Delete"), role: .destructive) {
                if let task = taskToDelete {
                    service.deleteScheduledTask(task)
                }
                taskToDelete = nil
            }
            Button(I18n.t("取消", "Cancel"), role: .cancel) {
                taskToDelete = nil
            }
        } message: {
            if let task = taskToDelete {
                Text(task.displayTitle)
            }
        }
    }
}

private enum ScheduleKind: String, CaseIterable, Identifiable {
    case weekday
    case monthDay
    var id: String { rawValue }
}

struct ScheduledTaskEditorSheet: View {
    @ObservedObject var service: TodoService
    let task: ScheduledTaskConfig?
    let originalId: String?
    let onDismiss: () -> Void

    @State private var project = ""
    @State private var text = ""
    @State private var kind: ScheduleKind = .weekday
    @State private var weekday = 2
    @State private var monthDay = 1
    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { task != nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(I18n.t("项目", "Project"), text: $project)
                    TextField(I18n.t("事项", "Task"), text: $text)

                    let matches = projectMatches
                    if !matches.isEmpty {
                        ForEach(matches, id: \.self) { name in
                            Button(name) { project = name }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(I18n.t("周期", "Schedule")) {
                    Picker(I18n.t("周期", "Schedule"), selection: $kind) {
                        Text(I18n.t("每周", "Weekly")).tag(ScheduleKind.weekday)
                        Text(I18n.t("每月", "Monthly")).tag(ScheduleKind.monthDay)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if kind == .weekday {
                        Picker(I18n.t("星期", "Weekday"), selection: $weekday) {
                            ForEach(ScheduledTaskConfig.weekdayOptions, id: \.value) { opt in
                                Text(opt.label).tag(opt.value)
                            }
                        }
                    } else {
                        Stepper(I18n.t("每月 \(monthDay) 日", "Day \(monthDay) of month"), value: $monthDay, in: 1...31)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(I18n.t("取消", "Cancel")) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(I18n.t("保存", "Save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(service.isSyncing)
            }
            .padding(12)
        }
        .frame(width: 340)
        .onAppear { loadFields() }
    }

    private var projectMatches: [String] {
        let input = project.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return [] }
        return service.knownProjects
            .filter { $0.localizedCaseInsensitiveContains(input) && $0 != input }
            .prefix(5)
            .map { $0 }
    }

    private func loadFields() {
        if let task {
            project = task.project
            text = task.text
            if task.weekday != nil {
                kind = .weekday
                weekday = task.weekday ?? 2
            } else {
                kind = .monthDay
                monthDay = task.monthDay ?? 1
            }
        }
    }

    private func save() {
        let w = kind == .weekday ? weekday : nil
        let m = kind == .monthDay ? monthDay : nil
        if let originalId {
            service.updateScheduledTask(replacingId: originalId, project: project, text: text, weekday: w, monthDay: m)
        } else {
            service.addScheduledTask(project: project, text: text, weekday: w, monthDay: m)
        }
        if service.lastError == nil {
            close()
        }
    }

    private func close() {
        dismiss()
        onDismiss()
    }
}
