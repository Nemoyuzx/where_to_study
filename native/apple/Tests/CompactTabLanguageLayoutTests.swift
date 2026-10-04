#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import WhereToStudyiOS

@MainActor
final class CompactTabLanguageLayoutTests: XCTestCase {
    func testNativeTitleRefreshKeepsControllersSelectionScrollAndAppearanceTask() async throws {
        let state = TabAppearanceProbeState()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        scroll.contentSize = CGSize(width: 300, height: 2000)
        let selected = UIHostingController(rootView: TabAppearanceProbe(state: state, scroll: scroll))
        let other = UIViewController()
        let tabs = UITabBarController()
        tabs.setViewControllers([selected, other], animated: false)
        tabs.selectedIndex = 0
        if #available(iOS 17.0, *) { tabs.tabBar.traitOverrides.verticalSizeClass = .regular }
        tabs.tabBar.scrollEdgeAppearance = nil
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        scroll.contentOffset = CGPoint(x: 0, y: 640)
        let probe = CompactTabLanguageLayoutView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        tabs.view.addSubview(probe)
        defer { probe.cancelPendingUpdate(); window.isHidden = true; window.rootViewController = nil }
        let items = try XCTUnwrap(tabs.tabBar.items)
        let controllers = try XCTUnwrap(tabs.viewControllers)
        var settledControllerFrame: CGRect?
        var settledBarFrame: CGRect?
        var settledSafeArea: UIEdgeInsets?
        for (index, titles) in [["课表", "设置"], ["Schedule", "Settings"], ["课表", "设置"]].enumerated() {
            probe.update(titles: titles)
            try await waitUntil { probe.refreshCount == index + 1 && state.taskStarts > 0 }
            XCTAssertTrue(tabs.selectedViewController === selected)
            XCTAssertTrue(tabs.viewControllers?.first === controllers[0])
            XCTAssertTrue(tabs.tabBar.items?.first === items[0])
            XCTAssertEqual(tabs.tabBar.items?.map(\.title), titles.map(Optional.some))
            XCTAssertEqual(tabs.tabBar.itemPositioning, .fill)
            XCTAssertEqual(tabs.tabBar.standardAppearance.stackedItemPositioning, .fill)
            XCTAssertNil(tabs.tabBar.scrollEdgeAppearance, "Fill must preserve the inherited scroll-edge appearance")
            XCTAssertEqual(scroll.contentOffset.y, 640)
            if let settledControllerFrame, let settledBarFrame, let settledSafeArea {
                XCTAssertEqual(tabs.view.frame, settledControllerFrame)
                XCTAssertEqual(tabs.tabBar.frame, settledBarFrame)
                XCTAssertEqual(tabs.view.safeAreaInsets, settledSafeArea)
            } else {
                settledControllerFrame = tabs.view.frame
                settledBarFrame = tabs.tabBar.frame
                settledSafeArea = tabs.view.safeAreaInsets
            }
            XCTAssertEqual(state.taskStarts, 1, "Refreshing translated titles must not reappear/reload the selected page")
            probe.update(titles: titles)
            XCTAssertEqual(probe.refreshCount, index + 1, "Unchanged titles must not schedule another refresh")
        }
        probe.update(titles: ["Canceled", "Canceled"])
        probe.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(probe.refreshCount, 3, "Detached probes must cancel pending native updates")
    }

    func testFourLocalizedItemsUseFillWithoutReplacingAppearanceOrControllers() async throws {
        let tabs = UITabBarController()
        let controllers = (0..<4).map { _ in UIViewController() }
        tabs.setViewControllers(controllers, animated: false)
        tabs.selectedIndex = 3
        if #available(iOS 17.0, *) { tabs.tabBar.traitOverrides.verticalSizeClass = .regular }
        let standard = UITabBarAppearance()
        standard.configureWithTransparentBackground()
        standard.stackedItemPositioning = .centered
        standard.stackedItemWidth = 57
        standard.stackedItemSpacing = 19
        standard.backgroundColor = .systemPurple
        standard.shadowColor = .systemOrange
        standard.stackedLayoutAppearance.normal.iconColor = .systemGreen
        let titleFont = UIFont.systemFont(ofSize: 11, weight: .medium)
        standard.stackedLayoutAppearance.normal.titleTextAttributes = [.font: titleFont, .foregroundColor: UIColor.systemBrown]
        let edge = UITabBarAppearance()
        edge.configureWithOpaqueBackground()
        edge.stackedItemPositioning = .centered
        edge.backgroundColor = .systemTeal
        edge.stackedLayoutAppearance.selected.iconColor = .systemYellow
        tabs.tabBar.standardAppearance = standard
        tabs.tabBar.scrollEdgeAppearance = edge
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        let probe = CompactTabLanguageLayoutView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        tabs.view.addSubview(probe)
        defer { probe.cancelPendingUpdate(); window.isHidden = true; window.rootViewController = nil }
        let items = try XCTUnwrap(tabs.tabBar.items)
        let selected = try XCTUnwrap(tabs.tabBar.selectedItem)
        let localizedTitles = [["空教室", "教学日历", "查询", "设置"],
                               ["Empty Rooms", "Academic Calendar", "Search", "Settings"],
                               ["空教室", "教学日历", "查询", "设置"]]
        for (index, titles) in localizedTitles.enumerated() {
            let language: AppLanguage = index == 1 ? .english : .simplifiedChinese
            let compactTitles = AppSection.allCases.map { CompactTabTitlePolicy.title(for: $0, language: language) }
            probe.update(titles: compactTitles, accessibilityLabels: titles)
            try await waitUntil { probe.refreshCount == index + 1 }
            XCTAssertEqual(tabs.tabBar.itemPositioning, .fill)
            XCTAssertEqual(tabs.tabBar.standardAppearance.stackedItemPositioning, .fill)
            XCTAssertEqual(tabs.tabBar.scrollEdgeAppearance?.stackedItemPositioning, .fill)
            XCTAssertEqual(tabs.tabBar.standardAppearance.backgroundColor, standard.backgroundColor)
            XCTAssertEqual(tabs.tabBar.standardAppearance.backgroundEffect, standard.backgroundEffect)
            XCTAssertEqual(tabs.tabBar.standardAppearance.shadowColor, standard.shadowColor)
            XCTAssertEqual(tabs.tabBar.standardAppearance.stackedItemWidth, 57)
            XCTAssertEqual(tabs.tabBar.standardAppearance.stackedItemSpacing, 19)
            XCTAssertEqual(tabs.tabBar.standardAppearance.stackedLayoutAppearance.normal.iconColor, .systemGreen)
            XCTAssertEqual(tabs.tabBar.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes[.font] as? UIFont, titleFont)
            XCTAssertEqual(tabs.tabBar.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes[.foregroundColor] as? UIColor, .systemBrown)
            XCTAssertEqual(tabs.tabBar.scrollEdgeAppearance?.backgroundColor, edge.backgroundColor)
            XCTAssertEqual(tabs.tabBar.scrollEdgeAppearance?.backgroundEffect, edge.backgroundEffect)
            XCTAssertEqual(tabs.tabBar.scrollEdgeAppearance?.stackedLayoutAppearance.selected.iconColor, .systemYellow)
            XCTAssertTrue(tabs.tabBar.selectedItem === selected)
            XCTAssertTrue(tabs.selectedViewController === controllers[3])
            XCTAssertEqual(tabs.tabBar.items?.map(\.title), compactTitles.map(Optional.some))
            XCTAssertEqual(tabs.tabBar.items?.map(\.accessibilityLabel), titles.map(Optional.some))
            for itemIndex in items.indices {
                XCTAssertTrue(tabs.tabBar.items?[itemIndex] === items[itemIndex])
                XCTAssertTrue(tabs.viewControllers?[itemIndex] === controllers[itemIndex])
            }
            probe.update(titles: compactTitles, accessibilityLabels: titles)
            XCTAssertEqual(probe.refreshCount, index + 1)
        }
    }

    func testCompactEnglishTitlesLeaveFullPageAndAccessibilityNamesAvailable() {
        XCTAssertEqual(AppSection.allCases.map { CompactTabTitlePolicy.title(for: $0, language: .english) },
                       ["Rooms", "Calendar", "Search", "Settings"])
        XCTAssertEqual(AppSection.allCases.map { CompactTabTitlePolicy.title(for: $0, language: .simplifiedChinese) },
                       ["空教室", "教学日历", "查询", "设置"])
        XCTAssertEqual(AppLocalization.string(AppSection.planner.titleKey, language: .english), "Empty Rooms")
        XCTAssertEqual(AppLocalization.string(AppSection.calendar.titleKey, language: .english), "Academic Calendar")
        let expectedSystemTitles = AppLanguage.system.resolvedResourceName == "en"
            ? ["Rooms", "Calendar", "Search", "Settings"] : ["空教室", "教学日历", "查询", "设置"]
        XCTAssertEqual(AppSection.allCases.map { CompactTabTitlePolicy.title(for: $0, language: .system) }, expectedSystemTitles)
    }

    func testHostedViewGeometryChangeReappliesNativePolicyOnce() async throws {
        let tabs = UITabBarController()
        let controllers = (0..<4).map { _ in UIViewController() }
        tabs.setViewControllers(controllers, animated: false)
        if #available(iOS 17.0, *) { tabs.tabBar.traitOverrides.verticalSizeClass = .regular }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        let probe = CompactTabLanguageLayoutView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        tabs.view.addSubview(probe)
        defer { probe.cancelPendingUpdate(); window.isHidden = true; window.rootViewController = nil }
        let titles = ["Rooms", "Calendar", "Search", "Settings"]
        probe.update(titles: titles)
        try await waitUntil { probe.refreshCount == 1 }
        tabs.tabBar.itemPositioning = .automatic
        let appearance = tabs.tabBar.standardAppearance.copy()
        appearance.stackedItemPositioning = .automatic
        tabs.tabBar.standardAppearance = appearance
        // Resize the actual hosted marker, not UIWindow: UIKit owns a test
        // window's screen bounds and may restore its frame before async work.
        let initialMarkerSize = probe.bounds.size
        probe.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        XCTAssertNotEqual(probe.bounds.size, initialMarkerSize, "The hosted-view fixture must actually change its geometry")
        probe.setNeedsLayout()
        probe.layoutIfNeeded()
        try await waitUntil { probe.refreshCount == 2 }
        XCTAssertEqual(tabs.tabBar.itemPositioning, .fill)
        XCTAssertEqual(tabs.tabBar.standardAppearance.stackedItemPositioning, .fill)
        XCTAssertTrue(tabs.viewControllers?.first === controllers[0])
        for _ in 0..<10 { probe.setNeedsLayout(); probe.layoutIfNeeded() }
        XCTAssertEqual(probe.refreshCount, 2, "Repeated layout passes in the same geometry must not reschedule title updates")
    }

    func testCompactHeightPolicyRequestsStackedBarWithoutChangingRegularOrUnspecifiedTraits() {
        XCTAssertEqual(CompactTabHeightPolicy.preferredBarHeightClass(for: .compact), .regular)
        XCTAssertEqual(CompactTabHeightPolicy.preferredBarHeightClass(for: .regular), .regular)
        XCTAssertEqual(CompactTabHeightPolicy.preferredBarHeightClass(for: .unspecified), .unspecified)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Native tab layout update did not complete")
    }
}

@MainActor
private final class TabAppearanceProbeState {
    var taskStarts = 0
}

private struct TabAppearanceProbe: View {
    let state: TabAppearanceProbeState
    let scroll: UIScrollView
    var body: some View { TabScrollProbe(scroll: scroll).task { state.taskStarts += 1 } }
}

private struct TabScrollProbe: UIViewRepresentable {
    let scroll: UIScrollView
    func makeUIView(context: Context) -> UIScrollView { scroll }
    func updateUIView(_ view: UIScrollView, context: Context) {}
}
#endif
