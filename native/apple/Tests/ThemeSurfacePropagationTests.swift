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
final class ThemeSurfacePropagationTests: XCTestCase {
    func testNativeSegmentKeepsSelectionAndDraftWhileItsSurfaceChangesAndRestores() async throws {
        let state = ThemeSurfaceProbeState()
        let fixture = ThemeSurfaceProbe(state: state)
        #if os(macOS)
        let host = NSHostingView(rootView: fixture)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 360, height: 260),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let control = try XCTUnwrap(findSegment(host))
        let originalSelection = control.selectedSegmentBezelColor
        #else
        let host = UIHostingController(rootView: fixture)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 260))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let control = try XCTUnwrap(findSegment(host.view))
        let originalSelection = control.selectedSegmentTintColor
        let originalBackground = control.backgroundColor
        #endif
        state.selected = 1
        state.draft = "unsaved account input"
        for dark in [false, true] {
            state.dark = dark
            for preset in [ColorThemePreset.ocean, .rose, .custom] {
                state.theme = preset == .custom
                    ? try XCTUnwrap(ColorThemeConfiguration.default.editing(primary: "#FFFFFF", accent: "#000000", selectedDate: "#000000"))
                    : .default.selecting(preset)
                try await Task.sleep(for: .milliseconds(150))
                let surfaces = ThemeSurfacePalette.resolved(primary: state.theme.seeds.primary, dark: dark)
                #if os(macOS)
                host.layoutSubtreeIfNeeded()
                XCTAssertTrue(findSegment(host) === control)
                XCTAssertEqual(control.selectedSegment, 1)
                XCTAssertEqual(control.selectedSegmentBezelColor, NSColor(AppThemeColor(surfaces.elevated).color))
                #else
                host.view.layoutIfNeeded()
                XCTAssertTrue(findSegment(host.view) === control)
                XCTAssertEqual(control.selectedSegmentIndex, 1)
                XCTAssertEqual(control.backgroundColor, UIColor(AppThemeColor(surfaces.surfaceVariant).color))
                XCTAssertEqual(control.selectedSegmentTintColor, UIColor(AppThemeColor(surfaces.elevated).color))
                #endif
                XCTAssertEqual(state.draft, "unsaved account input")
            }
        }
        state.theme = .default
        try await Task.sleep(for: .milliseconds(150))
        #if os(macOS)
        XCTAssertEqual(control.selectedSegmentBezelColor, originalSelection)
        #else
        XCTAssertEqual(control.selectedSegmentTintColor, originalSelection)
        XCTAssertEqual(control.backgroundColor, originalBackground)
        #endif
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
private final class ThemeSurfaceProbeState: ObservableObject {
    @Published var theme = ColorThemeConfiguration.default
    @Published var selected = 0
    @Published var draft = ""
    @Published var dark = false
}

private struct ThemeSurfaceProbe: View {
    @ObservedObject var state: ThemeSurfaceProbeState
    var body: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $state.selected) {
                Text("Day").tag(0)
                Text("Month").tag(1)
            }
            .pickerStyle(.segmented)
            .background(ThemeSegmentedSurface())
            TextField("Account", text: $state.draft)
                .textFieldStyle(ThemeTextFieldStyle())
        }
        .padding(20)
        .frame(width: 360, height: 260)
        .environment(\.appTheme, AppTheme(configuration: state.theme))
        .environment(\.colorScheme, state.dark ? .dark : .light)
    }
}
