import Combine
import Foundation
import UserNotifications

enum ReminderNotificationAction {
    static let category = "VOICE_REMINDER_ACTIONS"
    static let play = "VOICE_REMINDER_PLAY"
    static let snooze15 = "VOICE_REMINDER_SNOOZE_15"
    static let snooze60 = "VOICE_REMINDER_SNOOZE_60"
    static let snoozeTomorrow = "VOICE_REMINDER_SNOOZE_TOMORROW"
}

final class NotificationPlaybackRouter: ObservableObject {
    static let shared = NotificationPlaybackRouter()

    private let pendingKey = "VoiceReminderPendingPlaybackNotificationId"
    @Published private(set) var pendingNotificationId: String?

    private init() {
        pendingNotificationId = UserDefaults.standard.string(forKey: pendingKey)
    }

    func openFromNotification(_ response: UNNotificationResponse) {
        let id = response.notification.request.content.userInfo["nid"] as? String
            ?? response.notification.request.identifier
        if let attachmentURL = response.notification.request.content.attachments.first?.url {
            _ = try? ReminderAudioStore.copyNotificationAttachment(from: attachmentURL, notificationId: id)
        }
        open(notificationId: id)
    }

    func open(notificationId: String) {
        let id = notificationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        UserDefaults.standard.set(id, forKey: pendingKey)
        UserDefaults.standard.synchronize()
        DispatchQueue.main.async {
            self.pendingNotificationId = id
        }
    }

    func savedPendingNotificationId() -> String? {
        UserDefaults.standard.string(forKey: pendingKey)
    }

    func clearIfCurrent(_ notificationId: String) {
        DispatchQueue.main.async {
            if self.pendingNotificationId == notificationId {
                self.pendingNotificationId = nil
            }
        }
        if UserDefaults.standard.string(forKey: pendingKey) == notificationId {
            UserDefaults.standard.removeObject(forKey: pendingKey)
            UserDefaults.standard.synchronize()
        }
    }
}

enum ScheduledReminderPlayback {
    private static let idKey = "VoiceReminderScheduledNotificationId"
    private static let dateKey = "VoiceReminderScheduledDate"

    static func remember(notificationId: String, date: Date) {
        UserDefaults.standard.set(notificationId, forKey: idKey)
        UserDefaults.standard.set(date, forKey: dateKey)
        UserDefaults.standard.synchronize()
    }

    static func dueNotificationId(now: Date = Date()) -> String? {
        guard
            let id = UserDefaults.standard.string(forKey: idKey),
            let date = UserDefaults.standard.object(forKey: dateKey) as? Date,
            date <= now
        else {
            return nil
        }

        guard ReminderAudioStore.existingFileURL(forNotificationId: id) != nil else {
            clearIfCurrent(id)
            return nil
        }

        return id
    }

    static func clearIfCurrent(_ notificationId: String) {
        guard UserDefaults.standard.string(forKey: idKey) == notificationId else { return }
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: dateKey)
        UserDefaults.standard.synchronize()
    }
}
