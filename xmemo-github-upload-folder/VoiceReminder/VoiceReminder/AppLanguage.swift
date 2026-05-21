import Foundation

enum AppLanguage {
    static var isLithuanian: Bool {
        let language = Locale.preferredLanguages.first?.lowercased() ?? ""
        return language.hasPrefix("lt")
    }

    static func text(lt: String, en: String) -> String {
        isLithuanian ? lt : en
    }
}
