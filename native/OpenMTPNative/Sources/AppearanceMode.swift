import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var localizationKey: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    static func resolve(_ rawValue: String) -> AppearanceMode {
        AppearanceMode(rawValue: rawValue) ?? .system
    }

    static func apply(_ rawValue: String, to application: NSApplication = .shared) {
        let appearance: NSAppearance?
        switch resolve(rawValue) {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }

        application.appearance = appearance
        for window in application.windows {
            window.appearance = appearance
        }
    }
}
