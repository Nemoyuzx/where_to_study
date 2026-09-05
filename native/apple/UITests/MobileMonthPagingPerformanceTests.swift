import XCTest
import UIKit

@MainActor
final class MobileMonthPagingPerformanceTests: XCTestCase {
    func testUnobservedMonthPagingFrameSamples() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone frame sampling")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--review-demo", "--ui-test-month-performance", "--ui-test-month-autoplay"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = "zh-Hans"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["教学日历"].waitForExistence(timeout: 8))
        app.tabBars.buttons["教学日历"].tap()
        app.segmentedControls.buttons["月"].tap()
        // Let the app drive the same moveDate path without XCTest accessibility
        // snapshots/idle polling between animation frames.
        Thread.sleep(forTimeInterval: 9)
        let probe = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@", "Local month frame sample"
        )).firstMatch
        let value = try XCTUnwrap(probe.value as? String)
        let output = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
        let history = try XCTUnwrap(output["history"] as? [[String: Any]])
        XCTAssertEqual(history.count, 7)
        for record in history.dropFirst() {
            let data = try JSONSerialization.data(withJSONObject: record, options: .sortedKeys)
            print("MONTH_AUTO_FRAME_SAMPLE " + String(decoding: data, as: UTF8.self))
        }
    }

    func testMonthPagingFrameSamples() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone frame sampling")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--review-demo", "--ui-test-month-performance"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = "zh-Hans"
        app.launch()
        defer { app.terminate() }
        let calendar = app.tabBars.buttons["教学日历"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 8))
        calendar.tap()
        app.segmentedControls.buttons["月"].tap()
        let probe = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@", "Local month frame sample"
        )).firstMatch
        let probeExists = probe.waitForExistence(timeout: 8)
        if !probeExists {
            print(app.debugDescription)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "probe-diagnostic"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(probeExists)
        let ready = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value as? String)?.contains("maxGapMs") == true
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: probe)], timeout: 8), .completed)
        for direction in [-1, 1, -1, -1, 1, 1] {
            let oldValue = probe.value as? String
            if direction < 0 { app.swipeLeft() } else { app.swipeRight() }
            // Do not repeatedly query the app's accessibility hierarchy while
            // the sampler is still collecting its animation window.
            Thread.sleep(forTimeInterval: 0.65)
            let completed = NSPredicate { object, _ in
                guard let value = (object as? XCUIElement)?.value as? String else { return false }
                return value != oldValue && value.contains("maxGapMs")
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: completed, object: probe)], timeout: 8), .completed)
            let value = try XCTUnwrap(probe.value as? String)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
            XCTAssertGreaterThan(try XCTUnwrap(json["frames"] as? Int), 0)
            print("MONTH_FRAME_SAMPLE \(value)")
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        XCTAssertEqual(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "calendar.mobile.month-day-number."
        )).count, 42, "Only the active month's 42 dates may be exposed")
        screenshot.name = "month-pager-after-reversals"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
