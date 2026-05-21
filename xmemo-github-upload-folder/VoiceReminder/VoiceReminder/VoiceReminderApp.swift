import SwiftUI
import UIKit
import UserNotifications

private let voiceReminderThreadId = "lt.voicereminder.voice"

@main
struct VoiceReminderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerReminderNotificationActions()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let response = options.notificationResponse,
           response.notification.request.content.threadIdentifier == voiceReminderThreadId,
           shouldOpenPlayback(for: response) {
            NotificationPlaybackRouter.shared.openFromNotification(response)
        }
        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.content.threadIdentifier == voiceReminderThreadId else {
            completionHandler()
            return
        }
        let notificationId = response.notification.request.content.userInfo["nid"] as? String
            ?? response.notification.request.identifier

        switch response.actionIdentifier {
        case ReminderNotificationAction.play, UNNotificationDefaultActionIdentifier:
            NotificationPlaybackRouter.shared.openFromNotification(response)
            completionHandler()
        case ReminderNotificationAction.snooze15:
            snooze(notificationId: notificationId, until: Date().addingTimeInterval(15 * 60), completionHandler: completionHandler)
        case ReminderNotificationAction.snooze60:
            snooze(notificationId: notificationId, until: Date().addingTimeInterval(60 * 60), completionHandler: completionHandler)
        case ReminderNotificationAction.snoozeTomorrow:
            let date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(24 * 60 * 60)
            snooze(notificationId: notificationId, until: date, completionHandler: completionHandler)
        default:
            completionHandler()
        }
    }

    private func shouldOpenPlayback(for response: UNNotificationResponse) -> Bool {
        response.actionIdentifier == ReminderNotificationAction.play ||
            response.actionIdentifier == UNNotificationDefaultActionIdentifier
    }

    private func registerReminderNotificationActions() {
        let play = UNNotificationAction(
            identifier: ReminderNotificationAction.play,
            title: AppLanguage.text(lt: "Perklausyti", en: "Listen"),
            options: [.foreground]
        )
        let snooze15 = UNNotificationAction(
            identifier: ReminderNotificationAction.snooze15,
            title: "+15 min",
            options: []
        )
        let snooze60 = UNNotificationAction(
            identifier: ReminderNotificationAction.snooze60,
            title: AppLanguage.text(lt: "+1 val.", en: "+1 hr"),
            options: []
        )
        let snoozeTomorrow = UNNotificationAction(
            identifier: ReminderNotificationAction.snoozeTomorrow,
            title: AppLanguage.text(lt: "Rytoj", en: "Tomorrow"),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: ReminderNotificationAction.category,
            actions: [play, snooze15, snooze60, snoozeTomorrow],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func snooze(
        notificationId: String,
        until date: Date,
        completionHandler: @escaping () -> Void
    ) {
        Task {
            ReminderScheduler.cancelPendingAlerts(notificationId: notificationId)
            try? await ReminderScheduler.snooze(notificationId: notificationId, until: date)
            completionHandler()
        }
    }
}
