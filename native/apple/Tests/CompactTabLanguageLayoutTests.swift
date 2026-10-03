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
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        scroll.contentOffset = CGPoint(x: 0, y: 640)
        let probe = CompactTabLanguageLayoutView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        tabs.view.addSubview(probe)
        defer { probe.cancelPendingUpdate(); window.isHidden = true; window.rootViewController = nil }
        let items = try XCTUnwrap(tabs.tabBar.items)
        let controllers = try XCTUnwrap(tabs.viewControllers)
        for (index, titles) in [["课表", "设置"], ["Schedule", "Settings"], ["课表", "设置"]].enumerated() {
            probe.update(titles: titles)
            try await waitUntil { probe.refreshCount == index + 1 && state.taskStarts > 0 }
            XCTAssertTrue(tabs.selectedViewController === selected)
            XCTAssertTrue(tabs.viewControllers?.first === controllers[0])
            XCTAssertTrue(tabs.tabBar.items?.first === items[0])
            XCTAssertEqual(tabs.tabBar.items?.map(\.title), titles.map(Optional.some))
            XCTAssertEqual(scroll.contentOffset.y, 640)
            XCTAssertEqual(state.taskStarts, 1, "Refreshing translated titles must not reappear/reload the selected page")
            probe.update(titles: titles)
            XCTAssertEqual(probe.refreshCount, index + 1, "Unchanged titles must not schedule another refresh")
        }
        probe.update(titles: ["Canceled", "Canceled"])
        probe.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(probe.refreshCount, 3, "Detached probes must cancel pending native updates")
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
