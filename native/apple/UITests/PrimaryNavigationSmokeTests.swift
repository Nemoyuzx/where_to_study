import XCTest

@MainActor
final class PrimaryNavigationSmokeTests: XCTestCase {
    func testPrimaryPagesAreNavigable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }

        assertScreen("screen.planner", in: app)
        navigate(to: "教学日历", in: app)
        assertScreen("screen.calendar", in: app)
        assertMobileCalendarControls(in: app)
        navigate(to: "设置", in: app)
        assertScreen("screen.settings", in: app)
        navigate(to: "空教室", in: app)
        assertScreen("screen.planner", in: app)
    }

    private func assertMobileCalendarControls(in app: XCUIApplication) {
        let weekMode = app.segmentedControls.buttons["周"]
        XCTAssertTrue(weekMode.waitForExistence(timeout: 5))
        attachScreenshot(named: "calendar-week")

        let dayMode = app.segmentedControls.buttons["日"]
        XCTAssertTrue(dayMode.waitForExistence(timeout: 5))
        dayMode.tap()
        attachScreenshot(named: "calendar-day")

        let monthMode = app.segmentedControls.buttons["月"]
        XCTAssertTrue(monthMode.exists)
        monthMode.tap()
        attachScreenshot(named: "calendar-month")

        let yearMode = app.segmentedControls.buttons["年"]
        XCTAssertTrue(yearMode.exists)
        yearMode.tap()
        attachScreenshot(named: "calendar-year")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func navigate(to title: String, in app: XCUIApplication) {
        let destination = app.tabBars.buttons[title]
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "Missing navigation item: \(title)")
        destination.tap()
    }

    private func assertScreen(_ identifier: String, in app: XCUIApplication) {
        let screen = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 5), "Missing screen: \(identifier)")
    }
}
