import SwiftUI
import WidgetKit
import Vision
import XCTest
#if os(macOS)
import AppKit
@testable import WhereToStudyMac
#else
import UIKit
@testable import WhereToStudyiOS
#endif

@MainActor
final class TodayCourseWidgetRenderingTests: XCTestCase {
    func testActualHeightHidesTomorrowBeforeDroppingToday() throws {
        let date = try XCTUnwrap(Calendar.shanghai.date(from:
            DateComponents(year: 2026, month: 3, day: 2, hour: 10)))
        for height in [125.0, 190.0] {
            let card = TodayCourseWidgetCard(
                date: date, courses: [TodayCourseWidgetData.Course(
                    id: "today-algebra", name: "Algebra Today", room: "", timeRange: "08:00-09:35",
                    weekday: 1, weekNumbers: [1], startSlot: 0
                )],
                tomorrowCourses: TodayCourseWidgetData.previewTomorrowCourses(),
                preferences: .default, weekNumber: 1, family: .systemMedium,
                usesWidgetContainer: false, language: .english
            ).environment(\.colorScheme, .light).frame(width: 360, height: height)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 2
            let text = try recognizedText(in: XCTUnwrap(renderer.cgImage))
            XCTAssertTrue(text.contains("Algebra Today"), text)
            XCTAssertEqual(text.contains("Tomorrow"), height == 190, text)
        }
    }

    func testTomorrowRowsNeverReceiveCurrentOrNextBadges() throws {
        let date = try XCTUnwrap(Calendar.shanghai.date(from:
            DateComponents(year: 2026, month: 3, day: 2, hour: 10)))
        let card = TodayCourseWidgetCard(
            date: date, courses: [], tomorrowCourses: TodayCourseWidgetData.previewTodayCourses(),
            preferences: .default, weekNumber: 1, family: .systemLarge,
            usesWidgetContainer: false, language: .english
        ).environment(\.colorScheme, .light).frame(width: 360, height: 360)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        let text = try recognizedText(in: XCTUnwrap(renderer.cgImage))
        XCTAssertTrue(text.contains("Tomorrow"), text)
        XCTAssertTrue(text.contains("09:50"), text)
        XCTAssertFalse(text.contains("Now"), text)
        XCTAssertFalse(text.contains("Next"), text)
    }

    private func recognizedText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    func testBothDaysRenderAtActualFamilySizesInBothLanguages() throws {
        let date = try XCTUnwrap(Calendar.shanghai.date(from:
            DateComponents(year: 2026, month: 3, day: 2, hour: 10)))
        for (family, size) in [
            (WidgetFamily.systemSmall, CGSize(width: 158, height: 158)),
            (.systemMedium, CGSize(width: 360, height: 170)),
            (.systemLarge, CGSize(width: 360, height: 360))
        ] {
            for language in [TodayCourseWidgetData.Language.simplifiedChinese, .english] {
                for count in [0, 1, 2, 6] {
                    let card = TodayCourseWidgetCard(
                        date: date,
                        courses: Array(TodayCourseWidgetData.previewCourses().prefix(count)),
                        tomorrowCourses: TodayCourseWidgetData.previewTomorrowCourses(),
                        preferences: .init(showsLocation: true, showsTeacher: true, courseLimit: 6),
                        weekNumber: 1, family: family, usesWidgetContainer: false,
                        language: language
                    )
                    .environment(\.colorScheme, .light)
                    .frame(width: size.width, height: size.height)
                    let renderer = ImageRenderer(content: card)
                    renderer.scale = 2
                    let bitmap = try XCTUnwrap(renderer.cgImage)
                    XCTAssertEqual(bitmap.width, Int(size.width * 2))
                    XCTAssertEqual(bitmap.height, Int(size.height * 2))
                    #if os(macOS)
                    let png = try XCTUnwrap(NSBitmapImageRep(cgImage: bitmap)
                        .representation(using: .png, properties: [:]))
                    #else
                    let png = try XCTUnwrap(UIImage(cgImage: bitmap).pngData())
                    #endif
                    XCTAssertGreaterThan(png.count, 2_000)
                    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                    attachment.name = "widget-\(family)-\(language.rawValue)-today-\(count)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }
}
