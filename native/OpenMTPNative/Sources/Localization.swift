import Foundation

enum MTPShuttleLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .system: return "Automatic (System)"
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        }
    }

    var displayName: String {
        MTPShuttleText.localized(localizationKey)
    }

    static func locale(for rawValue: String) -> Locale {
        Locale(identifier: resolvedIdentifier(for: rawValue))
    }

    static func resourceIdentifier(for rawValue: String) -> String {
        resolvedIdentifier(for: rawValue)
    }

    static func resolvedIdentifier(for rawValue: String) -> String {
        switch MTPShuttleLanguage(rawValue: rawValue) ?? .system {
        case .system:
            return detectedSystemLanguage()
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        }
    }

    private static func detectedSystemLanguage() -> String {
        for identifier in Locale.preferredLanguages {
            let locale = Locale(identifier: identifier)
            guard let languageCode = locale.languageCode?.lowercased() else { continue }

            if languageCode == "en" {
                return "en"
            }

            if languageCode == "zh" {
                let script = locale.language.script?.identifier.lowercased()
                let region = locale.region?.identifier.uppercased()
                if script == "hant" || ["TW", "HK", "MO"].contains(region) {
                    return "zh-Hant"
                }
                return "zh-Hans"
            }
        }

        // The app currently ships English, Simplified Chinese, and Traditional Chinese.
        // Any other macOS language intentionally falls back to English.
        return "en"
    }
}

enum MTPShuttleText {
    static var currentLanguage: MTPShuttleLanguage {
        MTPShuttleLanguage(rawValue: UserDefaults.standard.string(forKey: MTPShuttleLanguage.storageKey) ?? "")
            ?? .system
    }

    static func localized(_ key: String) -> String {
        localized(key, language: currentLanguage)
    }

    static func localized(_ key: String, language: MTPShuttleLanguage) -> String {
        let resource = MTPShuttleLanguage.resourceIdentifier(for: language.rawValue)
        guard let path = Bundle.main.path(forResource: resource, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), arguments: arguments)
    }
}
