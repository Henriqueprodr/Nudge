import CryptoKit
import Foundation
import UserNotifications

@MainActor
protocol ReminderNotificationFallbackProviding {
    var statusMessage: String { get }
    func setSoundEnabled(_ isEnabled: Bool)
    func requestAuthorization() async -> Bool
    func deliver(_ reminder: Reminder) async -> Bool
}

@MainActor
final class ReminderNotificationFallback: NSObject, ReminderNotificationFallbackProviding,
    UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private(set) var statusMessage = "Notification fallback is off."
    private(set) var isSoundEnabled = true

    var notificationSound: UNNotificationSound? {
        isSoundEnabled ? .default : nil
    }

    var foregroundPresentationOptions: UNNotificationPresentationOptions {
        isSoundEnabled ? [.banner, .sound] : [.banner]
    }

    var authorizationOptions: UNAuthorizationOptions {
        isSoundEnabled ? [.alert, .sound] : [.alert]
    }

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: authorizationOptions)
            statusMessage = granted
                ? "Notification fallback is available."
                : "Notification permission was not granted; overlays remain enabled."
            return granted
        } catch {
            statusMessage = "Notification permission could not be requested; overlays remain enabled."
            return false
        }
    }

    func setSoundEnabled(_ isEnabled: Bool) {
        isSoundEnabled = isEnabled
    }

    func deliver(_ reminder: Reminder) async -> Bool {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else {
            statusMessage = "Notification fallback is unavailable; the reminder remains pending."
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.detail ?? "Calendar reminder"
        content.sound = notificationSound
        let data = (try? JSONEncoder().encode(reminder.occurrenceID)) ?? Data()
        let identifier = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: "nudge.reminder.\(identifier)",
                    content: content,
                    trigger: nil
                )
            )
            statusMessage = "The last unavailable overlay used notification fallback."
            return true
        } catch {
            statusMessage = "Notification fallback could not be delivered; the reminder remains pending."
            return false
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { self.foregroundPresentationOptions }
    }
}
