import SwiftUI

/// The settings page, which slides in over the task list (gear button or ⌘,).
struct SettingsView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var list: ListController
    @EnvironmentObject private var panel: PanelController
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Settings")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("Theme") { themePicker }
                    section("Style") { stylePicker }
                    section("Shuffle look") { rotation }
                    section("Tasks") { tasks }
                    section("General") { general }
                    quitButton
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.never)
        }
        .tint(.neutralAccent)
        .onAppear { settings.refreshLaunchAtLogin() }
    }

    // MARK: - Look

    private var themePicker: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Theme.allCases) { theme in
                let selected = settings.theme == theme
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { settings.theme = theme }
                } label: {
                    VStack(spacing: 5) {
                        ThemeSwatch(theme: theme)
                            .frame(height: 28)
                            .overlay(SelectionRing(selected: selected, cornerRadius: 7))
                        Text(theme.title)
                            .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stylePicker: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
            ForEach(WindowStyle.allCases) { style in
                let selected = settings.windowStyle == style
                Button {
                    settings.windowStyle = style
                } label: {
                    VStack(spacing: 5) {
                        StylePreview(style: style, theme: settings.theme)
                            .frame(height: 56)
                            .overlay(SelectionRing(selected: selected, cornerRadius: 8))
                        Text(style.title)
                            .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Rotation

    @ViewBuilder
    private var rotation: some View {
        SwitchRow(title: "Change automatically",
                  detail: "A random theme and style from the ones you pick",
                  isOn: $settings.rotationEnabled.animation(.easeOut(duration: 0.2)))
        if settings.rotationEnabled {
            Picker("How often", selection: $settings.rotationInterval) {
                ForEach(RotationInterval.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            Chips(label: "Themes", items: Theme.rotatable, title: \.title, selection: $settings.rotationThemes)
            Chips(label: "Styles", items: WindowStyle.allCases, title: \.title, selection: $settings.rotationStyles)
            HStack(spacing: 6) {
                TimelineView(.everyMinute) { _ in
                    Text("Next change \(nextChange)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                PillButton(title: "Shuffle now", systemName: "shuffle") {
                    settings.shuffleLook()
                }
            }
        }
    }

    private var nextChange: String {
        let date = settings.nextRotation
        let time = date.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(date) ? "today at \(time)" : "tomorrow at \(time)"
    }

    // MARK: - Tasks and general

    @ViewBuilder
    private var tasks: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sort")
                .font(.system(size: 12))
            Picker("Sort", selection: $list.sortMode) {
                ForEach(SortMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
        }
        Divider().opacity(0.5)
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Completed tasks")
                    .font(.system(size: 12))
                Text(store.doneCount == 1 ? "1 in Done" : "\(store.doneCount) in Done")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            PillButton(title: "Clear", systemName: "trash") {
                withAnimation(.easeOut(duration: 0.18)) { store.clearCompleted() }
            }
            .disabled(store.doneCount == 0)
        }
    }

    @ViewBuilder
    private var general: some View {
        SwitchRow(title: "Deadline reminders",
                  detail: "15 min before and at the deadline",
                  isOn: $settings.remindersEnabled)
        Divider().opacity(0.5)
        SwitchRow(title: "Fade when idle",
                  detail: "See-through while the mouse is away",
                  isOn: $settings.fadeWhenIdle)
        Divider().opacity(0.5)
        SwitchRow(title: "Launch at login",
                  detail: nil,
                  isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
    }

    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Quit TodoBar", systemImage: "power")
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Card())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Card())
        }
    }
}

// MARK: - Pieces

private struct SelectionRing: View {
    let selected: Bool
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.12)),
                          lineWidth: selected ? 2 : 1)
    }
}

private struct SwitchRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

/// Toggleable chips for picking what the rotation may choose. The last one can't be turned off.
private struct Chips<Item: Hashable & Identifiable>: View {
    let label: String
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Set<Item>

    init(label: String, items: [Item], title: KeyPath<Item, String>, selection: Binding<Set<Item>>) {
        self.label = label
        self.items = items
        self.title = { $0[keyPath: title] }
        _selection = selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    let on = selection.contains(item)
                    Button {
                        if on {
                            if selection.count > 1 { selection.remove(item) }
                        } else {
                            selection.insert(item)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10))
                            Text(title(item))
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(on ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(Color.primary.opacity(0.05))))
                        .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ThemeSwatch: View {
    let theme: Theme

    private static let light = Color(white: 0.97)
    private static let dark = Color(white: 0.14)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        ZStack {
            switch theme {
            case .system:
                Self.light
                // Half light, half dark, split on the diagonal.
                GeometryReader { geometry in
                    Path { p in
                        p.move(to: CGPoint(x: geometry.size.width, y: 0))
                        p.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                        p.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                        p.closeSubpath()
                    }
                    .fill(Self.dark)
                }
            case .light: Self.light
            case .dark: Self.dark
            case .pink: Color(nsColor: theme.wash ?? .white)
            }
        }
        .clipShape(shape)
    }
}

/// A miniature of a style: its background with a few pretend task rows on top.
private struct StylePreview: View {
    let style: WindowStyle
    let theme: Theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8,
                                           bottomTrailingRadius: 8, topTrailingRadius: 8, style: .continuous)
        ZStack(alignment: .topLeading) {
            switch style {
            case .glass:
                // Glass shows what's behind it; stand in a soft colourful desktop.
                shape.fill(LinearGradient(colors: [Color(red: 0.55, green: 0.72, blue: 1.0), Color(red: 0.88, green: 0.66, blue: 0.95)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(colorScheme == .dark ? 0.35 : 0.5))
                wash(shape)
                GlassSheen(shape: shape)
                GlassEdge(shape: shape)
            case .standard:
                shape.fill(Color(nsColor: .windowBackgroundColor))
                wash(shape)
            case .doodle:
                DoodleBackground(shape: shape, theme: theme)
            case .rilakkuma, .quby:
                StickerBackground(pack: style.stickerPack ?? .rilakkuma, shape: shape, theme: theme)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach([38, 52, 30], id: \.self) { width in
                    HStack(spacing: 4) {
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
                            .frame(width: 7, height: 7)
                        Capsule()
                            .fill(Color.primary.opacity(0.28))
                            .frame(width: CGFloat(width), height: 3.5)
                    }
                }
            }
            .padding(10)
        }
        .clipShape(shape)
    }

    @ViewBuilder
    private func wash(_ shape: UnevenRoundedRectangle) -> some View {
        if let wash = theme.wash {
            shape.fill(Color(nsColor: wash).opacity(0.6))
        }
    }
}
