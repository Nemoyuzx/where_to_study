import SwiftUI
import XCTest
#if os(macOS)
import AppKit
@testable import WhereToStudyMac
#else
import UIKit
@testable import WhereToStudyiOS
#endif

@MainActor
final class InformationQueryModePickerTests: XCTestCase {
    func testAllQueryDestinationsHaveDistinctAvailableSymbolsAndTranslatedLabels() throws {
        XCTAssertEqual(Set(InformationQueryMode.allCases.map(\.systemImage)).count, 5)
        for mode in InformationQueryMode.allCases {
            #if os(macOS)
            XCTAssertNotNil(NSImage(systemSymbolName: mode.systemImage, accessibilityDescription: nil))
            #else
            XCTAssertNotNil(UIImage(systemName: mode.systemImage))
            #endif
            XCTAssertNotEqual(AppLocalization.string(mode.titleKey, language: .english), mode.titleKey)
        }
    }

    func testTextFitUsesLocalizedWidthAndIncreasesWithLargerText() {
        let chinese = InformationQueryModePicker.minimumTextWidth(language: .simplifiedChinese, fontSize: 13)
        let english = InformationQueryModePicker.minimumTextWidth(language: .english, fontSize: 13)
        XCTAssertGreaterThan(english, chinese)
        XCTAssertLessThan(chinese, 720)
        XCTAssertLessThan(english, 900)
        for language in [AppLanguage.simplifiedChinese, .english] {
            XCTAssertGreaterThan(
                InformationQueryModePicker.minimumTextWidth(language: language, fontSize: 28),
                InformationQueryModePicker.minimumTextWidth(language: language, fontSize: 13)
            )
        }
    }

    func testNativeSegmentsStayInsideBoundsAndKeepSelectionAcrossAppearanceChanges() async throws {
        let state = QueryPickerProbeState()
        let fixture = QueryPickerProbe(state: state)
        #if os(macOS)
        let host = NSHostingView(rootView: fixture)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 980, height: 140),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        #else
        let host = UIHostingController(rootView: fixture)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 980, height: 140)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        #endif
        for language in [AppLanguage.simplifiedChinese, .english] {
            state.language = language
            for size in [DynamicTypeSize.large, .accessibility3] {
                state.size = size
                for dark in [false, true] {
                    state.dark = dark
                    for width in [320.0, 358.0, 720.0, 900.0] {
                        state.width = width
                        state.selection = .assignments
                        #if os(iOS)
                        // Explicitly invalidate the hosted root as UIKit test
                        // windows do not always receive display-link updates.
                        host.rootView = QueryPickerProbe(state: state)
                        #endif
                        try await Task.sleep(for: .milliseconds(100))
                        #if os(macOS)
                        host.layoutSubtreeIfNeeded()
                        let control = try XCTUnwrap(findSegment(host))
                        XCTAssertEqual(control.segmentCount, 5)
                        XCTAssertEqual(control.selectedSegment, 4)
                        XCTAssertLessThanOrEqual(control.bounds.width, width + 1)
                        if width == 320 {
                            for index in 0..<5 { XCTAssertNotNil(control.image(forSegment: index)) }
                        } else if width == 900 && size == .large {
                            for (index, mode) in InformationQueryMode.allCases.enumerated() {
                                XCTAssertEqual(control.label(forSegment: index), AppLocalization.string(mode.titleKey, language: language))
                            }
                        }
                        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        #else
                        host.view.layoutIfNeeded()
                        let control = try XCTUnwrap(findSegment(host.view))
                        XCTAssertEqual(control.numberOfSegments, 5)
                        XCTAssertEqual(control.selectedSegmentIndex, 4)
                        XCTAssertEqual(control.bounds.width, width, accuracy: 1)
                        if UIDevice.current.userInterfaceIdiom == .phone || width == 320 {
                            for index in 0..<5 {
                                let icon = try XCTUnwrap(control.imageForSegment(at: index))
                                XCTAssertLessThanOrEqual(icon.size.height, control.bounds.height)
                                XCTAssertLessThanOrEqual(icon.size.width, control.bounds.width / 5)
                                XCTAssertTrue((control.titleForSegment(at: index) ?? "").isEmpty)
                            }
                        } else if width == 900 && size == .large {
                            for (index, mode) in InformationQueryMode.allCases.enumerated() {
                                XCTAssertEqual(control.titleForSegment(at: index), AppLocalization.string(mode.titleKey, language: language))
                            }
                        }
                        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { context in
                            host.view.layer.render(in: context.cgContext)
                        }
                        let png = try XCTUnwrap(image.pngData())
                        #endif
                        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                        attachment.name = "query-picker-\(language.rawValue)-\(size)-\(dark ? "dark" : "light")-\(Int(width))"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
    }

    #if os(macOS)
    private func findSegment(_ view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl { return control }
        return view.subviews.lazy.compactMap(findSegment).first
    }
    #else
    private func findSegment(_ view: UIView) -> UISegmentedControl? {
        if let control = view as? UISegmentedControl { return control }
        return view.subviews.lazy.compactMap(findSegment).first
    }
    #endif
}

@MainActor
private final class QueryPickerProbeState: ObservableObject {
    @Published var width: CGFloat = 358
    @Published var language = AppLanguage.simplifiedChinese
    @Published var selection = InformationQueryMode.shuttle
    @Published var size = DynamicTypeSize.large
    @Published var dark = false
}

private struct QueryPickerProbe: View {
    @ObservedObject var state: QueryPickerProbeState

    var body: some View {
        InformationQueryModePicker(selection: $state.selection, language: state.language, availableWidth: state.width)
            .frame(width: state.width)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.dynamicTypeSize, state.size)
            .environment(\.colorScheme, state.dark ? .dark : .light)
            .background(state.dark ? Color.black : Color.white)
    }
}
