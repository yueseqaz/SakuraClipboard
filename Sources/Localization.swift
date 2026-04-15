import Foundation

enum AppLanguage: String {
    case zh = "zh"
    case en = "en"
}

struct I18N {
    private static let key = "app.language"

    static var current: AppLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: key),
               let lang = AppLanguage(rawValue: raw) {
                return lang
            }
            if Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true {
                return .zh
            }
            return .en
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    static func t(_ zh: String, _ en: String) -> String {
        current == .zh ? zh : en
    }
}

