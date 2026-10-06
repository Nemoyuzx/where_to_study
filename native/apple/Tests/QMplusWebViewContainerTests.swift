import XCTest
import WebKit
#if os(macOS)
import AppKit
@testable import WhereToStudyMac
#else
import UIKit
@testable import WhereToStudyiOS
#endif

@MainActor
final class QMplusWebViewContainerTests: XCTestCase {
    func testQuietBrowserKeepsNormalRenderingUnderAnOpaqueFullSizeShield() {
        let browser = makeBrowser()
        let container = QMplusWebViewContainer(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        let lease = QMplusBrowserMountLease(presentation: 1, role: .quiet, browser: ObjectIdentifier(browser))
        container.configure(browser, lease: lease) { true }
        XCTAssertTrue(browser.superview === container)
        XCTAssertEqual(browser.frame, container.bounds)
        let cover = container.subviews.last!
        XCTAssertFalse(cover === browser)
        XCTAssertFalse(cover.isHidden)
        XCTAssertEqual(cover.frame, container.bounds)
        #if os(iOS)
        XCTAssertEqual(browser.alpha, 1)
        XCTAssertTrue(cover.isOpaque)
        XCTAssertEqual(cover.backgroundColor?.cgColor.alpha, 1)
        XCTAssertFalse(container.isUserInteractionEnabled)
        XCTAssertTrue(browser.accessibilityElementsHidden)
        XCTAssertNil(container.hitTest(CGPoint(x: 100, y: 100), with: nil))
        container.bounds = CGRect(x: 0, y: 0, width: 500, height: 320)
        container.setNeedsLayout(); container.layoutIfNeeded()
        #else
        XCTAssertEqual(browser.alphaValue, 1)
        XCTAssertEqual(cover.layer?.backgroundColor?.alpha, 1)
        XCTAssertNil(container.hitTest(NSPoint(x: 100, y: 100)))
        container.setFrameSize(NSSize(width: 500, height: 320))
        container.needsLayout = true; container.layoutSubtreeIfNeeded()
        #endif
        XCTAssertEqual(cover.frame, container.bounds)
        XCTAssertEqual(browser.frame, container.bounds)
        let visibleLease = QMplusBrowserMountLease(presentation: 1, role: .visible, browser: ObjectIdentifier(browser))
        container.configure(browser, lease: visibleLease) { true }
        XCTAssertTrue(cover.isHidden, "Only the deliberately presented official verification page is uncovered")
        XCTAssertNil(browser.url)
        container.detachIfOwned()
    }

    func testRetiredQuietContainerCannotStealThePromotedVisibleBrowser() {
        let browser = makeBrowser()
        let quiet = QMplusWebViewContainer(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        let visible = QMplusWebViewContainer(frame: CGRect(x: 0, y: 0, width: 480, height: 650))
        var gate = QMplusLoginSynchronizationGate()
        gate.beginQuietConnection()
        let hiddenLease = QMplusBrowserMountLease(presentation: gate.presentation, role: .quiet, browser: ObjectIdentifier(browser))
        quiet.configure(browser, lease: hiddenLease) { gate.isActive && gate.ownerKind == .quiet && gate.presentation == hiddenLease.presentation }
        XCTAssertTrue(browser.superview === quiet)
        #if os(iOS)
        XCTAssertNil(quiet.hitTest(.zero, with: nil))
        #else
        XCTAssertNil(quiet.hitTest(.zero))
        #endif

        gate.presentExistingConnection()
        let visibleLease = QMplusBrowserMountLease(presentation: gate.presentation, role: .visible, browser: ObjectIdentifier(browser))
        visible.configure(browser, lease: visibleLease) { gate.isPresented && gate.presentation == visibleLease.presentation }
        XCTAssertTrue(browser.superview === visible)
        XCTAssertEqual(browser.frame, visible.bounds)
        quiet.configure(browser, lease: hiddenLease) { gate.isActive && gate.ownerKind == .quiet && gate.presentation == hiddenLease.presentation }
        quiet.detachIfOwned()
        XCTAssertTrue(browser.superview === visible, "A delayed quiet update or dismantle must not remove the visible MFA browser")
        XCTAssertEqual(browser.frame, visible.bounds)
        #if os(iOS)
        XCTAssertTrue(visible.isUserInteractionEnabled)
        XCTAssertFalse(browser.accessibilityElementsHidden)
        XCTAssertNotNil(visible.hitTest(CGPoint(x: 32, y: 32), with: nil),
                        "The promoted MFA browser must still receive touches after a late hidden update")
        #else
        XCTAssertNotNil(visible.hitTest(NSPoint(x: 32, y: 32)),
                        "The promoted MFA browser must still receive clicks after a late hidden update")
        #endif
        XCTAssertNil(browser.url, "Mounting tests must never load an authentication page")
        visible.detachIfOwned()
    }

    func testRetiredPresentationCannotReparentABrowserOwnedByTheNewPresentation() {
        let browser = makeBrowser()
        let old = QMplusWebViewContainer(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        let current = QMplusWebViewContainer(frame: CGRect(x: 0, y: 0, width: 480, height: 650))
        var gate = QMplusLoginSynchronizationGate()
        gate.beginPresentation()
        let oldLease = QMplusBrowserMountLease(presentation: gate.presentation, role: .visible, browser: ObjectIdentifier(browser))
        old.configure(browser, lease: oldLease) { gate.isPresented && gate.presentation == oldLease.presentation }
        gate.endPresentation()
        gate.beginPresentation()
        let currentLease = QMplusBrowserMountLease(presentation: gate.presentation, role: .visible, browser: ObjectIdentifier(browser))
        current.configure(browser, lease: currentLease) { gate.isPresented && gate.presentation == currentLease.presentation }
        old.configure(browser, lease: oldLease) { gate.isPresented && gate.presentation == oldLease.presentation }
        old.detachIfOwned()
        XCTAssertTrue(browser.superview === current)
        XCTAssertEqual(browser.frame, current.bounds)
        XCTAssertNil(browser.url)
        current.detachIfOwned()
    }

    func testLeaseForAnotherBrowserCannotMountOrHideTheCurrentBrowser() {
        let browser = makeBrowser()
        let other = makeBrowser()
        let container = QMplusWebViewContainer(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        let wrong = QMplusBrowserMountLease(presentation: 1, role: .quiet, browser: ObjectIdentifier(other))
        container.configure(browser, lease: wrong) { true }
        XCTAssertNil(browser.superview, "Browser identity must be checked before mutating or mounting the view")
        #if os(iOS)
        XCTAssertFalse(browser.accessibilityElementsHidden)
        #endif
        XCTAssertNil(browser.url)
        XCTAssertNil(other.url)
    }

    private func makeBrowser() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: configuration)
    }
}
