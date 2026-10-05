#if os(iOS)
import UIKit
typealias CompletionMarkPlatformView = UIView
#elseif os(macOS)
import AppKit
typealias CompletionMarkPlatformView = NSView
#endif

#if os(iOS) || os(macOS)
/// Original, platform-native circle/check stroke animation. No payment brand
/// assets, screenshots, timers or business data are retained by this view.
final class LanguageCompletionMark: CompletionMarkPlatformView {
    private let circle = CAShapeLayer()
    private let check = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if os(macOS)
        wantsLayer = true
        #endif
        for shape in [circle, check] {
            shape.fillColor = nil
            shape.lineWidth = 2.8
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.strokeEnd = 0
            #if os(iOS)
            layer.addSublayer(shape)
            #else
            layer?.addSublayer(shape)
            #endif
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    #if os(iOS)
    override func layoutSubviews() { super.layoutSubviews(); updatePaths() }
    #else
    override func layout() { super.layout(); updatePaths() }
    #endif

    private func updatePaths() {
        let size = min(bounds.width, bounds.height)
        let box = CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        circle.path = CGPath(ellipseIn: box.insetBy(dx: 3, dy: 3), transform: nil)
        let path = CGMutablePath()
        #if os(iOS)
        let tint = UIColor.label.cgColor
        path.move(to: CGPoint(x: box.minX + size * 0.27, y: box.minY + size * 0.51))
        path.addLine(to: CGPoint(x: box.minX + size * 0.44, y: box.minY + size * 0.67))
        path.addLine(to: CGPoint(x: box.minX + size * 0.74, y: box.minY + size * 0.34))
        #else
        let tint = NSColor.labelColor.cgColor
        path.move(to: CGPoint(x: box.minX + size * 0.27, y: box.minY + size * 0.49))
        path.addLine(to: CGPoint(x: box.minX + size * 0.44, y: box.minY + size * 0.33))
        path.addLine(to: CGPoint(x: box.minX + size * 0.74, y: box.minY + size * 0.66))
        #endif
        circle.strokeColor = tint; check.strokeColor = tint; check.path = path
        CATransaction.commit()
    }

    func reset() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for shape in [circle, check] { shape.removeAllAnimations(); shape.strokeEnd = 0 }
        CATransaction.commit()
    }

    func play() {
        #if os(iOS)
        layoutIfNeeded()
        #else
        layoutSubtreeIfNeeded()
        #endif
        updatePaths()
        for (index, shape) in [circle, check].enumerated() {
            shape.removeAllAnimations()
            CATransaction.begin(); CATransaction.setDisableActions(true); shape.strokeEnd = 1; CATransaction.commit()
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = 0; animation.toValue = 1
            animation.duration = index == 0 ? 0.18 : 0.24
            animation.beginTime = CACurrentMediaTime() + (index == 0 ? 0 : 0.12)
            animation.fillMode = .backwards
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shape.add(animation, forKey: "language-completion-stroke")
        }
    }
}
#endif
