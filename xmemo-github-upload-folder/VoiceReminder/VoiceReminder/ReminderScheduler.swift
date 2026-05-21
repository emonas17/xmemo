import Foundation
import UserNotifications
import UniformTypeIdentifiers

enum ReminderSchedulerError: LocalizedError {
    case notificationsDenied
    case timeInPast
    case attachmentFailed

    var errorDescription: String? {
        switch self {
        case .notificationsDenied:
            return AppLanguage.text(lt: "Reikia leidimo siųsti pranešimus.", en: "Notification permission is needed.")
        case .timeInPast:
            return AppLanguage.text(lt: "Pasirinkite laiką ateityje.", en: "Choose a future time.")
        case .attachmentFailed:
            return AppLanguage.text(lt: "Nepavyko pridėti balso failo prie pranešimo.", en: "Could not attach the voice file to the notification.")
        }
    }
}

enum ReminderScheduler {
    private static let followUpOffsets: [TimeInterval] = [10 * 60, 20 * 60, 30 * 60]

    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func schedule(at date: Date, voiceFileURL: URL, title: String, soundName: String?) async throws {
        guard date > Date().addingTimeInterval(2) else {
            throw ReminderSchedulerError.timeInPast
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            throw ReminderSchedulerError.notificationsDenied
        }

        let id = UUID().uuidString
        let persistentURL = try ReminderAudioStore.copyVoiceFile(from: voiceFileURL, notificationId: id)
        ReminderAudioStore.rememberTitle(title, notificationId: id)
        ReminderAudioStore.rememberNotificationSoundName(soundName, notificationId: id)
        try await scheduleStoredReminder(notificationId: id, date: date, voiceFileURL: persistentURL)
        for (index, offset) in followUpOffsets.enumerated() {
            let followUpDate = date.addingTimeInterval(offset)
            try await scheduleStoredReminder(
                notificationId: id,
                requestId: followUpRequestId(notificationId: id, index: index),
                date: followUpDate,
                voiceFileURL: persistentURL,
                isFollowUp: true
            )
        }
    }

    static func scheduleRepeating(
        weekdays: [Int],
        hour: Int,
        minute: Int,
        voiceFileURL: URL,
        title: String,
        soundName: String?
    ) async throws {
        let validWeekdays = weekdays.filter { (1...7).contains($0) }
        guard !validWeekdays.isEmpty else {
            throw ReminderSchedulerError.timeInPast
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            throw ReminderSchedulerError.notificationsDenied
        }

        let id = UUID().uuidString
        let persistentURL = try ReminderAudioStore.copyVoiceFile(from: voiceFileURL, notificationId: id)
        ReminderAudioStore.rememberTitle(title, notificationId: id)
        ReminderAudioStore.rememberNotificationSoundName(soundName, notificationId: id)

        var requestIds: [String] = []
        for weekday in validWeekdays {
            let requestId = "\(id)-w\(weekday)"
            requestIds.append(requestId)
            try await scheduleStoredReminder(
                notificationId: id,
                requestId: requestId,
                dateComponents: DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday),
                repeats: true,
                voiceFileURL: persistentURL
            )
        }
        ReminderAudioStore.rememberRepeatingRequestIds(requestIds, notificationId: id)
    }

    static func snooze(notificationId: String, until date: Date) async throws {
        guard date > Date().addingTimeInterval(2) else {
            throw ReminderSchedulerError.timeInPast
        }

        guard let url = ReminderAudioStore.existingFileURL(forNotificationId: notificationId) else {
            throw ReminderSchedulerError.attachmentFailed
        }

        try await scheduleStoredReminder(notificationId: notificationId, date: date, voiceFileURL: url)
        for (index, offset) in followUpOffsets.enumerated() {
            try await scheduleStoredReminder(
                notificationId: notificationId,
                requestId: followUpRequestId(notificationId: notificationId, index: index),
                date: date.addingTimeInterval(offset),
                voiceFileURL: url,
                isFollowUp: true
            )
        }
    }

    static func cancelPendingAlerts(notificationId: String) {
        let ids = [notificationId] + followUpOffsets.indices.map { followUpRequestId(notificationId: notificationId, index: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func cancelRepeating(notificationId: String) {
        let requestIds = ReminderAudioStore.repeatingRequestIds(forNotificationId: notificationId)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requestIds)
        ReminderAudioStore.clearRepeatingRequestIds(forNotificationId: notificationId)
    }

    private static func scheduleStoredReminder(
        notificationId id: String,
        date: Date,
        voiceFileURL: URL,
        isFollowUp: Bool = false
    ) async throws {
        try await scheduleStoredReminder(
            notificationId: id,
            requestId: id,
            date: date,
            voiceFileURL: voiceFileURL,
            isFollowUp: isFollowUp
        )
    }

    private static func scheduleStoredReminder(
        notificationId id: String,
        requestId: String,
        date: Date,
        voiceFileURL: URL,
        isFollowUp: Bool = false
    ) async throws {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        try await scheduleStoredReminder(
            notificationId: id,
            requestId: requestId,
            dateComponents: components,
            repeats: false,
            voiceFileURL: voiceFileURL,
            isFollowUp: isFollowUp
        )
        if !isFollowUp {
            ScheduledReminderPlayback.remember(notificationId: id, date: date)
        }
    }

    private static func scheduleStoredReminder(
        notificationId id: String,
        requestId: String,
        dateComponents components: DateComponents,
        repeats: Bool,
        voiceFileURL: URL,
        isFollowUp: Bool = false
    ) async throws {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = ReminderAudioStore.title(forNotificationId: id)
        content.body = isFollowUp
            ? AppLanguage.text(lt: "Pakartotinis priminimas. Perklausykite arba atidėkite.", en: "Reminder again. Listen or snooze.")
            : AppLanguage.text(lt: "Pasirinkite veiksmą: perklausyti arba priminti vėliau.", en: "Choose an action: listen or snooze.")
        if let soundName = ReminderAudioStore.notificationSoundName(forNotificationId: id) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundName))
        } else {
            content.sound = .default
        }
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "lt.voicereminder.voice"
        content.categoryIdentifier = ReminderNotificationAction.category
        content.userInfo = ["nid": id]

        if let attachment = try? UNNotificationAttachment(
            identifier: "voice",
            url: voiceFileURL,
            options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.audio.identifier]
        ) {
            content.attachments = [attachment]
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)
        try await center.add(request)
    }

    private static func followUpRequestId(notificationId: String, index: Int) -> String {
        "\(notificationId)-followup-\(index + 1)"
    }
}
