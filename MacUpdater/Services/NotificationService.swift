import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private var isAuthorized = false

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            logInfo("Notification authorization: \(granted)", category: "NotificationService")
        } catch {
            logError("Notification auth failed: \(error.localizedDescription)", category: "NotificationService")
        }
    }

    func sendDownloadStarted(title: String, version: String) {
        send(
            id: "download-start-\(version)",
            title: "Download Started",
            body: "\(title) \(version) is downloading."
        )
    }

    func sendDownloadCompleted(title: String, version: String) {
        send(
            id: "download-complete-\(version)",
            title: "Download Complete",
            body: "\(title) \(version) installer is ready in /Applications."
        )
    }

    func sendDownloadFailed(title: String, version: String, error: String) {
        send(
            id: "download-failed-\(version)",
            title: "Download Failed",
            body: "\(title) \(version) failed: \(error)"
        )
    }

    func sendInstallerDetected(title: String, version: String) {
        send(
            id: "installer-detected-\(version)",
            title: "Installer Detected",
            body: "\(title) \(version) found in /Applications."
        )
    }

    private func send(id: String, title: String, body: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logError("Notification error: \(error.localizedDescription)", category: "NotificationService")
            }
        }
    }
}
