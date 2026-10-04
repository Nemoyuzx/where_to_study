import XCTest
import UIKit

@MainActor
final class InterfaceLanguageUITests: XCTestCase {
    func testLanguageSwitchKeepsRootSafeAreaAndViewportGeometryDuringIntermediateFrames() {
        continueAfterFailure = false
        let app = application()
        app.launchArguments.append("--ui-test-language-geometry")
        app.launch()
        defer { app.terminate() }
        let tabs = app.tabBars.firstMatch
        let compact = tabs.waitForExistence(timeout: 2)
        if compact {
            app.tabBars.buttons["设置"].tap()
        } else {
            let settings = app.descendants(matching: .any)["navigation.settings"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
        }
        let picker = app.segmentedControls["settings.language"].firstMatch
        reveal(picker, app: app)
        let probe = app.descendants(matching: .any)["debug.language-layout.frames"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        picker.buttons["English"].tap()
        assertFrameSamples(probe, language: "en", compact: compact, app: app)
        XCTAssertTrue(picker.isHittable, "The language card must remain reachable without another reveal")
        picker.buttons["Simplified Chinese"].tap()
        assertFrameSamples(probe, language: "zh-Hans", compact: compact, app: app)
        XCTAssertTrue(picker.isHittable)
    }

    private func assertFrameSamples(_ probe: XCUIElement, language: String, compact: Bool, app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "value CONTAINS %@ AND value CONTAINS %@", "\"complete\":true", "\"language\":\"\(language)\""), object: probe)
        let wait = XCTWaiter.wait(for: [expectation], timeout: 8)
        if wait != .completed { attachGeometryFailure(app, value: probe.value) }
        XCTAssertEqual(wait, .completed)
        guard let text = probe.value as? String, let data = text.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Missing actual language layout samples"); return
        }
        XCTAssertEqual(values["hasTabBar"] as? Bool, compact, "Phone tabs and iPad sidebar must be distinguished")
        XCTAssertGreaterThan((values["samples"] as? NSNumber)?.intValue ?? 0, 0)
        for key in ["rootMaxDelta", "controllerMaxDelta", "safeAreaMaxDelta", "viewportMaxDelta"] + (compact ? ["barMaxDelta"] : []) {
            guard let delta = values[key] as? NSNumber else { XCTFail("Missing geometry field: \(key)"); continue }
            if delta.doubleValue > 1 { attachGeometryFailure(app, value: text) }
            XCTAssertLessThanOrEqual(delta.doubleValue, 1, "Intermediate layout changed: \(key)")
        }
    }

    private func attachGeometryFailure(_ app: XCUIApplication, value: Any?) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "language-intermediate-geometry"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("LANGUAGE_INTERMEDIATE_GEOMETRY \(String(describing: value)) appFrame=\(app.frame)")
    }

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
        app.tabBars.buttons["课程"].tap()
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
        XCTAssertTrue(app.tabBars.buttons["Courses"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Courses"].tap()
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
