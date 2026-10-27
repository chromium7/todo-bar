import SwiftUI

struct RootView: View {
    @EnvironmentObject private var panel: PanelController
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            if panel.isCollapsed {
                CollapsedTab()
            } else {
                // Keep a minimum layout size while the window animates open, so the
                // content slides out like a drawer instead of squashing.
                ExpandedView()
                    .frame(minWidth: PanelController.minSize.width, minHeight: PanelController.minSize.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: panel.edge == .right ? .topLeading : .topTrailing)
            }
        }
        .background {
            if settings.windowStyle == .glass && !panel.usesNativeGlass {
                GlassSheen(shape: shape)
            }
        }
        .overlay {
            // Real Liquid Glass draws its own edge.
            if !panel.usesNativeGlass {
                if settings.windowStyle == .glass {
                    GlassEdge(shape: shape)
                } else {
                    shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Matches the window's mask: rounded all round, or flat on the screen-edge side when collapsed.
    private var shape: UnevenRoundedRectangle {
        let r = panel.isCollapsed ? PanelController.tabCornerRadius : panel.cornerRadius
        let flatLeading = panel.isCollapsed && panel.edge == .left
        let flatTrailing = panel.isCollapsed && panel.edge == .right
        return UnevenRoundedRectangle(
            topLeadingRadius: flatLeading ? 0 : r,
            bottomLeadingRadius: flatLeading ? 0 : r,
            bottomTrailingRadius: flatTrailing ? 0 : r,
            topTrailingRadius: flatTrailing ? 0 : r,
            style: .circular
        )
    }
}

/// Imitation Liquid Glass, used until the app is built with the macOS 26 SDK:
/// a light wash over the blur plus a soft highlight along the top.
struct GlassSheen: View {
    let shape: UnevenRoundedRectangle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            shape.fill(Color.white.opacity(dark ? 0.04 : 0.22))
            shape.fill(LinearGradient(
                colors: [Color.white.opacity(dark ? 0.12 : 0.35), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.35)
            ))
        }
        .allowsHitTesting(false)
    }
}

/// The bright, uneven rim that makes glass read as glass: strongest top-left, faint mid-way,
/// picking up again bottom-right.
struct GlassEdge: View {
    let shape: UnevenRoundedRectangle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            if !dark {
                shape.strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
            }
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(dark ? 0.38 : 0.9),
                        Color.white.opacity(dark ? 0.06 : 0.25),
                        Color.white.opacity(dark ? 0.2 : 0.6),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Collapsed

struct CollapsedTab: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var panel: PanelController

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: panel.edge == .right ? "chevron.compact.left" : "chevron.compact.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(store.openCount)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if store.overdueCount > 0 {
                Text("\(store.overdueCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 14)
                    .background(Capsule().fill(.red))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            TabHandle(onClick: { panel.expand() }, onDragEnd: { panel.snapTab() })
        }
        .help(store.overdueCount > 0
              ? "\(store.overdueCount) overdue · click to expand"
              : "Click to expand · drag to move")
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var list: ListController
    @EnvironmentObject private var panel: PanelController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    @State private var newTitle = ""
    @State private var newDeadline: Date?
    @State private var newDeadlineHasTime = false
    @State private var newRepeat: RepeatRule?
    @State private var pickingNewDeadline = false
    @State private var draggingID: UUID?
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            addField
            Divider().opacity(0.6)
            taskList
            footer
        }
        .onChange(of: list.addFocusRequest) { _, _ in addFieldFocused = true }
        .onChange(of: list.selectedID) { _, id in
            if id != nil { addFieldFocused = false }
        }
        .onChange(of: addFieldFocused) { _, focused in
            if focused { list.selectedID = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("Todo")
                    .font(.system(size: 13, weight: .semibold))
                if store.openCount > 0 {
                    Text("\(store.openCount)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
            .overlay { WindowDragArea(onDoubleClick: { panel.collapse() }) }

            IconButton(systemName: colorScheme == .dark ? "sun.max" : "moon",
                       help: colorScheme == .dark ? "Light theme" : "Dark theme") {
                settings.toggleLightDark()
            }
            optionsMenu
            IconButton(systemName: "arrow.down.right.and.arrow.up.left",
                       help: "Collapse to side (Esc)", size: 26, fontSize: 14) {
                panel.collapse()
            }
        }
        .frame(height: 26)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Sort", selection: $list.sortMode) {
                ForEach(SortMode.allCases) { Text($0.title).tag($0) }
            }
            Picker("Theme", selection: $settings.theme) {
                ForEach(Theme.allCases) { Text($0.title).tag($0) }
            }
            Picker("Style", selection: $settings.windowStyle) {
                ForEach(WindowStyle.allCases) { Text($0.title).tag($0) }
            }
            Divider()
            Toggle("Deadline Reminders", isOn: $settings.remindersEnabled)
            Toggle("Fade When Idle", isOn: $settings.fadeWhenIdle)
            Toggle("Launch at Login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.setLaunchAtLogin($0) }
            ))
            Divider()
            Button("Clear Completed") {
                withAnimation(.easeOut(duration: 0.18)) { store.clearCompleted() }
            }
            .disabled(store.doneCount == 0)
            Divider()
            Button("Quit TodoBar") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 24, height: 22)
        .help("Options")
        .onAppear { settings.refreshLaunchAtLogin() }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 15)
            TextField("Add a task…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($addFieldFocused)
                .onSubmit(addTask)
                .onExitCommand { panel.collapse() }
                .onKeyPress(.downArrow) {
                    list.moveSelection(1)
                    return .handled
                }
            Button {
                pickingNewDeadline = true
            } label: {
                if let newDeadline {
                    DeadlineChip(date: newDeadline, hasTime: newDeadlineHasTime,
                                 repeats: newRepeat != nil, isDone: false, now: .now)
                } else {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Set a deadline")
            .popover(isPresented: $pickingNewDeadline, arrowEdge: .bottom) {
                DeadlineEditor(date: newDeadline, hasTime: newDeadlineHasTime, repeatRule: newRepeat) { date, hasTime, rule in
                    newDeadline = date
                    newDeadlineHasTime = hasTime
                    newRepeat = rule
                    pickingNewDeadline = false
                    addFieldFocused = true
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    @ViewBuilder private var taskList: some View {
        if store.items.isEmpty {
            Text("Nothing to do.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // Re-render every minute so "Today"/overdue labels stay current.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        LazyVStack(spacing: 1) {
                            ForEach(list.rows) { row in
                                switch row {
                                case .task(let item):
                                    TaskRow(item: item, now: context.date)
                                        .modifier(DragReorder(enabled: list.canReorder(item), item: item,
                                                              draggingID: $draggingID, store: store))
                                        .transition(.opacity)
                                case .doneHeader(let count):
                                    DoneHeader(count: count)
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                    }
                }
                .onChange(of: list.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id.uuidString) }
                }
            }
            .frame(maxHeight: .infinity)
            // Catches drops in the gaps and below the last row so the item doesn't fly back.
            .onDrop(of: [.todoTask], delegate: ReorderDropDelegate(
                targetID: nil, draggingID: $draggingID, store: store
            ))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if store.doneCount > 0 {
                Button("Clear done") {
                    withAnimation(.easeOut(duration: 0.18)) { store.clearCompleted() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            GripMark()
                .frame(width: 12, height: 12)
                .overlay { ResizeGrip() }
                .help("Resize")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }

    private var summary: String {
        let sorted = list.sortMode == .deadline ? " · by deadline" : ""
        return switch (store.openCount, store.doneCount) {
        case (0, 0): "No tasks"
        case (0, _): "All done"
        case (let open, _): "\(open) left" + sorted
        }
    }

    private func addTask() {
        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            store.add(title: newTitle, deadline: newDeadline, hasTime: newDeadlineHasTime, repeatRule: newRepeat)
        }
        newTitle = ""
        newDeadline = nil
        newDeadlineHasTime = false
        newRepeat = nil
    }
}

struct DoneHeader: View {
    let count: Int
    @EnvironmentObject private var list: ListController

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { list.showDone.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(list.showDone ? 90 : 0))
                Text("Done")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

struct TaskRow: View {
    let item: TodoItem
    let now: Date
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var list: ListController

    @State private var hovering = false
    @State private var editingDeadline = false
    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @FocusState private var focus: Field?

    private enum Field { case title, notes }

    private var isEditing: Bool { list.editingID == item.id }
    private var isSelected: Bool { list.selectedID == item.id }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            CheckButton(isOn: item.isDone) { list.toggle(item.id) }
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                if isEditing {
                    editor
                } else {
                    StrikeText(text: item.title, struck: item.isDone)
                    if let notes = item.notes {
                        NotesText(notes: notes, expanded: list.expandedNotes.contains(item.id)) {
                            list.toggleNotes(item.id)
                        }
                    }
                }
                if let deadline = item.deadline {
                    Button { editingDeadline = true } label: {
                        DeadlineChip(date: deadline, hasTime: item.deadlineHasTime,
                                     repeats: item.repeatRule != nil, isDone: item.isDone, now: now)
                    }
                    .buttonStyle(.plain)
                    .help(item.repeatRule.map { "\($0.title) · change deadline" } ?? "Change deadline")
                }
            }
            .opacity(item.isDone ? 0.45 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                if item.deadline == nil {
                    IconButton(systemName: "calendar.badge.plus", help: "Add deadline", size: 18) {
                        editingDeadline = true
                    }
                }
                IconButton(systemName: "xmark", help: "Delete", size: 18) {
                    list.delete(item.id)
                }
            }
            .opacity((hovering || isSelected) && !isEditing ? 1 : 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { list.beginEditing(item.id) }
        .onTapGesture { list.selectedID = item.id }
        .onHover { hovering = $0 }
        .popover(isPresented: $editingDeadline, arrowEdge: .trailing) {
            DeadlineEditor(date: item.deadline, hasTime: item.deadlineHasTime, repeatRule: item.repeatRule) { date, hasTime, rule in
                store.setDeadline(item.id, date, hasTime: hasTime, repeatRule: rule)
                editingDeadline = false
            }
        }
        .contextMenu {
            Button(item.isDone ? "Mark as Not Done" : "Mark as Done") { list.toggle(item.id) }
            Button(item.notes == nil ? "Edit / Add Note" : "Edit") { list.beginEditing(item.id) }
            Button(item.deadline == nil ? "Add Deadline…" : "Change Deadline…") { editingDeadline = true }
            if item.deadline != nil {
                Button("Remove Deadline") { store.setDeadline(item.id, nil, hasTime: false, repeatRule: nil) }
            }
            Divider()
            Button("Delete") { list.delete(item.id) }
        }
        .onChange(of: isEditing, initial: true) { _, editing in
            guard editing else { return }
            titleDraft = item.title
            notesDraft = item.notes ?? ""
            DispatchQueue.main.async { focus = .title }
        }
        .onChange(of: focus) { _, field in
            if field == nil { commit() }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Title", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focus, equals: .title)
                .onSubmit(commit)
                .onExitCommand(perform: cancel)
            TextField("Notes or link (⌥↩ for new line)", text: $notesDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1...6)
                .focused($focus, equals: .notes)
                .onSubmit(commit)
                .onExitCommand(perform: cancel)
        }
    }

    private func commit() {
        guard isEditing else { return }
        store.edit(item.id, title: titleDraft, notes: notesDraft)
        list.editingID = nil
    }

    private func cancel() {
        list.editingID = nil
    }
}

/// A task's note: one line by default, expandable; URLs are clickable.
struct NotesText: View {
    let notes: String
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Self.linkified(notes))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
            if notes.contains("\n") || notes.count > 36 {
                Button(action: onToggle) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help(expanded ? "Show less" : "Show more")
            }
        }
    }

    static func linkified(_ string: String) -> AttributedString {
        var result = AttributedString(string)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return result
        }
        for match in detector.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
            guard let url = match.url,
                  let range = Range(match.range, in: string),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
        }
        return result
    }
}

/// Text whose strikethrough draws in left-to-right when `struck` becomes true.
struct StrikeText: View {
    let text: String
    let struck: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.clear)
                    .strikethrough(true, color: .primary)
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: struck ? 1 : 0, anchor: .leading)
                    }
            }
    }
}

struct CheckButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.7), lineWidth: 1.3)
                Circle()
                    .fill(Color.accentColor)
                    .scaleEffect(isOn ? 1 : 0.3)
                    .opacity(isOn ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .scaleEffect(isOn ? 1 : 0.5)
                    .opacity(isOn ? 1 : 0)
            }
            .frame(width: 15, height: 15)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct DeadlineChip: View {
    let date: Date
    let hasTime: Bool
    let repeats: Bool
    let isDone: Bool
    let now: Date

    var body: some View {
        let item = TodoItem(title: "", isDone: isDone, deadline: date, deadlineHasTime: hasTime)
        let overdue = item.isOverdue(now: now)
        let tint: Color = overdue ? .red : item.isDueToday(now: now) ? .orange : .secondary
        HStack(spacing: 3) {
            Image(systemName: overdue ? "exclamationmark.circle" : "calendar")
            Text(DeadlineFormat.label(for: date, hasTime: hasTime, now: now))
            if repeats {
                Image(systemName: "repeat")
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(tint)
        .lineLimit(1)
    }
}

// MARK: - Deadline editor

struct DeadlineEditor: View {
    @State private var date: Date
    @State private var includeTime: Bool
    @State private var repeatRule: RepeatRule?
    private let hadDeadline: Bool
    private let onCommit: (Date?, Bool, RepeatRule?) -> Void

    init(date: Date?, hasTime: Bool, repeatRule: RepeatRule?,
         onCommit: @escaping (Date?, Bool, RepeatRule?) -> Void) {
        _date = State(initialValue: date ?? Self.defaultDate())
        _includeTime = State(initialValue: hasTime)
        _repeatRule = State(initialValue: repeatRule)
        hadDeadline = date != nil
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                quickButton("Today", days: 0)
                quickButton("Tomorrow", days: 1)
                quickButton("Next week", days: 7)
            }
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Toggle("Time", isOn: $includeTime)
                    .toggleStyle(.checkbox)
                Spacer()
                if includeTime {
                    DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
            Picker("Repeat", selection: $repeatRule) {
                Text("Never").tag(RepeatRule?.none)
                Divider()
                ForEach(RepeatRule.allCases) { Text($0.title).tag(RepeatRule?.some($0)) }
            }
            .pickerStyle(.menu)
            HStack {
                if hadDeadline {
                    Button("Remove") { onCommit(nil, false, nil) }
                }
                Spacer()
                Button("Set") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
        .padding(12)
        .frame(width: 236)
        // The panel never activates the app; popovers need it active to take clicks reliably.
        .onAppear { NSApp.activate() }
    }

    private func quickButton(_ title: String, days: Int) -> some View {
        Button(title) {
            let cal = Calendar.current
            let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: .now)) ?? .now
            let time = cal.dateComponents([.hour, .minute], from: date)
            date = cal.date(bySettingHour: time.hour ?? 17, minute: time.minute ?? 0, second: 0, of: day) ?? day
            commit()
        }
    }

    private func commit() {
        onCommit(includeTime ? date : Calendar.current.startOfDay(for: date), includeTime, repeatRule)
    }

    private static func defaultDate() -> Date {
        Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now) ?? .now
    }
}

// MARK: - Small pieces

struct IconButton: View {
    let systemName: String
    let help: String
    var size: CGFloat = 22
    var fontSize: CGFloat?
    var weight: Font.Weight = .medium
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize ?? size * 0.5, weight: weight))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct GripMark: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for offset in [4.0, 8.0] {
                path.move(to: CGPoint(x: size.width - offset, y: size.height - 1))
                path.addLine(to: CGPoint(x: size.width - 1, y: size.height - offset))
            }
            context.stroke(path, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
        }
    }
}
