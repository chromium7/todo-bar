import SwiftUI

/// The workspaces page, opened from the workspace name in the header: switch, add, rename
/// and delete workspaces.
struct WorkspacesView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var list: ListController
    @EnvironmentObject private var panel: PanelController
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft = ""
    @State private var hoveredID: UUID?
    @State private var confirmingDeleteID: UUID?
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Workspaces") {
                IconButton(systemName: "plus", help: "New workspace (⇧⌘N)", size: 24, fontSize: 13) {
                    confirmingDeleteID = nil
                    list.newWorkspace()
                }
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        row(workspace, index: index)
                    }
                    Text("Click a workspace to open it. ⌘1–⌘9 switch from anywhere, ⇧⌘N makes a new one.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.never)
        }
        .tint(.neutralAccent)
        .onChange(of: list.renamingWorkspaceID, initial: true) { _, id in
            guard let id, let workspace = store.workspaces.first(where: { $0.id == id }) else { return }
            draft = workspace.name
            DispatchQueue.main.async { nameFieldFocused = true }
        }
        .onChange(of: nameFieldFocused) { _, focused in
            if !focused { commitName() }
        }
        .onDisappear { commitName() }
    }

    private func row(_ workspace: Workspace, index: Int) -> some View {
        let isCurrent = workspace.id == store.currentWorkspaceID
        let isRenaming = list.renamingWorkspaceID == workspace.id
        let showActions = hoveredID == workspace.id && !isRenaming
        let tasks = store.allItems.filter { $0.workspaceID == workspace.id }
        let open = tasks.filter { !$0.isDone }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(workspace.name.prefix(1).uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08))))
                    // Graphite is light in dark mode, so the letter flips to stay readable.
                    .foregroundStyle(isCurrent ? AnyShapeStyle(colorScheme == .dark ? Color.black.opacity(0.8) : .white)
                                               : AnyShapeStyle(.secondary))

                VStack(alignment: .leading, spacing: 1) {
                    if isRenaming {
                        TextField("Workspace name", text: $draft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .focused($nameFieldFocused)
                            .onSubmit(commitName)
                            .onExitCommand { list.renamingWorkspaceID = nil }
                    } else {
                        Text(workspace.name)
                            .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    Text(summary(open: open, done: tasks.count - open))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if showActions {
                    IconButton(systemName: "pencil", help: "Rename") {
                        confirmingDeleteID = nil
                        list.renamingWorkspaceID = workspace.id
                    }
                    if store.workspaces.count > 1 {
                        IconButton(systemName: "trash", help: "Delete") {
                            requestDelete(workspace, taskCount: tasks.count)
                        }
                    }
                } else if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }

            if confirmingDeleteID == workspace.id {
                HStack(spacing: 6) {
                    Text("Delete it and its \(tasks.count) task\(tasks.count == 1 ? "" : "s")? ⌘Z undoes.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    PillButton(title: "Cancel", systemName: "xmark") { confirmingDeleteID = nil }
                        .tint(.secondary)
                    PillButton(title: "Delete", systemName: "trash") {
                        confirmingDeleteID = nil
                        list.deleteWorkspace(workspace.id)
                    }
                    .tint(.red)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Card(highlighted: isCurrent))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming else { return }
            list.switchWorkspace(to: workspace.id)
            panel.closePage()
        }
        .onHover { inside in
            if inside { hoveredID = workspace.id } else if hoveredID == workspace.id { hoveredID = nil }
        }
        .contextMenu {
            Button("Rename") { list.renamingWorkspaceID = workspace.id }
            Button("Delete…") { requestDelete(workspace, taskCount: tasks.count) }
                .disabled(store.workspaces.count < 2)
        }
    }

    private func summary(open: Int, done: Int) -> String {
        if open == 0 && done == 0 { return "No tasks" }
        return done > 0 ? "\(open) open · \(done) done" : "\(open) open"
    }

    /// An empty workspace goes straight away; one with tasks asks first, in the row.
    private func requestDelete(_ workspace: Workspace, taskCount: Int) {
        guard store.workspaces.count > 1 else { return }
        if taskCount == 0 {
            list.deleteWorkspace(workspace.id)
        } else {
            confirmingDeleteID = workspace.id
        }
    }

    private func commitName() {
        guard let id = list.renamingWorkspaceID else { return }
        store.renameWorkspace(id, to: draft)
        list.renamingWorkspaceID = nil
    }
}
