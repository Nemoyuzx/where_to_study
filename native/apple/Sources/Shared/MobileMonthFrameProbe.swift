#if os(iOS) && DEBUG
import SwiftUI
import UIKit

/// Opt-in local UI-test instrumentation. No telemetry and no per-frame SwiftUI
/// state publications; the final record is read by XCTest via accessibility.
struct MobileMonthFrameProbe: UIViewRepresentable {
    let pageID: String
    var sampleLabel = "Local month frame sample"
    var transitionTrace: MobileMonthTransitionTrace?
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {
        if let transitionTrace {
            view.recordTransition(transitionTrace)
        } else {
            view.record(pageID: pageID, sampleLabel: sampleLabel)
        }
    }
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
        private var transitionTrace: MobileMonthTransitionTrace?

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
        func recordTransition(_ trace: MobileMonthTransitionTrace) {
            transitionTrace = trace
            accessibilityIdentifier = "calendar.mobile.month-transition-probe"
            accessibilityLabel = "Local month transition sample"
            accessibilityValue = trace.serialized
        }
        func record(pageID: String, sampleLabel: String) {
            accessibilityLabel = sampleLabel
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
            if let transitionTrace {
                transitionTrace.samplePresentation()
                let value = transitionTrace.serialized
                if accessibilityValue != value { accessibilityValue = value }
                return
            }
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

/// Records the incoming page's presentation-layer position and displayed status during one
/// generation. XCTest reads the completed record, avoiding accessibility calls
/// inside a short animation window. This file is excluded from Release builds.
@MainActor
final class MobileMonthTransitionTrace {
    struct Sample: Codable {
        let offsetX: Double
        let messages: [String]
    }

    private var generation: UInt64?
    private var samples: [Sample] = []
    private var completed = false
    private var finalDate = ""
    private var finalMessages: [String] = []
    private var serializedResult: String?
    private weak var marker: UIView?
    private var markerGeneration: UInt64?
    private var displayedMessages: [String] = []

    func begin(generation: UInt64) {
        self.generation = generation
        samples.removeAll(keepingCapacity: true)
        completed = false
        finalDate = ""
        finalMessages = []
        serializedResult = nil
        marker = nil
        markerGeneration = nil
    }

    func observe(_ marker: UIView, generation: UInt64?, messages: [String]) {
        self.marker = marker
        markerGeneration = generation
        displayedMessages = messages
    }

    func samplePresentation() {
        guard !completed, generation != nil, markerGeneration == generation,
              let marker, let window = marker.window,
              let presentation = marker.layer.presentation(), samples.count < 1_000 else { return }
        let offsetX = presentation.convert(.zero, to: window.layer.presentation() ?? window.layer).x
        guard offsetX.isFinite else { return }
        samples.append(Sample(offsetX: Double(offsetX), messages: displayedMessages))
    }

    func finish(generation: UInt64, date: String, messages: [String]) {
        guard generation == self.generation else { return }
        finalDate = date
        finalMessages = messages
        completed = true
    }

    var serialized: String {
        guard completed else { return "{\"completed\":false}" }
        if let serializedResult { return serializedResult }
        struct Result: Codable {
            let generation: UInt64?
            let completed: Bool
            let samples: [Sample]
            let finalDate: String
            let finalMessages: [String]
        }
        let result = Result(generation: generation, completed: completed, samples: samples,
                            finalDate: finalDate, finalMessages: finalMessages)
        guard let data = try? JSONEncoder().encode(result) else { return "unavailable" }
        let value = String(decoding: data, as: UTF8.self)
        serializedResult = value
        return value
    }
}

/// Invisible marker inside the actual translated page. It does not replace or
/// drive the production offset/animation; the existing display link observes it.
struct MobileMonthMotionMarker: UIViewRepresentable {
    let trace: MobileMonthTransitionTrace
    let generation: UInt64?
    let messages: [String]

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        trace.observe(view, generation: generation, messages: messages)
    }
}
#endif
