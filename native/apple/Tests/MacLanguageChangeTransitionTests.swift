#if os(macOS)
import AppKit
import XCTest
@testable import WhereToStudyMac

@MainActor
final class MacLanguageChangeTransitionTests: XCTestCase {
    func testNativeMaterialCoversAppContentAndCommitsOnce() async throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let fixture = makeFixture()
        defer { fixture.host.removeFromSuperview(); fixture.window.close() }
        var commits = 0
        fixture.transition.perform(label: "English", reduceMotion: false) { commits += 1 }
        let cover = try XCTUnwrap(fixture.window.contentView?.subviews.first { $0 is NSVisualEffectView } as? NSVisualEffectView)
        XCTAssertEqual(cover.frame, fixture.window.contentView?.bounds)
        XCTAssertEqual(cover.material, .fullScreenUI)
        XCTAssertEqual(cover.blendingMode, .withinWindow)
        XCTAssertEqual(cover.state, .active)
        XCTAssertTrue(cover.isAccessibilityModal())
        XCTAssertEqual(commits, 0)
        try await waitUntil { !fixture.transition.isTransitioning }
        XCTAssertEqual(commits, 1)
        XCTAssertNil(cover.superview)
    }

    func testOnlyMatchingLocaleHostLayoutCanBeginReveal() async throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let fixture = makeFixture()
        defer { fixture.host.removeFromSuperview(); fixture.window.close() }
        var commits = 0
        fixture.host.localeIdentifier = "zh-Hans"
        fixture.transition.request(current: .simplifiedChinese, target: .english,
                                   label: "English", reduceMotion: false) { commits += 1 }
        try await waitUntil { commits == 1 }
        let cover = try XCTUnwrap(fixture.window.contentView?.subviews.first { $0 is NSVisualEffectView })
        XCTAssertEqual(cover.accessibilityValue() as? String, "covered")
        fixture.transition.layoutDidSettle(localeIdentifier: "wrong")
        XCTAssertEqual(cover.accessibilityValue() as? String, "covered")
        fixture.host.localeIdentifier = "en"
        fixture.host.needsLayout = true
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        try await waitUntil { !fixture.transition.isTransitioning }
        XCTAssertNil(cover.superview)
        XCTAssertEqual(commits, 1)
    }

    func testRapidReplacementAndPrecommitReversalDiscardOldCallbacks() async throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let fixture = makeFixture()
        defer { fixture.host.removeFromSuperview(); fixture.window.close() }
        var commits: [Int] = []
        fixture.transition.perform(label: "First", reduceMotion: false) { commits.append(1) }
        fixture.transition.perform(label: "Second", reduceMotion: false) { commits.append(2) }
        XCTAssertEqual(fixture.window.contentView?.subviews.filter { $0 is NSVisualEffectView }.count, 1)
        try await waitUntil { !fixture.transition.isTransitioning }
        XCTAssertEqual(commits, [2])
        fixture.transition.request(current: .simplifiedChinese, target: .english, label: "English", reduceMotion: false) { commits.append(3) }
        fixture.transition.request(current: .simplifiedChinese, target: .simplifiedChinese, label: "Chinese", reduceMotion: false) { commits.append(4) }
        XCTAssertFalse(fixture.transition.isTransitioning)
        XCTAssertEqual(commits, [2])
    }

    func testWindowLifecycleAndHostDetachCommitWithoutLeavingAnOverlay() {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        var commits = 0
        fixture.transition.perform(label: "English", reduceMotion: false) { commits += 1 }
        NotificationCenter.default.post(name: NSWindow.willMiniaturizeNotification, object: fixture.window)
        XCTAssertEqual(commits, 1)
        XCTAssertFalse(fixture.transition.isTransitioning)
        fixture.transition.perform(label: "Chinese", reduceMotion: false) { commits += 1 }
        fixture.host.removeFromSuperview()
        XCTAssertEqual(commits, 2)
        XCTAssertFalse(fixture.transition.isTransitioning)
        XCTAssertFalse(fixture.window.contentView?.subviews.contains { $0 is NSVisualEffectView } ?? true)
    }

    func testReduceMotionAndDetachedHostAreImmediate() {
        let fixture = makeFixture()
        defer { fixture.host.removeFromSuperview(); fixture.window.close() }
        var commits = 0
        fixture.transition.perform(label: "English", reduceMotion: true) { commits += 1 }
        XCTAssertEqual(commits, 1)
        XCTAssertFalse(fixture.transition.isTransitioning)
        XCTAssertFalse(fixture.window.contentView?.subviews.contains { $0 is NSVisualEffectView } ?? true)
        LanguageChangeTransition().perform(label: "Chinese", reduceMotion: false) { commits += 1 }
        XCTAssertEqual(commits, 2)
    }

    func testMissingTargetLayoutUsesFiniteCleanupNotFalseReadiness() async throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let fixture = makeFixture()
        defer { fixture.host.removeFromSuperview(); fixture.window.close() }
        fixture.host.localeIdentifier = "zh-Hans"
        var commits = 0
        fixture.transition.request(current: .simplifiedChinese, target: .english,
                                   label: "English", reduceMotion: false) { commits += 1 }
        try await waitUntil { commits == 1 }
        let cover = try XCTUnwrap(fixture.window.contentView?.subviews.first { $0 is NSVisualEffectView })
        XCTAssertEqual(cover.accessibilityValue() as? String, "covered")
        try await waitUntil { !fixture.transition.isTransitioning }
        XCTAssertEqual(commits, 1)
        XCTAssertNil(cover.superview)
        XCTAssertEqual(cover.accessibilityValue() as? String, "covered", "A readiness timeout must not masquerade as a normal fade")
    }

    private func makeFixture() -> (window: NSWindow, host: LanguageChangeTransitionHostView, transition: LanguageChangeTransition) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let transition = LanguageChangeTransition()
        let host = LanguageChangeTransitionHostView(transition: transition)
        window.contentView?.addSubview(host)
        window.orderFrontRegardless()
        return (window, host, transition)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        // Production now also waits for local notification/widget language
        // work. Timeout is failure cleanup, never a successful checkmark.
        for _ in 0..<1500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Native Mac transition did not complete within its finite bound")
    }
}
#endif
