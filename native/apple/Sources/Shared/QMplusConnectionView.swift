import SwiftUI
import WebKit

struct QMplusConnectionPresentationHost: View {
    @ObservedObject var store: QMplusStore

    var body: some View {
        Color.clear.sheet(isPresented: $store.isShowingConnection, onDismiss: store.endPresentation) {
            QMplusConnectionView(store: store)
        }
    }
}

private struct QMplusConnectionView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: QMplusStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text(model.localized("请在官方网页完成 SSO 与 MFA。本应用不读取或保存微软密码。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                Text(store.currentHost).font(.caption.monospaced()).foregroundStyle(theme.secondaryText)
                if !store.supportsPersistentIsolation {
                    Text(model.localized("当前系统使用隔离临时会话，关闭应用后可能需要重新登录。"))
                        .font(.caption).foregroundStyle(theme.secondaryText)
                }
                Text(model.localized(store.statusKey)).font(.caption).foregroundStyle(theme.secondaryText)
                if let code = store.navigationFailureCode {
                    Text(code).font(.caption.monospaced()).foregroundStyle(theme.secondaryText)
                        .accessibilityIdentifier("qmplus.connection.error")
                }
                if store.isSyncing { ProgressView() }
                if let browser = store.webView { QMplusOfficialWebView(browser: browser) }
            }
            .padding(.top, 8)
            .background(theme.background)
            .navigationTitle(model.localized("连接 QMplus"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.localized("完成")) {
                        store.endPresentation(); store.isShowingConnection = false
                    }.accessibilityIdentifier("qmplus.connection.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    QMplusConnectionToolbarActions(language: model.appLanguage,
                        canSynchronize: store.canSynchronize, isSyncing: store.isSyncing,
                        reload: store.reloadOfficialPage, synchronize: store.synchronize)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 560)
        #endif
        .accessibilityIdentifier("qmplus.connection.page")
    }
}

// A single native toolbar item hosts both controls on macOS and iOS. This
// presentation-only component can be rendered without a WebView or account.
struct QMplusToolbarActionDescriptor: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case reload, synchronize }
    let kind: Kind
    let label: String
    let enabled: Bool
    let image: String?
    var id: String { kind == .reload ? "qmplus.connection.reload" : "qmplus.connection.sync" }

    static func actions(language: AppLanguage, canSynchronize: Bool, isSyncing: Bool) -> [Self] {
        [Self(kind: .reload, label: AppLocalization.string("打开 QMplus 官方登录页", language: language), enabled: true, image: "arrow.clockwise"),
         Self(kind: .synchronize, label: AppLocalization.string("登录后同步", language: language),
              enabled: canSynchronize && !isSyncing, image: nil)]
    }
}

struct QMplusConnectionToolbarActions: View {
    let language: AppLanguage
    let canSynchronize: Bool
    let isSyncing: Bool
    let reload: () -> Void
    let synchronize: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(QMplusToolbarActionDescriptor.actions(language: language, canSynchronize: canSynchronize, isSyncing: isSyncing)) { action in
                Button {
                    switch action.kind {
                    case .reload: reload()
                    case .synchronize: synchronize()
                    }
                } label: {
                    if let image = action.image { Image(systemName: image) } else { Text(action.label) }
                }
                .disabled(!action.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel(action.label)
                .accessibilityIdentifier(action.id)
            }
        }
    }
}

#if DEBUG && os(iOS)
struct QMplusToolbarUITestFixture: View {
    let language: AppLanguage
    @State private var canSynchronize = false
    @State private var isSyncing = false
    @State private var reloadCount = 0
    @State private var syncCount = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Synthetic QMplus toolbar · no WebView or network")
                Toggle("Synthetic signed-in state", isOn: $canSynchronize)
                    .accessibilityIdentifier("qmplus.toolbar.fixture.ready")
                Toggle("Synthetic busy state", isOn: $isSyncing)
                    .accessibilityIdentifier("qmplus.toolbar.fixture.busy")
                Text("reload=\(reloadCount);sync=\(syncCount)")
                    .accessibilityIdentifier("qmplus.toolbar.fixture.actions")
            }
            .padding(16)
            .navigationTitle(AppLocalization.string("连接 QMplus", language: language))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    QMplusConnectionToolbarActions(language: language, canSynchronize: canSynchronize,
                        isSyncing: isSyncing, reload: { reloadCount += 1 }, synchronize: { syncCount += 1 })
                }
            }
        }.accessibilityIdentifier("qmplus.toolbar.fixture.page")
    }
}
#endif

#if os(iOS)
private struct QMplusOfficialWebView: UIViewRepresentable {
    let browser: WKWebView
    func makeUIView(context _: Context) -> WKWebView { browser }
    func updateUIView(_: WKWebView, context _: Context) {}
}
#else
private struct QMplusOfficialWebView: NSViewRepresentable {
    let browser: WKWebView
    func makeNSView(context _: Context) -> WKWebView { browser }
    func updateNSView(_: WKWebView, context _: Context) {}
}
#endif
