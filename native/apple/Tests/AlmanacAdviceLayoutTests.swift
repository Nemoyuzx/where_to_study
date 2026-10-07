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
final class AlmanacAdviceLayoutTests: XCTestCase {
    func testAdviceLabelsUseExistingLocalizationWithoutTranslatingProviderValues() {
        XCTAssertEqual(AppLocalization.string("宜", language: .english), "Recommended")
        XCTAssertEqual(AppLocalization.string("忌", language: .english), "Avoid")
        let providerValue = "原始民俗资料 · Synthetic source wording"
        let card = AlmanacAdviceCard(title: AppLocalization.string("宜", language: .english),
                                     value: providerValue, color: .blue)
        XCTAssertEqual(card.title, "Recommended")
        XCTAssertEqual(card.value, providerValue)
    }

    func testNarrowEnglishAdviceUsesMoreHeightThanTheNaturalHorizontalRow() {
        let card = AlmanacAdviceCard(title: "Recommended", value: "Rest", color: .blue)
        let wide = measure(card, width: 320, textSize: .large)
        let narrow = measure(card, width: 110, textSize: .large)
        XCTAssertGreaterThan(wide.height, 20)
        XCTAssertGreaterThan(narrow.height, wide.height + 5, "Narrow layouts must stack, not truncate the badge")
        XCTAssertLessThanOrEqual(narrow.width, 111)
    }

    func testLocalizedAdviceRemainsFiniteAndGrowsForNarrowLongContentAtAllTextSizes() {
        for language in [AppLanguage.simplifiedChinese, .english, .russian, .arabic] {
            for textSize in [DynamicTypeSize.large, .accessibility5] {
                let card = AlmanacAdviceCard(title: AppLocalization.string("宜", language: language),
                    value: "Rest and keep the original provider information unchanged. Additional synthetic advice remains fully visible.",
                    color: .blue)
                let wide = measure(card, width: 720, textSize: textSize)
                let narrow = measure(card, width: 320, textSize: textSize)
                XCTAssertTrue(narrow.width.isFinite && narrow.height.isFinite)
                XCTAssertGreaterThan(narrow.height, 20)
                XCTAssertGreaterThan(narrow.height, wide.height)
                XCTAssertLessThanOrEqual(narrow.width, 321)
            }
        }
    }

    private func measure(_ card: AlmanacAdviceCard, width: CGFloat, textSize: DynamicTypeSize) -> CGSize {
        let content = card.environment(\.dynamicTypeSize, textSize).frame(width: width)
        #if os(macOS)
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
        #else
        let host = UIHostingController(rootView: content)
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        #endif
    }
}
