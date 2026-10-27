import AppKit
import Combine
import SwiftUI

enum DockEdge: String {
    case left, right
}

/// Borderless, always-on-top panel that can take keyboard focus without activating the app.
final class FloatingPanel: NSPanel {
    var onEscape: () -> Void = {}
    /// Sees key presses first whenever no text field is being edited; returns true if it handled them.
    var keyHandler: (NSEvent) -> Bool = { _ in false }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape() }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !(firstResponder is NSText), keyHandler(event) { return }
        super.sendEvent(event)
    }

    // Don't let AppKit push the window back on screen while we position it ourselves.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Lets the first click on an inactive panel hit the button under the cursor.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PanelController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isCollapsed = false
    @Published private(set) var edge: DockEdge = .right

    static let tabSize = NSSize(width: 30, height: 96)
    static let minSize = NSSize(width: 250, height: 200)
    static let tabCornerRadius: CGFloat = 9
    static let idleAlpha: CGFloat = 0.4

    /// True when the panel sits on Apple's real Liquid Glass (macOS 26 SDK and later);
    /// otherwise the SwiftUI layer draws an imitation over a blur.
    @Published private(set) var usesNativeGlass = false

    var cornerRadius: CGFloat { settings.windowStyle == .glass ? 18 : 12 }

    let panel: FloatingPanel
    private let store: TodoStore
    private let list: ListController
    private let settings: AppSettings
    private let effectView = NSVisualEffectView()
    private var hostingView: NSView!
    private var expandedFrame: NSRect
    private var isAnimating = false
    private var mouseInside = false
    private var fadeTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    init(store: TodoStore, list: ListController, settings: AppSettings) {
        self.store = store
        self.list = list
        self.settings = settings
        let saved = defaults.string(forKey: "expandedFrame").map(NSRectFromString) ?? .zero
        expandedFrame = saved.width >= Self.minSize.width ? saved : Self.defaultFrame()
        panel = FloatingPanel(
            contentRect: expandedFrame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = Self.minSize
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.collapse() }
        panel.keyHandler = { [weak self] event in
            guard let self else { return false }
            if event.keyCode == 53 { // esc
                self.collapse()
                return true
            }
            return !self.isCollapsed && list.handleKey(event)
        }

        effectView.blendingMode = .behindWindow
        effectView.state = .active

        let root = RootView()
            .environmentObject(store)
            .environmentObject(list)
            .environmentObject(settings)
            .environmentObject(self)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hostingView = hosting
        installBackdrop()

        restoreState()

        settings.$windowStyle
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.installBackdrop()
                self?.updateChrome()
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        // Fade when idle: track the mouse over the panel and app activation.
        hostingView.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil
        ))
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(activationChanged), name: name, object: nil)
        }
        settings.$fadeWhenIdle
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateFade() }
            .store(in: &cancellables)
        mouseInside = panel.frame.contains(NSEvent.mouseLocation)
        updateFade()
    }

    // MARK: - Public

    func show() {
        panel.orderFrontRegardless()
    }

    func toggleCollapsed() {
        isCollapsed ? expand() : collapse()
    }

    func collapse() {
        guard !isCollapsed else { return }
        expandedFrame = panel.frame
        let screen = screen(for: panel.frame)
        edge = panel.frame.midX < screen.visibleFrame.midX ? .left : .right
        isCollapsed = true
        list.clearSelection()
        panel.makeFirstResponder(nil)
        updateFade()
        updateChrome()
        animate(to: tabFrame(top: panel.frame.maxY, on: screen))
    }

    func expand() {
        guard isCollapsed else { return }
        let screen = screen(for: panel.frame)
        let visible = screen.visibleFrame
        var target = expandedFrame
        // Open next to where the tab currently sits.
        target.origin.y = panel.frame.maxY - target.height
        let wasOnThisSide = visible.contains(NSPoint(x: target.midX, y: visible.midY))
            && (target.midX < visible.midX) == (edge == .left)
        if !wasOnThisSide {
            target.origin.x = edge == .left ? visible.minX + 12 : visible.maxX - target.width - 12
        }
        target = clamp(target, to: visible)
        isCollapsed = false
        updateChrome()
        animate(to: target)
        panel.makeKey()  // so Esc works straight away
        updateFade()
    }

    func focusAddField() {
        show()
        expand()
        panel.makeKey()
        list.focusAddField()
    }

    /// Called after the tab has been dragged: stick it to whichever edge is nearest.
    func snapTab() {
        guard isCollapsed else { return }
        let screen = screen(for: panel.frame)
        edge = panel.frame.midX < screen.visibleFrame.midX ? .left : .right
        updateChrome()
        animate(to: tabFrame(top: panel.frame.maxY, on: screen))
    }

    // MARK: - Geometry

    private static func defaultFrame() -> NSRect {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let size = NSSize(width: 290, height: 380)
        return NSRect(x: visible.maxX - size.width - 20, y: visible.maxY - size.height - 20,
                      width: size.width, height: size.height)
    }

    private func screen(for rect: NSRect) -> NSScreen {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.max { $0.frame.intersection(rect).width < $1.frame.intersection(rect).width }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func tabFrame(top: CGFloat, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let size = Self.tabSize
        let y = min(max(top - size.height, visible.minY), visible.maxY - size.height)
        let x = edge == .left ? visible.minX : visible.maxX - size.width
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func clamp(_ rect: NSRect, to visible: NSRect) -> NSRect {
        var r = rect
        r.size.width = min(r.width, visible.width)
        r.size.height = min(r.height, visible.height)
        r.origin.x = min(max(r.minX, visible.minX), visible.maxX - r.width)
        r.origin.y = min(max(r.minY, visible.minY), visible.maxY - r.height)
        return r
    }

    private func animate(to frame: NSRect) {
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.isAnimating = false
            self.panel.invalidateShadow()
            self.persist()
        })
    }

    /// Puts the SwiftUI content on real Liquid Glass when the SDK and OS have it,
    /// otherwise on a behind-window blur.
    private func installBackdrop() {
        hostingView.removeFromSuperview()
        #if compiler(>=6.2)
        if settings.windowStyle == .glass, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.contentView = hostingView
            panel.contentView = glass
            usesNativeGlass = true
            return
        }
        #endif
        usesNativeGlass = false
        effectView.material = settings.windowStyle == .glass ? .sidebar : .popover
        panel.contentView = effectView
        hostingView.frame = effectView.bounds
        effectView.addSubview(hostingView)
    }

    private func updateChrome() {
        let radius = isCollapsed ? Self.tabCornerRadius : cornerRadius
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = panel.contentView as? NSGlassEffectView {
            glass.cornerRadius = radius
        }
        #endif
        effectView.maskImage = Self.maskImage(radius: radius, squareSide: isCollapsed ? edge : nil)
        panel.invalidateShadow()
        if isCollapsed {
            panel.styleMask.remove(.resizable)
            panel.minSize = Self.tabSize
        } else {
            panel.styleMask.insert(.resizable)
            panel.minSize = Self.minSize
        }
    }

    /// Stretchable rounded-rect mask; `squareSide` keeps the corners flat on the side touching the screen edge.
    private static func maskImage(radius: CGFloat, squareSide: DockEdge?) -> NSImage {
        let length = radius * 2 + 1
        let image = NSImage(size: NSSize(width: length, height: length), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            switch squareSide {
            case .left: NSBezierPath(rect: NSRect(x: 0, y: 0, width: radius + 1, height: length)).fill()
            case .right: NSBezierPath(rect: NSRect(x: radius, y: 0, width: radius + 1, height: length)).fill()
            case nil: break
            }
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: - Persistence

    private func restoreState() {
        edge = DockEdge(rawValue: defaults.string(forKey: "edge") ?? "") ?? .right
        isCollapsed = defaults.bool(forKey: "isCollapsed")
        let screen = screen(for: expandedFrame)
        if isCollapsed {
            let savedTab = defaults.string(forKey: "tabFrame").map(NSRectFromString) ?? expandedFrame
            panel.setFrame(tabFrame(top: savedTab.maxY, on: self.screen(for: savedTab)), display: false)
        } else {
            panel.setFrame(clamp(expandedFrame, to: screen.visibleFrame), display: false)
        }
        updateChrome()
    }

    private func persist() {
        if !isCollapsed { expandedFrame = panel.frame }
        defaults.set(NSStringFromRect(expandedFrame), forKey: "expandedFrame")
        defaults.set(isCollapsed, forKey: "isCollapsed")
        defaults.set(edge.rawValue, forKey: "edge")
        if isCollapsed { defaults.set(NSStringFromRect(panel.frame), forKey: "tabFrame") }
    }

    @objc private func screensChanged() {
        if isCollapsed {
            snapTab()
        } else {
            panel.setFrame(clamp(panel.frame, to: screen(for: panel.frame).visibleFrame), display: true)
        }
    }

    // MARK: - Fade when idle

    private var shouldStayOpaque: Bool {
        !settings.fadeWhenIdle || isCollapsed || mouseInside || NSApp.isActive
            || (panel.isKeyWindow && panel.firstResponder is NSText)
    }

    private func updateFade() {
        fadeTimer?.invalidate()
        if shouldStayOpaque { setAlpha(1) }
        guard settings.fadeWhenIdle, !isCollapsed, !mouseInside else { return }
        // Fade after a moment; if still busy (typing, popover open), check again later.
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.shouldStayOpaque { self.updateFade() } else { self.setAlpha(Self.idleAlpha) }
        }
    }

    private func setAlpha(_ alpha: CGFloat) {
        guard panel.alphaValue != alpha else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = alpha
        }
    }

    @objc func mouseEntered(with event: NSEvent) {
        mouseInside = true
        updateFade()
    }

    @objc func mouseExited(with event: NSEvent) {
        mouseInside = false
        updateFade()
    }

    @objc private func activationChanged() {
        updateFade()
    }

    // MARK: - NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        store.undoManager
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateFade()
    }

    func windowDidResignKey(_ notification: Notification) {
        updateFade()
    }

    func windowDidMove(_ notification: Notification) {
        if !isAnimating && !isCollapsed { persist() }
    }

    func windowDidResize(_ notification: Notification) {
        if !isAnimating && !isCollapsed { persist() }
        panel.invalidateShadow()
    }
}
