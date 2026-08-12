import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AppThemeColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init(red: Int, green: Int, blue: Int, opacity: Double = 1) {
        self.red = Double(red) / 255
        self.green = Double(green) / 255
        self.blue = Double(blue) / 255
        self.opacity = opacity
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct AppThemePalette: Equatable, Sendable {
    let primary: AppThemeColor
    let primaryFill: AppThemeColor
    let accent: AppThemeColor
    let onPrimary: AppThemeColor

    static let light = AppThemePalette(
        primary: AppThemeColor(red: 22, green: 107, blue: 93),
        primaryFill: AppThemeColor(red: 22, green: 107, blue: 93),
        accent: AppThemeColor(red: 226, green: 188, blue: 98),
        onPrimary: AppThemeColor(red: 255, green: 255, blue: 255)
    )

    static let dark = AppThemePalette(
        primary: AppThemeColor(red: 90, green: 210, blue: 184),
        primaryFill: AppThemeColor(red: 25, green: 117, blue: 101),
        accent: AppThemeColor(red: 135, green: 102, blue: 34),
        onPrimary: AppThemeColor(red: 255, green: 255, blue: 255)
    )
}

enum AppTheme {
    static let primary = adaptiveColor(\.primary)
    static let primaryFill = adaptiveColor(\.primaryFill)
    static let accent = adaptiveColor(\.accent)
    static let onPrimary = adaptiveColor(\.onPrimary)

    #if os(macOS)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let text = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let border = Color(nsColor: .separatorColor)
    static let danger = Color(nsColor: .systemRed)
    #else
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let text = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let border = Color(uiColor: .separator)
    static let danger = Color(uiColor: .systemRed)
    #endif

    private static func adaptiveColor(
        _ keyPath: KeyPath<AppThemePalette, AppThemeColor>
    ) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let palette = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? AppThemePalette.dark
                : AppThemePalette.light
            let value = palette[keyPath: keyPath]
            return NSColor(
                srgbRed: value.red,
                green: value.green,
                blue: value.blue,
                alpha: value.opacity
            )
        })
        #else
        return Color(uiColor: UIColor { traits in
            let palette = traits.userInterfaceStyle == .dark
                ? AppThemePalette.dark
                : AppThemePalette.light
            let value = palette[keyPath: keyPath]
            return UIColor(
                red: value.red,
                green: value.green,
                blue: value.blue,
                alpha: value.opacity
            )
        })
        #endif
    }
}

struct PageTitle: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .foregroundStyle(AppTheme.text)
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
