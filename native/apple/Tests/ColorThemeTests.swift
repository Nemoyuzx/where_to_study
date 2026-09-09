import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class ColorThemeTests: XCTestCase {
    func testEveryPresetMatchesTheSharedContract() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("contracts/v1/color-themes.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let presets = try XCTUnwrap(object["presets"] as? [[String: String]])
        XCTAssertEqual(presets.compactMap { $0["id"] }, ColorThemePreset.allCases.filter { $0 != .custom }.map(\.rawValue))
        for values in presets {
            let preset = try XCTUnwrap(values["id"].flatMap(ColorThemePreset.init(rawValue:)))
            XCTAssertEqual(preset.seeds.primary.hex, values["primary"])
            XCTAssertEqual(preset.seeds.accent.hex, values["accent"])
            XCTAssertEqual(preset.seeds.selectedDate.hex, values["selectedDate"])
            XCTAssertEqual(preset.title(english: false), values["nameZh"])
            XCTAssertEqual(preset.title(english: true), values["nameEn"])
        }
    }

    func testDefaultRetainsEveryExistingAppAndWidgetColor() {
        XCTAssertEqual(AppThemePalette.resolved(.default, dark: false), .light)
        XCTAssertEqual(AppThemePalette.resolved(.default, dark: true), .dark)
        XCTAssertEqual(WidgetThemePalette.resolved(.default, dark: false), .light)
        XCTAssertEqual(WidgetThemePalette.resolved(.default, dark: true), .dark)
    }

    func testHexValidationNormalizesOnlyCompleteRGBColors() {
        XCTAssertEqual(ThemeRGB(hex: "  1a2B3c \n")?.hex, "#1A2B3C")
        XCTAssertEqual(ThemeRGB(hex: " #Ff00aA ")?.hex, "#FF00AA")
        for invalid in ["", "#123", "#12345678", "12345", "#12GG00", "##123456", "#１２３４５６", "#12 456", "0x123456"] {
            XCTAssertNil(ThemeRGB(hex: invalid), invalid)
        }
        XCTAssertNil(ColorThemeConfiguration.default.editing(primary: "#123", accent: "#000000", selectedDate: "#FFFFFF"))
    }

    func testPresetAndExtremeSeedsMeetContrastWithoutChangingDeadlineSemantics() throws {
        var configurations = ColorThemePreset.allCases.filter { $0 != .default }.map {
            ColorThemeConfiguration.default.selecting($0)
        }
        for seed in ["#FFFFFF", "#000000", "#FFFF00", "#00FF00", "#FF00FF", "#010101", "#FEFEFE"] {
            configurations.append(try XCTUnwrap(ColorThemeConfiguration.default.editing(primary: seed, accent: seed, selectedDate: seed)))
        }
        for configuration in configurations {
            for dark in [false, true] {
                let palette = AppThemePalette.resolved(configuration, dark: dark)
                let original = dark ? AppThemePalette.dark : .light
                XCTAssertGreaterThanOrEqual(rgb(palette.primaryFill).contrast(against: .white), 4.5)
                XCTAssertGreaterThanOrEqual(rgb(palette.selectedDate).contrast(against: .white), 4.5)
                let surface = dark ? ThemeRGB(40, 40, 40) : .white
                XCTAssertGreaterThanOrEqual(rgb(palette.primary).contrast(against: surface), 4.5)
                XCTAssertGreaterThanOrEqual(configuration.seeds.accent.readableText(dark: dark).contrast(against: surface), 4.5)
                XCTAssertEqual(palette.assignment, original.assignment)
                XCTAssertEqual(palette.schoolNotice, original.schoolNotice)
                XCTAssertEqual(palette.publicDeadline, original.publicDeadline)
                XCTAssertEqual(palette.conferenceDeadline, original.conferenceDeadline)
                XCTAssertEqual(palette.summerCampDeadline, original.summerCampDeadline)
                XCTAssertEqual(palette.hackathonDeadline, original.hackathonDeadline)
                XCTAssertEqual(palette.customDeadline, original.customDeadline)
                XCTAssertEqual(WidgetThemePalette.resolved(configuration, dark: dark).background,
                               dark ? WidgetThemePalette.dark.background : WidgetThemePalette.light.background)
            }
        }
        // The contract rounds each original-seed blend, never the last result.
        XCTAssertEqual(ThemeRGB.white.accessibleFill().hex, "#757575")
        XCTAssertEqual(ThemeRGB.black.readableText(dark: true).hex, "#8F8F8F")
    }

    func testPersistenceReloadFallbackAndRestoringDefaultKeepCustomSeeds() throws {
        let suite = "ColorThemeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ColorThemeConfiguration.load(defaults: defaults), .default)
        let custom = try XCTUnwrap(ColorThemeConfiguration.default.editing(primary: "ffffff", accent: "abc123", selectedDate: "000000"))
        custom.save(defaults: defaults)
        XCTAssertEqual(ColorThemeConfiguration.load(defaults: defaults), custom)
        for preset in ColorThemePreset.allCases {
            custom.selecting(preset).save(defaults: defaults)
            let reloaded = ColorThemeConfiguration.load(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
            XCTAssertEqual(reloaded.preset, preset)
            XCTAssertEqual(reloaded.custom, custom.custom)
        }
        defaults.set(["preset": "missing", "primary": "bad", "accent": "000000", "selectedDate": "##abc123"],
                     forKey: ColorThemeConfiguration.defaultsKey)
        let recovered = ColorThemeConfiguration.load(defaults: defaults)
        XCTAssertEqual(recovered.preset, .default)
        XCTAssertEqual(recovered.custom.primary, ColorThemePreset.default.seeds.primary)
        XCTAssertEqual(recovered.custom.accent, .black)
        XCTAssertEqual(recovered.custom.selectedDate, ColorThemePreset.default.seeds.selectedDate)
    }

    private func rgb(_ color: AppThemeColor) -> ThemeRGB {
        ThemeRGB(Int((color.red * 255).rounded()), Int((color.green * 255).rounded()), Int((color.blue * 255).rounded()))
    }
}
