#if os(iOS)
import SwiftUI
import UIKit

/// A short, window-level material transition. It does not snapshot private
/// content, remount navigation, or animate the locale's layout changes.
@MainActor
final class LanguageChangeTransition {
    static let coverDuration: TimeInterval = 0.12
    static let layoutDelay: TimeInterval = 0.06
    static let revealDuration: TimeInterval = 0.22

    private weak var host: UIView?
    private var cover: UIVisualEffectView?
    private var animator: UIViewPropertyAnimator?
    private var pendingReveal: DispatchWorkItem?
    private var pendingChange: (() -> Void)?
    private var targetLocaleIdentifier: String?
    private var waitingForLayout = false
    private var revision = 0
    private(set) var isTransitioning = false

    func attach(to host: UIView) { self.host = host }

    func detach(from host: UIView) {
        guard self.host === host else { return }
        finishImmediately()
        self.host = nil
    }

    func request(current: AppLanguage, target: AppLanguage, label: String,
                 reduceMotion: Bool, change: @escaping () -> Void) {
        guard current != target else {
            // A reversal to the still-current locale is meaningful while the
            // earlier selection is waiting underneath the covering material.
            revision &+= 1
            animator?.stopAnimation(true)
            animator = nil
            pendingReveal?.cancel()
            pendingReveal = nil
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
        revision &+= 1
        let currentRevision = revision
        animator?.stopAnimation(true)
        animator = nil
        pendingReveal?.cancel()
        pendingReveal = nil
        pendingChange = change
        self.targetLocaleIdentifier = targetLocaleIdentifier
        waitingForLayout = false

        guard !reduceMotion, !UIAccessibility.isReduceMotionEnabled,
              let window = host?.window, !window.isHidden else {
            finishImmediately()
            return
        }

        let effectView: UIVisualEffectView
        if let cover, cover.superview === window {
            effectView = cover
        } else {
            cover?.removeFromSuperview()
            effectView = UIVisualEffectView(effect: nil)
            effectView.frame = window.bounds
            effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            effectView.isAccessibilityElement = true
            effectView.accessibilityViewIsModal = true
            effectView.accessibilityIdentifier = "overlay.language-transition"
            window.addSubview(effectView)
            cover = effectView
        }
        effectView.accessibilityLabel = label
        effectView.isUserInteractionEnabled = true
        window.bringSubviewToFront(effectView)
        isTransitioning = true

        let covering = UIViewPropertyAnimator(duration: Self.coverDuration, curve: .easeOut) {
            effectView.effect = UIBlurEffect(style: .systemThinMaterial)
        }
        animator = covering
        covering.addCompletion { [weak self] position in
            guard let self, self.revision == currentRevision, position == .end else { return }
            effectView.accessibilityValue = "covered"
            self.waitingForLayout = self.targetLocaleIdentifier != nil
            // A finite fallback also handles an unchanged resolved locale or
            // a host removed before SwiftUI delivers a new layout callback.
            self.scheduleReveal(revision: currentRevision,
                                delay: self.waitingForLayout ? 0.25 : Self.layoutDelay)
            self.applyPendingChange()
        }
        covering.startAnimation()
        effectView.accessibilityValue = "covering"
    }

    func layoutDidSettle(localeIdentifier: String) {
        guard waitingForLayout, targetLocaleIdentifier == localeIdentifier,
              pendingChange == nil, cover != nil else { return }
        waitingForLayout = false
        scheduleReveal(revision: revision, delay: Self.layoutDelay)
    }

    private func scheduleReveal(revision currentRevision: Int, delay: TimeInterval) {
        pendingReveal?.cancel()
        let reveal = DispatchWorkItem { [weak self] in
            guard let self, self.revision == currentRevision else { return }
            self.pendingReveal = nil
            self.waitingForLayout = false
            self.reveal(revision: currentRevision)
        }
        pendingReveal = reveal
        // Defer animator creation, not just its start: effect=nil otherwise
        // becomes the model value before the covered locale finishes layout.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: reveal)
    }

    // Backgrounding, navigation away, Reduce Motion and host teardown must
    // never strand a full-screen blocker or discard the selected language.
    func finishImmediately() {
        revision &+= 1
        animator?.stopAnimation(true)
        animator = nil
        pendingReveal?.cancel()
        pendingReveal = nil
        applyPendingChange()
        removeCover()
    }

    private func applyPendingChange() {
        let change = pendingChange
        pendingChange = nil
        change?()
    }

    private func reveal(revision currentRevision: Int) {
        guard let cover else { finishImmediately(); return }
        let revealing = UIViewPropertyAnimator(duration: Self.revealDuration, curve: .easeInOut) {
            cover.effect = nil
            cover.accessibilityValue = "revealing"
        }
        animator = revealing
        revealing.addCompletion { [weak self] _ in
            guard let self, self.revision == currentRevision else { return }
            self.animator = nil
            self.removeCover()
        }
        // Let SwiftUI and the native bar settle underneath the material;
        // only the material is animated, not text or viewport geometry.
        revealing.startAnimation()
    }

    private func removeCover() {
        cover?.removeFromSuperview()
        cover = nil
        targetLocaleIdentifier = nil
        waitingForLayout = false
        isTransitioning = false
    }
}

struct LanguageChangeTransitionHost: UIViewRepresentable {
    let transition: LanguageChangeTransition
    @Environment(\.locale) private var locale
    func makeUIView(context _: Context) -> LanguageChangeTransitionHostView {
        LanguageChangeTransitionHostView(transition: transition)
    }
    func updateUIView(_ view: LanguageChangeTransitionHostView, context _: Context) {
        view.localeIdentifier = locale.identifier
        view.setNeedsLayout()
    }
    static func dismantleUIView(_ view: LanguageChangeTransitionHostView, coordinator _: ()) {
        view.transition.detach(from: view)
    }
}

final class LanguageChangeTransitionHostView: UIView {
    let transition: LanguageChangeTransition
    var localeIdentifier = ""
    init(transition: LanguageChangeTransition) {
        self.transition = transition
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { transition.detach(from: self) }
        else { transition.attach(to: self) }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        transition.layoutDidSettle(localeIdentifier: localeIdentifier)
    }
}
#endif
