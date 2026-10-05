#if os(macOS)
import AppKit
import SwiftUI

/// Native material for this window's app content. No image of user data is
/// captured, and the stable Root/session/controller hierarchy stays mounted.
@MainActor
final class LanguageChangeTransition {
    static let coverDuration: TimeInterval = 0.12
    static let layoutDelay: TimeInterval = 0.06
    static let revealDuration: TimeInterval = 0.22
    static let layoutTimeout: TimeInterval = 12
    static let completionDuration: TimeInterval = 0.18

    // An explicitly requested DEBUG/demo slow-motion mode makes the native
    // material observable without screenshot capture inside the application.
    // Release behavior and ordinary tests always retain the normal durations.
    private static var previewScale: Double {
        #if DEBUG
        if AppLaunchConfiguration.isReviewDemo &&
            ProcessInfo.processInfo.arguments.contains("--ui-testing-language-material-preview") { return 6 }
        #endif
        return 1
    }

    private weak var host: NSView?
    private var cover: LanguageTransitionEffectView?
    private var pendingReveal: DispatchWorkItem?
    private var pendingChange: (() -> Void)?
    private var targetLocaleIdentifier: String?
    private var waitingForLayout = false
    private var settledLocaleIdentifier: String?
    private var completionReady: () -> Bool = { true }
    private var completionFailed: () -> Bool = { false }
    private var completionGeometry: () -> [Double] = { [] }
    private var layoutGate = LanguageTransitionLayoutGate()
    private var readinessDeadline: TimeInterval = 0
    private var revision = 0
    private(set) var isTransitioning = false

    func attach(to host: NSView) { self.host = host; trace("attached") }

    private func trace(_ phase: String) {
        #if DEBUG
        if AppLaunchConfiguration.isReviewDemo &&
            ProcessInfo.processInfo.arguments.contains("--ui-testing-language-material-preview") {
            NSLog("WTSMacLanguage phase=%@ host=%d window=%d visible=%d transitioning=%d", phase,
                  host != nil ? 1 : 0, host?.window != nil ? 1 : 0,
                  host?.window?.isVisible == true ? 1 : 0, isTransitioning ? 1 : 0)
        }
        #endif
    }

    func detach(from host: NSView) {
        guard self.host === host else { return }
        finishImmediately()
        self.host = nil
    }

    func request(current: AppLanguage, target: AppLanguage, label: String,
                 reduceMotion: Bool, completionReady: @escaping () -> Bool = { true },
                 completionFailed: @escaping () -> Bool = { false },
                 completionGeometry: @escaping () -> [Double] = { [] }, change: @escaping () -> Void) {
        guard current != target else {
            cancelAnimationAndReveal()
            pendingChange = nil
            removeCover()
            return
        }
        perform(label: label, reduceMotion: reduceMotion,
                targetLocaleIdentifier: target.locale.identifier, completionReady: completionReady,
                completionFailed: completionFailed, completionGeometry: completionGeometry, change: change)
    }

    func perform(label: String, reduceMotion: Bool, change: @escaping () -> Void) {
        perform(label: label, reduceMotion: reduceMotion, targetLocaleIdentifier: nil, change: change)
    }

    private func perform(label: String, reduceMotion: Bool, targetLocaleIdentifier: String?,
                         completionReady: @escaping () -> Bool = { true },
                         completionFailed: @escaping () -> Bool = { false },
                         completionGeometry: @escaping () -> [Double] = { [] },
                         change: @escaping () -> Void) {
        cancelAnimationAndReveal()
        let currentRevision = revision
        pendingChange = change
        self.targetLocaleIdentifier = targetLocaleIdentifier
        self.completionReady = completionReady
        self.completionFailed = completionFailed
        self.completionGeometry = completionGeometry
        settledLocaleIdentifier = nil
        layoutGate.reset()
        waitingForLayout = false
        trace("requested")
        guard !reduceMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let window = host?.window, window.isVisible, let content = window.contentView else {
            finishImmediately()
            return
        }

        let effectView: LanguageTransitionEffectView
        if let cover, cover.superview === content {
            effectView = cover
        } else {
            cover?.removeFromSuperview()
            effectView = LanguageTransitionEffectView(frame: content.bounds)
            effectView.autoresizingMask = [.width, .height]
            effectView.alphaValue = 0
            content.addSubview(effectView, positioned: .above, relativeTo: nil)
            cover = effectView
        }
        effectView.setAccessibilityLabel(label)
        effectView.showProgress()
        effectView.setAccessibilityValue("covering")
        isTransitioning = true
        trace("covering")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.coverDuration * Self.previewScale
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            effectView.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.revision == currentRevision, self.cover != nil else { return }
                self.cover?.setAccessibilityValue("covered")
                self.waitingForLayout = self.targetLocaleIdentifier != nil
                self.applyPendingChange()
                self.host?.needsLayout = true
                self.readinessDeadline = ProcessInfo.processInfo.systemUptime + Self.layoutTimeout
                self.scheduleReadinessProbe(revision: currentRevision)
            }
        }
    }

    func layoutDidSettle(localeIdentifier: String) {
        trace("layout")
        guard waitingForLayout, targetLocaleIdentifier == localeIdentifier,
              pendingChange == nil, cover != nil else { return }
        settledLocaleIdentifier = localeIdentifier
    }

    private func scheduleReadinessProbe(revision currentRevision: Int, delay: TimeInterval = 1.0 / 60.0) {
        pendingReveal?.cancel()
        let probe = DispatchWorkItem { [weak self] in
            guard let self, self.revision == currentRevision, let host = self.host,
                  let content = host.window?.contentView, let cover = self.cover else { return }
            self.pendingReveal = nil
            if self.completionFailed() { self.finishImmediately(); return }
            if ProcessInfo.processInfo.systemUptime >= self.readinessDeadline {
                self.finishImmediately(); return
            }
            guard self.completionReady() else {
                self.layoutGate.reset()
                self.scheduleReadinessProbe(revision: currentRevision, delay: 0.05)
                return
            }
            content.layoutSubtreeIfNeeded()
            let geometry = [Double(content.bounds.width), Double(content.bounds.height)] + self.completionGeometry()
            let matches = self.targetLocaleIdentifier == nil || self.settledLocaleIdentifier == self.targetLocaleIdentifier
            if self.layoutGate.observe(tasksComplete: true, localeMatches: matches, geometry: geometry) {
                self.waitingForLayout = false
                cover.showCompletion()
                cover.setAccessibilityValue("completed")
                self.scheduleReveal(revision: currentRevision)
            } else { self.scheduleReadinessProbe(revision: currentRevision) }
        }
        pendingReveal = probe
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: probe)
    }

    private func scheduleReveal(revision currentRevision: Int) {
        pendingReveal?.cancel()
        let reveal = DispatchWorkItem { [weak self] in
            guard let self, self.revision == currentRevision, let cover = self.cover else { return }
            self.pendingReveal = nil
            cover.setAccessibilityValue("revealing")
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.revealDuration * Self.previewScale
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                cover.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.revision == currentRevision else { return }
                    self.removeCover()
                }
            }
        }
        pendingReveal = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.completionDuration * Self.previewScale, execute: reveal)
    }

    func finishImmediately() {
        trace("finish")
        cancelAnimationAndReveal()
        applyPendingChange()
        removeCover()
    }

    private func cancelAnimationAndReveal() {
        revision &+= 1
        pendingReveal?.cancel()
        pendingReveal = nil
        if let cover {
            let alpha = cover.layer?.presentation()?.opacity ?? Float(cover.alphaValue)
            cover.layer?.removeAllAnimations()
            cover.alphaValue = CGFloat(alpha)
        }
    }

    private func applyPendingChange() {
        let change = pendingChange
        pendingChange = nil
        change?()
    }

    private func removeCover() {
        cover?.layer?.removeAllAnimations()
        cover?.removeFromSuperview()
        cover = nil
        targetLocaleIdentifier = nil
        waitingForLayout = false
        settledLocaleIdentifier = nil
        completionReady = { true }
        completionFailed = { false }
        completionGeometry = { [] }
        layoutGate.reset()
        isTransitioning = false
    }
}

private final class LanguageTransitionEffectView: NSVisualEffectView {
    private let progressLabel = NSTextField(labelWithString: "Switching…")
    private let completionImage = NSImageView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        material = .fullScreenUI
        blendingMode = .withinWindow
        state = .active
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityModal(true)
        setAccessibilityIdentifier("overlay.language-transition")
        progressLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        progressLabel.textColor = .labelColor
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        completionImage.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        completionImage.contentTintColor = .labelColor
        completionImage.translatesAutoresizingMaskIntoConstraints = false
        completionImage.isHidden = true
        addSubview(progressLabel); addSubview(completionImage)
        NSLayoutConstraint.activate([
            progressLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            completionImage.centerXAnchor.constraint(equalTo: centerXAnchor),
            completionImage.centerYAnchor.constraint(equalTo: centerYAnchor),
            completionImage.widthAnchor.constraint(equalToConstant: 36), completionImage.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
    func showProgress() { progressLabel.isHidden = false; completionImage.isHidden = true }
    func showCompletion() { progressLabel.isHidden = true; completionImage.isHidden = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override func mouseDown(with _: NSEvent) {}
    override func scrollWheel(with _: NSEvent) {}
}

struct LanguageChangeTransitionHost: NSViewRepresentable {
    let transition: LanguageChangeTransition
    @Environment(\.locale) private var locale
    func makeNSView(context _: Context) -> LanguageChangeTransitionHostView { LanguageChangeTransitionHostView(transition: transition) }
    func updateNSView(_ view: LanguageChangeTransitionHostView, context _: Context) {
        view.localeIdentifier = locale.identifier
        view.needsLayout = true
    }
    static func dismantleNSView(_ view: LanguageChangeTransitionHostView, coordinator _: ()) { view.transition.detach(from: view) }
}

final class LanguageChangeTransitionHostView: NSView {
    let transition: LanguageChangeTransition
    var localeIdentifier = ""
    private var layoutCheckpoint: DispatchWorkItem?
    private var layoutRevision = 0
    init(transition: LanguageChangeTransition) {
        self.transition = transition
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            transition.attach(to: self)
            for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification, NSWindow.didResignKeyNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(windowDeactivated), name: name, object: window)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(windowDeactivated), name: NSApplication.didResignActiveNotification, object: nil)
        } else {
            layoutRevision &+= 1
            layoutCheckpoint?.cancel()
            layoutCheckpoint = nil
            transition.detach(from: self)
        }
    }
    override func hitTest(_: NSPoint) -> NSView? { nil }
    @objc private func windowDeactivated(_: Notification) { transition.finishImmediately() }
    override func layout() {
        super.layout()
        guard transition.isTransitioning, layoutCheckpoint == nil else { return }
        layoutRevision &+= 1
        let revision = layoutRevision
        let checkpoint = DispatchWorkItem { [weak self] in
            guard let self, self.layoutRevision == revision, let content = self.window?.contentView else { return }
            self.layoutCheckpoint = nil
            content.layoutSubtreeIfNeeded()
            self.transition.layoutDidSettle(localeIdentifier: self.localeIdentifier)
        }
        layoutCheckpoint = checkpoint
        DispatchQueue.main.async(execute: checkpoint)
    }
}
#endif
