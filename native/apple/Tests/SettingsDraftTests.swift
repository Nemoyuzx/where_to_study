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
final class SettingsDraftTests: XCTestCase {
    func testReminderReappearancePreservesUncommittedRowsAndValidation() {
        let draft = SettingsPreClassReminderDraft()
        draft.synchronize(with: [10])
        draft.minuteFields = ["37", ""]
        draft.validationFailed = true
        draft.synchronize(with: [10])
        XCTAssertEqual(draft.minuteFields, ["37", ""])
        XCTAssertTrue(draft.validationFailed)
        draft.synchronize(with: [20, 30])
        XCTAssertEqual(draft.minuteFields, ["20", "30"])
        XCTAssertFalse(draft.validationFailed)
    }

    func testColorReappearancePreservesAnInvalidUncommittedDraft() throws {
        let draft = SettingsColorThemeDraft()
        let saved = ColorThemeConfiguration.default.custom
        draft.synchronize(with: saved)
        draft.primary = "#GGGGGG"
        draft.accent = "#123456"
        draft.hasEdited = true
        draft.synchronize(with: saved)
        XCTAssertEqual(draft.primary, "#GGGGGG")
        XCTAssertEqual(draft.accent, "#123456")
        XCTAssertTrue(draft.hasEdited)
        draft.reset(to: saved)
        XCTAssertEqual(draft.primary, saved.primary.hex)
        XCTAssertFalse(draft.hasEdited)
        draft.primary = "#BADBAD"
        let changed = try XCTUnwrap(ColorThemeConfiguration.default.editing(primary: "#123456", accent: "#654321", selectedDate: "#246810"))
        draft.synchronize(with: changed.custom)
        XCTAssertEqual(draft.primary, "#123456")
        XCTAssertEqual(draft.accent, "#654321")
        XCTAssertFalse(draft.hasEdited)
    }

    func testSheetHostChangesDoNotRebuildItsStableOwner() async throws {
        let state = SettingsPresentationOwnerProbeState()
        let fixture = SettingsPresentationOwnerProbe(state: state)
        #if os(macOS)
        let host = NSHostingView(rootView: fixture)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 680, height: 720),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        #else
        let host = UIHostingController(rootView: fixture)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 680, height: 720))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        #endif
        try await Task.sleep(for: .milliseconds(150))
        let initialBuilds = state.bodyBuilds
        XCTAssertGreaterThan(initialBuilds, 0)
        state.presentation.isPresented = true
        try await Task.sleep(for: .milliseconds(500))
        #if os(macOS)
        XCTAssertNotNil(window.attachedSheet)
        #else
        XCTAssertNotNil(host.presentedViewController)
        #endif
        XCTAssertEqual(state.bodyBuilds, initialBuilds)
        state.presentation.isPresented = false
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(state.bodyBuilds, initialBuilds)
    }

    func testEditorsKeepDraftsWhenAdaptiveBranchesRecreateThem() async throws {
        XCTAssertEqual(AdaptiveLayoutPolicy.contentColumnCount(width: 390), 1)
        XCTAssertEqual(AdaptiveLayoutPolicy.contentColumnCount(width: 844), 2)
        let suite = "SettingsDraftTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(runtimeMode: .sample(review: true), defaults: defaults,
                             themeWidgetDefaults: nil, reloadWidgetTheme: {})
        let state = SettingsDraftBranchProbeState()
        state.reminder.synchronize(with: model.preClassNotificationOffsets)
        state.colors.synchronize(with: model.colorTheme.custom)
        let fixture = SettingsDraftBranchProbe(state: state)
            .environmentObject(model)
            .environmentObject(CalendarDeadlineStore())
        #if os(macOS)
        // The shipping Mac window has a 960-point minimum. This smaller test
        // fixture exercises the shared adaptive branches, not a Mac rotation.
        let host = NSHostingView(rootView: fixture)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        #else
        let host = UIHostingController(rootView: fixture)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 900))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        #endif
        try await Task.sleep(for: .milliseconds(150))
        let initialAppearances = state.editorAppearances
        XCTAssertGreaterThan(initialAppearances, 0)
        state.reminder.minuteFields = ["37", "22"]
        state.colors.primary = "#123456"
        state.colors.hasEdited = true
        for width in [844.0, 390.0] {
            state.width = width
            try await Task.sleep(for: .milliseconds(150))
            #if os(macOS)
            host.layoutSubtreeIfNeeded()
            #else
            host.view.layoutIfNeeded()
            #endif
            XCTAssertEqual(state.reminder.minuteFields, ["37", "22"])
            XCTAssertEqual(state.colors.primary, "#123456")
            XCTAssertTrue(state.colors.hasEdited)
        }
        XCTAssertGreaterThan(state.editorAppearances, initialAppearances, "The regression must recreate the editing subtrees")
        XCTAssertEqual(model.preClassNotificationOffsets, [10])
        XCTAssertEqual(model.colorTheme, .default, "Uncommitted fields must never change the saved theme")
    }
}

@MainActor
private final class SettingsDraftBranchProbeState: ObservableObject {
    @Published var width: CGFloat = 390
    let session = SettingsViewSession()
    var reminder: SettingsPreClassReminderDraft { session.reminderDraft }
    var colors: SettingsColorThemeDraft { session.colorThemeDraft }
    var editorAppearances = 0
}

private struct SettingsDraftBranchProbe: View {
    @ObservedObject var state: SettingsDraftBranchProbeState

    var body: some View {
        Group {
            if AdaptiveLayoutPolicy.primaryNavigation(width: state.width, horizontalClass: .regular) == .sidebar {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 64)
                    settings
                }
            } else {
                VStack(spacing: 0) { settings }
            }
        }
        .frame(width: state.width, height: 900)
        .background { SettingsPresentationHost(session: state.session) }
    }

    private var settings: some View {
        SettingsView(session: state.session)
            .onAppear { state.editorAppearances += 1 }
    }
}

@MainActor
private final class SettingsPresentationOwnerProbeState {
    let presentation = InAppPresentationState()
    var bodyBuilds = 0
}

private struct SettingsPresentationOwnerProbe: View {
    let state: SettingsPresentationOwnerProbeState

    var body: some View {
        let _ = state.bodyBuilds += 1
        Color.clear.background {
            InAppSheetPresentationHost(presentation: state.presentation) {
                Text("Presentation fixture")
            }
        }
    }
}
