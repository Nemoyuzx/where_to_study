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
    static let assignment = Color(nsColor: .systemPurple)
    static let schoolNotice = Color(nsColor: .systemOrange)
    static let publicDeadline = Color(nsColor: .systemBlue)
    #else
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let text = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let border = Color(uiColor: .separator)
    static let danger = Color(uiColor: .systemRed)
    static let assignment = Color(uiColor: .systemPurple)
    static let schoolNotice = Color(uiColor: .systemOrange)
    static let publicDeadline = Color(uiColor: .systemBlue)
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

enum AppHaptics {
    @MainActor
    static func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }

    @MainActor
    static func impact() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}

struct MobilePageLayoutMetrics: Equatable {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let sectionSpacing: CGFloat
    let usesCompactTitle: Bool
}

enum MobilePageLayoutPolicy {
    static let compactHeightThreshold: CGFloat = 500

    static func metrics(availableHeight: CGFloat) -> MobilePageLayoutMetrics {
        if availableHeight < compactHeightThreshold {
            return MobilePageLayoutMetrics(
                horizontalPadding: 16,
                topPadding: 16,
                bottomPadding: 16,
                sectionSpacing: 12,
                usesCompactTitle: true
            )
        }
        return MobilePageLayoutMetrics(
            horizontalPadding: 20,
            topPadding: 20,
            bottomPadding: 20,
            sectionSpacing: 16,
            usesCompactTitle: false
        )
    }
}

struct PageTitle: View {
    let eyebrow: String
    let title: String
    let compact: Bool

    init(eyebrow: String, title: String, compact: Bool = false) {
        self.eyebrow = eyebrow
        self.title = title
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(title)
                .font(compact ? .title2.bold() : .largeTitle.bold())
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
