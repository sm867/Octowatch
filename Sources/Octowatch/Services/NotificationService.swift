import AppKit
import Foundation
import UserNotifications

@MainActor
enum NotificationService {
    private static var currentSound: NSSound?

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            _, _ in
        }
    }

    static func sendStatusChanged(repo: RepoSummary, passed: Bool, playSound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = passed ? "Checks Passed" : "Checks Failed"
        content.body = repo.fullName
        if playSound {
            currentSound = NSSound(named: passed ? "Glass" : "Basso")
            currentSound?.play()
        }
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "status-\(repo.fullName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
