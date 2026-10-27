import Combine
import Foundation
import UserNotifications

/// Keeps one notification per upcoming deadline in sync with the task list:
/// 15 minutes before and at the deadline for timed tasks, 9:00 on the day for date-only ones.
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: () -> Void = {}

    private let center = UNUserNotificationCenter.current()
    private var cancellable: AnyCancellable?

    init(store: TodoStore, settings: AppSettings) {
        super.init()
        center.delegate = self
        cancellable = store.$items
            .combineLatest(settings.$remindersEnabled)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] items, enabled in
                self?.reschedule(items, enabled: enabled)
            }
    }

    private func reschedule(_ items: [TodoItem], enabled: Bool) {
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }

        let requests = Self.requests(for: items, now: Date())
        guard !requests.isEmpty else { return }
        center.requestAuthorization(options: [.alert, .sound]) { [center] granted, _ in
            guard granted else { return }
            requests.forEach { center.add($0) }
        }
    }

    private static func requests(for items: [TodoItem], now: Date) -> [UNNotificationRequest] {
        let cal = Calendar.current
        var reminders: [(id: String, date: Date, title: String, body: String)] = []

        for item in items where !item.isDone {
            guard let deadline = item.deadline else { continue }
            if item.deadlineHasTime {
                let time = deadline.formatted(date: .omitted, time: .shortened)
                reminders.append(("\(item.id)-soon", deadline.addingTimeInterval(-15 * 60), item.title, "Due in 15 minutes (\(time))"))
                reminders.append(("\(item.id)-due", deadline, item.title, "Due now"))
            } else if let morning = cal.date(bySettingHour: 9, minute: 0, second: 0, of: deadline) {
                reminders.append(("\(item.id)-day", morning, item.title, "Due today"))
            }
        }

        // macOS keeps at most 64 pending notifications per app; schedule the soonest.
        return reminders
            .filter { $0.date > now }
            .sorted { $0.date < $1.date }
            .prefix(60)
            .map { reminder in
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default
                let components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            }
    }

    // Show banners even though TodoBar counts as the running app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.onOpen() }
        completionHandler()
    }
}
