import AppKit
import ServiceManagement

enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum WindowStyle: String, CaseIterable, Identifiable {
    case standard, glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .glass: "Liquid Glass"
        }
    }
}

final class AppSettings: ObservableObject {
    @Published var windowStyle: WindowStyle {
        didSet { UserDefaults.standard.set(windowStyle.rawValue, forKey: "windowStyle") }
    }
    @Published var theme: Theme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
            applyTheme()
        }
    }
    @Published var remindersEnabled: Bool {
        didSet { UserDefaults.standard.set(remindersEnabled, forKey: "remindersEnabled") }
    }
    @Published var fadeWhenIdle: Bool {
        didSet { UserDefaults.standard.set(fadeWhenIdle, forKey: "fadeWhenIdle") }
    }
    @Published private(set) var launchAtLogin = false

    init() {
        let defaults = UserDefaults.standard
        windowStyle = WindowStyle(rawValue: defaults.string(forKey: "windowStyle") ?? "") ?? .glass
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        remindersEnabled = defaults.object(forKey: "remindersEnabled") as? Bool ?? true
        fadeWhenIdle = defaults.object(forKey: "fadeWhenIdle") as? Bool ?? true
        refreshLaunchAtLogin()
    }

    func applyTheme() {
        NSApp.appearance = switch theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func toggleLightDark() {
        theme = isDark ? .light : .dark
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("TodoBar: could not update login item: \(error)")
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Turn on launch-at-login the first time the app runs; after that, respect the user's choice.
    func enableLaunchAtLoginOnFirstRun() {
        let key = "didConfigureLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        setLaunchAtLogin(true)
    }
}
