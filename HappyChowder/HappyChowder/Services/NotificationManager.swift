import UserNotifications
import UIKit

final class NotificationManager: @unchecked Sendable {
    static let shared = NotificationManager()
    private init() {}

    private var isAuthorized = false

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.isAuthorized = granted
            }
        }
    }

    func notifyTaskComplete(sessionName: String?, summary: String?) {
        guard isAuthorized, UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = sessionName ?? "Claude Code"
        content.body = summary ?? "Task completed"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyError(sessionName: String?, error: String) {
        guard isAuthorized, UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = sessionName ?? "Claude Code"
        content.body = "Error: \(error)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyPermissionNeeded(tool: String, sessionName: String?) {
        guard isAuthorized, UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "Permission Required"
        content.body = "\(sessionName ?? "Claude") wants to use \(tool)"
        content.sound = .default
        content.categoryIdentifier = "PERMISSION_REQUEST"
        let request = UNNotificationRequest(identifier: "perm-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
