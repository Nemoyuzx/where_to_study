import SwiftUI
#if os(iOS)
import UIKit
#endif

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
            #if os(iOS)
            HStack(alignment: .center, spacing: 12) {
                Text(text("允许官方登录页自动填写"))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)
                QMplusNativeCredentialSwitch(isOn: optedIn, enabled: !sampleMode,
                    tint: theme.primary, label: text("允许官方登录页自动填写"))
                    .fixedSize().layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            #else
            Toggle(text("允许官方登录页自动填写"), isOn: optedIn)
            .toggleStyle(.switch)
            .disabled(sampleMode)
            .accessibilityIdentifier("settings.qmplus.autofill")
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
            Text(text("保存后会在本机安全存储中保留独立 QMplus 登录资料。首次默认开启自动填写，也可在保存前关闭。"))
                .font(.caption).foregroundStyle(theme.secondaryText)
            if authorization.isEnabled {
                Label(text("已在本机安全保存 QMplus 登录资料。"), systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.qmplus.credentials-saved")
            }
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
                if !draft.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.password.isEmpty {
                    Text(text("保存新的登录信息会清除现有 QMplus 会话与快照，避免复用其他身份。"))
                        .font(.caption).foregroundStyle(theme.secondaryText)
                }
                Button(text("安全保存 QMplus 登录资料")) {
                    _ = save(draft.account, draft.password)
                }
                .buttonStyle(.bordered)
                .disabled(sampleMode || draft.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.password.isEmpty)
                .accessibilityIdentifier("settings.qmplus.save-credentials")
                Button(text("删除已保存的 QMplus 登录资料")) { disable(); draft.disableSaving() }
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

#if os(iOS)
// Reserve the UIKit control's fitting size rather than a fixed width. A long
// SwiftUI label must not compress the native switch's rounded track.
private struct QMplusNativeCredentialSwitch: UIViewRepresentable {
    @Binding var isOn: Bool
    let enabled: Bool
    let tint: Color
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(isOn: $isOn) }
    func makeUIView(context: Context) -> UISwitch {
        let control = UISwitch()
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }
    func updateUIView(_ control: UISwitch, context: Context) {
        context.coordinator.isOn = $isOn
        if control.isOn != isOn { control.setOn(isOn, animated: false) }
        control.isEnabled = enabled
        control.onTintColor = UIColor(tint)
        control.accessibilityLabel = label
        control.accessibilityIdentifier = "settings.qmplus.autofill"
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISwitch, context: Context) -> CGSize? {
        let fitted = uiView.sizeThatFits(.zero), intrinsic = uiView.intrinsicContentSize
        return CGSize(width: max(fitted.width, intrinsic.width), height: max(fitted.height, intrinsic.height))
    }
    @MainActor final class Coordinator: NSObject {
        var isOn: Binding<Bool>
        init(isOn: Binding<Bool>) { self.isOn = isOn }
        @objc func changed(_ control: UISwitch) { isOn.wrappedValue = control.isOn }
    }
}
#endif
