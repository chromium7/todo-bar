import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
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
        reminders.onOpen = { [weak self] taskID in self?.showTask(taskID) }
        setUpStatusItem()
    }

    // MARK: - Main menu (never visible for a menu-bar app, but it provides the
    // ⌘Z / ⌘C / ⌘V / ⌘N / ⌘1…⌘9 shortcuts)

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

        let workspaceMenu = NSMenu(title: "Workspace")
        let newWorkspace = item("New Workspace", #selector(newWorkspace))
        newWorkspace.keyEquivalent = "N"  // ⇧⌘N
        workspaceMenu.addItem(newWorkspace)
        for index in 0..<9 {
            let switchItem = item("Workspace \(index + 1)", #selector(switchWorkspaceByIndex(_:)))
            switchItem.keyEquivalent = "\(index + 1)"
            switchItem.tag = index
            workspaceMenu.addItem(switchItem)
        }
        addSubmenu(workspaceMenu, to: main)

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

    @objc private func newWorkspace() {
        showPanel()
        list.newWorkspace()
    }

    @objc private func switchWorkspaceByIndex(_ sender: NSMenuItem) {
        list.switchWorkspace(at: sender.tag)
    }

    @objc private func switchWorkspace(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        list.switchWorkspace(to: id)
    }

    /// From a clicked reminder: open the panel on the task's workspace with the task selected.
    private func showTask(_ id: UUID?) {
        showPanel()
        guard let id, let item = store.item(id) else { return }
        if let workspaceID = item.workspaceID { list.switchWorkspace(to: workspaceID) }
        list.selectedID = id
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(switchWorkspaceByIndex(_:)) {
            return store.workspaces.indices.contains(menuItem.tag)
        }
        return true
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

        // Switch workspace without opening the panel.
        for workspace in store.workspaces {
            let workspaceItem = item(workspace.name, #selector(switchWorkspace(_:)))
            workspaceItem.representedObject = workspace.id.uuidString
            workspaceItem.state = workspace.id == store.currentWorkspaceID ? .on : .off
            menu.addItem(workspaceItem)
        }
        menu.addItem(item("New Workspace…", #selector(newWorkspace)))
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
