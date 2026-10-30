import AppKit
import ServiceManagement

enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark, pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .pink: "Soft Pink"
        }
    }
}

enum WindowStyle: String, CaseIterable, Identifiable {
    case standard, glass, doodle, rilakkuma, quby

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .glass: "Liquid Glass"
        case .doodle: "Doodles"
        case .rilakkuma: "Rilakkuma"
        case .quby: "Quby"
        }
    }
}

/// How often the look shuffles when rotation is on. Changes happen at midnight (and noon).
enum RotationInterval: String, CaseIterable, Identifiable {
    case halfDay, daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .halfDay: "Every 12 hours"
        case .daily: "Every day"
        }
    }
}

extension Theme {
    /// The themes the rotation can pick; System isn't a look of its own.
    static let rotatable: [Theme] = [.light, .dark, .pink]

    /// Checkboxes, selection and controls. nil means the system accent colour.
    var accent: NSColor? {
        self == .pink ? NSColor(srgbRed: 0.89, green: 0.44, blue: 0.59, alpha: 1) : nil
    }

    /// Laid over the window background. nil means no tint.
    var wash: NSColor? {
        self == .pink ? NSColor(srgbRed: 1.0, green: 0.84, blue: 0.89, alpha: 1) : nil
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

    /// Shuffle theme and style on a schedule.
    @Published var rotationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(rotationEnabled, forKey: "rotationEnabled")
            // Keep the look just chosen until the next change, rather than shuffling right away.
            if rotationEnabled { markRotated() }
        }
    }
    @Published var rotationInterval: RotationInterval {
        didSet {
            UserDefaults.standard.set(rotationInterval.rawValue, forKey: "rotationInterval")
            markRotated()
        }
    }
    @Published var rotationThemes: Set<Theme> {
        didSet { UserDefaults.standard.set(rotationThemes.map(\.rawValue), forKey: "rotationThemes") }
    }
    @Published var rotationStyles: Set<WindowStyle> {
        didSet { UserDefaults.standard.set(rotationStyles.map(\.rawValue), forKey: "rotationStyles") }
    }
    private var rotationTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        windowStyle = WindowStyle(rawValue: defaults.string(forKey: "windowStyle") ?? "") ?? .glass
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        remindersEnabled = defaults.object(forKey: "remindersEnabled") as? Bool ?? true
        fadeWhenIdle = defaults.object(forKey: "fadeWhenIdle") as? Bool ?? true
        rotationEnabled = defaults.bool(forKey: "rotationEnabled")
        rotationInterval = RotationInterval(rawValue: defaults.string(forKey: "rotationInterval") ?? "") ?? .daily
        let themes = Set((defaults.stringArray(forKey: "rotationThemes") ?? []).compactMap(Theme.init(rawValue:)))
        rotationThemes = themes.isEmpty ? Set(Theme.rotatable) : themes
        let styles = Set((defaults.stringArray(forKey: "rotationStyles") ?? []).compactMap(WindowStyle.init(rawValue:)))
        rotationStyles = styles.isEmpty ? Set(WindowStyle.allCases) : styles
        refreshLaunchAtLogin()
    }

    // MARK: - Rotation

    /// Checks once a minute whether a new half-day or day has begun (this also catches up after sleep).
    func startRotation() {
        rotateIfDue()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.rotateIfDue()
        }
        rotationTimer?.tolerance = 10
    }

    /// Picks a random theme and style from the chosen ones, different from the current look when possible.
    func shuffleLook() {
        let themes = Theme.rotatable.filter(rotationThemes.contains)
        let styles = WindowStyle.allCases.filter(rotationStyles.contains)
        var looks = themes.flatMap { theme in styles.map { (theme, $0) } }
        if looks.count > 1 {
            looks.removeAll { $0.0 == theme && $0.1 == windowStyle }
        }
        guard let look = looks.randomElement() else { return }
        theme = look.0
        windowStyle = look.1
        markRotated()
    }

    /// When the look will next change.
    var nextRotation: Date {
        let calendar = Calendar.current
        let start = rotationPeriodStart(for: Date())
        if rotationInterval == .halfDay, calendar.component(.hour, from: start) < 12,
           let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start) {
            return noon
        }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? start
    }

    private func rotateIfDue() {
        guard rotationEnabled else { return }
        let rotated = UserDefaults.standard.double(forKey: "rotationPeriod")
        if rotated != rotationPeriodStart(for: Date()).timeIntervalSince1970 {
            shuffleLook()
        }
    }

    private func markRotated() {
        UserDefaults.standard.set(rotationPeriodStart(for: Date()).timeIntervalSince1970, forKey: "rotationPeriod")
    }

    /// Midnight, or noon in the afternoon when rotating every 12 hours.
    private func rotationPeriodStart(for date: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        if rotationInterval == .halfDay, calendar.component(.hour, from: date) >= 12,
           let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) {
            return noon
        }
        return day
    }

    func applyTheme() {
        NSApp.appearance = switch theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .pink: NSAppearance(named: .aqua)
        }
    }

    /// The theme's accent, except that sticker styles bring their own (Soft Pink keeps its rose).
    var accent: NSColor? {
        if let pack = windowStyle.stickerPack, theme != .pink {
            return pack.accent
        }
        return theme.accent
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
