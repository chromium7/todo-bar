import SwiftUI

/// Header for a page that slides in over the task list: back arrow, title, room to drag the
/// window, and optional buttons on the right.
struct PageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @EnvironmentObject private var panel: PanelController

    var body: some View {
        HStack(spacing: 4) {
            IconButton(systemName: "chevron.left", help: "Back to tasks (Esc)", size: 24, fontSize: 12, weight: .semibold) {
                panel.closePage()
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            // Empty header space moves the window; double-click collapses.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { WindowDragArea(onDoubleClick: { panel.collapse() }) }
            trailing
        }
        .frame(height: 26)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

extension Color {
    /// Graphite for a page's controls and selection, so they stay neutral whatever the style.
    static let neutralAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.68, alpha: 1)
            : NSColor(white: 0.32, alpha: 1)
    })
}

/// A soft, lightly frosted card that keeps a page readable over any style's background.
/// `highlighted` rims it in the accent colour.
struct Card: View {
    var highlighted = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        shape.fill(.background.opacity(colorScheme == .dark ? 0.4 : 0.6))
            .overlay(shape.strokeBorder(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.07)),
                                        lineWidth: highlighted ? 1.5 : 1))
    }
}

/// A small capsule button in the accent colour (set `.tint` to change it).
struct PillButton: View {
    let title: String
    let systemName: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(.tint.opacity(hovering && isEnabled ? 0.25 : 0.15)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}
