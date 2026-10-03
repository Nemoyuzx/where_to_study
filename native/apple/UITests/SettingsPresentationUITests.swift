import XCTest
import UIKit

@MainActor
final class SettingsPresentationUITests: XCTestCase {
    func testUnsavedDraftsSurviveRotationAndReturningFromSettingsPresentations() throws {
        let app = try phoneApplicationCrossingColumnThreshold()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let reminder = app.textFields["settings.pre-class.offset.0"]
        reveal(reminder, app: app)
        replace(reminder, with: "37")
        let keyboardDone = app.buttons["settings.pre-class.dismiss-keyboard"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        keyboardDone.tap()
        let primary = app.textFields["theme.custom.primary"]
        reveal(primary, app: app)
        replace(primary, with: "#123456\n")
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            if orientation != .portrait { collapseLandscapeSidebar(app) }
            assertSettingsLayout(app, columns: orientation == .portrait ? 1 : 2)
            assertDrafts(app)
        }

        let favorites = app.buttons["settings.favorite-management"]
        reveal(favorites, app: app)
        favorites.tap()
        XCTAssertTrue(app.descendants(matching: .any)["favorites.page"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        app.buttons["favorites.dismiss"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["favorites.page"].waitForNonExistence(timeout: 5))
        assertDrafts(app)

        let support = app.buttons["action.open-app-support"]
        reveal(support, app: app)
        support.tap()
        XCTAssertTrue(app.staticTexts["screen.app-support"].waitForExistence(timeout: 5))
        app.buttons["action.dismiss-app-support"].tap()
        XCTAssertTrue(app.staticTexts["screen.app-support"].waitForNonExistence(timeout: 5))
        assertDrafts(app)
    }

    func testSupportAndFavoritesKeepTheirPresentationsAcrossRotation() throws {
        let app = try phoneApplicationCrossingColumnThreshold()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let support = app.buttons["action.open-app-support"]
        reveal(support, app: app)
        support.tap()
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.staticTexts["screen.app-support"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["action.dismiss-app-support"].isHittable)
        }
        app.buttons["action.dismiss-app-support"].tap()
        XCTAssertTrue(app.staticTexts["screen.app-support"].waitForNonExistence(timeout: 5))
        let favorites = app.buttons["settings.favorite-management"]
        reveal(favorites, app: app)
        favorites.tap()
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.descendants(matching: .any)["favorites.page"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["favorites.dismiss"].isHittable)
            XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        }
        app.buttons["favorites.dismiss"].tap()
    }

    private func phoneApplicationCrossingColumnThreshold() throws -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--review-demo", "--ui-test-settings-layout"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = "zh-Hans"
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5),
                      "Run this regression on the selected iPhone tab-layout device")
        app.tabBars.buttons["设置"].tap()
        assertSettingsLayout(app, columns: 1)
        XCUIDevice.shared.orientation = .landscapeLeft
        collapseLandscapeSidebar(app)
        assertSettingsLayout(app, columns: 2)
        XCUIDevice.shared.orientation = .portrait
        assertSettingsLayout(app, columns: 1)
        return app
    }

    private func collapseLandscapeSidebar(_ app: XCUIApplication) {
        let toggle = app.buttons["navigation.sidebar-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "The wide iPhone must enter the real root sidebar branch")
        if toggle.label == "收起侧栏" { toggle.tap() }
        XCTAssertEqual(toggle.label, "展开侧栏")
    }

    private func assertSettingsLayout(_ app: XCUIApplication, columns: Int,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let metrics = app.descendants(matching: .any)["settings.layout-metrics"].firstMatch
        XCTAssertTrue(metrics.waitForExistence(timeout: 5), file: file, line: line)
        let ready = NSPredicate { element, _ in
            guard let value = (element as? XCUIElement)?.value as? String else { return false }
            return Int(value.split(separator: "|").first ?? "") == columns
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: metrics)], timeout: 5),
                       .completed, "The actual Settings GeometryReader must cross the column threshold", file: file, line: line)
        guard let value = metrics.value as? String else {
            XCTFail("Missing settings layout metrics", file: file, line: line)
            return
        }
        let values = value.split(separator: "|")
        guard values.count == 2, let actualColumns = Int(values[0]), let width = Double(values[1]) else {
            XCTFail("Invalid settings layout metrics: \(value)", file: file, line: line)
            return
        }
        XCTAssertEqual(actualColumns, columns, file: file, line: line)
        if columns == 1 {
            XCTAssertLessThan(width, 760, file: file, line: line)
        } else {
            XCTAssertGreaterThanOrEqual(width, 760, file: file, line: line)
        }
    }

    private func assertDrafts(_ app: XCUIApplication) {
        let reminder = app.textFields["settings.pre-class.offset.0"]
        reveal(reminder, app: app)
        XCTAssertEqual(reminder.value as? String, "37")
        let primary = app.textFields["theme.custom.primary"]
        reveal(primary, app: app)
        XCTAssertEqual(primary.value as? String, "#123456")
    }

    private func replace(_ field: XCUIElement, with value: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let count = (field.value as? String ?? "").count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + value)
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            let matchingScroll = element.exists
                ? app.scrollViews.containing(.any, identifier: element.identifier).firstMatch
                : app.scrollViews.firstMatch
            let scroll = matchingScroll.exists ? matchingScroll : app.scrollViews.firstMatch
            guard scroll.exists else { break }
            let appFrame = app.frame
            let viewport = scroll.frame.intersection(appFrame)
            var top = viewport.minY + 12
            var bottom = viewport.maxY - 12
            for bar in app.navigationBars.allElementsBoundByIndex {
                if bar.frame.intersects(viewport) { top = max(top, bar.frame.maxY + 8) }
            }
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists && keyboard.frame.intersects(viewport) {
                bottom = min(bottom, keyboard.frame.minY - 12)
            }
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists && tabBar.frame.intersects(viewport) {
                bottom = min(bottom, tabBar.frame.minY - 12)
            }
            guard !viewport.isNull, viewport.width > 40, bottom - top > 40 else { break }
            let center = (top + bottom) / 2
            let target = element.exists ? element.frame : .zero
            let upward = target.isEmpty || target.midY > center
            let requestedTravel = target.isEmpty ? 160 : max(16, abs(target.midY - center))
            let travel = min(180, (bottom - top) * 0.55, requestedTravel)
            let startY = center + (upward ? travel / 2 : -travel / 2)
            let endY = center + (upward ? -travel / 2 : travel / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX - appFrame.minX, dy: startY - appFrame.minY))
            let end = origin.withOffset(CGVector(dx: viewport.midX - appFrame.minX, dy: endY - appFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        guard !element.exists || !element.isHittable else { return }
        let scroll = app.scrollViews.firstMatch
        let keyboard = app.keyboards.firstMatch
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "settings-draft-scroll-failure"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SETTINGS_SCROLL_FAILURE target=\(element.exists ? element.frame : .zero) app=\(app.frame) " +
              "scroll=\(scroll.exists ? scroll.frame : .zero) keyboard=\(keyboard.exists ? keyboard.frame : .zero) " +
              "nav=\(app.navigationBars.allElementsBoundByIndex.map(\.frame)) tabs=\(app.tabBars.allElementsBoundByIndex.map(\.frame))")
        XCTAssertTrue(element.exists && element.isHittable)
    }
}
