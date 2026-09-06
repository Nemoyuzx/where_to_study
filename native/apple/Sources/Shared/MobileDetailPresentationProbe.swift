#if os(iOS) && DEBUG
import SwiftUI
import UIKit

/// Opt-in UI-test observation of the actual UIKit sheet transition, including
/// the first presentation after launch. No application-state writes or timers.
struct MobileDetailPresentationProbe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ProbeController { ProbeController() }
    func updateUIViewController(_ controller: ProbeController, context: Context) {}

    final class ProbeController: UIViewController {
        private var willAppearAnimated = false
        private var coordinatorAnimated = false
        private var duration: TimeInterval = 0

        override func loadView() {
            let label = UILabel()
            label.text = "presentation"
            label.font = .systemFont(ofSize: 6)
            label.textColor = .secondaryLabel
            label.isUserInteractionEnabled = false
            label.isAccessibilityElement = true
            label.accessibilityLabel = "Calendar detail presentation metrics"
            label.accessibilityValue = "waiting"
            view = label
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            willAppearAnimated = animated
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
            let values: [String: Any] = [
                "willAppearAnimated": willAppearAnimated,
                "didAppearAnimated": animated,
                "coordinatorAnimated": coordinatorAnimated,
                "duration": duration,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys) {
                view.accessibilityValue = String(decoding: data, as: UTF8.self)
            }
        }
    }
}
#endif
