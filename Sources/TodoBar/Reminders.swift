import Combine
import Foundation
import UserNotifications

/// Keeps one notification per upcoming deadline in sync with the task list:
/// 15 minutes before and at the deadline for timed tasks, 9:00 on the day for date-only ones.
/// Covers every workspace, not just the one showing.
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    /// Called with the task's id when a notification is clicked.
    var onOpen: (UUID?) -> Void = { _ in }

    private let center = UNUserNotificationCenter.current()
    private var cancellable: AnyCancellable?

    init(store: TodoStore, settings: AppSettings) {
        super.init()
        center.delegate = self
        cancellable = store.$allItems
            .combineLatest(store.$workspaces, settings.$remindersEnabled)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] items, workspaces, enabled in
                self?.reschedule(items, workspaces: workspaces, enabled: enabled)
            }
    }

    private func reschedule(_ items: [TodoItem], workspaces: [Workspace], enabled: Bool) {
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }

        let requests = Self.requests(for: items, workspaces: workspaces, now: Date())
        guard !requests.isEmpty else { return }
        center.requestAuthorization(options: [.alert, .sound]) { [center] granted, _ in
            guard granted else { return }
            requests.forEach { center.add($0) }
        }
    }

    private static func requests(for items: [TodoItem], workspaces: [Workspace], now: Date) -> [UNNotificationRequest] {
        let cal = Calendar.current
        // Only label notifications with the workspace once there's more than one.
        let names = workspaces.count > 1
            ? Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0.name) })
            : [:]
        var reminders: [(item: TodoItem, suffix: String, date: Date, body: String)] = []

        for item in items where !item.isDone {
            guard let deadline = item.deadline else { continue }
            if item.deadlineHasTime {
                let time = deadline.formatted(date: .omitted, time: .shortened)
                reminders.append((item, "soon", deadline.addingTimeInterval(-15 * 60), "Due in 15 minutes (\(time))"))
                reminders.append((item, "due", deadline, "Due now"))
            } else if let morning = cal.date(bySettingHour: 9, minute: 0, second: 0, of: deadline) {
                reminders.append((item, "day", morning, "Due today"))
            }
        }

        // macOS keeps at most 64 pending notifications per app; schedule the soonest.
        return reminders
            .filter { $0.date > now }
            .sorted { $0.date < $1.date }
            .prefix(60)
            .map { reminder in
                let content = UNMutableNotificationContent()
                content.title = reminder.item.title
                content.subtitle = reminder.item.workspaceID.flatMap { names[$0] } ?? ""
                content.body = reminder.body
                content.sound = .default
                content.userInfo = ["taskID": reminder.item.id.uuidString]
                let components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                return UNNotificationRequest(identifier: "\(reminder.item.id)-\(reminder.suffix)",
                                             content: content, trigger: trigger)
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
        let taskID = (response.notification.request.content.userInfo["taskID"] as? String).flatMap { UUID(uuidString: $0) }
        DispatchQueue.main.async { self.onOpen(taskID) }
        completionHandler()
    }
}
