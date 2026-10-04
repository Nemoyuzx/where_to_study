import XCTest

@MainActor
enum LanguageMenuTestSupport {
    static func select(_ rawValue: String, nativeName: String, in app: XCUIApplication) {
        let picker = app.buttons["settings.language"].firstMatch
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        let identified = app.descendants(matching: .any)["settings.language.option.\(rawValue)"].firstMatch
        let option = identified.exists ? identified : app.descendants(matching: .any)[nativeName].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "The native language menu must expose \(rawValue)")
        XCTAssertTrue(option.isHittable)
        option.tap()
    }
}
