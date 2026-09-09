#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import WhereToStudyMac

@MainActor
final class AppStorePresentationTests: XCTestCase {
    private let screenshotSize = CGSize(width: 1440, height: 900)

    func testInstalledApplicationUsesItsProductName() throws {
        let application = Bundle.main
        guard application.bundleURL.pathExtension == "app" else {
            throw XCTSkip("This check requires the macOS application test host.")
        }

        XCTAssertEqual(application.object(forInfoDictionaryKey: "CFBundleName") as? String, "Where To Study")
        XCTAssertEqual(application.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Where To Study")
        XCTAssertEqual(application.bundleURL.lastPathComponent, "Where To Study.app")
    }

    func testPlannerAndCalendarPresentationInBothLanguages() async throws {
        // Offscreen AppKit snapshots omit the vibrancy-backed native sidebar.
        // These attachments check detail content, not complete store screenshots.
        for language in [AppLanguage.simplifiedChinese, .english] {
            let suite = "AppStorePresentationTests.root.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defaults.set(language.rawValue, forKey: AppLocalization.defaultsKey)
            defer { defaults.removePersistentDomain(forName: suite) }
            let model = makeSampleModel(defaults: defaults)

            for section in [AppSection.planner, .calendar] {
                model.navigation.selectedSection = section
                let root = RootView()
                    .environmentObject(model)
                    .environmentObject(model.navigation)
                    .environment(\.locale, language.locale)

                try await attach(root, name: "mac-app-review-\(section.rawValue)-\(language.rawValue)")
            }
        }
    }

    func testSupportPresentationInBothLanguages() async throws {
        for language in [AppLanguage.simplifiedChinese, .english] {
            let support = AppSupportView()
                .environment(\.appTheme, AppTheme())
                .environment(\.locale, language.locale)

            try await attach(support, name: "mac-app-review-support-\(language.rawValue)")
        }
    }

    func testFirstLaunchPrivacyPresentationInBothLanguages() async throws {
        for language in [AppLanguage.simplifiedChinese, .english] {
            let suite = "AppStorePresentationTests.privacy.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let state = PrivacyConsentState(defaults: defaults)
            let consent = PrivacyConsentGate(state: state)
                .environment(\.appTheme, AppTheme())
                .environment(\.locale, language.locale)

            try await attach(consent, name: "mac-app-review-first-launch-\(language.rawValue)")
        }
    }

    private func makeSampleModel(defaults: UserDefaults) -> AppModel {
        // Keep the presentation run independent of Keychain, disk caches,
        // network clients, system calendars, notifications, and widget storage.
        AppModel(
            runtimeMode: .sample(review: false),
            credentialStore: AppReviewCredentialStore(),
            scheduleStore: AppReviewScheduleStore(),
            classroomStore: AppReviewClassroomStore(),
            defaults: defaults,
            themeWidgetDefaults: nil,
            reloadWidgetTheme: {}
        )
    }

    private func attach<Content: View>(_ content: Content, name: String) async throws {
        let host = NSHostingView(rootView: content
            .environment(\.colorScheme, .light)
            .frame(width: screenshotSize.width, height: screenshotSize.height)
            .background(AppTheme.background))
        host.frame = CGRect(origin: .zero, size: screenshotSize)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        // Allow SwiftUI's sample-data tasks and navigation layout to settle.
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()

        // Core Graphics supports this interleaved RGBA format. These are QA
        // attachments with alpha, not finished App Store screenshot assets.
        // Keep 1440 x 900 pixels regardless of the Mac's backing scale.
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(screenshotSize.width),
            pixelsHigh: Int(screenshotSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ))
        bitmap.size = screenshotSize
        _ = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap), "The capture bitmap must support drawing.")
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var visibleColors = Set<UInt32>()
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 16) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 16) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.01 else { continue }
                let red = UInt32((min(max(color.redComponent, 0), 1) * 255).rounded())
                let green = UInt32((min(max(color.greenComponent, 0), 1) * 255).rounded())
                let blue = UInt32((min(max(color.blueComponent, 0), 1) * 255).rounded())
                visibleColors.insert((red << 16) | (green << 8) | blue)
            }
        }
        XCTAssertGreaterThan(visibleColors.count, 8, "The capture must contain varied visible RGB pixels, not a blank bitmap.")
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// AppModel's sample runtime blocks external requests and system writes, but
// initialization still reads these three stores. Supply only fictional data.
private struct AppReviewCredentialStore: CredentialStoring {
    func load() throws -> Credentials? { nil }
    func save(_: Credentials) throws { throw CocoaError(.featureUnsupported) }
    func clear() throws {}
}

private struct AppReviewScheduleStore: ScheduleStoring {
    func load() throws -> ScheduleSnapshot? { SampleData.schedule() }
    func save(_: ScheduleSnapshot) throws { throw CocoaError(.featureUnsupported) }
    func clear() throws {}
}

private struct AppReviewClassroomStore: ClassroomStoring {
    func load() throws -> ClassroomsCache? { SampleData.classrooms() }
    func save(_: ClassroomsCache) throws { throw CocoaError(.featureUnsupported) }
    func clear() throws {}
}
#endif
