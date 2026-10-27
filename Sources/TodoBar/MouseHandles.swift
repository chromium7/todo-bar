import AppKit
import SwiftUI

/// Drag anywhere on it to move the window; double-click to run `onDoubleClick`.
struct WindowDragArea: NSViewRepresentable {
    var onDoubleClick: () -> Void = {}

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { view.onDoubleClick = onDoubleClick }

    final class DragView: NSView {
        var onDoubleClick: () -> Void = {}
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick()
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

/// The collapsed tab: click to expand, drag to move it (it re-snaps to the nearest edge on release).
struct TabHandle: NSViewRepresentable {
    var onClick: () -> Void
    var onDragEnd: () -> Void

    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {
        view.onClick = onClick
        view.onDragEnd = onDragEnd
    }

    final class HandleView: NSView {
        var onClick: () -> Void = {}
        var onDragEnd: () -> Void = {}
        private var startMouse = NSPoint.zero
        private var startOrigin = NSPoint.zero
        private var dragging = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

        override func mouseDown(with event: NSEvent) {
            startMouse = NSEvent.mouseLocation
            startOrigin = window?.frame.origin ?? .zero
            dragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - startMouse.x
            let dy = mouse.y - startMouse.y
            if !dragging && hypot(dx, dy) < 3 { return }
            dragging = true
            window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        }

        override func mouseUp(with event: NSEvent) {
            dragging ? onDragEnd() : onClick()
        }
    }
}

/// Bottom-right grip for resizing the borderless panel.
struct ResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> GripView { GripView() }
    func updateNSView(_ view: GripView, context: Context) {}

    final class GripView: NSView {
        private var startMouse = NSPoint.zero
        private var startFrame = NSRect.zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            startMouse = NSEvent.mouseLocation
            startFrame = window?.frame ?? .zero
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let mouse = NSEvent.mouseLocation
            let width = max(window.minSize.width, startFrame.width + mouse.x - startMouse.x)
            let height = max(window.minSize.height, startFrame.height - (mouse.y - startMouse.y))
            window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height),
                            display: true)
        }
    }
}
