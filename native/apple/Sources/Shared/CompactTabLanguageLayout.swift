#if os(iOS)
import SwiftUI
import UIKit

/// Native compact-tab labels are intentionally concise. Page headings,
/// sidebars and VoiceOver keep the full localized section names.
enum CompactTabTitlePolicy {
    static func title(for section: AppSection, language: AppLanguage) -> String {
        guard language.resolvedResourceName == "en" else {
            return AppLocalization.string(section.titleKey, language: language)
        }
        return switch section {
        case .planner: "Rooms"
        case .calendar: "Agenda"
        case .courses: "Courses"
        case .queries: "Search"
        case .settings: "Settings"
        }
    }
}

enum CompactTabHeightPolicy {
    static func isHorizontalBottomBar(frame: CGRect, containerBounds: CGRect) -> Bool {
        frame.width > frame.height && frame.height > 0 && containerBounds.height > 0
            && abs(frame.maxY - containerBounds.maxY) <= 1
    }

    static func preferredBarHeightClass(for heightClass: UIUserInterfaceSizeClass,
                                       isHorizontalBottomBar: Bool = true) -> UIUserInterfaceSizeClass {
        guard isHorizontalBottomBar else { return .unspecified }
        return heightClass == .compact ? .regular : heightClass
    }
}

// Refresh only native titles. Recreating TabView also recreates scroll views,
// local query state and appearance tasks. A managed bar's items are read-only.
struct CompactTabLanguageLayout: UIViewRepresentable {
    let language: AppLanguage
    var transition: LanguageChangeTransition? = nil

    func makeUIView(context: Context) -> CompactTabLanguageLayoutView {
        let view = CompactTabLanguageLayoutView(frame: .zero)
        view.transition = transition
        return view
    }

    func updateUIView(_ view: CompactTabLanguageLayoutView, context: Context) {
        view.transition = transition
        view.localeIdentifier = language.locale.identifier
        if view.window != nil { transition?.attachNavigation(to: view) }
        view.update(
            titles: AppSection.allCases.map { CompactTabTitlePolicy.title(for: $0, language: language) },
            accessibilityLabels: AppSection.allCases.map { AppLocalization.string($0.titleKey, language: language) }
        )
    }

    static func dismantleUIView(_ view: CompactTabLanguageLayoutView, coordinator: ()) {
        view.cancelPendingUpdate()
        view.transition?.detachNavigation(from: view)
    }
}

final class CompactTabLanguageLayoutView: UIView {
    weak var transition: LanguageChangeTransition?
    var localeIdentifier = ""
    private var titles: [String] = []
    private var accessibilityLabels: [String] = []
    private var appliedTitles: [String] = []
    private var appliedAccessibilityLabels: [String] = []
    private var appliedViewSize: CGSize?
    private var appliedHorizontalBottomBar: Bool?
    private weak var appliedController: UITabBarController?
    private var pendingUpdate: DispatchWorkItem?
    private var remainingLookups = 0
    private var updateRevision = 0
    private(set) var refreshCount = 0
    #if DEBUG
    private var diagnosticCount = 0
    private var diagnosticFields = [String: [String: Any]]()
    private var spacingDiagnosticsEnabled: Bool {
        (AppLaunchConfiguration.isUITesting || AppLaunchConfiguration.isReviewDemo)
            && ProcessInfo.processInfo.arguments.contains("--ui-test-tab-spacing")
    }
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        #if DEBUG
        if spacingDiagnosticsEnabled {
            isAccessibilityElement = true
            accessibilityIdentifier = "debug.native-tab-layout"
            accessibilityLabel = "Native tab layout geometry"
        }
        #endif
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update(titles: [String], accessibilityLabels: [String]? = nil) {
        let labels = accessibilityLabels ?? titles
        guard labels.count == titles.count,
              self.titles != titles || self.accessibilityLabels != labels else { return }
        self.titles = titles
        self.accessibilityLabels = labels
        remainingLookups = 2
        scheduleUpdate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            transition?.detachNavigation(from: self)
            cancelPendingUpdate()
            appliedController = nil
            appliedTitles = []
            appliedAccessibilityLabels = []
            appliedViewSize = nil
        } else if !titles.isEmpty {
            transition?.attachNavigation(to: self)
            remainingLookups = 2
            scheduleUpdate()
        }
    }

    func translationIsReady(for locale: String) -> Bool {
        guard window != nil, localeIdentifier == locale, !titles.isEmpty,
              pendingUpdate == nil, appliedTitles == titles,
              appliedAccessibilityLabels == accessibilityLabels,
              let bar = appliedController?.tabBar, bar.bounds.width > 0, bar.bounds.height > 0,
              let items = bar.items, items.count == titles.count else { return false }
        return zip(items, titles).allSatisfy { $0.title == $1 } &&
            zip(items, accessibilityLabels).allSatisfy { $0.accessibilityLabel == $1 }
    }

    var languageCompletionGeometry: [Double] {
        guard let window, let bar = appliedController?.tabBar else { return [] }
        let frame = bar.convert(bar.bounds, to: window)
        return [frame.minX, frame.minY, frame.width, frame.height].map(Double.init)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let window, let bar = appliedController?.tabBar, !titles.isEmpty,
              pendingUpdate == nil else { return }
        let horizontalBottomBar = CompactTabHeightPolicy.isHorizontalBottomBar(
            frame: bar.convert(bar.bounds, to: window), containerBounds: window.bounds
        )
        guard appliedViewSize != bounds.size || appliedHorizontalBottomBar != horizontalBottomBar else { return }
        // Rotation can rebuild UIKit's inline appearance without changing any
        // labels. Refresh once for the new window geometry, never each frame.
        scheduleUpdate()
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
        let bar = controller.tabBar
        let isHorizontalBottomBar = CompactTabHeightPolicy.isHorizontalBottomBar(
            frame: bar.convert(bar.bounds, to: window), containerBounds: window.bounds
        )
        guard controller !== appliedController || appliedTitles != titles || appliedAccessibilityLabels != accessibilityLabels
                || appliedViewSize != bounds.size || appliedHorizontalBottomBar != isHorizontalBottomBar else { return }
        appliedController = controller
        appliedTitles = titles
        appliedAccessibilityLabels = accessibilityLabels
        appliedViewSize = bounds.size
        appliedHorizontalBottomBar = isHorizontalBottomBar
        refreshCount += 1
        let selected = bar.selectedItem
        #if DEBUG
        logPositioning("before", bar: bar)
        #endif
        UIView.performWithoutAnimation {
            // Keep icons above concise labels in compact-height navigation.
            // Override the bar only: page/controller traits remain adaptive.
            if #available(iOS 17.0, *) {
                let heightClass = bar.traitCollection.verticalSizeClass
                let preferred = CompactTabHeightPolicy.preferredBarHeightClass(
                    for: heightClass, isHorizontalBottomBar: isHorizontalBottomBar
                )
                // Clear our old override when the system moves the bar to a
                // side or another placement; its own traits then apply again.
                if preferred != heightClass { bar.traitOverrides.verticalSizeClass = preferred }
            }
            bar.itemPositioning = isHorizontalBottomBar ? .fill : .automatic
            let appearance = bar.standardAppearance.copy()
            appearance.stackedItemPositioning = isHorizontalBottomBar ? .fill : .automatic
            bar.standardAppearance = appearance
            if let edgeAppearance = bar.scrollEdgeAppearance?.copy() {
                edgeAppearance.stackedItemPositioning = isHorizontalBottomBar ? .fill : .automatic
                bar.scrollEdgeAppearance = edgeAppearance
            }
            for (index, item) in items.enumerated() {
                // Force the public setter to invalidate a previously measured
                // native title, including the return to the shorter language.
                item.title = nil
                item.title = titles[index]
                item.accessibilityLabel = accessibilityLabels[index]
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
        #if DEBUG
        logPositioning("after", bar: bar)
        #endif
    }

    #if DEBUG
    override var accessibilityValue: String? {
        get {
            guard spacingDiagnosticsEnabled else { return super.accessibilityValue }
            var values: [String: Any] = diagnosticFields
            values["refreshCount"] = refreshCount
            values["attached"] = window != nil
            if let bar = appliedController?.tabBar { values["current"] = positioningValues(bar) }
            guard let data = try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        set { super.accessibilityValue = newValue }
    }

    private func positioningValues(_ bar: UITabBar) -> [String: Any] {
        var values: [String: Any] = ["position": bar.itemPositioning.rawValue,
                                    "standard": bar.standardAppearance.stackedItemPositioning.rawValue,
                                    "itemWidth": Double(bar.itemWidth), "itemSpacing": Double(bar.itemSpacing),
                                    "barWidth": Double(bar.bounds.width), "barHeight": Double(bar.bounds.height),
                                    "viewWidth": Double(bounds.width), "viewHeight": Double(bounds.height),
                                    "verticalSizeClass": bar.traitCollection.verticalSizeClass.rawValue]
        if let window {
            values["windowWidth"] = Double(window.bounds.width)
            values["windowHeight"] = Double(window.bounds.height)
        }
        if let edge = bar.scrollEdgeAppearance { values["edge"] = edge.stackedItemPositioning.rawValue }
        values["hasScrollEdgeAppearance"] = bar.scrollEdgeAppearance != nil
        return values
    }

    private func logPositioning(_ phase: String, bar: UITabBar) {
        guard diagnosticCount < 8, spacingDiagnosticsEnabled else { return }
        diagnosticCount += 1
        diagnosticFields[phase] = positioningValues(bar)
        NSLog("%@", "NATIVE_TAB_POSITIONING phase=\(phase) refresh=\(refreshCount) window=\(String(describing: window?.bounds.size)) bar=\(bar.frame) position=\(bar.itemPositioning.rawValue) standard=\(bar.standardAppearance.stackedItemPositioning.rawValue) edge=\(String(describing: bar.scrollEdgeAppearance?.stackedItemPositioning.rawValue)) itemWidth=\(bar.itemWidth) itemSpacing=\(bar.itemSpacing)")
    }
    #endif

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
