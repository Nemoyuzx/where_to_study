import SwiftUI

struct ColorThemeSettingsSurface: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @State private var primary = "#166B5D"
    @State private var accent = "#E2BC62"
    @State private var selectedDate = "#2563EB"
    @State private var hasEdited = false
    @FocusState private var focusedField: String?

    private var english: Bool { model.appLanguage.resolvedResourceName == "en" }
    private func text(_ chinese: String, _ english: String) -> String { self.english ? english : chinese }
    private var draft: ColorThemeConfiguration? {
        model.colorTheme.editing(primary: primary, accent: accent, selectedDate: selectedDate)
    }
    private var previewTheme: AppTheme {
        AppTheme(configuration: hasEdited ? (draft ?? model.colorTheme) : model.colorTheme)
    }

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Label(text("颜色主题", "Color Theme"), systemImage: "paintpalette")
                    .font(.headline)
                Text(text("选择柔和配色，页面背景与卡片会随主色协调变化，浅深外观仍跟随系统。",
                          "Choose a softer palette. Backgrounds and cards follow your primary color; light and dark appearance follows the system."))
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                    ForEach(ColorThemePreset.allCases) { preset in
                        presetButton(preset)
                    }
                }
                Divider()
                Text(text("自定义颜色", "Custom Colors"))
                    .font(.subheadline.weight(.semibold))
                colorField(text("主色", "Primary"), id: "primary", value: $primary)
                colorField(text("强调色", "Accent"), id: "accent", value: $accent)
                colorField(text("选中日期", "Selected Date"), id: "selected-date", value: $selectedDate)
                if hasEdited && draft == nil {
                    HStack(alignment: .top, spacing: 6) {
                        if theme.configuration.preset != .default {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(AppTheme.danger)
                                .accessibilityHidden(true)
                        }
                        Text(text("请输入六位十六进制颜色，例如 #166B5D。已保存的主题未更改。",
                                  "Enter six hexadecimal digits, such as #166B5D. Your saved theme is unchanged."))
                            .foregroundStyle(theme.configuration.preset == .default ? AppTheme.danger : theme.text)
                            .accessibilityIdentifier("theme.validation-error")
                    }
                    .font(.caption)
                }
                Button(text("应用自定义颜色", "Apply Custom Colors")) {
                    hasEdited = true
                    if model.setCustomColorTheme(primary: primary, accent: accent, selectedDate: selectedDate) {
                        synchronizeFields()
                        focusedField = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.primaryFill)
                .accessibilityIdentifier("theme.apply-custom")
                preview
                Button(text("恢复默认", "Restore Default")) {
                    model.restoreDefaultColorTheme()
                    synchronizeFields()
                    focusedField = nil
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("theme.restore-default")
                if model.isSampleMode {
                    Text(text("示例模式下仅预览，不修改真实设置或小组件。",
                              "Demo changes are temporary and do not modify your saved settings or widgets."))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("theme.settings")
        .onAppear { synchronizeFields() }
        .onChange(of: model.colorTheme.custom) { _ in synchronizeFields() }
    }

    private func presetButton(_ preset: ColorThemePreset) -> some View {
        let configuration = model.colorTheme.selecting(preset)
        let presetTheme = AppTheme(configuration: configuration)
        let isSelected = model.colorTheme.preset == preset
        return Button {
            model.selectColorTheme(preset)
            synchronizeFields()
            focusedField = nil
            AppHaptics.selection()
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    ForEach([configuration.seeds.primary, configuration.seeds.accent, configuration.seeds.selectedDate].indices, id: \.self) { index in
                        let colors = [configuration.seeds.primary, configuration.seeds.accent, configuration.seeds.selectedDate]
                        Circle().fill(AppThemeColor(colors[index]).color)
                            .frame(width: 17, height: 17)
                            .overlay(Circle().stroke(theme.border, lineWidth: 0.5))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? theme.primary : theme.secondaryText)
                }
                Text(preset.title(english: english))
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(presetTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(preset == .default && isSelected ? theme.primary.opacity(0.10) : presetTheme.background,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? theme.primary : theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.title(english: english))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("theme.preset.\(preset.rawValue)")
    }

    private func colorField(_ label: String, id: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.callout.weight(.medium))
            HStack(spacing: 10) {
                Circle().fill(ThemeRGB(hex: value.wrappedValue).map { AppThemeColor($0).color } ?? theme.secondaryText)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(theme.border))
                    .accessibilityHidden(true)
                TextField("#RRGGBB", text: Binding(get: { value.wrappedValue }, set: {
                    value.wrappedValue = $0
                    hasEdited = true
                }))
                .font(.body.monospaced())
                .textFieldStyle(ThemeTextFieldStyle())
                .autocorrectionDisabled()
                .focused($focusedField, equals: id)
                .accessibilityLabel(label)
                .accessibilityIdentifier("theme.custom.\(id)")
                .onSubmit { focusedField = nil }
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                #endif
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("实时预览", "Live Preview"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
            ThemeSurfacePreview(theme: previewTheme, english: english)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("theme.preview")
    }

    private func synchronizeFields() {
        primary = model.colorTheme.custom.primary.hex
        accent = model.colorTheme.custom.accent.hex
        selectedDate = model.colorTheme.custom.selectedDate.hex
        hasEdited = false
    }
}

struct ThemeSurfacePreview: View {
    let theme: AppTheme
    let english: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(english ? "Today's Courses" : "今日课程", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primary)
                Spacer(minLength: 0)
                Image(systemName: "star.fill").foregroundStyle(theme.accentText)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text("08").font(.headline.monospacedDigit())
                        .padding(10)
                        .foregroundStyle(theme.onPrimary)
                        .background(theme.selectedDate, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.selectedDateOutline))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(english ? "Sample Course" : "示例课程")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.text)
                        Text("08:00 – 09:35")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                Text(english ? "View Schedule" : "查看课表")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.onPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(theme.primaryFill, in: Capsule())
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border))
        }
        .padding(14)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border))
    }
}
