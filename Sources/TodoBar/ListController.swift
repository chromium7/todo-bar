import AppKit
import SwiftUI

enum SortMode: String, CaseIterable, Identifiable {
    case manual, deadline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "Manual"
        case .deadline: "By Deadline"
        }
    }
}

enum ListRow: Identifiable {
    case task(TodoItem)
    case doneHeader(count: Int)

    var id: String {
        switch self {
        case .task(let item): item.id.uuidString
        case .doneHeader: "done-header"
        }
    }
}

/// View state for the list (sorting, the Done section, selection, editing) and keyboard handling.
final class ListController: ObservableObject {
    let store: TodoStore

    @Published var selectedID: UUID?
    @Published var editingID: UUID?
    @Published var expandedNotes: Set<UUID> = []
    /// The workspace whose name is being edited on the workspaces page, if any.
    @Published var renamingWorkspaceID: UUID?
    /// Bumped to ask the view to focus "Add a task…".
    @Published private(set) var addFocusRequest = 0
    /// Just-completed tasks stay in place briefly so the strikethrough can play before they move to Done.
    @Published private(set) var settling: Set<UUID> = []

    @Published var showDone: Bool {
        didSet {
            UserDefaults.standard.set(showDone, forKey: "showDone")
            if !showDone, let id = selectedID, store.item(id)?.isDone == true { selectedID = nil }
        }
    }
    @Published var sortMode: SortMode {
        didSet { UserDefaults.standard.set(sortMode.rawValue, forKey: "sortMode") }
    }

    init(store: TodoStore) {
        self.store = store
        showDone = UserDefaults.standard.object(forKey: "showDone") as? Bool ?? true
        sortMode = SortMode(rawValue: UserDefaults.standard.string(forKey: "sortMode") ?? "") ?? .manual
    }

    // MARK: - What's shown

    func isInOpenSection(_ item: TodoItem) -> Bool {
        !item.isDone || settling.contains(item.id)
    }

    var openItems: [TodoItem] {
        let open = store.items.filter(isInOpenSection)
        guard sortMode == .deadline else { return open }
        return open.enumerated()
            .sorted { a, b in
                let da = a.element.deadline ?? .distantFuture
                let db = b.element.deadline ?? .distantFuture
                return da != db ? da < db : a.offset < b.offset
            }
            .map(\.element)
    }

    var doneItems: [TodoItem] {
        store.items
            .filter { !isInOpenSection($0) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var rows: [ListRow] {
        var rows = openItems.map(ListRow.task)
        let done = doneItems
        if !done.isEmpty {
            rows.append(.doneHeader(count: done.count))
            if showDone { rows += done.map(ListRow.task) }
        }
        return rows
    }

    private var navigableItems: [TodoItem] {
        openItems + (showDone ? doneItems : [])
    }

    func canReorder(_ item: TodoItem) -> Bool {
        sortMode == .manual && isInOpenSection(item)
    }

    // MARK: - Actions

    func toggle(_ id: UUID) {
        guard let item = store.item(id) else { return }
        withAnimation(.easeOut(duration: 0.25)) { store.toggle(id) }
        guard !item.isDone else { return }
        settling.insert(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            withAnimation(.easeInOut(duration: 0.3)) { _ = self?.settling.remove(id) }
        }
    }

    func delete(_ id: UUID) {
        let list = navigableItems
        if selectedID == id, let index = list.firstIndex(where: { $0.id == id }) {
            selectedID = list.indices.contains(index + 1) ? list[index + 1].id
                : index > 0 ? list[index - 1].id : nil
        }
        if editingID == id { editingID = nil }
        withAnimation(.easeOut(duration: 0.18)) { store.delete(id) }
    }

    func beginEditing(_ id: UUID) {
        selectedID = id
        editingID = id
    }

    func toggleNotes(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.15)) {
            if expandedNotes.contains(id) { expandedNotes.remove(id) } else { expandedNotes.insert(id) }
        }
    }

    func focusAddField() {
        selectedID = nil
        addFocusRequest += 1
    }

    func clearSelection() {
        selectedID = nil
        editingID = nil
    }

    // MARK: - Workspaces

    func switchWorkspace(to id: UUID) {
        guard id != store.currentWorkspaceID else { return }
        clearSelection()
        renamingWorkspaceID = nil
        withAnimation(.easeOut(duration: 0.15)) { store.switchWorkspace(to: id) }
    }

    /// ⌘1…⌘9.
    func switchWorkspace(at index: Int) {
        guard store.workspaces.indices.contains(index) else { return }
        switchWorkspace(to: store.workspaces[index].id)
    }

    /// Creates a workspace, switches to it and starts editing its name.
    func newWorkspace() {
        clearSelection()
        let id = withAnimation(.easeOut(duration: 0.15)) { store.addWorkspace(named: "New Workspace") }
        renamingWorkspaceID = id
    }

    /// Deletes the workspace and its tasks (undoable). The workspaces page asks first when it has tasks.
    func deleteWorkspace(_ id: UUID) {
        guard store.workspaces.count > 1 else { return }
        clearSelection()
        renamingWorkspaceID = nil
        withAnimation(.easeOut(duration: 0.15)) { store.deleteWorkspace(id) }
    }

    /// ↑/↓: move the selection. Going up past the first task returns to "Add a task…".
    func moveSelection(_ delta: Int) {
        let list = navigableItems
        guard !list.isEmpty else { return }
        guard let current = selectedID, let index = list.firstIndex(where: { $0.id == current }) else {
            selectedID = (delta > 0 ? list.first : list.last)?.id
            return
        }
        let target = index + delta
        if target < 0 {
            focusAddField()
        } else if target < list.count {
            selectedID = list[target].id
        }
    }

    /// ⌘↑/⌘↓: move the selected task among the open ones (manual order only).
    func moveSelectedTask(_ delta: Int) {
        guard sortMode == .manual, let id = selectedID else { return }
        let open = openItems.filter { !$0.isDone }
        guard let index = open.firstIndex(where: { $0.id == id }), open.indices.contains(index + delta) else { return }
        withAnimation(.easeOut(duration: 0.15)) { store.move(id, to: open[index + delta].id) }
    }

    /// Keys pressed while no text field is being edited. Returns true if handled.
    func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 125: // ↓
            command ? moveSelectedTask(1) : moveSelection(1)
        case 126: // ↑
            command ? moveSelectedTask(-1) : moveSelection(-1)
        case 49: // space
            guard let id = selectedID else { return false }
            toggle(id)
        case 51, 117: // delete, forward delete
            guard let id = selectedID else { return false }
            delete(id)
        case 36, 76: // return, enter
            guard let id = selectedID else { return false }
            beginEditing(id)
        default:
            return false
        }
        return true
    }
}
