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
                Text(text("选择预设或自定义三种颜色，浅色与深色外观仍跟随系统。",
                          "Choose a preset or customize three colors. Light and dark appearance follows the system."))
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
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
                    Text(text("请输入六位十六进制颜色，例如 #166B5D。已保存的主题未更改。",
                              "Enter six hexadecimal digits, such as #166B5D. Your saved theme is unchanged."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                        .accessibilityIdentifier("theme.validation-error")
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
                        .foregroundStyle(AppTheme.secondaryText)
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
                            .overlay(Circle().stroke(AppTheme.border, lineWidth: 0.5))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? theme.primary : AppTheme.secondaryText)
                }
                Text(preset.title(english: english))
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(AppTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.primary.opacity(0.10) : AppTheme.background,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? theme.primary : AppTheme.border))
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
                Circle().fill(ThemeRGB(hex: value.wrappedValue).map { AppThemeColor($0).color } ?? AppTheme.secondaryText)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(AppTheme.border))
                    .accessibilityHidden(true)
                TextField("#RRGGBB", text: Binding(get: { value.wrappedValue }, set: {
                    value.wrappedValue = $0
                    hasEdited = true
                }))
                .font(.body.monospaced())
                .textFieldStyle(.roundedBorder)
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
                .foregroundStyle(AppTheme.secondaryText)
            Label(text("今日课程", "Today's Courses"), systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(previewTheme.primary)
            HStack(alignment: .top, spacing: 10) {
                Text("08").font(.headline)
                    .padding(10)
                    .foregroundStyle(previewTheme.onPrimary)
                    .background(previewTheme.selectedDate, in: RoundedRectangle(cornerRadius: 8))
                Text(text("示例课程 · 08:00", "Sample Course · 08:00"))
                    .font(.callout.weight(.semibold))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(previewTheme.onPrimary)
                    .background(previewTheme.primaryFill, in: RoundedRectangle(cornerRadius: 8))
            }
            Label(text("收藏日程", "Favorite Event"), systemImage: "star.fill")
                .font(.callout)
                .foregroundStyle(previewTheme.accentText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border))
        .accessibilityIdentifier("theme.preview")
    }

    private func synchronizeFields() {
        primary = model.colorTheme.custom.primary.hex
        accent = model.colorTheme.custom.accent.hex
        selectedDate = model.colorTheme.custom.selectedDate.hex
        hasEdited = false
    }
}
