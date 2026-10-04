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
    static let layoutTimeout: TimeInterval = 1

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
                 reduceMotion: Bool, change: @escaping () -> Void) {
        guard current != target else {
            cancelAnimationAndReveal()
            pendingChange = nil
            removeCover()
            return
        }
        perform(label: label, reduceMotion: reduceMotion,
                targetLocaleIdentifier: target.locale.identifier, change: change)
    }

    func perform(label: String, reduceMotion: Bool, change: @escaping () -> Void) {
        perform(label: label, reduceMotion: reduceMotion, targetLocaleIdentifier: nil, change: change)
    }

    private func perform(label: String, reduceMotion: Bool, targetLocaleIdentifier: String?,
                         change: @escaping () -> Void) {
        cancelAnimationAndReveal()
        let currentRevision = revision
        pendingChange = change
        self.targetLocaleIdentifier = targetLocaleIdentifier
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
                if self.waitingForLayout { self.scheduleLayoutTimeout(revision: currentRevision) }
                else { self.scheduleReveal(revision: currentRevision) }
                self.applyPendingChange()
                self.host?.needsLayout = true
            }
        }
    }

    func layoutDidSettle(localeIdentifier: String) {
        trace("layout")
        guard waitingForLayout, targetLocaleIdentifier == localeIdentifier,
              pendingChange == nil, cover != nil else { return }
        waitingForLayout = false
        scheduleReveal(revision: revision)
    }

    private func scheduleLayoutTimeout(revision currentRevision: Int) {
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.revision == currentRevision, self.waitingForLayout else { return }
            // Failure cleanup is not a claim that translated layout is ready.
            self.finishImmediately()
        }
        pendingReveal = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.layoutTimeout, execute: timeout)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.layoutDelay * Self.previewScale, execute: reveal)
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
        isTransitioning = false
    }
}

private final class LanguageTransitionEffectView: NSVisualEffectView {
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
    }
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
