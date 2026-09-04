import Foundation
import SwiftUI

@MainActor
final class PrivacyConsentState: ObservableObject {
    static let storageKey = "privacyConsentVersion"
    static let currentVersion = 1

    @Published private(set) var hasAccepted: Bool
    @Published private(set) var hasDeclined = false

    private let defaults: UserDefaults
    private let bypassesConsent: Bool

    init(
        defaults: UserDefaults = .standard,
        bypassesConsent: Bool = false,
        resetsConsent: Bool = false
    ) {
        self.defaults = defaults
        self.bypassesConsent = bypassesConsent
        if resetsConsent {
            defaults.removeObject(forKey: Self.storageKey)
        }
        hasAccepted = bypassesConsent
            || defaults.integer(forKey: Self.storageKey) >= Self.currentVersion
    }

    func accept() {
        defaults.set(Self.currentVersion, forKey: Self.storageKey)
        hasDeclined = false
        hasAccepted = true
    }

    func decline() {
        guard !bypassesConsent else { return }
        hasDeclined = true
    }

    func reconsider() {
        hasDeclined = false
    }
}

struct PrivacyConsentGate: View {
    @ObservedObject var state: PrivacyConsentState
    @State private var showingPrivacyPolicy = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: state.hasDeclined ? "hand.raised.slash" : "hand.raised.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                        .accessibilityHidden(true)

                    Text(LocalizedStringKey(
                        state.hasDeclined
                            ? "未同意隐私政策，无法使用应用"
                            : "欢迎使用 Where To Study"
                    ))
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.text)
                        .multilineTextAlignment(.center)

                    Text(LocalizedStringKey(
                        state.hasDeclined
                            ? "您可以重新阅读隐私政策，并在同意后继续使用。"
                            : "首次使用前，请先阅读并同意《隐私政策》。应用会处理您主动提供的账号信息；保存有效账号后，还可能按已启用的设置自动刷新课表、空教室与公开数据。具体内容以完整政策为准。"
                    ))
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        AppHaptics.impact()
                        showingPrivacyPolicy = true
                    } label: {
                        Label("查看完整隐私政策", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("privacy-consent.open-policy")

                    if state.hasDeclined {
                        Button {
                            AppHaptics.impact()
                            state.reconsider()
                        } label: {
                            Text("重新查看并选择")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("privacy-consent.reconsider")
                    } else {
                        Button {
                            AppHaptics.impact()
                            state.accept()
                        } label: {
                            Text("同意并继续")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("privacy-consent.accept")

                        Button("不同意，暂不使用") {
                            AppHaptics.impact()
                            state.decline()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.secondaryText)
                        .accessibilityIdentifier("privacy-consent.decline")
                    }
                }
                .padding(28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("screen.privacy-consent")
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }
}
