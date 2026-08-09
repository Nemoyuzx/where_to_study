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
        navigate(to: "设置", in: app)
        assertScreen("screen.settings", in: app)
        navigate(to: "空教室", in: app)
        assertScreen("screen.planner", in: app)
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
