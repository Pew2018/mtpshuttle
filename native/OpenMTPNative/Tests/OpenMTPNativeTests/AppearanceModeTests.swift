import XCTest
@testable import SwiftMTP

final class AppearanceModeTests: XCTestCase {
    func testAppearanceModesMapToExpectedColorSchemes() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
    }

    func testUnknownStoredAppearanceFallsBackToSystem() {
        XCTAssertEqual(AppearanceMode.resolve("unknown"), .system)
        XCTAssertEqual(AppearanceMode.resolve("dark"), .dark)
    }
}
