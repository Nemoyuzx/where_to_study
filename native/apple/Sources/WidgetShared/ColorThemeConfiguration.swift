import Foundation

/// Shared by both applications and WidgetKit extensions. RGB seeds follow
/// contracts/v1/color-themes.json; the classic palette is handled separately.
struct ThemeRGB: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int

    init(_ red: Int, _ green: Int, _ blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.utf8.count == 6,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(Int((rgb >> 16) & 255), Int((rgb >> 8) & 255), Int(rgb & 255))
    }

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    var luminance: Double {
        func linear(_ byte: Int) -> Double {
            let c = Double(byte) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(against other: ThemeRGB) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }

    func blended(toward other: ThemeRGB, amount: Double) -> ThemeRGB {
        func mix(_ a: Int, _ b: Int) -> Int { Int((Double(a) + Double(b - a) * amount).rounded()) }
        return ThemeRGB(mix(red, other.red), mix(green, other.green), mix(blue, other.blue))
    }

    func accessibleFill() -> ThemeRGB { adjusted(against: .white, toward: .black) }
    func readableText(dark: Bool) -> ThemeRGB {
        dark ? adjusted(against: ThemeRGB(40, 40, 40), toward: .white) : accessibleFill()
    }

    private func adjusted(against background: ThemeRGB, toward target: ThemeRGB) -> ThemeRGB {
        if contrast(against: background) >= 4.5 { return self }
        for step in 1...50 {
            let candidate = blended(toward: target, amount: Double(step) * 0.02)
            if candidate.contrast(against: background) >= 4.5 { return candidate }
        }
        return target
    }

    static let white = ThemeRGB(255, 255, 255)
    static let black = ThemeRGB(0, 0, 0)
}

struct ColorThemeSeeds: Equatable, Sendable {
    let primary: ThemeRGB
    let accent: ThemeRGB
    let selectedDate: ThemeRGB
}

enum ColorThemePreset: String, CaseIterable, Sendable, Identifiable {
    case `default`, ocean, violet, amber, rose, custom
    var id: String { rawValue }

    var seeds: ColorThemeSeeds {
        let values: (String, String, String) = switch self {
        case .default, .custom: ("#166B5D", "#E2BC62", "#2563EB")
        case .ocean: ("#1565C0", "#26A69A", "#7C3AED")
        case .violet: ("#7C3AED", "#D08A2E", "#00796B")
        case .amber: ("#A65300", "#2E7D6F", "#2563EB")
        case .rose: ("#B42368", "#8C6A35", "#2563EB")
        }
        return ColorThemeSeeds(primary: ThemeRGB(hex: values.0)!, accent: ThemeRGB(hex: values.1)!, selectedDate: ThemeRGB(hex: values.2)!)
    }

    func title(english: Bool) -> String {
        switch self {
        case .default: english ? "Classic Teal" : "默认青绿"
        case .ocean: english ? "Ocean Blue" : "海洋蓝"
        case .violet: english ? "Iris Violet" : "鸢尾紫"
        case .amber: english ? "Warm Amber" : "暖琥珀"
        case .rose: english ? "Rose" : "玫瑰"
        case .custom: english ? "Custom" : "自定义"
        }
    }
}

struct ColorThemeConfiguration: Equatable, Sendable {
    let preset: ColorThemePreset
    let custom: ColorThemeSeeds
    static let `default` = ColorThemeConfiguration(preset: .default, custom: ColorThemePreset.default.seeds)
    static let defaultsKey = "colorTheme.v1"

    var seeds: ColorThemeSeeds { preset == .custom ? custom : preset.seeds }

    func selecting(_ preset: ColorThemePreset) -> ColorThemeConfiguration {
        ColorThemeConfiguration(preset: preset, custom: custom)
    }

    func editing(primary: String, accent: String, selectedDate: String) -> ColorThemeConfiguration? {
        guard let primary = ThemeRGB(hex: primary), let accent = ThemeRGB(hex: accent),
              let selectedDate = ThemeRGB(hex: selectedDate) else { return nil }
        return ColorThemeConfiguration(preset: .custom,
            custom: ColorThemeSeeds(primary: primary, accent: accent, selectedDate: selectedDate))
    }

    static func load(defaults: UserDefaults) -> ColorThemeConfiguration {
        guard let values = defaults.dictionary(forKey: defaultsKey) else { return .default }
        let fallback = ColorThemePreset.default.seeds
        return ColorThemeConfiguration(
            preset: ColorThemePreset(rawValue: values["preset"] as? String ?? "") ?? .default,
            custom: ColorThemeSeeds(
                primary: (values["primary"] as? String).flatMap(ThemeRGB.init(hex:)) ?? fallback.primary,
                accent: (values["accent"] as? String).flatMap(ThemeRGB.init(hex:)) ?? fallback.accent,
                selectedDate: (values["selectedDate"] as? String).flatMap(ThemeRGB.init(hex:)) ?? fallback.selectedDate
            )
        )
    }

    func save(defaults: UserDefaults) {
        defaults.set(["preset": preset.rawValue, "primary": custom.primary.hex,
                      "accent": custom.accent.hex, "selectedDate": custom.selectedDate.hex],
                     forKey: Self.defaultsKey)
    }

    static func loadForWidget() -> ColorThemeConfiguration {
        guard let defaults = UserDefaults(suiteName: TodayCourseWidgetData.appGroupIdentifier) else { return .default }
        return load(defaults: defaults)
    }
}
