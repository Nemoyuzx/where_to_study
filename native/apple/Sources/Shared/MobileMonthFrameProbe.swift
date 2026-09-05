#if os(iOS) && DEBUG
import SwiftUI
import UIKit

/// Opt-in local UI-test instrumentation. No telemetry and no per-frame SwiftUI
/// state publications; the final record is read by XCTest via accessibility.
struct MobileMonthFrameProbe: UIViewRepresentable {
    let pageID: String
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) { view.record(pageID: pageID) }
    static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.stop() }

    final class ProbeView: UILabel {
        private var displayLink: CADisplayLink?
        private var pageID = ""
        private var started: CFTimeInterval = 0
        private var previousTick: CFTimeInterval = 0
        private var recording = false
        private var frames = 0
        private var delayedFrames = 0
        private var maximumGap: Double = 0
        private var firstFrameDelay: Double = 0
        private var serial = 0
        private var sampleTimes: [Double] = []
        private var sampleGaps: [Double] = []
        private var history: [[String: Any]] = []

        init() {
            super.init(frame: .zero)
            text = "frames"
            font = .systemFont(ofSize: 6)
            textColor = .secondaryLabel
            isUserInteractionEnabled = false
            isAccessibilityElement = true
            accessibilityIdentifier = "calendar.mobile.month-frame-probe"
            accessibilityLabel = "Local month frame sample"
            accessibilityValue = "waiting"
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func stop() { displayLink?.invalidate(); displayLink = nil }
        func record(pageID: String) {
            guard self.pageID != pageID else { return }
            self.pageID = pageID
            started = CACurrentMediaTime()
            frames = 0
            delayedFrames = 0
            maximumGap = 0
            firstFrameDelay = 0
            recording = true
            sampleTimes.removeAll(keepingCapacity: true)
            sampleGaps.removeAll(keepingCapacity: true)
            serial += 1
        }
        @objc private func tick(_ link: CADisplayLink) {
            let now = CACurrentMediaTime()
            defer { previousTick = now }
            guard recording else { return }
            let expected = max(link.targetTimestamp - link.timestamp, 1.0 / 120)
            if frames == 0 { firstFrameDelay = (now - started) * 1000 }
            if previousTick > 0 {
                let gap = now - previousTick
                maximumGap = max(maximumGap, gap * 1000)
                if gap > expected * 1.5 { delayedFrames += 1 }
            }
            frames += 1
            sampleTimes.append((now - started) * 1000)
            sampleGaps.append(previousTick > 0 ? (now - previousTick) * 1000 : 0)
            if now - started >= 0.55 {
                recording = false
                let record: [String: Any] = [
                    "page": pageID, "serial": serial, "frames": frames,
                    "delayedFrames": delayedFrames, "maxGapMs": maximumGap,
                    "firstFrameDelayMs": firstFrameDelay,
                    "timesMs": sampleTimes, "gapsMs": sampleGaps
                ]
                history.append(record)
                if history.count > 16 { history.removeFirst() }
                var output = record
                output["history"] = history
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .sortedKeys) {
                    accessibilityValue = String(decoding: data, as: UTF8.self)
                }
            }
        }
    }
}
#endif
