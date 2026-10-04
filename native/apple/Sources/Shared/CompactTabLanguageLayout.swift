#if os(iOS)
import SwiftUI
import UIKit

// Refresh only native titles. Recreating TabView also recreates scroll views,
// local query state and appearance tasks. A managed bar's items are read-only.
struct CompactTabLanguageLayout: UIViewRepresentable {
    let language: AppLanguage

    func makeUIView(context: Context) -> CompactTabLanguageLayoutView {
        CompactTabLanguageLayoutView(frame: .zero)
    }

    func updateUIView(_ view: CompactTabLanguageLayoutView, context: Context) {
        view.update(titles: AppSection.allCases.map { AppLocalization.string($0.titleKey, language: language) })
    }

    static func dismantleUIView(_ view: CompactTabLanguageLayoutView, coordinator: ()) {
        view.cancelPendingUpdate()
    }
}

final class CompactTabLanguageLayoutView: UIView {
    private var titles: [String] = []
    private var appliedTitles: [String] = []
    private weak var appliedController: UITabBarController?
    private var pendingUpdate: DispatchWorkItem?
    private var remainingLookups = 0
    private var updateRevision = 0
    private(set) var refreshCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update(titles: [String]) {
        guard self.titles != titles else { return }
        self.titles = titles
        remainingLookups = 2
        scheduleUpdate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cancelPendingUpdate()
            appliedController = nil
            appliedTitles = []
        } else if !titles.isEmpty {
            remainingLookups = 2
            scheduleUpdate()
        }
    }

    func cancelPendingUpdate() {
        updateRevision &+= 1
        pendingUpdate?.cancel()
        pendingUpdate = nil
        remainingLookups = 0
    }

    private func scheduleUpdate() {
        pendingUpdate?.cancel()
        updateRevision &+= 1
        let revision = updateRevision
        let update = DispatchWorkItem { [weak self] in
            guard let self, self.updateRevision == revision else { return }
            self.pendingUpdate = nil
            self.applyTitles()
        }
        pendingUpdate = update
        DispatchQueue.main.async(execute: update)
    }

    private func applyTitles() {
        guard let window, !titles.isEmpty else { return }
        guard let controller = Self.tabController(in: window.rootViewController),
              let items = controller.tabBar.items, items.count == titles.count else {
            if remainingLookups > 0 {
                remainingLookups -= 1
                scheduleUpdate()
            }
            return
        }
        guard controller !== appliedController || appliedTitles != titles else { return }
        appliedController = controller
        appliedTitles = titles
        refreshCount += 1
        let bar = controller.tabBar
        let selected = bar.selectedItem
        UIView.performWithoutAnimation {
            for (item, title) in zip(items, titles) {
                // Force the public setter to invalidate a previously measured
                // native title, including the return to the shorter language.
                item.title = nil
                item.title = title
            }
            bar.invalidateIntrinsicContentSize()
            bar.setNeedsLayout()
            // The bar can invalidate its container's safe area. Flush both
            // layouts in the same nonanimated transaction, not on a later
            // frame after SwiftUI has already displayed the new locale.
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            bar.layoutIfNeeded()
            if let selected, bar.selectedItem !== selected { bar.selectedItem = selected }
        }
    }

    private static func tabController(in root: UIViewController?) -> UITabBarController? {
        guard let root else { return nil }
        if let tab = root as? UITabBarController { return tab }
        for child in root.children {
            if let tab = tabController(in: child) { return tab }
        }
        return nil
    }
}
#endif
