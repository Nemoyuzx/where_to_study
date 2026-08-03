import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

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
                        SecureField("教务密码", text: $model.password)
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
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primary)
                        Button {
                            model.saveSettings()
                            model.refreshSchedule()
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
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
    }
}
