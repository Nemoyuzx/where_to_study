import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct InformationQueryModePicker: View {
    @Binding var selection: InformationQueryMode
    let language: AppLanguage
    let availableWidth: CGFloat
    @ScaledMetric(relativeTo: .subheadline) private var titleFontSize: CGFloat = 13

    private var usesIcons: Bool {
        // A native segment displays either a title or an image. Keep every
        // phone destination recognizable by its icon, including in landscape.
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            return true
        }
        #endif
        return availableWidth < Self.minimumTextWidth(language: language, fontSize: titleFontSize)
    }

    var body: some View {
        Picker(AppLocalization.string("查询类型", language: language), selection: $selection) {
            ForEach(InformationQueryMode.allCases) { mode in
                Group {
                    if usesIcons {
                        Image(systemName: mode.systemImage)
                    } else {
                        Text(AppLocalization.string(mode.titleKey, language: language))
                    }
                }
                .accessibilityLabel(AppLocalization.string(mode.titleKey, language: language))
                .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // AppKit retains previous segment titles when SwiftUI replaces them
        // with images. Recreate only the presentation, keeping its binding.
        .id(usesIcons)
        .background(ThemeSegmentedSurface())
        .accessibilityIdentifier("queries.mode")
    }

    static func minimumTextWidth(language: AppLanguage, fontSize: CGFloat) -> CGFloat {
        #if os(iOS)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        #else
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        #endif
        let widestTitle = InformationQueryMode.allCases.map { mode in
            (AppLocalization.string(mode.titleKey, language: language) as NSString)
                .size(withAttributes: [.font: font]).width
        }.max() ?? 0
        // Native segments share equal widths; reserve insets on both sides
        // of the longest title, rather than estimating from character counts.
        return ceil(widestTitle + 24) * CGFloat(InformationQueryMode.allCases.count)
    }
}
