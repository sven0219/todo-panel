import SwiftUI
import AppKit

/// Pick a directory or file using Finder.
enum PathPicker {
    static func chooseDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the todo repository directory"
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }

    static func chooseFile() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select a todo.config.json file"
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }
}

/// Setup screen shown at launch when no repo is found.
struct SetupView: View {
    @State private var path = ""
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.questionmark")
                    .foregroundStyle(Palette.primary)
                Text(I18n.t("todo 仓库未找到", "todo repo not found"))
                    .font(.headline)
                    .fontDesign(.rounded)
            }
            Text(I18n.t("请输入 todo 仓库所在路径（包含 AGENTS.md 或 .git 的目录）：",
                        "Enter the todo repo path (the directory containing AGENTS.md or .git):"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(I18n.t("例如 /Users/you/work/todo", "e.g. /Users/you/work/todo"), text: $path)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                Button {
                    if let p = PathPicker.chooseDirectory() {
                        path = p
                    }
                } label: {
                    Label(I18n.t("选择…", "Choose…"), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(I18n.t("退出", "Quit")) {
                    NSApp.terminate(nil)
                }
                Button(I18n.t("保存并启动", "Save & Launch")) {
                    UserDefaults.standard.set(path.trimmingCharacters(in: .whitespaces), forKey: "repoPathOverride")
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.primary)
                .disabled(path.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(I18n.t("可直接粘贴路径（⌘V）", "You can paste the path (⌘V)"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 360)
    }
}
