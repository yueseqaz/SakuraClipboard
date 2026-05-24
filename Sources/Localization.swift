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

    static func relativeTime(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return current == .zh ? "刚刚" : "Now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)min"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd"
            return formatter.string(from: date)
        }
    }
}

