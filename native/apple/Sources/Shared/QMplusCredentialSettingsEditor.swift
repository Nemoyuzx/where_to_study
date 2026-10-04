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
        Binding(get: { draft.wantsToSave || authorization.isEnabled }, set: { enabled in
            if enabled { draft.wantsToSave = true }
            else { disable(); draft.clear() }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(text("保存 QMplus 登录信息并在官方页面自动填写（可选）"), isOn: optedIn)
                .toggleStyle(.switch)
                .disabled(sampleMode).accessibilityIdentifier("settings.qmplus.autofill")
            Text(text("默认关闭。登录信息仅保存在本机系统 Keychain，与北邮密码独立，不上传或同步。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
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
                Text(text("仅在已核验的官方登录页自动选择精确匹配的已保存账号，并填写账号和密码，各步骤最多一次。未匹配的账号选择、MFA、验证码、保持登录、风险及协议确认仍须本人操作。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                Text(text("保存新的登录信息会清除现有 QMplus 会话与快照，避免复用其他身份。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                Button(text("保存并授权 QMplus 官方网页自动填写")) {
                    _ = save(draft.account, draft.password)
                }
                .buttonStyle(.bordered)
                .disabled(sampleMode || draft.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.password.isEmpty)
                .accessibilityIdentifier("settings.qmplus.save-credentials")
                Button(text("关闭自动填写并删除 QMplus 登录信息")) { disable(); draft.clear() }
                    .buttonStyle(.bordered).disabled(sampleMode)
                    .accessibilityIdentifier("settings.qmplus.delete-credentials")
            }
            if !authorization.statusKey.isEmpty {
                Text(text(authorization.statusKey)).font(.caption).foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("settings.qmplus.credential-status")
            }
        }
        .onAppear { if !sampleMode { authorization.loadIfNeeded() } }
        .accessibilityIdentifier("settings.qmplus.credentials")
    }
}
