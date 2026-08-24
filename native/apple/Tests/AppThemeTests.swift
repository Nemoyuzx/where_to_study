import XCTest

#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class AppThemeTests: XCTestCase {
    func testPrimaryFillMaintainsReadableWhiteTextInBothAppearances() {
        XCTAssertGreaterThanOrEqual(contrast(.white, AppThemePalette.light.primaryFill), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(.white, AppThemePalette.dark.primaryFill), 4.5)
    }

    func testSelectedDateMaintainsReadableWhiteTextInBothAppearances() {
        XCTAssertGreaterThanOrEqual(contrast(.white, AppThemePalette.light.selectedDate), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(.white, AppThemePalette.dark.selectedDate), 4.5)
        XCTAssertNotEqual(AppThemePalette.light.selectedDate, AppThemePalette.light.primaryFill)
        XCTAssertNotEqual(AppThemePalette.dark.selectedDate, AppThemePalette.dark.primaryFill)
    }

    func testCalendarSemanticColorsMatchTheCrossPlatformContract() {
        XCTAssertEqual(AppThemePalette.light.selectedDate, color(0x25, 0x63, 0xEB))
        XCTAssertEqual(AppThemePalette.dark.selectedDate, color(0x1D, 0x4E, 0xD8))
        XCTAssertEqual(AppThemePalette.light.assignment, color(0x9A, 0x65, 0x00))
        XCTAssertEqual(AppThemePalette.dark.assignment, color(0xFF, 0xC1, 0x4D))
        XCTAssertEqual(AppThemePalette.light.schoolNotice, color(0x5B, 0x4B, 0xC4))
        XCTAssertEqual(AppThemePalette.dark.schoolNotice, color(0xB7, 0xA8, 0xFF))
        XCTAssertEqual(AppThemePalette.light.publicDeadline, color(0x00, 0x7C, 0x91))
        XCTAssertEqual(AppThemePalette.dark.publicDeadline, color(0x68, 0xD5, 0xE5))
    }

    func testBrandForegroundMaintainsContrastAgainstPageBackgrounds() {
        let lightBackground = AppThemeColor(red: 244, green: 247, blue: 244)
        let darkBackground = AppThemeColor(red: 24, green: 28, blue: 26)

        XCTAssertGreaterThanOrEqual(contrast(AppThemePalette.light.primary, lightBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(AppThemePalette.dark.primary, darkBackground), 4.5)
    }

    #if os(macOS)
    func testWidgetBrandForegroundMaintainsContrastAgainstWidgetBackgrounds() {
        XCTAssertGreaterThanOrEqual(
            contrast(WidgetThemePalette.light.primary, WidgetThemePalette.light.background),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            contrast(WidgetThemePalette.dark.primary, WidgetThemePalette.dark.background),
            4.5
        )
    }

    func testWidgetBackgroundMaintainsSemanticTextContrast() {
        let lightText = WidgetThemeColor(red: 23, green: 32, blue: 29)
        let darkText = WidgetThemeColor(red: 255, green: 255, blue: 255)

        XCTAssertGreaterThanOrEqual(contrast(lightText, WidgetThemePalette.light.background), 7)
        XCTAssertGreaterThanOrEqual(contrast(darkText, WidgetThemePalette.dark.background), 7)
    }
    #endif

    private func contrast(_ left: AppThemeColor, _ right: AppThemeColor) -> Double {
        contrast(
            left: (left.red, left.green, left.blue),
            right: (right.red, right.green, right.blue)
        )
    }

    private func color(_ red: Int, _ green: Int, _ blue: Int) -> AppThemeColor {
        AppThemeColor(red: red, green: green, blue: blue)
    }

    #if os(macOS)
    private func contrast(_ left: WidgetThemeColor, _ right: WidgetThemeColor) -> Double {
        contrast(
            left: (left.red, left.green, left.blue),
            right: (right.red, right.green, right.blue)
        )
    }
    #endif

    private func contrast(
        left: (Double, Double, Double),
        right: (Double, Double, Double)
    ) -> Double {
        let values = [relativeLuminance(left), relativeLuminance(right)].sorted(by: >)
        return (values[0] + 0.05) / (values[1] + 0.05)
    }

    private func relativeLuminance(_ color: (Double, Double, Double)) -> Double {
        let channels = [color.0, color.1, color.2].map { channel in
            channel <= 0.04045
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}

private extension AppThemeColor {
    static let white = AppThemeColor(red: 255, green: 255, blue: 255)
}
