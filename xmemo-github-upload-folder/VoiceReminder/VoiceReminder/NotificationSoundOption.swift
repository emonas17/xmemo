import Foundation

enum NotificationSoundOption: String, CaseIterable, Identifiable {
    case signal = "xmemo_signal.wav"
    case bell = "xmemo_bell.wav"
    case chime = "xmemo_chime.wav"
    case system = "system"

    static let defaultValue: NotificationSoundOption = .signal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signal:
            return AppLanguage.text(lt: "Signalas", en: "Signal")
        case .bell:
            return AppLanguage.text(lt: "Varpelis", en: "Bell")
        case .chime:
            return AppLanguage.text(lt: "Melodija", en: "Chime")
        case .system:
            return "iPhone"
        }
    }

    var notificationSoundName: String? {
        switch self {
        case .system:
            return nil
        case .signal, .bell, .chime:
            return rawValue
        }
    }

    static func option(for rawValue: String) -> NotificationSoundOption {
        NotificationSoundOption(rawValue: rawValue) ?? defaultValue
    }
}
