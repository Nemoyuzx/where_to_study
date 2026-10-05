import XCTest

@MainActor
final class QMplusToolbarUITests: XCTestCase {
    func testToolbarOnlyKeepsReloadAndLoginDoesNotRequireManualSyncInBothLanguages() {
        continueAfterFailure = false
        for language in ["zh-Hans", "en"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--ui-test-qmplus-toolbar"]
            app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = language
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["qmplus.toolbar.fixture.page"].waitForExistence(timeout: 5))
            let reload = app.buttons["qmplus.connection.reload"].firstMatch
            let sync = app.buttons["qmplus.connection.sync"].firstMatch
            XCTAssertTrue(reload.waitForExistence(timeout: 5))
            XCTAssertFalse(sync.exists)
            XCTAssertEqual(reload.label, language == "en" ? "Open the official QMplus login page" : "打开 QMplus 官方登录页")
            XCTAssertTrue(reload.isEnabled)
            assertVisibleBounds(reload, in: app)
            reload.tap()
            XCTAssertTrue(app.staticTexts["qmplus.toolbar.fixture.actions"].label.contains("reload=1"))
            assertVisibleBounds(reload, in: app)
            XCTAssertFalse(sync.exists)
            XCTAssertEqual(app.webViews.count, 0, "The fixture must never construct a login WebView")
            app.terminate()
        }
    }

    private func setSwitch(_ control: XCUIElement, on: Bool, in app: XCUIApplication) {
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertTrue(control.isHittable)
        let expected = on ? "1" : "0"
        if control.value as? String != expected {
            // SwiftUI exposes this Toggle's entire label row as the Switch.
            // The recorded center tap hit x=195, while its actual control is
            // at the right edge; tap inside that control, not the label.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected), object: control)], timeout: 5)
        if result != .completed { attachStateFailure(in: app, control: control) }
        XCTAssertEqual(result, .completed, "The actual synthetic Switch must reach its requested value")
        XCTAssertEqual(control.value as? String, expected)
    }

    private func waitForEnabled(_ action: XCUIElement, enabled: Bool, in app: XCUIApplication) {
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == %@", NSNumber(value: enabled)), object: action)], timeout: 5)
        if result != .completed { attachStateFailure(in: app, control: action) }
        XCTAssertEqual(result, .completed, "Toolbar state must reflect the actual fixture input")
        XCTAssertEqual(action.isEnabled, enabled)
    }

    private func attachStateFailure(in app: XCUIApplication, control: XCUIElement) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "qmplus-toolbar-synthetic-state-failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let ready = app.switches["qmplus.toolbar.fixture.ready"].firstMatch
        let busy = app.switches["qmplus.toolbar.fixture.busy"].firstMatch
        let sync = app.buttons["qmplus.connection.sync"].firstMatch
        print("QM_TOOLBAR_SYNTHETIC_STATE control=\(control.identifier) frame=\(control.frame) ready=\(String(describing: ready.value)) readyFrame=\(ready.frame) busy=\(String(describing: busy.value)) syncEnabled=\(sync.isEnabled) syncFrame=\(sync.frame)")
    }

    private func assertVisibleBounds(_ action: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(action.exists)
        XCTAssertTrue(action.isHittable)
        XCTAssertGreaterThan(action.frame.width, 0)
        XCTAssertGreaterThan(action.frame.height, 0)
        XCTAssertGreaterThanOrEqual(action.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(action.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(action.frame.minY, app.frame.minY)
        XCTAssertLessThanOrEqual(action.frame.maxY, app.frame.maxY)
    }
}
