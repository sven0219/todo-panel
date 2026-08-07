import SwiftUI

struct TodoSection: View {
    let title: String
    let icon: String
    let color: Color
    let items: [TodoItem]
    let addPlaceholderProject: String
    let addPlaceholderText: String
    @ObservedObject var service: TodoService
    let toCompleted: Bool
    var showAdd: Bool = true

    @State private var isCollapsed: Bool
    @State private var showInput = false
    @State private var project = ""
    @State private var text = ""
    @State private var editingItem: TodoItem?
    init(title: String, icon: String, color: Color, items: [TodoItem],
         addPlaceholderProject: String, addPlaceholderText: String,
         service: TodoService, toCompleted: Bool, showAdd: Bool = true,
         initiallyCollapsed: Bool = false) {
        self.title = title
        self.icon = icon
        self.color = color
        self.items = items
        self.addPlaceholderProject = addPlaceholderProject
        self.addPlaceholderText = addPlaceholderText
        self._service = ObservedObject(wrappedValue: service)
        self.toCompleted = toCompleted
        self.showAdd = showAdd
        _isCollapsed = State(initialValue: initiallyCollapsed)
    }

    /// Historical projects matching the current input (up to 5).
    private var projectMatches: [String] {
        let input = project.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return [] }
        return service.knownProjects
            .filter { $0.localizedCaseInsensitiveContains(input) && $0 != input }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? I18n.t("展开", "Expand") : I18n.t("收起", "Collapse"))
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.bold())
                    .fontDesign(.rounded)
                Text("\(items.count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(color.opacity(0.18)))
                Spacer()
                if showAdd {
                    Button {
                        showInput.toggle()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                            .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isSyncing)
                }
            }

            if !isCollapsed {
                if showInput {
                    AddTodoRow(project: $project, text: $text, placeholderProject: addPlaceholderProject, placeholderText: addPlaceholderText) {
                        service.addTodo(project: project, text: text, toCompleted: !toCompleted)
                        project = ""
                        text = ""
                        showInput = false
                    }
                    .disabled(service.isSyncing)

                    let matches = projectMatches
                    if !matches.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(matches, id: \.self) { name in
                                Button {
                                    project = name
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.uturn.left")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.tertiary)
                                        Text(name)
                                            .font(.caption)
                                            .foregroundStyle(Palette.primary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help(I18n.t("使用项目「\(name)」", "Use project \"\(name)\""))
                            }
                        }
                        .padding(.leading, 6)
                    }
                }

                if items.isEmpty {
                    Text(I18n.t("暂无内容", "Nothing here"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            TodoRow(
                                item: item,
                                toCompleted: toCompleted,
                                moveDown: { service.move(item, offset: 1) },
                                moveUp: { service.move(item, offset: -1) },
                                onToggle: { service.moveTodo(item, toCompleted: toCompleted) },
                                onSubToggle: { sub in service.toggleSubItem(item, sub: sub) },
                                onEdit: { editingItem = item },
                                onDelete: { service.deleteTodo(item, fromCompleted: !toCompleted) }
                            )
                            .disabled(service.isSyncing)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .sheet(item: $editingItem) { item in
            EditTodoSheet(service: service, item: item)
        }
    }
}

struct AddTodoRow: View {
    @Binding var project: String
    @Binding var text: String
    let placeholderProject: String
    let placeholderText: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholderProject, text: $project)
                .textFieldStyle(.plain)
                .font(.caption)
                .frame(width: 88)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6)))
            TextField(placeholderText, text: $text)
                .textFieldStyle(.plain)
                .font(.caption)
                .onSubmit(onAdd)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6)))
            Button {
                onAdd()
            } label: {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Palette.primary))
            }
            .buttonStyle(.plain)
        }
    }
}

struct TodoRow: View {
    let item: TodoItem
    let toCompleted: Bool
    let moveDown: () -> Void
    let moveUp: () -> Void
    let onToggle: () -> Void
    let onSubToggle: (String) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// Bold project name + task text.
    private var attributedParent: AttributedString {
        var result = AttributedString()
        if !item.project.isEmpty {
            result.append(AttributedString(item.project, attributes: AttributeContainer([.font: Font.callout.bold()])))
            if !item.text.isEmpty {
                result.append(AttributedString(" - \(item.text)", attributes: AttributeContainer([.font: Font.callout])))
            }
        } else {
            result.append(AttributedString(item.text, attributes: AttributeContainer([.font: Font.callout])))
        }
        return result
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onToggle()
            } label: {
                Image(systemName: toCompleted ? "circle" : "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(toCompleted ? Color.secondary : Palette.completed)
            }
            .buttonStyle(.plain)
            .help(toCompleted ? I18n.t("标记为完成", "Mark done") : I18n.t("恢复为待办", "Restore"))

            VStack(alignment: .leading, spacing: 2) {
                Text(attributedParent)
                    .foregroundStyle(toCompleted ? .secondary : .primary)
                    .lineLimit(2)
                if !item.subItems.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(item.subItems, id: \.self) { sub in
                            Button {
                                onSubToggle(sub)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Image(systemName: item.isSubDone(sub) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 9))
                                        .foregroundStyle(item.isSubDone(sub) ? Palette.completed : Color.secondary)
                                    Text(item.subDisplay(sub))
                                        .font(.caption)
                                        .foregroundStyle(item.isSubDone(sub) ? Color.secondary : Color.primary)
                                        .strikethrough(item.isSubDone(sub), color: .secondary)
                                        .lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(I18n.t("点击切换子事项完成状态", "Click to toggle subtask"))
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.top, 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(toCompleted ? .quaternary : .quinary)
                            .frame(width: 2)
                            .padding(.vertical, 1)
                    }
                }
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(I18n.t("编辑", "Edit"))

            Button {
                moveUp()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)

            Button {
                moveDown()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.red.opacity(0.9))
            .help(I18n.t("删除", "Delete"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

struct EditTodoSheet: View {
    @ObservedObject var service: TodoService
    let item: TodoItem
    @State private var project: String
    @State private var text: String
    @State private var subItems: String
    @Environment(\.dismiss) private var dismiss

    init(service: TodoService, item: TodoItem) {
        self.service = service
        self.item = item
        _project = State(initialValue: item.project)
        _text = State(initialValue: item.text)
        _subItems = State(initialValue: item.subItems.joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(I18n.t("编辑待办", "Edit Todo"))
                .font(.headline)
                .fontDesign(.rounded)
            TextField(I18n.t("项目", "Project"), text: $project)
                .textFieldStyle(.roundedBorder)
            TextField(I18n.t("事项", "Task"), text: $text)
                .textFieldStyle(.roundedBorder)
            Text(I18n.t("子事项（每行一个）", "Subtasks (one per line)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $subItems)
                .font(.body)
                .frame(height: 70)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Spacer()
                Button(I18n.t("取消", "Cancel")) { dismiss() }
                Button(I18n.t("保存", "Save")) {
                    service.updateTodo(item, project: project, text: text,
                                       subItems: subItems.components(separatedBy: "\n"))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Palette.primary)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
