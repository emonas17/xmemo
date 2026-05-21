import Foundation

/// Balsas saugomas Application Support, kad būtų galima groti atidarius pranešimą (priedas pranešime vis tiek reikalauja išskleidimo).
enum ReminderAudioStore {
    private static let folderName = "VoiceReminders"

    static var voiceDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func savedPathKey(forNotificationId id: String) -> String {
        "VoiceReminderAudioPath.\(id)"
    }

    private static func titleKey(forNotificationId id: String) -> String {
        "VoiceReminderTitle.\(id)"
    }

    private static func repeatingRequestIdsKey(forNotificationId id: String) -> String {
        "VoiceReminderRepeatingRequestIds.\(id)"
    }

    private static func notificationSoundKey(forNotificationId id: String) -> String {
        "VoiceReminderNotificationSound.\(id)"
    }

    static func rememberTitle(_ title: String, notificationId: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        UserDefaults.standard.set(cleanTitle, forKey: titleKey(forNotificationId: notificationId))
        UserDefaults.standard.synchronize()
    }

    static func title(forNotificationId id: String) -> String {
        UserDefaults.standard.string(forKey: titleKey(forNotificationId: id)) ?? ReminderTitleGenerator.fallbackTitle
    }

    static func rememberRepeatingRequestIds(_ requestIds: [String], notificationId: String) {
        UserDefaults.standard.set(requestIds, forKey: repeatingRequestIdsKey(forNotificationId: notificationId))
        UserDefaults.standard.synchronize()
    }

    static func repeatingRequestIds(forNotificationId id: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: repeatingRequestIdsKey(forNotificationId: id)) ?? []
    }

    static func isRepeating(notificationId: String) -> Bool {
        !repeatingRequestIds(forNotificationId: notificationId).isEmpty
    }

    static func clearRepeatingRequestIds(forNotificationId id: String) {
        UserDefaults.standard.removeObject(forKey: repeatingRequestIdsKey(forNotificationId: id))
        UserDefaults.standard.synchronize()
    }

    static func rememberNotificationSoundName(_ soundName: String?, notificationId: String) {
        if let soundName {
            UserDefaults.standard.set(soundName, forKey: notificationSoundKey(forNotificationId: notificationId))
        } else {
            UserDefaults.standard.removeObject(forKey: notificationSoundKey(forNotificationId: notificationId))
        }
        UserDefaults.standard.synchronize()
    }

    static func notificationSoundName(forNotificationId id: String) -> String? {
        UserDefaults.standard.string(forKey: notificationSoundKey(forNotificationId: id))
    }

    static func rememberExistingFile(_ url: URL, notificationId: String) {
        guard FileManager.default.fileExists(atPath: url.path), fileSize(url) > 0 else { return }
        UserDefaults.standard.set(url.path, forKey: savedPathKey(forNotificationId: notificationId))
        UserDefaults.standard.synchronize()
    }

    static func existingFileURL(forNotificationId id: String) -> URL? {
        candidateFileURLs(forNotificationId: id).first
    }

    static func fileURL(forNotificationId id: String) -> URL {
        existingFileURL(forNotificationId: id) ?? voiceDirectory.appendingPathComponent("\(id).m4a")
    }

    static func candidateFileURLs(forNotificationId id: String) -> [URL] {
        var urls: [URL] = []

        if let path = UserDefaults.standard.string(forKey: savedPathKey(forNotificationId: id)) {
            urls.append(URL(fileURLWithPath: path))
        }

        urls.append(voiceDirectory.appendingPathComponent("\(id).m4a"))
        urls.append(voiceDirectory.appendingPathComponent("\(id).caf"))

        var seen = Set<String>()
        return urls.filter { url in
            guard FileManager.default.fileExists(atPath: url.path), fileSize(url) > 0 else {
                return false
            }
            return seen.insert(url.path).inserted
        }
    }

    @discardableResult
    static func copyVoiceFile(from source: URL, notificationId: String) throws -> URL {
        try FileManager.default.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        let dest = voiceDirectory.appendingPathComponent("\(notificationId).\(ext)")

        if source.standardizedFileURL.path == dest.standardizedFileURL.path {
            rememberExistingFile(dest, notificationId: notificationId)
            return dest
        }

        for oldURL in [
            voiceDirectory.appendingPathComponent("\(notificationId).m4a"),
            voiceDirectory.appendingPathComponent("\(notificationId).caf")
        ] where oldURL.standardizedFileURL.path != source.standardizedFileURL.path {
            try? FileManager.default.removeItem(at: oldURL)
        }

        try FileManager.default.copyItem(at: source, to: dest)
        UserDefaults.standard.set(dest.path, forKey: savedPathKey(forNotificationId: notificationId))
        UserDefaults.standard.synchronize()
        return dest
    }

    @discardableResult
    static func copyNotificationAttachment(from source: URL, notificationId: String) throws -> URL {
        if let existing = existingFileURL(forNotificationId: notificationId) {
            return existing
        }

        let didAccess = source.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        do {
            return try copyVoiceFile(from: source, notificationId: notificationId)
        } catch {
            rememberExistingFile(source, notificationId: notificationId)
            throw error
        }
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values?.fileSize ?? 0)
    }
}
