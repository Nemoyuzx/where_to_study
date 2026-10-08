#if os(iOS)
import UIKit
import XCTest
@testable import WhereToStudyiOS

@MainActor
final class LanguageChangeTransitionTests: XCTestCase {
    func testBlurCoversTheWholeWindowCommitsOnceAndRemovesItsBlocker() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let fixture = makeFixture()
        defer { fixture.host.removeFromSuperview(); fixture.window.isHidden = true }
        var commits = 0
        fixture.transition.perform(label: "Switching language", reduceMotion: false) { commits += 1 }
        let cover = try XCTUnwrap(fixture.window.subviews.first { $0.accessibilityIdentifier == "overlay.language-transition" })
        XCTAssertEqual(cover.frame, fixture.window.bounds)
        XCTAssertTrue(cover.isUserInteractionEnabled)
        XCTAssertTrue(cover.accessibilityViewIsModal)
        XCTAssertTrue(fixture.transition.isTransitioning)
        XCTAssertEqual(commits, 0, "Locale changes only after the material has covered the interface")
        try await waitUntil { !fixture.transition.isTransitioning }
        XCTAssertEqual(commits, 1)
        XCTAssertNil(cover.superview)
        XCTAssertFalse(fixture.window.subviews.contains { $0.accessibilityIdentifier == "overlay.language-transition" })
    }

    func testRapidReplacementAppliesOnlyTheLatestPendingChoice() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let fixture = makeFixture()
        defer { fixture.host.removeFromSuperview(); fixture.window.isHidden = true }
        var commits: [Int] = []
        fixture.transition.perform(label: "English", reduceMotion: false) { commits.append(1) }
        fixture.transition.perform(label: "Chinese", reduceMotion: false) { commits.append(2) }
        XCTAssertEqual(fixture.window.subviews.filter { $0.accessibilityIdentifier == "overlay.language-transition" }.count, 1)
        try await waitUntil { !fixture.transition.isTransitioning }
        XCTAssertEqual(commits, [2], "Canceled animation completions must not overwrite the latest choice")
    }

    func testDetachingOrBackgroundFinishingCommitsPendingChoiceAndCleansUp() async throws {
        let fixture = makeFixture()
        defer { fixture.window.isHidden = true }
        var commits = 0
        fixture.transition.perform(label: "English", reduceMotion: false) { commits += 1 }
        fixture.host.removeFromSuperview()
        XCTAssertEqual(commits, 1)
        XCTAssertFalse(fixture.transition.isTransitioning)
        XCTAssertFalse(fixture.window.subviews.contains { $0.accessibilityIdentifier == "overlay.language-transition" })
        fixture.transition.finishImmediately()
        XCTAssertEqual(commits, 1)
    }

    func testRealRequestEntryCancelsAReversalToTheNotYetChangedLocale() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let fixture = makeFixture()
        defer { fixture.host.removeFromSuperview(); fixture.window.isHidden = true }
        var current: AppLanguage = .simplifiedChinese
        var commits = 0
        fixture.transition.request(current: current, target: .english, label: "English", reduceMotion: false) {
            current = .english; commits += 1
        }
        fixture.transition.request(current: current, target: .simplifiedChinese, label: "Chinese", reduceMotion: false) {
            current = .simplifiedChinese; commits += 1
        }
        XCTAssertEqual(current, .simplifiedChinese)
        XCTAssertEqual(commits, 0)
        XCTAssertFalse(fixture.transition.isTransitioning)
        fixture.transition.finishImmediately()
        XCTAssertEqual(commits, 0, "A canceled pending language must never be applied later")
    }

    func testRevealWaitsForMatchingTranslatedHostLayoutAndThenRemovesBlur() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let fixture = makeFixture()
        defer { fixture.host.removeFromSuperview(); fixture.window.isHidden = true }
        var commits = 0
        fixture.transition.request(current: .simplifiedChinese, target: .english,
                                   label: "English", reduceMotion: false) { commits += 1 }
        try await waitUntil { commits == 1 }
        let cover = try XCTUnwrap(fixture.window.subviews.first {
            $0.accessibilityIdentifier == "overlay.language-transition"
        } as? UIVisualEffectView)
        XCTAssertNotNil(cover.effect, "Material must remain active while translated layout is pending")
        fixture.transition.layoutDidSettle(localeIdentifier: "wrong")
        XCTAssertNotNil(cover.effect)
        fixture.transition.layoutDidSettle(localeIdentifier: "en")
        try await waitUntil { !fixture.transition.isTransitioning }
        XCTAssertNil(cover.superview)
        XCTAssertEqual(commits, 1)
    }

    func testReduceMotionAndMissingWindowSwitchImmediatelyWithoutAnOverlay() {
        let fixture = makeFixture()
        defer { fixture.host.removeFromSuperview(); fixture.window.isHidden = true }
        var commits = 0
        fixture.transition.perform(label: "English", reduceMotion: true) { commits += 1 }
        XCTAssertEqual(commits, 1)
        XCTAssertFalse(fixture.transition.isTransitioning)
        XCTAssertFalse(fixture.window.subviews.contains { $0.accessibilityIdentifier == "overlay.language-transition" })
        let detached = LanguageChangeTransition()
        detached.perform(label: "Chinese", reduceMotion: false) { commits += 1 }
        XCTAssertEqual(commits, 2)
        XCTAssertFalse(detached.isTransitioning)
    }

    func testWrongLocaleCannotTriggerNormalFadeAndTimeoutStillCleansUp() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let fixture = makeFixture()
        defer { fixture.host.removeFromSuperview(); fixture.window.isHidden = true }
        fixture.host.localeIdentifier = "zh-Hans"
        var commits = 0
        fixture.transition.request(current: .simplifiedChinese, target: .english,
                                   label: "English", reduceMotion: false) { commits += 1 }
        try await waitUntil { commits == 1 }
        let cover = try XCTUnwrap(fixture.window.subviews.first { $0.accessibilityIdentifier == "overlay.language-transition" } as? UIVisualEffectView)
        fixture.transition.layoutDidSettle(localeIdentifier: "wrong")
        XCTAssertNotNil(cover.effect)
        XCTAssertEqual(cover.accessibilityValue, "covered")
        // 0.4 waits for language tasks and stable geometry for up to twelve
        // seconds. Preserve that production gate instead of restoring 0.3's
        // one-second timeout just to satisfy this imported regression test.
        let deadline = ProcessInfo.processInfo.systemUptime + LanguageChangeTransition.layoutTimeout + 1
        while ProcessInfo.processInfo.systemUptime < deadline {
            if !fixture.transition.isTransitioning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(fixture.transition.isTransitioning)
        XCTAssertNil(cover.superview)
        XCTAssertEqual(cover.accessibilityValue, "covered", "Timeout cleanup is not successful target-layout readiness")
        XCTAssertEqual(commits, 1)
    }

    private func makeFixture() -> (window: UIWindow, host: LanguageChangeTransitionHostView, transition: LanguageChangeTransition) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let transition = LanguageChangeTransition()
        let host = LanguageChangeTransitionHostView(transition: transition)
        window.rootViewController?.view.addSubview(host)
        return (window, host, transition)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Language transition did not complete within its bounded animation window")
    }
}
#endif
