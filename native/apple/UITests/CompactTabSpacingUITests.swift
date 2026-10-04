import XCTest
import UIKit

@MainActor
final class CompactTabSpacingUITests: XCTestCase {
    private let chineseTitles = ["空教室", "教学日历", "课程", "查询", "设置"]
    private let englishTitles = ["Empty Rooms", "Academic Calendar", "Courses", "Search", "Settings"]

    func testFiveNativeTabItemsKeepEqualSpacingAcrossLanguageRoundTrip() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Native five-tab geometry is an iPhone layout")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = application(language: "zh-Hans")
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        waitForPortrait(app)
        let initialFrames = assertEqualItemGeometry(titles: chineseTitles, app: app, phase: "initial-chinese")
        assertDestinationsAreClickable(titles: chineseTitles, app: app)
        let picker = app.buttons["settings.language"].firstMatch
        reveal(picker, app: app)
        LanguageMenuTestSupport.select("en", nativeName: "English", in: app)
        assertEqualItemGeometry(titles: englishTitles, app: app, phase: "english")
        assertDestinationsAreClickable(titles: englishTitles, app: app)
        XCTAssertTrue(picker.isHittable, "The existing language-card position must survive native title updates")
        LanguageMenuTestSupport.select("zh-Hans", nativeName: "简体中文", in: app)
        let restoredFrames = assertEqualItemGeometry(titles: chineseTitles, app: app, phase: "restored-chinese")
        XCTAssertEqual(restoredFrames.count, initialFrames.count)
        for (initial, restored) in zip(initialFrames, restoredFrames) {
            XCTAssertEqual(restored.minX, initial.minX, accuracy: 1)
            XCTAssertEqual(restored.minY, initial.minY, accuracy: 1)
            XCTAssertEqual(restored.width, initial.width, accuracy: 1)
            XCTAssertEqual(restored.height, initial.height, accuracy: 1)
        }
    }

    func testEnglishNativeTabSpacingSurvivesRotationBackToPortrait() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Native five-tab geometry is an iPhone layout")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = application(language: "en")
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        waitForPortrait(app)
        assertEqualItemGeometry(titles: englishTitles, app: app, phase: "portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        if app.tabBars.firstMatch.exists {
            assertEqualItemGeometry(titles: englishTitles, app: app, phase: "landscape-tabs")
        } else {
            XCTAssertTrue(app.descendants(matching: .any)["layout.regular-sidebar"].firstMatch.waitForExistence(timeout: 5),
                          "A sidebar is a different layout, not evidence of equal native tab spacing")
        }
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width < app.frame.height }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed)
        assertEqualItemGeometry(titles: englishTitles, app: app, phase: "returned-portrait")
    }

    @discardableResult
    private func assertEqualItemGeometry(titles: [String], app: XCUIApplication, phase: String) -> [CGRect] {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let buttons = titles.map { bar.buttons[$0].firstMatch }
        var previousFrames: [CGRect]?
        let equality = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard bar.buttons.count == titles.count,
                  buttons.allSatisfy({ $0.exists && $0.frame.width > 0 && $0.frame.height > 0 }) else {
                previousFrames = nil
                return false
            }
            let frames = buttons.map(\.frame)
            let stable = previousFrames.map { previous in
                zip(previous, frames).allSatisfy { pair in
                    abs(pair.0.minX - pair.1.minX) <= 1 && abs(pair.0.minY - pair.1.minY) <= 1
                        && abs(pair.0.width - pair.1.width) <= 1 && abs(pair.0.height - pair.1.height) <= 1
                }
            } ?? false
            previousFrames = frames
            let widths = frames.map(\.width)
            let gaps = zip(frames, frames.dropFirst()).map { pair in pair.1.midX - pair.0.midX }
            return stable && (widths.max() ?? 0) - (widths.min() ?? 0) <= 1
                && (gaps.max() ?? 0) - (gaps.min() ?? 0) <= 1
                && gaps.allSatisfy { $0 > 0 }
        }, object: bar)
        let outcome = XCTWaiter.wait(for: [equality], timeout: 5)
        if outcome != .completed { attachFailure(app, phase: phase, buttons: buttons) }
        XCTAssertEqual(outcome, .completed, "Actual native items must have equal widths and adjacent center gaps in \(phase)")
        let cover = app.descendants(matching: .any)["overlay.language-transition"].firstMatch
        let uncovered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cover)
        XCTAssertEqual(XCTWaiter.wait(for: [uncovered], timeout: 3), .completed,
                       "Actual interaction is checked after the full-window language transition finishes")
        XCTAssertEqual(bar.buttons.count, 5)
        let frames = buttons.map(\.frame)
        guard frames.count == 5 else { XCTFail("Missing native tab items"); return frames }
        for (title, button) in zip(titles, buttons) {
            XCTAssertEqual(button.label, title, "VoiceOver and navigation lookup must retain the full localized name")
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(bar.frame.insetBy(dx: -1, dy: -1).contains(button.frame))
            XCTAssertEqual(button.frame.midY, frames[0].midY, accuracy: 1)
            XCTAssertEqual(button.frame.width, frames[0].width, accuracy: 1)
        }
        let gaps = zip(frames, frames.dropFirst()).map { pair in pair.1.midX - pair.0.midX }
        for gap in gaps { XCTAssertEqual(gap, gaps[0], accuracy: 1) }
        return frames
    }

    private func assertDestinationsAreClickable(titles: [String], app: XCUIApplication) {
        for title in titles {
            let button = app.tabBars.buttons[title].firstMatch
            XCTAssertTrue(button.isHittable)
            button.tap()
            XCTAssertTrue(button.isSelected, "The actual \(title) destination must remain selectable")
        }
    }

    private func application(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--review-demo", "--ui-test-tab-spacing"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = language
        return app
    }

    private func waitForPortrait(_ app: XCUIApplication) {
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width < app.frame.height }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed,
                       "This fixture must observe an actual portrait viewport before measuring native tab geometry")
    }

    private func attachFailure(_ app: XCUIApplication, phase: String, buttons: [XCUIElement]) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "native-tab-spacing-\(phase)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let probe = app.descendants(matching: .any)["debug.native-tab-layout"].firstMatch
        let policy = probe.exists ? probe.value : "diagnostic-element-unavailable"
        print("NATIVE_TAB_SPACING phase=\(phase) bar=\(app.tabBars.firstMatch.frame) items=\(buttons.map { "\($0.label):\($0.frame)" }) policy=\(String(describing: policy))")
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
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 12) }
            if app.tabBars.firstMatch.exists { bottom = min(bottom, app.tabBars.firstMatch.frame.minY - 12) }
            guard bottom - top > 40 else { break }
            let center = (top + bottom) / 2
            let bounds = target.exists ? target.frame : .zero
            let upward = bounds.isEmpty || bounds.midY > center
            let travel = min(180, (bottom - top) * 0.55, bounds.isEmpty ? 160 : max(16, abs(bounds.midY - center)))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: viewport.midX, dy: center + (upward ? travel / 2 : -travel / 2)))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: viewport.midX, dy: center + (upward ? -travel / 2 : travel / 2))))
        }
        attachFailure(app, phase: "language-card-reveal", buttons: [])
        XCTAssertTrue(target.exists && target.isHittable)
    }
}
