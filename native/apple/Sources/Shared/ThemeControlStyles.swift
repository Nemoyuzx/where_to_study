import SwiftUI

struct ThemeTextFieldStyle: TextFieldStyle {
    @Environment(\.appTheme) private var theme

    @ViewBuilder
    func _body(configuration: TextField<Self._Label>) -> some View {
        if theme.configuration.preset == .default {
            configuration.textFieldStyle(.roundedBorder)
        } else {
            configuration.textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .foregroundStyle(theme.text)
                .background(theme.surfaceVariant, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border))
        }
    }
}

/// The probe is scoped by the picker bounds. It updates the existing native
/// segmented control, preserving selection, accessibility and keyboard behavior.
struct ThemeSegmentedSurface: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NativeSegmentSurface(theme: theme, dark: colorScheme == .dark)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if os(iOS)
import UIKit

private struct NativeSegmentSurface: UIViewRepresentable {
    let theme: AppTheme
    let dark: Bool
    func makeUIView(context: Context) -> SegmentSurfaceView { SegmentSurfaceView() }
    func updateUIView(_ view: SegmentSurfaceView, context: Context) {
        view.theme = theme
        view.dark = dark
        view.appliedTheme = nil
        view.applyPalette()
        DispatchQueue.main.async { [weak view] in view?.applyPalette() }
    }
}

private final class SegmentSurfaceView: UIView {
    var theme = AppTheme()
    var dark = false
    var appliedTheme: AppTheme?
    private weak var control: UISegmentedControl?
    private var originalBackground: UIColor?
    private var originalSelection: UIColor?
    private var originalNormal: [NSAttributedString.Key: Any]?
    private var originalSelected: [NSAttributedString.Key: Any]?
    private var appliedDark = false

    override func didMoveToWindow() { super.didMoveToWindow(); applyPalette() }
    override func layoutSubviews() { super.layoutSubviews(); applyPalette() }

    func applyPalette() {
        guard let window, bounds.width > 0 else { return }
        if control == nil {
            let target = convert(bounds, to: window)
            var ancestor = superview
            while let candidate = ancestor {
                func matches(_ view: UIView) -> [UISegmentedControl] {
                    if let control = view as? UISegmentedControl,
                       control.convert(control.bounds, to: window).intersects(target) { return [control] }
                    return view.subviews.flatMap(matches)
                }
                let values = matches(candidate)
                if values.count == 1 {
                    control = values[0]
                    originalBackground = values[0].backgroundColor
                    originalSelection = values[0].selectedSegmentTintColor
                    originalNormal = values[0].titleTextAttributes(for: .normal)
                    originalSelected = values[0].titleTextAttributes(for: .selected)
                    break
                }
                ancestor = candidate.superview
            }
        }
        guard let control, appliedTheme != theme || appliedDark != dark else { return }
        appliedTheme = theme
        appliedDark = dark
        if theme.configuration.preset == .default {
            control.backgroundColor = originalBackground
            control.selectedSegmentTintColor = originalSelection
            control.setTitleTextAttributes(originalNormal, for: .normal)
            control.setTitleTextAttributes(originalSelected, for: .selected)
        } else {
            let palette = ThemeSurfacePalette.resolved(primary: theme.configuration.seeds.primary, dark: dark)
            func color(_ rgb: ThemeRGB) -> UIColor { UIColor(AppThemeColor(rgb).color) }
            control.backgroundColor = color(palette.surfaceVariant)
            control.selectedSegmentTintColor = color(palette.elevated)
            control.setTitleTextAttributes([.foregroundColor: color(palette.secondaryText)], for: .normal)
            control.setTitleTextAttributes([.foregroundColor: color(palette.text)], for: .selected)
        }
    }
}
#else
import AppKit

private struct NativeSegmentSurface: NSViewRepresentable {
    let theme: AppTheme
    let dark: Bool
    func makeNSView(context: Context) -> SegmentSurfaceView { SegmentSurfaceView() }
    func updateNSView(_ view: SegmentSurfaceView, context: Context) {
        view.theme = theme
        view.dark = dark
        view.appliedTheme = nil
        DispatchQueue.main.async { [weak view] in view?.applyPalette() }
    }
}

private final class SegmentSurfaceView: NSView {
    var theme = AppTheme()
    var dark = false
    var appliedTheme: AppTheme?
    private weak var control: NSSegmentedControl?
    private var originalSelection: NSColor?
    private var originalBackground: CGColor?
    private var originalWantsLayer = false
    private var originalCornerRadius: CGFloat = 0
    private var appliedDark = false

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyPalette() }
    override func layout() { super.layout(); applyPalette() }

    func applyPalette() {
        guard window != nil, bounds.width > 0 else { return }
        if control == nil {
            let target = convert(bounds, to: nil)
            var ancestor = superview
            while let candidate = ancestor {
                func matches(_ view: NSView) -> [NSSegmentedControl] {
                    if let control = view as? NSSegmentedControl,
                       control.convert(control.bounds, to: nil).intersects(target) { return [control] }
                    return view.subviews.flatMap(matches)
                }
                let values = matches(candidate)
                if values.count == 1 {
                    control = values[0]
                    originalSelection = values[0].selectedSegmentBezelColor
                    originalBackground = values[0].layer?.backgroundColor
                    originalWantsLayer = values[0].wantsLayer
                    originalCornerRadius = values[0].layer?.cornerRadius ?? 0
                    break
                }
                ancestor = candidate.superview
            }
        }
        guard let control, appliedTheme != theme || appliedDark != dark else { return }
        appliedTheme = theme
        appliedDark = dark
        if theme.configuration.preset == .default {
            control.selectedSegmentBezelColor = originalSelection
            control.layer?.backgroundColor = originalBackground
            control.layer?.cornerRadius = originalCornerRadius
            control.wantsLayer = originalWantsLayer
        } else {
            let palette = ThemeSurfacePalette.resolved(primary: theme.configuration.seeds.primary, dark: dark)
            control.selectedSegmentBezelColor = NSColor(AppThemeColor(palette.elevated).color)
            control.wantsLayer = true
            control.layer?.cornerRadius = 6
            control.layer?.backgroundColor = NSColor(AppThemeColor(palette.surfaceVariant).color).cgColor
        }
    }
}
#endif
