import SwiftUI
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
final class GradeQueryRenderingTests: XCTestCase {
    func testResultsUseLessHeightAtPhoneTabletAndDesktopWidths() throws {
        for language in [AppLanguage.simplifiedChinese, .english] {
            let snapshot = sample(language: language)
            for width in [358.0, 720.0, 900.0] {
                let before = try render(LegacyGradeResults(snapshot: snapshot, language: language), width: width)
                let after = try render(GradeResultsView(snapshot: snapshot, language: language), width: width)
                XCTAssertLessThan(Double(after.height), Double(before.height) * 0.85,
                                  "The same complete grade results should use at least 15% less height.")
                let first = try XCTUnwrap(snapshot.items.first)
                let oldRow = try render(LegacyGradeCourseRow(item: first, language: language), width: width)
                let newRow = try render(GradeCourseRow(item: first, language: language), width: width)
                XCTAssertLessThan(newRow.height, oldRow.height)
                print("Grade density \(language.rawValue) width=\(width): results \(Double(before.height) / 2 - 32) -> \(Double(after.height) / 2 - 32) pt; first row \(Double(oldRow.height) / 2 - 32) -> \(Double(newRow.height) / 2 - 32) pt")
                try attach(before, name: "grades-before-\(language.rawValue)-\(Int(width))")
                try attach(after, name: "grades-after-\(language.rawValue)-\(Int(width))")
            }
        }
    }

    func testLongNamesAndAllMetadataRemainVisibleAtLargeAccessibilitySizes() throws {
        for language in [AppLanguage.simplifiedChinese, .english] {
            let name = language == .english
                ? "Synthetic Advanced Communication Systems and Interdisciplinary Engineering Laboratory"
                : "合成课程：现代通信系统与跨学科工程实践综合实验课程完整名称"
            let item = GradeItem(id: "long", name: name, score: "Passed", credits: "0",
                                 courseCode: "CODE123", courseAttribute: "Required",
                                 courseNature: "Theory", examNature: "Retake",
                                 semesterName: "TERM2026", gradeStatus: "Complete")
            for width in [358.0, 720.0] {
                for size in [DynamicTypeSize.large, .accessibility3] {
                    let bitmap = try render(GradeCourseRow(item: item, language: language), width: width, size: size)
                    let text = try recognizedText(in: bitmap, language: language).replacingOccurrences(of: " ", with: "")
                    let expected = language == .english ? "Laboratory" : "完整名称"
                    for value in [expected, "Passed", "0", "CODE123", "Required", "Theory", "Retake", "TERM2026", "Complete"] {
                        XCTAssertTrue(text.contains(value), "Missing \(value) at \(width), \(size): \(text)")
                    }
                    try attach(bitmap, name: "grades-long-\(language.rawValue)-\(Int(width))-\(size)")
                }
            }
        }
    }

    func testZeroTextAndUnpublishedScoresAndAverageRemainVisible() throws {
        let snapshot = sample(language: .english)
        for size in [DynamicTypeSize.large, .accessibility3] {
            let bitmap = try render(GradeResultsView(snapshot: snapshot, language: .english), width: 358, size: size)
            let text = try recognizedText(in: bitmap)
            for value in ["3.75", "0", "Passed", "Not published"] {
                XCTAssertTrue(text.contains(value), "Missing \(value): \(text)")
            }
            try attach(bitmap, name: "grades-score-values-\(size)")
        }
    }

    private func sample(language: AppLanguage) -> GradeSnapshot {
        let names = language == .english ? ["Synthetic Algebra", "Synthetic Physics", "Synthetic Ethics"]
            : ["合成高等数学", "合成大学物理", "合成思想道德"]
        let scores: [String?] = ["0", "Passed", nil]
        let items = names.enumerated().map { index, name in
            GradeItem(id: String(index), name: name, score: scores[index], credits: index == 0 ? "0" : "2",
                      courseCode: "DEMO\(index)", courseAttribute: nil, courseNature: nil, examNature: nil,
                      semesterName: "2026-2027-1")
        }
        return GradeSnapshot(termID: "synthetic", recordType: "", fetchedAt: "synthetic",
                             averageGradePoint: "3.75", items: items)
    }

    private func render<Content: View>(_ content: Content, width: Double,
                                      size: DynamicTypeSize = .large) throws -> CGImage {
        let renderer = ImageRenderer(content: content
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, size)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .background(AppTheme.background))
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
    }

    private func recognizedText(in image: CGImage, language: AppLanguage = .english) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = language == .simplifiedChinese ? ["zh-Hans", "en-US"] : ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private func attach(_ image: CGImage, name: String) throws {
        #if os(macOS)
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        #else
        let png = try XCTUnwrap(UIImage(cgImage: image).pngData())
        #endif
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// The pre-density layout is retained only here so the same synthetic content can
// be measured and visually compared on each platform without changing app data.
private struct LegacyGradeResults: View {
    let snapshot: GradeSnapshot
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let average = snapshot.averageGradePoint {
                LabeledContent(AppLocalization.string("平均学分绩点", language: language), value: average)
            }
            ForEach(snapshot.items) { item in
                LegacyGradeCourseRow(item: item, language: language)
            }
        }
    }
}

private struct LegacyGradeCourseRow: View {
    @Environment(\.appTheme) private var theme
    let item: GradeItem
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name).font(.headline)
                Spacer()
                Text(item.score ?? AppLocalization.string("未公布", language: language)).font(.title3.bold())
            }
            if let credits = item.credits {
                Text(AppLocalization.string("学分", language: language) + "：" + credits)
            }
            let metadata = [item.semesterName, item.courseCode, item.courseAttribute, item.courseNature,
                            item.examNature, item.gradeStatus].compactMap { $0 }
            if !metadata.isEmpty {
                Text(metadata.joined(separator: " · ")).font(.caption).foregroundStyle(theme.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
