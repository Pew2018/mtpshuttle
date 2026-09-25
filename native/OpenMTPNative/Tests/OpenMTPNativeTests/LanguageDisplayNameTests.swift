import XCTest
@testable import SwiftMTP

final class LanguageDisplayNameTests: XCTestCase {
    func testLanguageNamesUseTheirOwnNativeNames() {
        XCTAssertEqual(MTPShuttleLanguage.english.displayName, "English")
        XCTAssertEqual(MTPShuttleLanguage.simplifiedChinese.displayName, "简体中文")
        XCTAssertEqual(MTPShuttleLanguage.traditionalChinese.displayName, "繁體中文")
    }
}
