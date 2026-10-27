import Foundation
import SwiftUI

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case daily, weekdays, weekly, monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }

    /// The next occurrence after `date` that is also in the future, so a task ticked off
    /// late doesn't come back already overdue.
    func next(after date: Date, hasTime: Bool, now: Date = Date()) -> Date {
        let cal = Calendar.current
        var steps = 1
        var next = occurrence(steps, after: date, cal)
        while hasTime ? next <= now : cal.startOfDay(for: next) <= cal.startOfDay(for: now) {
            steps += 1
            next = occurrence(steps, after: date, cal)
        }
        return next
    }

    /// The `n`th occurrence counted from the original date, so "monthly on the 31st"
    /// doesn't drift to the 28th after February.
    private func occurrence(_ n: Int, after date: Date, _ cal: Calendar) -> Date {
        switch self {
        case .daily:
            return cal.date(byAdding: .day, value: n, to: date) ?? date
        case .weekdays:
            var day = date
            for _ in 0..<n {
                repeat {
                    day = cal.date(byAdding: .day, value: 1, to: day) ?? day
                } while cal.isDateInWeekend(day)
            }
            return day
        case .weekly:
            return cal.date(byAdding: .weekOfYear, value: n, to: date) ?? date
        case .monthly:
            return cal.date(byAdding: .month, value: n, to: date) ?? date
        }
    }
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
    var deadline: Date?
    var deadlineHasTime = false
    var createdAt = Date()
    var repeatRule: RepeatRule?
    var notes: String?
    var completedAt: Date?

    func isOverdue(now: Date = Date()) -> Bool {
        guard let deadline, !isDone else { return false }
        if deadlineHasTime { return deadline < now }
        let cal = Calendar.current
        return cal.startOfDay(for: deadline) < cal.startOfDay(for: now)
    }

    func isDueToday(now: Date = Date()) -> Bool {
        guard let deadline, !isDone else { return false }
        return Calendar.current.isDate(deadline, inSameDayAs: now)
    }
}

final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    /// Shared with the panel, so ⌘Z / ⇧⌘Z go through the normal Edit menu.
    let undoManager = UndoManager()

    private let fileURL: URL
    private var dragUndoPending = false

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TodoBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tasks.json")
        load()
    }

    var openCount: Int { items.filter { !$0.isDone }.count }
    var doneCount: Int { items.count - openCount }
    var overdueCount: Int { items.filter { $0.isOverdue() }.count }

    func item(_ id: UUID) -> TodoItem? {
        items.first { $0.id == id }
    }

    func add(title: String, deadline: Date?, hasTime: Bool, repeatRule: RepeatRule?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordUndo("Add Task")
        var item = TodoItem(title: trimmed, deadline: deadline, deadlineHasTime: deadline != nil && hasTime)
        item.repeatRule = deadline == nil ? nil : repeatRule
        items.append(item)
        save()
    }

    /// Completing a repeating task leaves it in Done and adds a fresh copy with the next date.
    func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        recordUndo(item.isDone ? "Mark as Not Done" : "Complete Task")
        item.isDone.toggle()
        item.completedAt = item.isDone ? Date() : nil

        if item.isDone, let rule = item.repeatRule {
            let base = item.deadline ?? Calendar.current.startOfDay(for: Date())
            var next = TodoItem(title: item.title,
                                deadline: rule.next(after: base, hasTime: item.deadlineHasTime),
                                deadlineHasTime: item.deadlineHasTime)
            next.repeatRule = rule
            next.notes = item.notes
            item.repeatRule = nil
            items[index] = item
            items.insert(next, at: index + 1)
        } else {
            items[index] = item
        }
        save()
    }

    func edit(_ id: UUID, title: String, notes: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, let current = item(id),
              current.title != trimmedTitle || (current.notes ?? "") != trimmedNotes else { return }
        recordUndo("Edit Task")
        mutate(id) {
            $0.title = trimmedTitle
            $0.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        }
    }

    func setDeadline(_ id: UUID, _ date: Date?, hasTime: Bool, repeatRule: RepeatRule?) {
        recordUndo(date == nil ? "Remove Deadline" : "Set Deadline")
        mutate(id) {
            $0.deadline = date
            $0.deadlineHasTime = date != nil && hasTime
            $0.repeatRule = date == nil ? nil : repeatRule
        }
    }

    /// Moves `id` into the position currently held by `targetID`, as one undo step.
    func move(_ id: UUID, to targetID: UUID) {
        guard canMove(id, to: targetID) else { return }
        recordUndo("Reorder")
        reorder(id, to: targetID)
    }

    /// A drag fires many small moves; `beginDrag` makes the whole drag a single undo step.
    func beginDrag() {
        dragUndoPending = true
    }

    func moveDuringDrag(_ id: UUID, to targetID: UUID) {
        guard canMove(id, to: targetID) else { return }
        if dragUndoPending {
            recordUndo("Reorder")
            dragUndoPending = false
        }
        reorder(id, to: targetID)
    }

    func delete(_ id: UUID) {
        recordUndo("Delete Task")
        items.removeAll { $0.id == id }
        save()
    }

    func clearCompleted() {
        guard doneCount > 0 else { return }
        recordUndo("Clear Completed")
        items.removeAll { $0.isDone }
        save()
    }

    // MARK: - Private

    private func canMove(_ id: UUID, to targetID: UUID) -> Bool {
        id != targetID && item(id) != nil && item(targetID) != nil
    }

    private func reorder(_ id: UUID, to targetID: UUID) {
        guard let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == targetID }) else { return }
        items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        save()
    }

    private func mutate(_ id: UUID, _ change: (inout TodoItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        save()
    }

    private func recordUndo(_ actionName: String) {
        let snapshot = items
        undoManager.registerUndo(withTarget: self) { store in
            store.restore(snapshot, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Registering inside an undo puts the inverse on the redo stack.
    private func restore(_ snapshot: [TodoItem], actionName: String) {
        recordUndo(actionName)
        withAnimation(.easeOut(duration: 0.18)) { items = snapshot }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([TodoItem].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

enum DeadlineFormat {
    static func label(for date: Date, hasTime: Bool, now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = hasTime ? " " + date.formatted(date: .omitted, time: .shortened) : ""
        if cal.isDateInToday(date) { return "Today" + time }
        if cal.isDateInTomorrow(date) { return "Tomorrow" + time }
        if cal.isDateInYesterday(date) { return "Yesterday" + time }

        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        if (2..<7).contains(days) {
            return date.formatted(.dateTime.weekday(.wide)) + time
        }
        let sameYear = cal.component(.year, from: date) == cal.component(.year, from: now)
        let day = sameYear
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
        return day + time
    }
}
