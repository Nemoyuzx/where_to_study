#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import WhereToStudyMac

@MainActor
final class PreClassReminderRenderingTests: XCTestCase {
    func testFiveReminderRowsRenderInNarrowChineseAndEnglishSettingsColumn() async throws {
        let suite = "PreClassReminderRendering.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(runtimeMode: .sample(review: true), defaults: defaults,
                             themeWidgetDefaults: nil, reloadWidgetTheme: {})
        for language in [AppLanguage.simplifiedChinese, .english] {
            model.setAppLanguage(language)
            XCTAssertTrue(model.setPreClassNotificationOffsets([1, 5, 10, 30, 1440]))
            let content = PreClassReminderSettingsView().environmentObject(model)
                .environment(\.locale, language.locale).padding(16)
                .frame(width: 360, height: 620, alignment: .top)
                .background(AppTheme.surface)
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(x: 0, y: 0, width: 360, height: 620)
            host.appearance = NSAppearance(named: .aqua)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(data.count, 5_000)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "mac-pre-class-five-rows-\(language.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
#endif
