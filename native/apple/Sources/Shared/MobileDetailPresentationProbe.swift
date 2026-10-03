#if os(iOS) && DEBUG
import SwiftUI
import UIKit

@MainActor
enum PrivacyPolicyPresentationTiming {
    private(set) static var requestedAt: TimeInterval?

    static var isEnabled: Bool {
        (AppLaunchConfiguration.isUITesting || AppLaunchConfiguration.isUITestingLive || AppLaunchConfiguration.isReviewDemo)
            && ProcessInfo.processInfo.arguments.contains("--ui-test-privacy-presentation")
    }

    static func begin() {
        guard isEnabled else { return }
        requestedAt = ProcessInfo.processInfo.systemUptime
    }
}

/// Opt-in UI-test observation of the actual UIKit sheet transition, including
/// the first presentation after launch. No application-state writes or timers.
struct MobileDetailPresentationProbe: UIViewControllerRepresentable {
    var metricsLabel = "Calendar detail presentation metrics"
    var requestedAt: @MainActor () -> TimeInterval? = { nil }

    func makeUIViewController(context: Context) -> ProbeController {
        let controller = ProbeController()
        controller.metricsLabel = metricsLabel
        controller.requestedAt = requestedAt
        return controller
    }
    func updateUIViewController(_ controller: ProbeController, context: Context) {
        controller.requestedAt = requestedAt
    }

    final class ProbeController: UIViewController {
        var metricsLabel = "Calendar detail presentation metrics"
        var requestedAt: @MainActor () -> TimeInterval? = { nil }
        private var presentationRequestedAt: TimeInterval?
        private var willAppearAnimated = false
        private var coordinatorAnimated = false
        private var duration: TimeInterval = 0
        private var requestToWillAppear: TimeInterval?

        override func loadView() {
            let label = UILabel()
            label.text = "presentation"
            label.font = .systemFont(ofSize: 6)
            label.textColor = .secondaryLabel
            label.isUserInteractionEnabled = false
            label.isAccessibilityElement = true
            label.accessibilityLabel = metricsLabel
            label.accessibilityValue = "waiting"
            view = label
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            willAppearAnimated = animated
            presentationRequestedAt = requestedAt()
            requestToWillAppear = presentationRequestedAt.map { ProcessInfo.processInfo.systemUptime - $0 }
            var controller: UIViewController? = self
            while let current = controller {
                if let transition = current.transitionCoordinator {
                    coordinatorAnimated = transition.isAnimated
                    duration = transition.transitionDuration
                    break
                }
                controller = current.parent
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            var values: [String: Any] = [
                "willAppearAnimated": willAppearAnimated,
                "didAppearAnimated": animated,
                "coordinatorAnimated": coordinatorAnimated,
                "duration": duration,
            ]
            if let requestedAt = presentationRequestedAt, let requestToWillAppear {
                values["requestToWillAppear"] = requestToWillAppear
                values["requestToDidAppear"] = ProcessInfo.processInfo.systemUptime - requestedAt
            }
            if let data = try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys) {
                view.accessibilityValue = String(decoding: data, as: UTF8.self)
            }
        }
    }
}
#endif
