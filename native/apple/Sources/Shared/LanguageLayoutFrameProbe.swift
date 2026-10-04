#if DEBUG && os(iOS)
import SwiftUI
import UIKit

/// Opt-in geometry-only sampling. It never reads text fields, account data or
/// network/cache state, and stops after a bounded language-layout window.
struct LanguageLayoutFrameProbe: UIViewRepresentable {
    let language: AppLanguage
    func makeUIView(context _: Context) -> LanguageLayoutFrameProbeView { LanguageLayoutFrameProbeView() }
    func updateUIView(_ view: LanguageLayoutFrameProbeView, context _: Context) { view.update(language: language) }
    static func dismantleUIView(_ view: LanguageLayoutFrameProbeView, coordinator _: ()) { view.stop() }
}

final class LanguageLayoutFrameProbeView: UIView {
    private struct Geometry {
        let root: CGRect
        let controller: CGRect
        let safeArea: UIEdgeInsets
        let bar: CGRect?
        let viewport: CGRect?
    }
    private weak var controller: UIViewController?
    private weak var bar: UITabBar?
    private weak var scroll: UIScrollView?
    private var currentLanguage: AppLanguage?
    private var stable: Geometry?
    private var baseline: Geometry?
    private var displayLink: CADisplayLink?
    private var generation = 0
    private var sampleCount = 0
    private var firstTimestamp: CFTimeInterval?
    private var maxima = [String: CGFloat]()
    private var logCount = 0

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "debug.language-layout.frames"
        accessibilityLabel = "Language layout geometry"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update(language: AppLanguage) {
        resolveViews()
        guard let currentLanguage else {
            self.currentLanguage = language
            stable = capture()
            return
        }
        guard currentLanguage != language else {
            if displayLink == nil { stable = capture() }
            return
        }
        stop()
        self.currentLanguage = language
        generation += 1
        sampleCount = 0
        firstTimestamp = nil
        maxima = [:]
        baseline = stable ?? capture()
        publish(complete: false)
        logGeometry("before", geometry: baseline)
        let link = CADisplayLink(target: self, selector: #selector(sample(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { resolveViews(); stable = capture() }
    }

    func stop() { displayLink?.invalidate(); displayLink = nil }

    @objc private func sample(_ link: CADisplayLink) {
        guard let baseline, let current = capture() else { stop(); return }
        if firstTimestamp == nil { firstTimestamp = link.timestamp }
        sampleCount += 1
        record("rootMaxDelta", frameDelta(baseline.root, current.root))
        record("controllerMaxDelta", frameDelta(baseline.controller, current.controller))
        record("safeAreaMaxDelta", max(abs(baseline.safeArea.top - current.safeArea.top), abs(baseline.safeArea.bottom - current.safeArea.bottom)))
        if let before = baseline.bar, let after = current.bar { record("barMaxDelta", frameDelta(before, after)) }
        if let before = baseline.viewport, let after = current.viewport { record("viewportMaxDelta", frameDelta(before, after)) }
        if sampleCount >= 60 || link.timestamp - (firstTimestamp ?? link.timestamp) >= 0.7 {
            stop()
            stable = current
            logGeometry("after", geometry: current)
            publish(complete: true)
        }
    }

    private func record(_ key: String, _ value: CGFloat) { maxima[key] = max(maxima[key] ?? 0, value) }
    private func frameDelta(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(max(abs(a.minX - b.minX), abs(a.minY - b.minY)), max(abs(a.width - b.width), abs(a.height - b.height)))
    }

    private func resolveViews() {
        guard let root = window?.rootViewController else { return }
        let tabs = findTab(in: root)
        let selected = tabs?.selectedViewController ?? root
        // Refresh viewport references when navigation selects a different page.
        if controller !== selected { stable = nil }
        controller = selected
        bar = tabs?.tabBar
        scroll = largestVerticalScroll(in: selected.view)
    }

    private func findTab(in root: UIViewController) -> UITabBarController? {
        if let tabs = root as? UITabBarController { return tabs }
        for child in root.children { if let tabs = findTab(in: child) { return tabs } }
        return nil
    }

    private func largestVerticalScroll(in view: UIView) -> UIScrollView? {
        var pending = [view], visited = 0
        var best: UIScrollView?
        while !pending.isEmpty, visited < 600 {
            let next = pending.removeLast(); visited += 1
            if let candidate = next as? UIScrollView, !candidate.isHidden,
               candidate.bounds.height > 100, candidate.contentSize.height > candidate.bounds.height + 30 {
                if (best?.bounds.height ?? 0) < candidate.bounds.height { best = candidate }
            }
            pending.append(contentsOf: next.subviews)
        }
        return best
    }

    private func capture() -> Geometry? {
        guard let window, let controller, bounds.width > 0, bounds.height > 0 else { return nil }
        return Geometry(root: convert(bounds, to: window), controller: controller.view.convert(controller.view.bounds, to: window),
                        safeArea: controller.view.safeAreaInsets, bar: bar.map { $0.convert($0.bounds, to: window) },
                        viewport: scroll.map { $0.convert($0.bounds, to: window) })
    }

    private func publish(complete: Bool) {
        var values: [String: Any] = maxima.mapValues { Double($0) }
        values["generation"] = generation
        values["language"] = currentLanguage?.rawValue ?? ""
        values["samples"] = sampleCount
        values["complete"] = complete
        values["hasTabBar"] = bar != nil
        if let data = try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys) {
            accessibilityValue = String(decoding: data, as: UTF8.self)
        }
    }

    private func logGeometry(_ phase: String, geometry: Geometry?) {
        guard logCount < 12, let geometry else { return }
        logCount += 1
        NSLog("%@", "LANGUAGE_LAYOUT_GEOMETRY phase=\(phase) generation=\(generation) root=\(geometry.root) controller=\(geometry.controller) safeArea=\(geometry.safeArea) bar=\(String(describing: geometry.bar)) viewport=\(String(describing: geometry.viewport))")
    }
}
#endif
