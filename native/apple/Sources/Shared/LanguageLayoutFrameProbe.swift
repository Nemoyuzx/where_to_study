#if DEBUG && os(iOS)
import SwiftUI
import UIKit

@MainActor
private enum LanguageLayoutViewportRegistry {
    static weak var viewport: UIScrollView?
    static weak var probe: LanguageLayoutFrameProbeView?
}

/// Mounted inside Settings' scroll content, so the nearest UIScrollView is
/// the actual page viewport even in a regular-sidebar hosting hierarchy.
struct SettingsLanguageViewportMarker: UIViewRepresentable {
    static func prepareForLanguageSwitch() { LanguageLayoutViewportRegistry.probe?.prepareForLanguageSwitch() }
    func makeUIView(context _: Context) -> SettingsLanguageViewportMarkerView { SettingsLanguageViewportMarkerView() }
    func updateUIView(_ view: SettingsLanguageViewportMarkerView, context _: Context) { view.registerViewport() }
    static func dismantleUIView(_ view: SettingsLanguageViewportMarkerView, coordinator _: ()) { view.unregisterViewport() }
}

final class SettingsLanguageViewportMarkerView: UIView {
    private weak var registered: UIScrollView?
    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func didMoveToSuperview() { super.didMoveToSuperview(); registerViewport() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { unregisterViewport() } else { registerViewport() }
    }
    override func layoutSubviews() { super.layoutSubviews(); registerViewport() }

    func registerViewport() {
        guard window != nil else { return }
        var ancestor = superview
        var depth = 0
        while let view = ancestor, depth < 40 {
            if let scroll = view as? UIScrollView {
                registered = scroll
                LanguageLayoutViewportRegistry.viewport = scroll
                LanguageLayoutViewportRegistry.probe?.refreshViewport()
                return
            }
            ancestor = view.superview; depth += 1
        }
    }

    func unregisterViewport() {
        if LanguageLayoutViewportRegistry.viewport === registered { LanguageLayoutViewportRegistry.viewport = nil }
        registered = nil
        LanguageLayoutViewportRegistry.probe?.refreshViewport()
    }
}

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
    private var prepared: Geometry?
    private var baseline: Geometry?
    private var displayLink: CADisplayLink?
    private var generation = 0
    private var sampleCount = 0
    private var firstTimestamp: CFTimeInterval?
    private var pendingTimestamp: CFTimeInterval?
    private var viewportSamples = 0
    private var baselineViewportReady = false
    private var samplingError: String?
    private var completedSample = false
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
            if displayLink == nil { stable = capture(); publish(complete: completedSample) }
            return
        }
        stop()
        self.currentLanguage = language
        generation += 1
        sampleCount = 0
        firstTimestamp = nil
        pendingTimestamp = nil
        viewportSamples = 0
        samplingError = nil
        maxima = [:]
        baseline = prepared ?? stable ?? capture()
        prepared = nil
        baselineViewportReady = baseline?.viewport != nil
        publish(complete: false)
        logGeometry("before", geometry: baseline)
        let link = CADisplayLink(target: self, selector: #selector(sample(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stop()
            if LanguageLayoutViewportRegistry.probe === self { LanguageLayoutViewportRegistry.probe = nil }
        } else {
            LanguageLayoutViewportRegistry.probe = self
            refreshViewport()
        }
    }

    func stop() { displayLink?.invalidate(); displayLink = nil }

    func refreshViewport() {
        resolveViews()
        if displayLink == nil { stable = capture(); publish(complete: completedSample) }
    }

    func prepareForLanguageSwitch() {
        resolveViews()
        prepared = capture()
    }

    @objc private func sample(_ link: CADisplayLink) {
        if pendingTimestamp == nil { pendingTimestamp = link.timestamp }
        if scroll == nil || scroll?.window !== window { resolveViews() }
        guard let baseline, baseline.viewport != nil, let current = capture(), current.viewport != nil else {
            if link.timestamp - (pendingTimestamp ?? link.timestamp) >= 2 {
                samplingError = "viewport-not-ready"
                stop()
                publish(complete: false)
            }
            return
        }
        if firstTimestamp == nil { firstTimestamp = link.timestamp }
        sampleCount += 1
        record("rootMaxDelta", frameDelta(baseline.root, current.root))
        record("controllerMaxDelta", frameDelta(baseline.controller, current.controller))
        record("safeAreaMaxDelta", max(abs(baseline.safeArea.top - current.safeArea.top), abs(baseline.safeArea.bottom - current.safeArea.bottom)))
        if let before = baseline.bar, let after = current.bar { record("barMaxDelta", frameDelta(before, after)) }
        if let before = baseline.viewport, let after = current.viewport {
            record("viewportMaxDelta", frameDelta(before, after))
            viewportSamples += 1
        }
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
        if let registered = LanguageLayoutViewportRegistry.viewport, registered.window === window,
           registered.bounds.width > 0, registered.bounds.height > 0 {
            scroll = registered
        } else {
            scroll = nil
        }
    }

    private func findTab(in root: UIViewController) -> UITabBarController? {
        if let tabs = root as? UITabBarController { return tabs }
        for child in root.children { if let tabs = findTab(in: child) { return tabs } }
        return nil
    }

    private func capture() -> Geometry? {
        guard let window, let controller, bounds.width > 0, bounds.height > 0 else { return nil }
        return Geometry(root: convert(bounds, to: window), controller: controller.view.convert(controller.view.bounds, to: window),
                        safeArea: controller.view.safeAreaInsets, bar: bar.map { $0.convert($0.bounds, to: window) },
                        viewport: scroll.map { $0.convert($0.bounds, to: window) })
    }

    private func publish(complete: Bool) {
        completedSample = complete
        var values: [String: Any] = maxima.mapValues { Double($0) }
        values["generation"] = generation
        values["language"] = currentLanguage?.rawValue ?? ""
        values["samples"] = sampleCount
        values["complete"] = complete
        values["hasTabBar"] = bar != nil
        values["viewportReady"] = scroll?.window === window && scroll != nil
        values["baselineViewportReady"] = baselineViewportReady
        values["viewportSamples"] = viewportSamples
        if let samplingError { values["samplingError"] = samplingError }
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
