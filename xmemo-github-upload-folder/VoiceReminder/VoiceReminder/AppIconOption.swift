import Foundation
import UIKit

enum AppIconOption: String, CaseIterable, Identifiable {
    case red
    case ral8025
    case silver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red:
            return AppLanguage.text(lt: "Raudona", en: "Red")
        case .ral8025:
            return AppLanguage.text(lt: "Ruda", en: "Brown")
        case .silver:
            return AppLanguage.text(lt: "Sidabrinė", en: "Silver")
        }
    }

    var iconName: String? {
        switch self {
        case .red:
            return nil
        case .ral8025:
            return "AppIconRAL8025"
        case .silver:
            return "AppIconSilver"
        }
    }

    static func current() -> AppIconOption {
        switch UIApplication.shared.alternateIconName {
        case "AppIconRAL8025":
            return .ral8025
        case "AppIconSilver":
            return .silver
        default:
            return .red
        }
    }
}

enum PendingAppIconChange {
    private static var option: AppIconOption?

    static func remember(_ nextOption: AppIconOption) {
        option = nextOption
    }

    static func take() -> AppIconOption? {
        defer { option = nil }
        return option
    }
}

@MainActor
final class AppIconChanger: ObservableObject {
    @Published private(set) var current = AppIconOption.current()
    @Published private(set) var message: String?

    func select(_ option: AppIconOption) {
        PendingAppIconChange.remember(option)
    }

    func applyPendingChange() {
        guard let option = PendingAppIconChange.take() else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            message = AppLanguage.text(
                lt: "Šis iPhone neleidžia keisti ikonos.",
                en: "This iPhone does not allow changing the app icon."
            )
            return
        }

        UIApplication.shared.setAlternateIconName(option.iconName) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error == nil {
                    self.current = option
                    self.message = nil
                } else {
                    self.message = AppLanguage.text(
                        lt: "Nepavyko pakeisti ikonos.",
                        en: "Could not change the app icon."
                    )
                }
            }
        }
    }
}
