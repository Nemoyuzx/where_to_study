import XCTest
import UIKit

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

    func testReviewDemoShowsLocalDataWithoutAccount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--review-demo"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.descendants(matching: .any)["banner.sample-mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["数据挖掘"].waitForExistence(timeout: 5))
        attachScreenshot(named: "store-iphone-planner")
        navigate(to: "教学日历", in: app)
        assertScreen("screen.calendar", in: app)
        attachScreenshot(named: "store-iphone-calendar-week")
        let actions = app.buttons["课表操作"]
        if actions.exists {
            actions.tap()
            app.buttons["导入系统日历"].tap()
        } else {
            app.buttons["导入系统日历"].tap()
        }
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH '示例模式已模拟同步 '")
        ).firstMatch.waitForExistence(timeout: 5))
        navigate(to: "设置", in: app)
        XCTAssertTrue(app.staticTexts["内置示例模式已开启，不会连接教务服务或读写真实用户数据。"]
            .waitForExistence(timeout: 5))
        attachScreenshot(named: "store-iphone-settings")
        let reminder = app.switches["每天 07:30 发送当日课程摘要"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        reminder.tap()
        XCTAssertTrue(app.staticTexts["示例模式已模拟开启每日课程摘要，未申请通知权限"]
            .waitForExistence(timeout: 5))
    }

    func testSettingsCanEnterAndExitBuiltInSampleMode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-live"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "设置", in: app)
        let enterButton = app.descendants(matching: .any)["action.enter-sample-mode"]
        XCTAssertTrue(enterButton.waitForExistence(timeout: 5))
        enterButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["banner.sample-mode"].waitForExistence(timeout: 5))

        let exitButton = app.descendants(matching: .any)["action.exit-sample-mode"]
        XCTAssertTrue(exitButton.waitForExistence(timeout: 5))
        exitButton.tap()
        XCTAssertFalse(app.descendants(matching: .any)["banner.sample-mode"].waitForExistence(timeout: 1))
    }

    func testSettingsKeyboardDismissesAfterEnteringCredentials() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-live"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "设置", in: app)
        let accountField = app.textFields["field.account"]
        XCTAssertTrue(accountField.waitForExistence(timeout: 5))
        accountField.tap()
        accountField.typeText("2026000000")

        let passwordField = app.secureTextFields["field.password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText("keyboard-test")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.18)).tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        passwordField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        let doneButton = app.buttons["action.dismiss-keyboard"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 2))
        doneButton.tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
    }

    func testPrivacyPolicyOpensInsideTheAppAndOffersGitHubLink() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-live"]
        app.launch()
        defer { app.terminate() }

        navigate(to: "设置", in: app)
        let openButton = app.descendants(matching: .any)["action.open-privacy-policy"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 5))
        for _ in 0..<4 where !openButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(openButton.isHittable)
        openButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.privacy-policy"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["action.open-privacy-github"]
            .waitForExistence(timeout: 5))

        let dismissButton = app.buttons["action.dismiss-privacy-policy"].firstMatch
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 5))
        dismissButton.tap()
        assertScreen("screen.settings", in: app)
    }

    func testPlannerSummaryLabelsRemainSeparatedOnIPhone() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "仅在 iPhone 模拟器验证")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }

        let firstLabel = app.descendants(matching: .any)["planner.summary.label.0"].firstMatch
        for _ in 0..<8 where !firstLabel.isHittable {
            app.swipeUp()
        }

        let labels = (0..<3).map {
            app.descendants(matching: .any)["planner.summary.label.\($0)"].firstMatch
        }
        for label in labels {
            XCTAssertTrue(label.waitForExistence(timeout: 5))
        }
        XCTAssertTrue(firstLabel.isHittable)
        attachScreenshot(named: "planner-summary")
        XCTAssertLessThan(labels[0].frame.maxX, labels[1].frame.minX)
        XCTAssertLessThan(labels[1].frame.maxX, labels[2].frame.minX)
    }

    func testIPadUsesPersistentSidebarAndExpandedLayoutsAcrossRotation() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "仅在 iPad 模拟器验证")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        assertRegularSidebar(in: app)
        assertScreen("screen.planner", in: app)
        attachScreenshot(named: "store-ipad-planner-landscape")
        navigateFromSidebar(to: "教学日历", in: app)
        assertScreen("screen.calendar", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["layout.calendar.expanded"]
            .waitForExistence(timeout: 5))
        attachScreenshot(named: "ipad-calendar-landscape")

        XCUIDevice.shared.orientation = .portrait
        assertRegularSidebar(in: app)
        navigateFromSidebar(to: "设置", in: app)
        assertScreen("screen.settings", in: app)
        attachScreenshot(named: "ipad-settings-portrait")
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
        let tabDestination = app.tabBars.buttons[title]
        if tabDestination.exists {
            XCTAssertTrue(tabDestination.waitForExistence(timeout: 5), "Missing navigation item: \(title)")
            tabDestination.tap()
        } else {
            navigateFromSidebar(to: title, in: app)
        }
    }

    private func navigateFromSidebar(to title: String, in app: XCUIApplication) {
        let destination = app.descendants(matching: .any)["navigation.\(sectionID(for: title))"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "Missing navigation item: \(title)")
        destination.tap()
    }

    private func assertRegularSidebar(in app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["layout.regular-sidebar"]
            .waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    private func sectionID(for title: String) -> String {
        switch title {
        case "空教室": return "planner"
        case "教学日历": return "calendar"
        case "设置": return "settings"
        default:
            XCTFail("Unknown section: \(title)")
            return ""
        }
    }

    private func assertScreen(_ identifier: String, in app: XCUIApplication) {
        let screen = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 5), "Missing screen: \(identifier)")
    }
}
