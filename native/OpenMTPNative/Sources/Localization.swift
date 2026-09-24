import Foundation

enum MTPShuttleText {
    static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
    }
}
