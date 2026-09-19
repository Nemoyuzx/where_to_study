import SwiftUI

struct PreClassReminderSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @State private var minuteFields = ["10"]
    @State private var validationFailed = false
    @State private var saved = false
    @FocusState private var focusedRow: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("课前提醒", isOn: Binding(
                get: { model.preClassNotificationsEnabled },
                set: { model.setPreClassNotificationsEnabled($0) }
            ))
            .toggleStyle(.switch)
            .tint(theme.primary)
            .accessibilityIdentifier("settings.pre-class.enabled")
            Text("每次课程或定时考试开始前提醒，默认提前 10 分钟；可设置 1–5 次，每次提前 1–1440 分钟。")
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(minuteFields.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text(model.localizedFormat("提醒 %d", index + 1))
                        .font(.callout)
                    Spacer(minLength: 0)
                    minuteField(index)
                        .frame(width: 78)
                    Text("分钟前")
                        .font(.callout)
                    Button {
                        focusedRow = nil
                        minuteFields.remove(at: index)
                        saved = false
                    } label: {
                        Image(systemName: "minus.circle")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.localizedFormat("移除提醒 %d", index + 1))
                    .accessibilityIdentifier("settings.pre-class.remove.\(index)")
                    .disabled(minuteFields.count == 1)
                }
            }
            HStack {
                Button {
                    minuteFields.append("")
                    saved = false
                } label: {
                    Label("添加提醒", systemImage: "plus")
                }
                .disabled(minuteFields.count >= PreClassNotificationSettings.maximumCount)
                .accessibilityIdentifier("settings.pre-class.add")
                Spacer(minLength: 8)
                Button("保存提醒时间") {
                    focusedRow = nil
                    guard let offsets = PreClassNotificationSettings.parse(minuteFields),
                          model.setPreClassNotificationOffsets(offsets) else {
                        validationFailed = true
                        saved = false
                        return
                    }
                    minuteFields = offsets.map(String.init)
                    validationFailed = false
                    saved = true
                }
                .accessibilityIdentifier("settings.pre-class.save")
            }
            .buttonStyle(.bordered)
            if validationFailed {
                Text("请输入 1–5 个不重复的整数，每个为 1–1440 分钟。")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.pre-class.validation")
            } else if saved {
                Text("课前提醒时间已保存")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("settings.pre-class.saved")
            }
            Text("提醒时间按北京时间计算。设置仅保存在本机；系统限制待发数量，重新打开应用时会补充后续提醒。")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !model.preClassNotificationStatusMessage.isEmpty {
                Text(model.localized(model.preClassNotificationStatusMessage))
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("settings.pre-class.status")
            }
        }
        .disabled(model.isSampleMode && !model.isReviewDemo)
        .onAppear { minuteFields = model.preClassNotificationOffsets.map(String.init) }
        .onChange(of: model.preClassNotificationOffsets) { offsets in
            minuteFields = offsets.map(String.init)
        }
    }

    private func minuteField(_ index: Int) -> some View {
        TextField("分钟", text: Binding(
            get: { minuteFields.indices.contains(index) ? minuteFields[index] : "" },
            set: { value in
                guard minuteFields.indices.contains(index), minuteFields[index] != value else { return }
                minuteFields[index] = value
                saved = false
            }
        ))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .focused($focusedRow, equals: index)
            .accessibilityLabel(model.localizedFormat("提醒 %d 提前分钟数", index + 1))
            .accessibilityIdentifier("settings.pre-class.offset.\(index)")
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
    }
}
