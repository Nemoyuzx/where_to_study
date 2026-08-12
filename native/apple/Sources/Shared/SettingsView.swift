import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingClearDataConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(eyebrow: "Where To Study", title: "设置")
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("个人账户", systemImage: "person.crop.circle")
                            .font(.headline)
                        TextField("学号", text: $model.account)
                            .textFieldStyle(.roundedBorder)
                        SecureField(
                            model.canPreserveSavedPassword ? "已安全保存，留空保持不变" : "教务密码",
                            text: $model.password
                        )
                            .textFieldStyle(.roundedBorder)
                        TextField("学期编号", text: $model.termID)
                            .textFieldStyle(.roundedBorder)
                        TextField("第一周周一（YYYY-MM-DD）", text: $model.termStartDate)
                            .textFieldStyle(.roundedBorder)
                        Picker("默认校区", selection: $model.campusID) {
                            Text("西土城").tag("01")
                            Text("沙河").tag("04")
                        }
                        Button {
                            model.saveSettings()
                        } label: {
                            Label("保存设置", systemImage: "checkmark")
                                .foregroundStyle(AppTheme.onPrimary)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primaryFill)
                        Button {
                            if model.saveSettings() {
                                model.refreshSchedule()
                            }
                        } label: {
                            Label(
                                model.isRefreshingSchedule ? "正在获取…" : "获取/刷新个人课表",
                                systemImage: "arrow.clockwise"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isRefreshingSchedule)
                        if !model.statusMessage.isEmpty {
                            Text(model.statusMessage)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("课程提醒", systemImage: "bell")
                            .font(.headline)
                        Toggle(
                            "每天 07:30 发送当日课程摘要",
                            isOn: Binding(
                                get: { model.dailyCourseNotificationsEnabled },
                                set: { enabled in
                                    model.setDailyCourseNotificationsEnabled(enabled)
                                }
                            )
                        )
                        .tint(AppTheme.primary)
                        Text("仅在当天有课时通知；课表更新或账号变更后会自动重排。")
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryText)
                        if !model.dailyCourseNotificationStatusMessage.isEmpty {
                            Text(model.dailyCourseNotificationStatusMessage)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("本地数据", systemImage: "externaldrive")
                            .font(.headline)
                        Text("清除已保存的教务账户与密码、个人课表、空教室和节假日缓存，并恢复本地设置。")
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryText)
                        Link(destination: URL(
                            string: "https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md"
                        )!) {
                            Label("隐私说明", systemImage: "hand.raised")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("隐私说明")
                        .accessibilityHint("在浏览器中打开隐私说明")
                        Button(role: .destructive) {
                            showingClearDataConfirmation = true
                        } label: {
                            Label("清除本地数据", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .accessibilityIdentifier("screen.settings")
        .confirmationDialog(
            "清除本地数据？",
            isPresented: $showingClearDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除本地数据", role: .destructive) {
                model.clearLocalData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除本机保存的账户密码、个人课表、空教室和节假日缓存，且无法撤销。")
        }
    }
}
