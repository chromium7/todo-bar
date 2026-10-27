import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Private drag type so tasks can't be dropped into other apps and outside drags don't reorder.
    static let todoTask = UTType(exportedAs: "local.todobar.task-id")
}

extension NSItemProvider {
    static func todoTask(_ id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.todoTask.identifier,
                                            visibility: .ownProcess) { completion in
            completion(Data(id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }
}

/// Makes a row draggable and a drop target. Applied to every row, with `enabled` deciding
/// whether it does anything, so toggling it never swaps the row's identity mid-animation.
struct DragReorder: ViewModifier {
    let enabled: Bool
    let item: TodoItem
    @Binding var draggingID: UUID?
    let store: TodoStore

    func body(content: Content) -> some View {
        content
            .onDrag {
                guard enabled else { return NSItemProvider() }
                draggingID = item.id
                store.beginDrag()
                return .todoTask(item.id)
            } preview: {
                DragPreview(item: item)
            }
            .onDrop(of: [.todoTask], delegate: ReorderDropDelegate(
                targetID: enabled ? item.id : nil, draggingID: $draggingID, store: store
            ))
    }
}

/// Live reorder: as the dragged row passes over another row, it takes that row's place.
struct ReorderDropDelegate: DropDelegate {
    let targetID: UUID?
    @Binding var draggingID: UUID?
    let store: TodoStore

    func validateDrop(info: DropInfo) -> Bool {
        draggingID != nil && info.hasItemsConforming(to: [.todoTask])
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID, let targetID, draggingID != targetID else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            store.moveDuringDrag(draggingID, to: targetID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

/// What follows the cursor while a task is dragged.
struct DragPreview: View {
    let item: TodoItem

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.3)
                .frame(width: 15, height: 15)
            Text(item.title)
                .font(.system(size: 13))
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(width: 230, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}
