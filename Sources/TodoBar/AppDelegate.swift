import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = TodoStore()
    private let settings = AppSettings()
    private lazy var list = ListController(store: store)
    private var panelController: PanelController!
    private var reminders: ReminderScheduler!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.applyTheme()
        settings.enableLaunchAtLoginOnFirstRun()
        setUpMainMenu()
        panelController = PanelController(store: store, list: list, settings: settings)
        panelController.show()
        reminders = ReminderScheduler(store: store, settings: settings)
        reminders.onOpen = { [weak self] in self?.showPanel() }
        setUpStatusItem()
    }

    // MARK: - Main menu (never visible for a menu-bar app, but it provides the
    // ⌘Z / ⌘C / ⌘V / ⌘N shortcuts)

    private func setUpMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit TodoBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        addSubmenu(appMenu, to: main)

        let fileMenu = NSMenu(title: "File")
        let newTask = item("New Task", #selector(newTask))
        newTask.keyEquivalent = "n"
        fileMenu.addItem(newTask)
        addSubmenu(fileMenu, to: main)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        addSubmenu(editMenu, to: main)

        NSApp.mainMenu = main
    }

    private func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let holder = NSMenuItem()
        holder.submenu = submenu
        menu.addItem(holder)
    }

    @objc private func newTask() {
        panelController.focusAddField()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    // MARK: - Menu bar item (a way back if the panel ever gets lost)

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "TodoBar")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        settings.refreshLaunchAtLogin()

        menu.addItem(item("Show TodoBar", #selector(showPanel)))
        menu.addItem(item(panelController.isCollapsed ? "Expand" : "Collapse to Side", #selector(toggleCollapsed)))
        menu.addItem(.separator())

        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for theme in Theme.allCases {
            let themeOption = item(theme.title, #selector(selectTheme(_:)))
            themeOption.representedObject = theme.rawValue
            themeOption.state = settings.theme == theme ? .on : .off
            themeMenu.addItem(themeOption)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = settings.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TodoBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showPanel() {
        panelController.show()
        panelController.expand()
    }

    @objc private func toggleCollapsed() {
        panelController.show()
        panelController.toggleCollapsed()
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let theme = Theme(rawValue: raw) else { return }
        settings.theme = theme
    }

    @objc private func toggleLaunchAtLogin() {
        settings.setLaunchAtLogin(!settings.launchAtLogin)
    }
}
