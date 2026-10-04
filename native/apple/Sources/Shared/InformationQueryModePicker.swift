import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

protocol QueryDestinationMode: CaseIterable, Identifiable, Hashable {
    var systemImage: String { get }
    var titleKey: String { get }
}

struct InformationQueryModePicker: View {
    @Binding var selection: InformationQueryMode
    let language: AppLanguage
    let availableWidth: CGFloat

    var body: some View {
        QueryDestinationPicker(selection: $selection, language: language,
                               availableWidth: availableWidth, identifier: "queries.mode", titleKey: "查询类型")
    }

    static func minimumTextWidth(language: AppLanguage, fontSize: CGFloat) -> CGFloat {
        QueryDestinationPicker<InformationQueryMode>.minimumTextWidth(language: language, fontSize: fontSize)
    }
}

struct QueryDestinationPicker<Mode: QueryDestinationMode>: View {
    @Binding var selection: Mode
    let language: AppLanguage
    let availableWidth: CGFloat
    let identifier: String
    let titleKey: String
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
        Picker(AppLocalization.string(titleKey, language: language), selection: $selection) {
            ForEach(Array(Mode.allCases)) { mode in
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
        .accessibilityIdentifier(identifier)
    }

    static func minimumTextWidth(language: AppLanguage, fontSize: CGFloat) -> CGFloat {
        #if os(iOS)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        #else
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        #endif
        let widestTitle = Mode.allCases.map { mode in
            (AppLocalization.string(mode.titleKey, language: language) as NSString)
                .size(withAttributes: [.font: font]).width
        }.max() ?? 0
        // Native segments share equal widths; reserve insets on both sides
        // of the longest title, rather than estimating from character counts.
        return ceil(widestTitle + 24) * CGFloat(Mode.allCases.count)
    }
}
