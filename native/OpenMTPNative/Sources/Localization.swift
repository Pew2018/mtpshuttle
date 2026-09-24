import Foundation

enum MTPShuttleLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "Automatic (System)"
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        }
    }

    static func locale(for rawValue: String) -> Locale {
        let language = MTPShuttleLanguage(rawValue: rawValue) ?? .system
        switch language {
        case .system:
            return Locale(identifier: detectedLanguageIdentifier())
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        case .traditionalChinese:
            return Locale(identifier: "zh-Hant")
        }
    }

    static func resourceIdentifier(for rawValue: String) -> String {
        let language = MTPShuttleLanguage(rawValue: rawValue) ?? .system
        switch language {
        case .system:
            return detectedLanguageIdentifier()
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        }
    }

    private static func detectedLanguageIdentifier() -> String {
        let identifier = Locale.preferredLanguages.first?.lowercased() ?? Locale.current.identifier.lowercased()
        if identifier.contains("hant") || identifier.contains("tw") || identifier.contains("hk") || identifier.contains("mo") {
            return "zh-Hant"
        }
        if identifier.hasPrefix("zh") {
            return "zh-Hans"
        }
        return "en"
    }
}

enum MTPShuttleText {
    static func localized(_ key: String) -> String {
        let selected = UserDefaults.standard.string(forKey: "appLanguage")
            ?? MTPShuttleLanguage.system.rawValue
        let resource = MTPShuttleLanguage.resourceIdentifier(for: selected)
        let bundle = Bundle(path: Bundle.main.path(forResource: resource, ofType: "lproj") ?? "")
        return bundle?.localizedString(forKey: key, value: key, table: "Localizable")
            ?? Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
    }
}
