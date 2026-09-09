#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import WhereToStudyMac

@MainActor
final class ColorThemeMacRenderingTests: XCTestCase {
    func testSettingsAndWidgetRenderAcrossThemesAndAppearances() async throws {
        let suite = "ColorThemeMacRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set("en", forKey: AppLocalization.defaultsKey)
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(runtimeMode: .sample(review: false), defaults: defaults,
                             themeWidgetDefaults: nil, reloadWidgetTheme: {})
        for preset in [ColorThemePreset.default, .ocean, .custom] {
            if preset == .custom {
                XCTAssertTrue(model.setCustomColorTheme(primary: "#FFFFFF", accent: "#000000", selectedDate: "#FF00FF"))
            } else { model.selectColorTheme(preset) }
            for dark in [false, true] {
                let scheme: ColorScheme = dark ? .dark : .light
                let settings = ColorThemeSettingsSurface()
                    .environmentObject(model)
                    .environment(\.appTheme, AppTheme(configuration: model.colorTheme))
                    .environment(\.colorScheme, scheme)
                    .padding(16)
                    .background(AppTheme.background)
                try await attach(settings, size: CGSize(width: 410, height: 1080), dark: dark,
                                 name: "mac-theme-\(preset.rawValue)-\(dark ? "dark" : "light")")
                if preset == .ocean {
                    let widget = TodayCourseWidgetCard(date: .now, courses: TodayCourseWidgetData.previewCourses(),
                        preferences: .default, weekNumber: 8, family: .systemMedium, usesWidgetContainer: false,
                        language: .english, colorTheme: model.colorTheme)
                        .environment(\.colorScheme, scheme)
                    try await attach(widget, size: CGSize(width: 360, height: 170), dark: dark,
                                     name: "mac-widget-ocean-\(dark ? "dark" : "light")")
                }
            }
        }
    }

    private func attach<Content: View>(_ content: Content, size: CGSize, dark: Bool, name: String) async throws {
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 5_000, "The view must contain rendered content")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
