#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import WhereToStudyMac

@MainActor
final class ColorThemeMacRenderingTests: XCTestCase {
    func testRootCanvasTracksPresetCustomAndAppearanceWithoutReplacingThePage() async throws {
        let suite = "SurfaceThemeRootTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(runtimeMode: .sample(review: false), credentialStore: ThemePreviewCredentialStore(),
            scheduleStore: ThemePreviewScheduleStore(), classroomStore: ThemePreviewClassroomStore(), defaults: defaults,
            themeWidgetDefaults: nil, reloadWidgetTheme: {})
        model.navigation.selectedSection = .settings
        let host = NSHostingView(rootView: RootView().environmentObject(model).environmentObject(model.navigation)
            .frame(width: 1280, height: 900))
        host.frame = CGRect(x: 0, y: 0, width: 1280, height: 900)
        for dark in [false, true] {
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for preset in [ColorThemePreset.ocean, .violet, .amber, .rose, .custom] {
                if preset == .custom {
                    XCTAssertTrue(model.setCustomColorTheme(primary: "#FFFFFF", accent: "#000000", selectedDate: "#000000"))
                } else { model.selectColorTheme(preset) }
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let color = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide - 3, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
                let expected = ThemeSurfacePalette.resolved(primary: model.colorTheme.seeds.primary, dark: dark).background
                XCTAssertEqual(color.redComponent, Double(expected.red) / 255, accuracy: 0.02)
                XCTAssertEqual(color.greenComponent, Double(expected.green) / 255, accuracy: 0.02)
                XCTAssertEqual(color.blueComponent, Double(expected.blue) / 255, accuracy: 0.02)
                XCTAssertEqual(model.navigation.selectedSection, .settings)
                if preset == .ocean || preset == .custom {
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                    attachment.name = "mac-root-surfaces-\(preset.rawValue)-\(dark ? "dark" : "light")"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testSettingsAndWidgetRenderAcrossThemesAndAppearances() async throws {
        let suite = "ColorThemeMacRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set("en", forKey: AppLocalization.defaultsKey)
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(runtimeMode: .sample(review: false), credentialStore: ThemePreviewCredentialStore(),
                             scheduleStore: ThemePreviewScheduleStore(), classroomStore: ThemePreviewClassroomStore(), defaults: defaults,
                             themeWidgetDefaults: nil, reloadWidgetTheme: {})
        for preset in [ColorThemePreset.default, .ocean, .violet, .amber, .rose, .custom] {
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
                    .background(AppTheme(configuration: model.colorTheme).background)
                try await attach(settings, size: CGSize(width: 410, height: 1180), dark: dark,
                                 name: "mac-theme-\(preset.rawValue)-\(dark ? "dark" : "light")")
                if preset == .ocean {
                    let widget = TodayCourseWidgetCard(date: .now, courses: TodayCourseWidgetData.previewCourses(),
                        preferences: .default, weekNumber: 8, family: .systemMedium, usesWidgetContainer: false,
                        language: .english, colorTheme: model.colorTheme)
                        .environment(\.colorScheme, scheme)
                    try await attach(widget, size: CGSize(width: 360, height: 190), dark: dark,
                                     name: "mac-widget-ocean-\(dark ? "dark" : "light")")
                }
            }
        }
    }

    private func attach<Content: View>(_ content: Content, size: CGSize, dark: Bool, name: String) async throws {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
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

private struct ThemePreviewCredentialStore: CredentialStoring {
    func load() throws -> Credentials? { nil }
    func save(_: Credentials) throws { throw CocoaError(.featureUnsupported) }
    func clear() throws {}
}
private struct ThemePreviewScheduleStore: ScheduleStoring {
    func load() throws -> ScheduleSnapshot? { SampleData.schedule() }
    func save(_: ScheduleSnapshot) throws { throw CocoaError(.featureUnsupported) }
    func clear() throws {}
}
private struct ThemePreviewClassroomStore: ClassroomStoring {
    func load() throws -> ClassroomsCache? { SampleData.classrooms() }
    func save(_: ClassroomsCache) throws { throw CocoaError(.featureUnsupported) }
    func clear() throws {}
}
#endif
