import XCTest
import UIKit

@MainActor
final class ColorThemeUITests: XCTestCase {
    func testPresetsCustomValidationRestoreAndCalendarState() {
        continueAfterFailure = false
        let app = application(language: "zh-Hans")
        app.launch()
        defer { app.terminate() }
        navigate("calendar", title: "教学日历", app: app)
        let year = app.segmentedControls.buttons["年"]
        XCTAssertTrue(year.waitForExistence(timeout: 10))
        year.tap()
        XCTAssertTrue(year.isSelected)
        navigate("settings", title: "设置", app: app)

        for preset in ["ocean", "violet", "amber", "rose", "default"] {
            let button = app.buttons["theme.preset.\(preset)"]
            reveal(button, app: app)
            button.tap()
            XCTAssertTrue(button.isSelected)
        }
        attach(app, name: "theme-presets-zh")

        let primary = app.textFields["theme.custom.primary"]
        replace(primary, with: "#GGGGGG", app: app)
        let apply = app.buttons["theme.apply-custom"]
        reveal(apply, app: app)
        apply.tap()
        XCTAssertTrue(app.staticTexts["theme.validation-error"].exists)
        replace(primary, with: "ffffff", app: app)
        replace(app.textFields["theme.custom.accent"], with: "000000", app: app)
        replace(app.textFields["theme.custom.selected-date"], with: "ff00ff", app: app)
        reveal(apply, app: app)
        apply.tap()
        XCTAssertFalse(app.staticTexts["theme.validation-error"].exists)
        XCTAssertEqual(primary.value as? String, "#FFFFFF")
        attach(app, name: "theme-custom-extremes-zh")
        let custom = app.buttons["theme.preset.custom"]
        reveal(custom, app: app, towardTop: true)
        XCTAssertTrue(custom.isSelected)
        let restore = app.buttons["theme.restore-default"]
        reveal(restore, app: app)
        restore.tap()
        let defaultPreset = app.buttons["theme.preset.default"]
        reveal(defaultPreset, app: app, towardTop: true)
        XCTAssertTrue(defaultPreset.isSelected)
        reveal(custom, app: app)
        custom.tap()
        XCTAssertEqual(primary.value as? String, "#FFFFFF", "Restore Default preserves custom seeds")
        navigate("calendar", title: "教学日历", app: app)
        XCTAssertTrue(year.isSelected, "Theme edits must preserve the selected calendar mode")
        attach(app, name: "theme-custom-calendar-year")
    }

    func testEnglishThemeSettingsAtAccessibilityTextSize() {
        continueAfterFailure = false
        let app = application(language: "en")
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        defer { app.terminate() }
        navigate("settings", title: "Settings", app: app)
        let preset = app.buttons["theme.preset.ocean"]
        reveal(preset, app: app)
        XCTAssertTrue(app.staticTexts["Color Theme"].exists)
        preset.tap()
        XCTAssertTrue(preset.isSelected)
        XCTAssertLessThanOrEqual(preset.frame.maxX, app.frame.maxX)
        attach(app, name: "theme-presets-en-large-text")
        let apply = app.buttons["theme.apply-custom"]
        reveal(apply, app: app)
        XCTAssertEqual(apply.label, "Apply Custom Colors")
        XCTAssertLessThanOrEqual(apply.frame.maxX, app.frame.maxX)
        let restore = app.buttons["theme.restore-default"]
        reveal(restore, app: app)
        XCTAssertEqual(restore.label, "Restore Default")
        attach(app, name: "theme-preview-en-large-text")
    }

    private func application(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = language
        return app
    }

    private func navigate(_ id: String, title: String, app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        if tab.exists { tab.tap() }
        else {
            let sidebar = app.buttons["navigation.\(id)"]
            XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
            sidebar.tap()
        }
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<18 {
            if element.exists && element.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            if towardTop || (element.exists && element.frame.maxY < app.frame.midY) { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reach \(element.identifier)")
    }

    private func replace(_ element: XCUIElement, with text: String, app: XCUIApplication) {
        reveal(element, app: app)
        element.tap()
        let existing = element.value as? String ?? ""
        element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + text + "\n")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
