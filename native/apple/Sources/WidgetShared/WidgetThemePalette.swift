import Foundation

struct WidgetThemeColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Int, green: Int, blue: Int) {
        self.red = Double(red) / 255
        self.green = Double(green) / 255
        self.blue = Double(blue) / 255
    }

    init(_ rgb: ThemeRGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

struct WidgetThemePalette: Equatable, Sendable {
    let primary: WidgetThemeColor
    let accent: WidgetThemeColor
    let background: WidgetThemeColor

    static let light = WidgetThemePalette(
        primary: WidgetThemeColor(red: 22, green: 107, blue: 93),
        accent: WidgetThemeColor(red: 230, green: 176, blue: 72),
        background: WidgetThemeColor(red: 244, green: 247, blue: 244)
    )

    static let dark = WidgetThemePalette(
        primary: WidgetThemeColor(red: 90, green: 210, blue: 184),
        accent: WidgetThemeColor(red: 230, green: 176, blue: 72),
        background: WidgetThemeColor(red: 24, green: 28, blue: 26)
    )

    static func resolved(_ configuration: ColorThemeConfiguration, dark: Bool) -> WidgetThemePalette {
        let original = dark ? Self.dark : Self.light
        guard configuration.preset != .default else { return original }
        let surfaces = ThemeSurfacePalette.resolved(primary: configuration.seeds.primary, dark: dark)
        return WidgetThemePalette(primary: WidgetThemeColor(surfaces.readable(configuration.seeds.primary.readableText(dark: dark))),
                                  accent: WidgetThemeColor(configuration.seeds.accent), background: WidgetThemeColor(surfaces.surface))
    }
}
