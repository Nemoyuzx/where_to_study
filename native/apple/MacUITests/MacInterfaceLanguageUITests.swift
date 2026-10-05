import AppKit
import XCTest

/// A dedicated macOS runner, not the iOS orientation/keyboard fixture. XCTest
/// launches its built target and owns that launch session; CUA/bundle lookup is
/// deliberately not involved. All screenshots contain review-demo data only.
@MainActor
final class MacInterfaceLanguageUITests: XCTestCase {
    private struct Geometry {
        let window: CGRect
        let sidebar: CGRect
        let viewport: CGRect
        let languageOffset: CGFloat
    }

    private enum FixtureFailure: Error { case missing(String), timeout(String) }

    func testRealRootLanguageRoundTripCoversSidebarAndSettingsBeforeRevealing() async throws {
        continueAfterFailure = false
        // Respect the user's accessibility policy rather than forcing motion.
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      "Native motion is deliberately disabled by the system accessibility setting")
        let app = XCUIApplication()
        app.launchArguments = ["--review-demo", "--ui-testing-privacy-consent",
                               "--ui-testing-language-material-preview"]
        app.launchEnvironment["WHERE_TO_STUDY_UI_LANGUAGE"] = "zh-Hans"
        app.launch()
        defer { app.terminate() }
        XCTAssertEqual(app.state, .runningForeground)

        let window = app.windows.firstMatch
        try require(window, named: "the test application's actual window")
        let settings = app.descendants(matching: .any)["navigation.settings"].firstMatch
        if !settings.exists {
            let consent = app.buttons["privacy-consent.accept"].firstMatch
            if consent.waitForExistence(timeout: 3) { consent.click() }
        }
        try require(settings, named: "actual Root settings navigation")
        settings.click()
        try require(app.descendants(matching: .any)["screen.settings"].firstMatch, named: "real Settings page")
        try await revealLanguageCard(app, window: window)
        try assertLanguageOptions(app, language: "zh-Hans")
        let chinese = try languageOption("简体中文", app: app)
        XCTAssertTrue(chinese.isSelected, "The launch must really select Chinese before clicking a different language")
        let baseline = try geometry(app, window: window)

        try await change(to: "en", app: app, window: window, baseline: baseline)
        try await change(to: "zh-Hans", app: app, window: window, baseline: baseline)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(overlay(app).exists, "The real Root must not leave a transition blocker behind")
        attach(window, name: "mac-root-language-roundtrip-restored")
    }

    private func change(to language: String, app: XCUIApplication, window: XCUIElement,
                        baseline: Geometry) async throws {
        let targetLabel = language == "en" ? "English" : "Simplified Chinese"
        let target = try languageOption(targetLabel, app: app)
        XCTAssertTrue(target.isHittable, "Round-trip selection must not need another scroll/reveal")
        XCTAssertFalse(target.isSelected, "Click a genuinely different language, not an already-selected segment")
        target.click() // The actual SwiftUI Settings binding; never a model setter/test shortcut.

        var sawOverlay = false
        var sawCovered = false
        var sawTargetUnderCover = false
        var savedMaterialSample = false
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        while ProcessInfo.processInfo.systemUptime < deadline {
            let cover = overlay(app)
            if cover.exists {
                sawOverlay = true
                let frame = try measuredFrame(cover, named: "actual full-window material")
                let expanded = frame.insetBy(dx: -2, dy: -2)
                XCTAssertTrue(expanded.contains(baseline.sidebar.intersection(baseline.window)),
                              "Material must cover the measured app sidebar, not only Settings")
                XCTAssertTrue(expanded.contains(baseline.viewport.intersection(baseline.window)),
                              "Material must cover the measured Settings viewport; OS titlebar geometry is not guessed")
                let phase = cover.value as? String
                if phase == "covered" { sawCovered = true }
                let targetIsRendered = hasTargetLanguage(app, language: language)
                if targetIsRendered && (phase == "covered" || phase == "revealing") {
                    sawTargetUnderCover = true
                }
                if targetIsRendered && phase == "covered" && !savedMaterialSample {
                    // A visual material sample, not a performance/frame-rate measurement.
                    attach(window, name: "mac-root-native-material-covered-\(language)")
                    savedMaterialSample = true
                }
            } else if sawOverlay && hasTargetLanguage(app, language: language) {
                break
            }
            // Poll actual AX state with a finite deadline; no fixed stabilization
            // sleep or private XCTest quiescence override conceals a missing phase.
            await Task.yield()
        }
        if !sawOverlay || !sawCovered || !sawTargetUnderCover {
            attach(window, name: "mac-root-language-missing-phase-\(language)")
            print("MAC_ROOT_LANGUAGE_PHASE language=\(language) overlay=\(sawOverlay) covered=\(sawCovered) targetUnderCover=\(sawTargetUnderCover)")
        }
        XCTAssertTrue(sawOverlay, "The real Settings action must install native full-window material")
        XCTAssertTrue(sawCovered, "Observe the actual covered phase, not just the final translated UI")
        XCTAssertTrue(sawTargetUnderCover, "Target-language Root content must appear while material still covers it")
        try await waitUntil("material removed after target layout", window: window) {
            !self.overlay(app).exists && self.hasTargetLanguage(app, language: language)
        }
        try assertLanguageOptions(app, language: language)
        XCTAssertTrue(try languageOption(language == "en" ? "English" : "简体中文", app: app).isSelected)
        let restored = try geometry(app, window: window)
        assertSameFrame(restored.window, baseline.window, name: "same app window")
        assertSameFrame(restored.sidebar, baseline.sidebar, name: "visible app sidebar")
        assertSameFrame(restored.viewport, baseline.viewport, name: "Settings scroll viewport")
        XCTAssertEqual(restored.languageOffset, baseline.languageOffset, accuracy: 2,
                       "The language card's measured viewport position must not jump or reset to the top")
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func hasTargetLanguage(_ app: XCUIApplication, language: String) -> Bool {
        let header = language == "en" ? "Interface Language" : "界面语言"
        let navigation = app.descendants(matching: .any)["navigation.settings"].firstMatch
        return app.staticTexts[header].firstMatch.exists && navigation.exists
            && navigation.label == (language == "en" ? "Settings" : "设置")
    }

    private func overlay(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["overlay.language-transition"].firstMatch
    }

    private func card(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["settings.language"].firstMatch
    }

    private func languageOption(_ label: String, app: XCUIApplication) throws -> XCUIElement {
        let container = card(app)
        try require(container, named: "identified language card/selector")
        let matches = container.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
        let controls = matches.allElementsBoundByIndex.filter {
            $0.elementType == .button || $0.elementType == .radioButton || $0.elementType == .menuItem
        }
        guard controls.count == 1, let control = controls.first else {
            XCTFail("Expected one actual language control for \(label), got \(controls.count)")
            throw FixtureFailure.missing("language control \(label)")
        }
        _ = try measuredFrame(control, named: "language control \(label)")
        return control
    }

    private func assertLanguageOptions(_ app: XCUIApplication, language: String) throws {
        let labels = language == "en" ? ["System", "Simplified Chinese", "English"] : ["跟随系统", "简体中文", "English"]
        for label in labels { _ = try languageOption(label, app: app) }
    }

    private func settingsViewport(_ app: XCUIApplication, window: XCUIElement) throws -> XCUIElement {
        let page = app.descendants(matching: .any)["screen.settings"].firstMatch
        let pageFrame = try measuredFrame(page, named: "Settings page")
        let windowFrame = try measuredFrame(window, named: "app window")
        let candidates = app.scrollViews.allElementsBoundByIndex.filter {
            $0.exists && !$0.frame.isEmpty && $0.frame.intersects(pageFrame)
                && $0.frame.intersects(windowFrame) && $0.frame.width > 300
        }
        guard let viewport = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            XCTFail("Missing actual Settings scroll viewport")
            throw FixtureFailure.missing("Settings scroll viewport")
        }
        return viewport
    }

    private func revealLanguageCard(_ app: XCUIApplication, window: XCUIElement) async throws {
        var wheelDirection: CGFloat = -1
        for _ in 0..<24 {
            let scroll = try settingsViewport(app, window: window)
            let viewport = try measuredFrame(scroll, named: "Settings viewport during scroll")
            // AppKit may omit the off-screen segmented-control children from
            // AX. Scroll using the real card, then inspect its actual controls.
            let container = card(app)
            let before = try measuredFrame(container, named: "language card during reveal")
            if before.intersects(viewport) {
                let option = try languageOption("English", app: app)
                if option.isHittable { return }
            }
            let desiredMovement: CGFloat = before.midY > viewport.midY ? -1 : 1
            scroll.scroll(byDeltaX: 0, deltaY: wheelDirection * min(220, viewport.height * 0.35))
            await Task.yield()
            let after = try measuredFrame(container, named: "language card after native scroll")
            let moved = after.midY - before.midY
            if abs(moved) > 0.5 && moved * desiredMovement < 0 { wheelDirection *= -1 }
        }
        attach(window, name: "mac-root-language-card-reveal-failure")
        XCTFail("Actual language control was not reachable after bounded native Settings scrolling")
        throw FixtureFailure.missing("hittable language control")
    }

    private func geometry(_ app: XCUIApplication, window: XCUIElement) throws -> Geometry {
        let windowFrame = try measuredFrame(window, named: "app window")
        let sidebar = try measuredFrame(app.descendants(matching: .any)["layout.regular-sidebar"].firstMatch, named: "Root sidebar")
        let viewport = try measuredFrame(settingsViewport(app, window: window), named: "Settings viewport")
        let language = try measuredFrame(card(app), named: "language card")
        XCTAssertTrue(language.intersects(viewport), "The real language card must remain inside the current viewport")
        return Geometry(window: windowFrame, sidebar: sidebar, viewport: viewport,
                        languageOffset: language.minY - viewport.minY)
    }

    private func measuredFrame(_ element: XCUIElement, named name: String) throws -> CGRect {
        try require(element, named: name)
        let frame = element.frame
        guard !frame.isEmpty, !frame.isNull, !frame.isInfinite,
              [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) else {
            XCTFail("Missing/non-finite geometry for \(name): \(frame)")
            throw FixtureFailure.missing(name)
        }
        return frame
    }

    private func require(_ element: XCUIElement, named name: String) throws {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("Missing actual UI node: \(name)")
            throw FixtureFailure.missing(name)
        }
    }

    private func assertSameFrame(_ actual: CGRect, _ expected: CGRect, name: String) {
        for (value, baseline) in zip([actual.minX, actual.minY, actual.width, actual.height],
                                     [expected.minX, expected.minY, expected.width, expected.height]) {
            XCTAssertEqual(value, baseline, accuracy: 2, "Changed \(name) geometry")
        }
    }

    private func waitUntil(_ description: String, window: XCUIElement, condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return }
            await Task.yield()
        }
        attach(window, name: "mac-root-language-readiness-failure")
        XCTFail("Timed out waiting for actual UI state: \(description)")
        throw FixtureFailure.timeout(description)
    }

    private func attach(_ window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
