import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class AppLanguageTests: XCTestCase {
    func testAllThirteenResourcesHaveStableLanguageIdentities() {
        let expected: Set<String> = ["zh-Hans", "zh-Hant", "en", "ja", "es", "pt", "ar", "ru", "tr", "th", "ms", "vi", "id"]
        XCTAssertEqual(AppLanguage.allCases.count, 14)
        XCTAssertEqual(Set(AppLanguage.allCases.filter { $0 != .system }.map(\.rawValue)), expected)
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.nativeName)).count, 14)
        for language in AppLanguage.allCases where language != .system {
            XCTAssertEqual(language.resourceName(preferredLanguages: ["unknown"]), language.rawValue)
            XCTAssertFalse(language.locale.identifier.isEmpty)
        }
    }

    func testSystemLanguageHonorsScriptRegionAndPreferenceOrder() {
        for tag in ["zh-Hant", "zh-Hant-TW", "zh-TW", "zh_HK", "zh-MO"] {
            XCTAssertEqual(AppLanguage.system.resourceName(preferredLanguages: [tag]), "zh-Hant")
        }
        for tag in ["zh-Hans", "zh-Hans-TW", "zh-CN", "zh-SG"] {
            XCTAssertEqual(AppLanguage.system.resourceName(preferredLanguages: [tag]), "zh-Hans")
        }
        for (tag, resource) in [("ja-JP", "ja"), ("es-419", "es"), ("pt-BR", "pt"), ("ar-EG", "ar"),
                                ("ru-RU", "ru"), ("tr-TR", "tr"), ("th-TH", "th"), ("ms-MY", "ms"),
                                ("vi-VN", "vi"), ("id-ID", "id"), ("en-GB", "en")] {
            XCTAssertEqual(AppLanguage.system.resourceName(preferredLanguages: [tag]), resource)
        }
        XCTAssertEqual(AppLanguage.system.resourceName(preferredLanguages: ["de-DE", "pt-BR", "en-US"]), "pt")
        XCTAssertEqual(AppLanguage.system.resourceName(preferredLanguages: ["de-DE"]), "en")
        XCTAssertEqual(AppLanguage.system.resourceName(preferredLanguages: []), "en")
    }

    func testPersistenceAndWidgetResolutionDoNotReduceLanguageToEnglishOrChinese() throws {
        let suite = "WhereToStudy-language-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for language in AppLanguage.allCases {
            defaults.set(language.rawValue, forKey: AppLocalization.defaultsKey)
            XCTAssertEqual(AppLocalization.persistedLanguage(defaults: defaults), language)
            if language != .system {
                XCTAssertEqual(TodayCourseWidgetData.Language.resolve(rawValue: language.rawValue).rawValue, language.rawValue)
            }
        }
        XCTAssertEqual(TodayCourseWidgetData.Language.resolve(rawValue: "system", preferredLanguages: ["zh-TW"]), .traditionalChinese)
        XCTAssertEqual(TodayCourseWidgetData.Language.resolve(rawValue: "system", preferredLanguages: ["ar-SA"]), .arabic)
    }

    func testArabicDirectionAndPresentationDateFormatsDoNotChangeMachineDates() {
        XCTAssertTrue(AppLanguage.arabic.isRightToLeft)
        XCTAssertFalse(AppLanguage.japanese.isRightToLeft)
        XCTAssertFalse(AppLanguage.traditionalChinese.isRightToLeft)
        XCTAssertEqual(AppLanguage.arabic.dateFormat(chinese: "yyyy-MM-dd", english: "yyyy-MM-dd"), "yyyy-MM-dd")
        XCTAssertFalse(AppLanguage.spanish.dateFormat(chinese: "yyyy年M月d日", english: "MMMM d, yyyy").contains("年"))
        XCTAssertEqual(AppLocalization.string("日", language: .english), "Day")
        XCTAssertEqual(AppLocalization.weekdaySymbol(for: "日", language: .english), "S")
        XCTAssertEqual(AppLocalization.weekdaySymbol(for: "一", language: .japanese), "月")
        let raw = "EBU Sample / Submitted for grading / 2026-10-01T10:00:00Z"
        for language in AppLanguage.allCases {
            XCTAssertEqual(AppLocalization.string(raw, language: language), raw)
        }
    }
}
