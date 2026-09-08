import XCTest
import UIKit

/// Opt-in capture for an isolated simulator whose app container has already
/// received the developer's authorized, current-day JSON caches. This test
/// never imports credentials, enters settings, or requests an academic refresh.
@MainActor
final class IOSAppStoreLiveCaptureTests: XCTestCase {
    func testCaptureLiveIPadMainPages() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["WTS_CAPTURE_LIVE_IPAD"] == "1"
                || environment["TEST_RUNNER_WTS_CAPTURE_LIVE_IPAD"] == "1",
            "Set TEST_RUNNER_WTS_CAPTURE_LIVE_IPAD=1 only for an authorized, isolated simulator with real caches."
        )
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires a 13-inch iPad simulator.")
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let acceptPrivacy = app.buttons["privacy-consent.accept"]
        if acceptPrivacy.waitForExistence(timeout: 5) {
            acceptPrivacy.tap()
        }
        assertScreen("screen.planner", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["layout.regular-sidebar"]
            .waitForExistence(timeout: 5))
        assertLiveMainPage(in: app)

        // This label appears only after a real current-day classroom cache has
        // loaded. Do not press the academic refresh button if it is missing.
        let liveSource = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "数据源：移动教务实时接口")
        ).firstMatch
        XCTAssertTrue(liveSource.waitForExistence(timeout: 20), "A current-day classroom cache must be preloaded.")
        let useSchedule = app.switches["使用个人课表排除已有课程"]
        XCTAssertTrue(useSchedule.waitForExistence(timeout: 5))
        XCTAssertEqual(useSchedule.value as? String, "1", "Keep real personal courses in the slot filter.")

        let clearSlots = app.buttons["清空"].firstMatch
        reveal(clearSlots, in: app)
        clearSlots.tap()
        let freeSlot = try availableSlot(in: app)
        reveal(freeSlot, in: app)
        freeSlot.tap()

        let building = app.buttons["教3"].firstMatch
        XCTAssertTrue(building.waitForExistence(timeout: 5), "The real cache must include 教3.")
        reveal(building, in: app)
        building.tap()
        XCTAssertTrue(app.descendants(matching: .any)["planner.results.two-columns"]
            .waitForExistence(timeout: 10), "The chosen free period and building must show real classroom results.")
        scrollPlannerToTop(in: app)
        attachMainPage("01-planner", in: app)

        navigate("calendar", screen: "screen.calendar", in: app)
        let week = app.segmentedControls.buttons["周"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        XCTAssertTrue(week.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["calendar.timeline.horizontal"]
            .waitForExistence(timeout: 10))
        attachMainPage("02-calendar-week", in: app)

        let month = app.segmentedControls.buttons["月"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        month.tap()
        XCTAssertTrue(month.isSelected)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "calendar.regular.month-day-cell.")
        ).firstMatch.waitForExistence(timeout: 10))
        attachMainPage("03-calendar-month", in: app)

        navigate("queries", screen: "screen.information-queries", in: app)
        let shuttle = app.segmentedControls.buttons["班车查询"].firstMatch
        XCTAssertTrue(shuttle.waitForExistence(timeout: 5))
        if !shuttle.isSelected { shuttle.tap() }
        let shuttleSnapshot = app.descendants(matching: .any)["queries.shuttle.snapshot"].firstMatch
        XCTAssertTrue(shuttleSnapshot.waitForExistence(timeout: 45), "Wait for the real public shuttle response.")
        XCTAssertNotEqual(shuttleSnapshot.value as? String, "示例数据")
        XCTAssertTrue(app.descendants(matching: .any)["queries.shuttle.status"]
            .waitForExistence(timeout: 5))
        waitUntilEnabled(app.buttons["刷新班车信息"].firstMatch)
        XCTAssertFalse(app.staticTexts["班车信息暂不可用"].exists)
        attachMainPage("04-shuttle", in: app)

        let events = app.segmentedControls.buttons["重要事件"].firstMatch
        XCTAssertTrue(events.waitForExistence(timeout: 5))
        events.tap()
        let firstEvent = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "queries.event.")
        ).firstMatch
        XCTAssertTrue(firstEvent.waitForExistence(timeout: 45), "Wait for real public event rows.")
        waitUntilEnabled(app.buttons["刷新"].firstMatch)
        XCTAssertFalse(app.staticTexts["重要事件暂不可用"].exists)
        attachMainPage("05-important-events", in: app)
    }

    private func availableSlot(in app: XCUIApplication) throws -> XCUIElement {
        let slots = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "(?s)^第 [0-9]+ 节.*$")
        ).allElementsBoundByIndex.filter { $0.isEnabled }
        let preferred = slots.first { $0.label.hasPrefix("第 11 节") }
        return try XCTUnwrap(preferred ?? slots.first, "No available period is exposed by the real personal schedule filter.")
    }

    private func navigate(_ section: String, screen: String, in app: XCUIApplication) {
        let destination = app.descendants(matching: .any)["navigation.\(section)"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        assertScreen(screen, in: app)
    }

    private func assertScreen(_ identifier: String, in app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch
            .waitForExistence(timeout: 10), "The requested main page must be visible.")
    }

    private func assertLiveMainPage(in app: XCUIApplication) {
        XCTAssertFalse(app.descendants(matching: .any)["banner.sample-mode"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["screen.settings"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["field.account"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["field.password"].exists)
        XCTAssertGreaterThan(app.frame.width, app.frame.height, "Capture the iPad in landscape.")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        for _ in 0 ..< 6 {
            if element.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(element.isEnabled)
        XCTAssertTrue(element.isHittable)
    }

    private func scrollPlannerToTop(in app: XCUIApplication) {
        let heading = app.staticTexts["联动查询"].firstMatch
        let scroll = app.scrollViews.firstMatch
        for _ in 0 ..< 6 {
            if heading.isHittable { break }
            scroll.swipeDown()
        }
        XCTAssertTrue(heading.isHittable)
    }

    private func waitUntilEnabled(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)
        ], timeout: 45), .completed, "The public data request must finish before capture.")
    }

    private func attachMainPage(_ name: String, in app: XCUIApplication) {
        assertLiveMainPage(in: app)
        XCTAssertEqual(XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: app.progressIndicators.firstMatch
            )
        ], timeout: 45), .completed, "Wait for visible loading indicators to finish.")
        let screenshot = XCUIScreen.main.screenshot()
        XCTAssertEqual(screenshot.image.cgImage?.width, 2752)
        XCTAssertEqual(screenshot.image.cgImage?.height, 2064)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
