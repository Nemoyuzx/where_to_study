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
    static let layoutTimeout: TimeInterval = 12
    static let completionDuration: TimeInterval = 0.18

    private weak var host: UIView?
    private weak var navigationHost: CompactTabLanguageLayoutView?
    private var cover: UIVisualEffectView?
    private var animator: UIViewPropertyAnimator?
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
    private weak var progressLabel: UILabel?
    private weak var completionImage: UIImageView?
    private var revision = 0
    private(set) var isTransitioning = false

    func attach(to host: UIView) { self.host = host }
    func attachNavigation(to host: CompactTabLanguageLayoutView) { navigationHost = host }
    func detachNavigation(from host: CompactTabLanguageLayoutView) {
        if navigationHost === host { navigationHost = nil; layoutGate.reset() }
    }

    func detach(from host: UIView) {
        guard self.host === host else { return }
        finishImmediately()
        self.host = nil
    }

    func request(current: AppLanguage, target: AppLanguage, label: String,
                 reduceMotion: Bool, completionReady: @escaping () -> Bool = { true },
                 completionFailed: @escaping () -> Bool = { false },
                 completionGeometry: @escaping () -> [Double] = { [] }, change: @escaping () -> Void) {
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
        revision &+= 1
        let currentRevision = revision
        animator?.stopAnimation(true)
        animator = nil
        pendingReveal?.cancel()
        pendingReveal = nil
        pendingChange = change
        self.targetLocaleIdentifier = targetLocaleIdentifier
        self.completionReady = completionReady
        self.completionFailed = completionFailed
        self.completionGeometry = completionGeometry
        self.settledLocaleIdentifier = nil
        layoutGate.reset()
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
            installProgress(on: effectView)
        }
        progressLabel?.text = "Switching…"
        progressLabel?.isHidden = false
        completionImage?.isHidden = true
        effectView.accessibilityLabel = label
        effectView.alpha = 1
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
            self.applyPendingChange()
            self.readinessDeadline = ProcessInfo.processInfo.systemUptime + Self.layoutTimeout
            self.scheduleReadinessProbe(revision: currentRevision)
        }
        covering.startAnimation()
        effectView.accessibilityValue = "covering"
    }

    func layoutDidSettle(localeIdentifier: String) {
        guard waitingForLayout, targetLocaleIdentifier == localeIdentifier,
              pendingChange == nil, cover != nil else { return }
        settledLocaleIdentifier = localeIdentifier
    }

    private func scheduleReadinessProbe(revision currentRevision: Int, delay: TimeInterval = 1.0 / 60.0) {
        pendingReveal?.cancel()
        let probe = DispatchWorkItem { [weak self] in
            guard let self, self.revision == currentRevision, let window = self.host?.window,
                  let cover = self.cover, cover.superview === window else { return }
            self.pendingReveal = nil
            if self.completionFailed() { self.finishImmediately(); return }
            if ProcessInfo.processInfo.systemUptime >= self.readinessDeadline {
                // Emergency cancellation is not a successful language change.
                self.finishImmediately(); return
            }
            guard self.completionReady() else {
                self.layoutGate.reset()
                self.scheduleReadinessProbe(revision: currentRevision, delay: 0.05)
                return
            }
            if let target = self.targetLocaleIdentifier, let navigation = self.navigationHost,
               !navigation.translationIsReady(for: target) {
                self.layoutGate.reset()
                self.scheduleReadinessProbe(revision: currentRevision, delay: 0.05)
                return
            }
            window.layoutIfNeeded()
            let insets = window.safeAreaInsets
            let geometry = [Double(window.bounds.width), Double(window.bounds.height),
                            Double(insets.top), Double(insets.bottom)] + self.completionGeometry() +
                (self.navigationHost?.languageCompletionGeometry ?? [])
            let localeMatches = self.targetLocaleIdentifier == nil ||
                self.settledLocaleIdentifier == self.targetLocaleIdentifier
            if self.layoutGate.observe(tasksComplete: true, localeMatches: localeMatches, geometry: geometry) {
                self.waitingForLayout = false
                self.progressLabel?.isHidden = true
                self.completionImage?.isHidden = false
                cover.accessibilityValue = "completed"
                self.scheduleReveal(revision: currentRevision, delay: Self.completionDuration)
            } else { self.scheduleReadinessProbe(revision: currentRevision) }
        }
        pendingReveal = probe
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: probe)
    }

    private func installProgress(on effect: UIVisualEffectView) {
        let label = UILabel()
        label.text = "Switching…"
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        image.tintColor = .label
        image.isHidden = true
        image.translatesAutoresizingMaskIntoConstraints = false
        effect.contentView.addSubview(label)
        effect.contentView.addSubview(image)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: effect.contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: effect.contentView.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: effect.contentView.leadingAnchor, constant: 20),
            image.centerXAnchor.constraint(equalTo: effect.contentView.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: effect.contentView.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 36), image.heightAnchor.constraint(equalToConstant: 36)
        ])
        progressLabel = label; completionImage = image
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
            cover.alpha = 0
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
        settledLocaleIdentifier = nil
        completionReady = { true }
        completionFailed = { false }
        completionGeometry = { [] }
        progressLabel = nil; completionImage = nil
        layoutGate.reset()
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
