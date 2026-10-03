import XCTest
import UIKit

@MainActor
final class InterfaceLanguageUITests: XCTestCase {
    func testLanguageRoundTripKeepsCurrentSettingsPositionAndUncommittedFields() {
        continueAfterFailure = false
        let app = application()
        app.launch()
        defer { app.terminate() }
        app.tabBars.buttons["设置"].tap()
        let reminder = app.textFields["settings.pre-class.offset.0"]
        reveal(reminder, app: app)
        replace(reminder, with: "37")
        app.buttons["settings.pre-class.dismiss-keyboard"].tap()
        let primary = app.textFields["theme.custom.primary"]
        reveal(primary, app: app)
        replace(primary, with: "#123456\n")
        let picker = app.segmentedControls["settings.language"].firstMatch
        reveal(picker, app: app)
        picker.buttons["English"].tap()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        let english = app.segmentedControls["settings.language"].firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        if !english.isHittable {
            let failure = XCTAttachment(screenshot: app.screenshot())
            failure.name = "language-card-anchor-failure"
            failure.lifetime = .keepAlways
            add(failure)
            print("LANGUAGE_CARD_ANCHOR_FAILURE picker=\(english.frame) app=\(app.frame) scrolls=\(app.scrollViews.allElementsBoundByIndex.map { $0.frame })")
        }
        XCTAssertTrue(english.isHittable, "Language conversion must keep the current settings location, without another reveal")
        english.buttons["Simplified Chinese"].tap()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["设置"].isSelected)
        XCTAssertTrue(app.segmentedControls["settings.language"].firstMatch.isHittable)
        reveal(reminder, app: app)
        XCTAssertEqual(reminder.value as? String, "37")
        reveal(primary, app: app)
        XCTAssertEqual(primary.value as? String, "#123456")
    }

    func testLanguageRoundTripKeepsQueryModeFiltersAndCalendarState() {
        continueAfterFailure = false
        let app = application()
        app.launch()
        defer { app.terminate() }
        app.tabBars.buttons["教学日历"].tap()
        let month = app.segmentedControls.buttons["月"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        month.tap()
        let monthState = app.descendants(matching: .any)["calendar.mobile.month-state"].firstMatch
        XCTAssertTrue(monthState.waitForExistence(timeout: 5))
        let previousMonthState = monthState.value as? String
        app.tabBars.buttons["查询"].tap()
        let assignments = app.segmentedControls.buttons["课程作业 DDL"].firstMatch
        XCTAssertTrue(assignments.waitForExistence(timeout: 5))
        assignments.tap()
        let search = app.textFields["assignments.search"]
        reveal(search, app: app)
        search.tap()
        search.typeText("示例\n")
        app.tabBars.buttons["设置"].tap()
        let picker = app.segmentedControls["settings.language"].firstMatch
        reveal(picker, app: app)
        picker.buttons["English"].tap()
        XCTAssertTrue(app.tabBars.buttons["Search"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Assignment Deadlines"].isSelected)
        XCTAssertEqual(app.textFields["assignments.search"].value as? String, "示例", "Raw entered/API content must not be translated or reset")
        app.descendants(matching: .any)["navigation.calendar"].firstMatch.tap()
        XCTAssertTrue(app.segmentedControls.buttons["Month"].firstMatch.isSelected)
        let translatedMonthState = previousMonthState == "已展开" ? "Expanded"
            : previousMonthState == "已收起" ? "Collapsed" : "Details Expanded"
        XCTAssertEqual(monthState.value as? String, translatedMonthState)
    }

    private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--review-demo", "--ui-test-language-anchor"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = "zh-Hans"
        return app
    }

    private func replace(_ field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count) + text)
    }

    private func reveal(_ target: XCUIElement, app: XCUIApplication) {
        for _ in 0..<30 {
            if target.exists && target.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            guard scroll.exists else { break }
            let viewport = scroll.frame.intersection(app.frame)
            var top = viewport.minY + 12
            var bottom = viewport.maxY - 12
            for bar in app.navigationBars.allElementsBoundByIndex where bar.frame.intersects(viewport) {
                top = max(top, bar.frame.maxY + 8)
            }
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists { bottom = min(bottom, keyboard.frame.minY - 12) }
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists { bottom = min(bottom, tabBar.frame.minY - 12) }
            guard bottom - top > 40 else { break }
            let center = (top + bottom) / 2
            let bounds = target.exists ? target.frame : .zero
            let upward = bounds.isEmpty || bounds.midY > center
            let travel = min(180, (bottom - top) * 0.55, bounds.isEmpty ? 160 : max(16, abs(bounds.midY - center)))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX, dy: center + (upward ? travel / 2 : -travel / 2)))
            let end = origin.withOffset(CGVector(dx: viewport.midX, dy: center + (upward ? -travel / 2 : travel / 2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "language-state-reveal-failure"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(target.exists && target.isHittable)
    }
}
