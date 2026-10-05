import SwiftUI

// Store retains both references across Settings tab/sidebar reconstruction;
// only this editing subtree subscribes to credential drafts and authorization.
struct QMplusCredentialSettingsEditor: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var authorization: QMplusCredentialAuthorization
    @ObservedObject var draft: QMplusCredentialDraft
    let language: AppLanguage
    let sampleMode: Bool
    let save: (String, String) -> Bool
    let disable: () -> Void

    private func text(_ key: String) -> String { AppLocalization.string(key, language: language) }
    private var optedIn: Binding<Bool> {
        Binding(get: { draft.wantsToSave }, set: { enabled in
            if enabled { draft.wantsToSave = true }
            else { disable(); draft.disableSaving() }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(text("保存 QMplus 登录信息并在官方页面自动填写（可选）"))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)
                Toggle("", isOn: optedIn)
                    .labelsHidden().toggleStyle(.switch).fixedSize()
                    .frame(width: 52, alignment: .trailing)
                    .layoutPriority(1)
                    .accessibilityLabel(text("保存 QMplus 登录信息并在官方页面自动填写（可选）"))
                    .disabled(sampleMode).accessibilityIdentifier("settings.qmplus.autofill")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(text("保存后会在本机安全存储中保留独立 QMplus 登录资料。首次默认开启自动填写，也可在保存前关闭。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
            if authorization.isEnabled {
                Label(text("已在本机安全保存 QMplus 登录资料。"), systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.qmplus.credentials-saved")
                Text(text("已保存的密码不会回显。仅更新登录资料时需要重新填写。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
            }
            Text(text("关闭“启用 QMplus”只暂停连接和同步，保留登录资料、会话及课程缓存。关闭自动填写、删除登录资料或退出并清除数据，请使用对应操作。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
            if optedIn.wrappedValue {
                TextField(text("QMplus 微软账号"), text: $draft.account)
                    .textFieldStyle(.roundedBorder)
                    .environment(\.layoutDirection, .leftToRight)
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    #endif
                    .disabled(sampleMode).accessibilityIdentifier("settings.qmplus.saved-account")
                SecureField(text("QMplus 微软密码"), text: $draft.password)
                    .textFieldStyle(.roundedBorder)
                    .environment(\.layoutDirection, .leftToRight)
                    .disabled(sampleMode).accessibilityIdentifier("settings.qmplus.saved-password")
                Text(text("已保存的账号和密码用于自动完成官方登录；只有验证码或 MFA 需要您操作。未知页面会暂停，可手动继续。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                Text(text("保存新的登录信息会清除现有 QMplus 会话与快照，避免复用其他身份。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                Button(text("保存并授权 QMplus 官方网页自动填写")) {
                    _ = save(draft.account, draft.password)
                }
                .buttonStyle(.bordered)
                .disabled(sampleMode || draft.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.password.isEmpty)
                .accessibilityIdentifier("settings.qmplus.save-credentials")
                Button(text("关闭自动填写并删除 QMplus 登录信息")) { disable(); draft.disableSaving() }
                    .buttonStyle(.bordered).disabled(sampleMode)
                    .accessibilityIdentifier("settings.qmplus.delete-credentials")
            }
            if !authorization.statusKey.isEmpty &&
                !(authorization.isEnabled && authorization.statusKey == "已保存 QMplus 登录信息并授权官方网页自动填写") {
                Text(text(authorization.statusKey)).font(.caption).foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("settings.qmplus.credential-status")
            }
        }
        .onAppear { if !sampleMode { authorization.loadIfNeeded() } }
        .accessibilityIdentifier("settings.qmplus.credentials")
    }
}
