import XCTest

@MainActor
final class PreClassReminderUITests: XCTestCase {
    func testChineseReminderRowsValidationAndIndependentSwitch() { exercise(language: "zh-Hans") }
    func testEnglishReminderRowsValidationAndIndependentSwitch() { exercise(language: "en") }

    private func exercise(language: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--review-demo"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = language
        app.launch()
        defer { app.terminate() }
        let settings = app.tabBars.buttons[language == "en" ? "Settings" : "设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let enabled = app.switches["settings.pre-class.enabled"]
        reveal(enabled, in: app)
        XCTAssertEqual(enabled.value as? String, "0")
        let first = app.textFields["settings.pre-class.offset.0"]
        XCTAssertEqual(first.value as? String, "10")
        enabled.tap()
        XCTAssertEqual(enabled.value as? String, "1")
        XCTAssertEqual(app.switches["settings.daily-course.enabled"].value as? String, "0")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Review demo must never request system permission")
        capture("pre-class-default-\(language)")

        let add = app.buttons["settings.pre-class.add"]
        let save = app.buttons["settings.pre-class.save"]
        reveal(add, in: app)
        add.tap()
        let second = app.textFields["settings.pre-class.offset.1"]
        reveal(second, in: app)
        second.tap()
        second.typeText("10")
        reveal(save, in: app)
        save.tap()
        let invalid = app.staticTexts["settings.pre-class.validation"]
        reveal(invalid, in: app)
        XCTAssertTrue(invalid.exists)
        capture("pre-class-duplicate-error-\(language)")

        reveal(second, in: app, downward: true)
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        second.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "20")
        XCTAssertEqual(second.value as? String, "20")
        for index in 2 ... 4 {
            reveal(add, in: app)
            add.tap()
            let field = app.textFields["settings.pre-class.offset.\(index)"]
            reveal(field, in: app)
            field.tap()
            field.typeText(String((index + 1) * 10))
            XCTAssertEqual(field.value as? String, String((index + 1) * 10))
        }
        reveal(save, in: app)
        save.tap()
        capture("pre-class-save-attempt-\(language)")
        let saved = app.staticTexts["settings.pre-class.saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertFalse(invalid.exists)
        XCTAssertFalse(add.isEnabled)
        XCTAssertEqual(app.textFields["settings.pre-class.offset.1"].value as? String, "20")
        let last = app.textFields["settings.pre-class.offset.4"]
        XCTAssertEqual(last.value as? String, "50")
        XCTAssertGreaterThan(last.frame.width, 60)
        XCTAssertLessThanOrEqual(last.frame.maxX, app.frame.maxX)
        capture("pre-class-five-rows-bottom-\(language)")
        reveal(enabled, in: app, downward: true)
        capture("pre-class-five-rows-top-\(language)")
        XCTAssertEqual(enabled.value as? String, "1")

        let remove = app.buttons["settings.pre-class.remove.4"]
        reveal(remove, in: app)
        remove.tap()
        XCTAssertFalse(app.textFields["settings.pre-class.offset.4"].exists)
        XCTAssertTrue(add.isEnabled)
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(saved.exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, downward: Bool = false) {
        for _ in 0 ..< 16 {
            if element.exists && element.isHittable { return }
            if downward { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
