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

    private var projectMatches: [String] {
        let input = project.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return [] }
        return service.knownProjects
            .filter { $0.localizedCaseInsensitiveContains(input) && $0 != input }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                if !isCollapsed {
                    if showInput {
                        AddTodoRow(project: $project, text: $text,
                                   placeholderProject: addPlaceholderProject,
                                   placeholderText: addPlaceholderText) {
                            service.addTodo(project: project, text: text, toCompleted: !toCompleted)
                            project = ""
                            text = ""
                            showInput = false
                        }
                        .disabled(service.isSyncing)
                        .padding(.bottom, 8)

                        let matches = projectMatches
                        if !matches.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(matches, id: \.self) { name in
                                    Button(name) { project = name }
                                        .buttonStyle(.plain)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }

                    if items.isEmpty {
                        Text(I18n.t("暂无内容", "Nothing here"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 0) {
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
                                if index < items.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isCollapsed.toggle() }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(isCollapsed ? I18n.t("展开", "Expand") : I18n.t("收起", "Collapse"))

                Label {
                    HStack(spacing: 6) {
                        Text(title)
                        Text("\(items.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
                .font(.subheadline.weight(.semibold))

                Spacer()

                if showAdd {
                    Button {
                        showInput.toggle()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(service.isSyncing)
                }
            }
        }
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
        HStack(spacing: 8) {
            TextField(placeholderProject, text: $project)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 96)
            TextField(placeholderText, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit(onAdd)
            Button(I18n.t("添加", "Add"), action: onAdd)
                .buttonStyle(.bordered)
                .controlSize(.small)
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

    @State private var isHovering = false

    private var attributedParent: AttributedString {
        var result = AttributedString()
        if !item.project.isEmpty {
            result.append(AttributedString(item.project, attributes: AttributeContainer([.font: Font.body.weight(.semibold)])))
            if !item.text.isEmpty {
                result.append(AttributedString(" — \(item.text)", attributes: AttributeContainer([.font: Font.body])))
            }
        } else {
            result.append(AttributedString(item.text, attributes: AttributeContainer([.font: Font.body])))
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: toCompleted ? "circle" : "checkmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(toCompleted ? Color.secondary : Palette.completed)
            }
            .buttonStyle(.borderless)
            .help(toCompleted ? I18n.t("标记为完成", "Mark done") : I18n.t("恢复为待办", "Restore"))

            VStack(alignment: .leading, spacing: 4) {
                Text(attributedParent)
                    .foregroundStyle(toCompleted ? .secondary : .primary)
                    .lineLimit(3)

                if !item.subItems.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(item.subItems, id: \.self) { sub in
                            Button { onSubToggle(sub) } label: {
                                Label {
                                    Text(item.subDisplay(sub))
                                        .font(.caption)
                                        .strikethrough(item.isSubDone(sub), color: .secondary)
                                } icon: {
                                    Image(systemName: item.isSubDone(sub) ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                }
                                .foregroundStyle(item.isSubDone(sub) ? .secondary : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 4)
                }
            }

            Spacer(minLength: 0)

            if isHovering {
                HStack(spacing: 2) {
                    Button(action: onEdit) {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.borderless)
                    .help(I18n.t("编辑", "Edit"))

                    Button(action: moveUp) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)

                    Button(action: moveDown) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help(I18n.t("删除", "Delete"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(isHovering ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12) : .clear)
        .onHover { isHovering = $0 }
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
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(I18n.t("项目", "Project"), text: $project)
                    TextField(I18n.t("事项", "Task"), text: $text)
                }
                Section(I18n.t("子事项（每行一个）", "Subtasks (one per line)")) {
                    TextEditor(text: $subItems)
                        .font(.body)
                        .frame(height: 80)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(I18n.t("取消", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(I18n.t("保存", "Save")) {
                    service.updateTodo(item, project: project, text: text,
                                       subItems: subItems.components(separatedBy: "\n"))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 340)
    }
}
