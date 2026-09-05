#if os(iOS)
import SwiftUI
import UIKit

/// A mounted page acknowledges actual UIKit layout; Task.yield alone does not
/// establish that the incoming SwiftUI grid has a viewport and has been laid out.
struct MobileMonthPageLayout: UIViewRepresentable {
    let month: Date
    let generation: String
    let ready: (Date, String) -> Void

    func makeUIView(context: Context) -> LayoutView { LayoutView() }

    func updateUIView(_ view: LayoutView, context: Context) {
        view.configure(month: month, generation: generation, ready: ready)
    }

    static func dismantleUIView(_ view: LayoutView, coordinator: ()) { view.ready = nil }

    final class LayoutView: UIView {
        var ready: ((Date, String) -> Void)?
        private var month: Date?
        private var generation = ""
        private var reported = false

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            accessibilityElementsHidden = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func configure(month: Date, generation: String, ready: @escaping (Date, String) -> Void) {
            if self.month != month || self.generation != generation { reported = false }
            self.month = month
            self.generation = generation
            self.ready = ready
            setNeedsLayout()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            setNeedsLayout()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            reportIfReady()
        }

        private func reportIfReady() {
            guard !reported, window != nil, bounds.width > 0, bounds.height > 0,
                  let month, ready != nil else { return }
            reported = true
            let generation = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.month == month, self.generation == generation else { return }
                self.ready?(month, generation)
            }
        }
    }
}
#endif
