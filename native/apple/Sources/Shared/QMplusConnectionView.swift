import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#endif

struct QMplusConnectionPresentationHost: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: QMplusStore

    var body: some View {
        Color.clear
        .background {
            if let browser = store.quietBrowser,
               let lease = store.browserMountLease(for: browser, role: .quiet) {
                QMplusOfficialWebView(browser: browser, lease: lease, store: store)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .sheet(isPresented: $store.isShowingConnection, onDismiss: store.connectionSheetDidDismiss) {
            QMplusConnectionView(store: store)
        }
        .onChange(of: scenePhase) {
            if $0 == .active { store.resumeAuthenticationRecognitionForActiveScene() }
            else { store.stopAutomaticLoginForInactiveScene() }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.resumeAuthenticationRecognitionForActiveScene()
        }
        #endif
        .onDisappear { store.endPresentation() }
    }
}

private struct QMplusConnectionView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: QMplusStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text(model.localized("请在官方网页完成 SSO 与 MFA；可选自动填写只用于已确认的官方登录页面。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                Text(store.currentHost).font(.caption.monospaced()).foregroundStyle(theme.secondaryText)
                if !store.supportsPersistentIsolation {
                    Text(model.localized("当前系统使用隔离临时会话，关闭应用后可能需要重新登录。"))
                        .font(.caption).foregroundStyle(theme.secondaryText)
                }
                Text(model.localized(store.statusKey)).font(.caption).foregroundStyle(theme.secondaryText)
                Text(model.localized("登录完成后会自动同步一次 EBU 课程与活动；失败时可手动重试。"))
                    .font(.caption).foregroundStyle(theme.secondaryText)
                if let code = store.navigationFailureCode {
                    Text(code).font(.caption.monospaced()).foregroundStyle(theme.secondaryText)
                        .accessibilityIdentifier("qmplus.connection.error")
                }
                if store.isSyncing { ProgressView() }
                if store.popupWebView != nil {
                    Button(model.localized("返回主登录页面")) { store.closeAuthenticationPopup() }
                        .accessibilityIdentifier("qmplus.connection.close-popup")
                }
                if let browser = store.popupWebView ?? store.webView,
                   let lease = store.browserMountLease(for: browser, role: .visible) {
                    QMplusOfficialWebView(browser: browser, lease: lease, store: store).id(ObjectIdentifier(browser))
                }
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
                        reload: store.reloadOfficialPage)
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
    enum Kind: String, Sendable { case reload }
    let kind: Kind
    let label: String
    let enabled: Bool
    let image: String?
    var id: String { "qmplus.connection.reload" }

    static func actions(language: AppLanguage) -> [Self] {
        [Self(kind: .reload, label: AppLocalization.string("打开 QMplus 官方登录页", language: language), enabled: true, image: "arrow.clockwise")]
    }
}

struct QMplusConnectionToolbarActions: View {
    let language: AppLanguage
    let reload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(QMplusToolbarActionDescriptor.actions(language: language)) { action in
                Button(action: reload) {
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
    @State private var reloadCount = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Synthetic QMplus toolbar · no WebView or network")
                Text("reload=\(reloadCount)")
                    .accessibilityIdentifier("qmplus.toolbar.fixture.actions")
            }
            .padding(16)
            .navigationTitle(AppLocalization.string("连接 QMplus", language: language))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    QMplusConnectionToolbarActions(language: language, reload: { reloadCount += 1 })
                }
            }
        }.accessibilityIdentifier("qmplus.toolbar.fixture.page")
    }
}
#endif

#if os(iOS)
private struct QMplusOfficialWebView: UIViewRepresentable {
    @Environment(\.appTheme) private var theme
    let browser: WKWebView
    let lease: QMplusBrowserMountLease
    let store: QMplusStore
    func makeUIView(context _: Context) -> QMplusWebViewContainer {
        let view = QMplusWebViewContainer(); configure(view); return view
    }
    func updateUIView(_ view: QMplusWebViewContainer, context _: Context) { configure(view) }
    static func dismantleUIView(_ view: QMplusWebViewContainer, coordinator _: ()) { view.detachIfOwned() }
    private func configure(_ view: QMplusWebViewContainer) {
        view.configure(browser, lease: lease, shieldColor: UIColor(theme.background).withAlphaComponent(1)) {
            store.acceptsBrowserMountLease(lease, for: browser)
        }
    }
}

@MainActor
final class QMplusWebViewContainer: UIView {
    private weak var browser: WKWebView?
    private var quiet = false
    private let shield = UIView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        shield.backgroundColor = UIColor.systemBackground.withAlphaComponent(1)
        shield.isOpaque = true; shield.isUserInteractionEnabled = false; shield.accessibilityElementsHidden = true
        shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(shield)
    }
    required init?(coder: NSCoder) { fatalError("QMplus containers are constructed programmatically") }
    func configure(_ browser: WKWebView, lease: QMplusBrowserMountLease, shieldColor: UIColor? = nil,
                   isCurrent: @MainActor () -> Bool) {
        guard lease.browser == ObjectIdentifier(browser), isCurrent() else { return }
        let quiet = lease.role == .quiet
        self.browser = browser; self.quiet = quiet
        isUserInteractionEnabled = !quiet; accessibilityElementsHidden = quiet
        browser.accessibilityElementsHidden = quiet
        shield.backgroundColor = (shieldColor ?? .systemBackground).withAlphaComponent(1)
        shield.isHidden = !quiet
        if browser.superview !== self { browser.removeFromSuperview(); addSubview(browser) }
        // Keep WebKit normally rendered beneath a native opaque shield instead
        // of changing its rendering visibility to hide the official page.
        browser.alpha = 1
        browser.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        browser.frame = bounds
        shield.frame = bounds; bringSubviewToFront(shield)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let browser, browser.superview === self { browser.frame = bounds }
        shield.frame = bounds; bringSubviewToFront(shield)
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        quiet ? nil : super.hitTest(point, with: event)
    }
    func detachIfOwned() {
        if let browser, browser.superview === self { browser.removeFromSuperview() }
        browser = nil
    }
}
#else
private struct QMplusOfficialWebView: NSViewRepresentable {
    @Environment(\.appTheme) private var theme
    let browser: WKWebView
    let lease: QMplusBrowserMountLease
    let store: QMplusStore
    func makeNSView(context _: Context) -> QMplusWebViewContainer {
        let view = QMplusWebViewContainer(); configure(view); return view
    }
    func updateNSView(_ view: QMplusWebViewContainer, context _: Context) { configure(view) }
    static func dismantleNSView(_ view: QMplusWebViewContainer, coordinator _: ()) { view.detachIfOwned() }
    private func configure(_ view: QMplusWebViewContainer) {
        view.configure(browser, lease: lease, shieldColor: NSColor(theme.background).withAlphaComponent(1)) {
            store.acceptsBrowserMountLease(lease, for: browser)
        }
    }
}

@MainActor
final class QMplusWebViewContainer: NSView {
    private weak var browser: WKWebView?
    private var quiet = false
    private let shield = NSView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        shield.wantsLayer = true
        shield.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(1).cgColor
        shield.setAccessibilityHidden(true)
        shield.autoresizingMask = [.width, .height]
        addSubview(shield)
    }
    required init?(coder: NSCoder) { fatalError("QMplus containers are constructed programmatically") }
    func configure(_ browser: WKWebView, lease: QMplusBrowserMountLease, shieldColor: NSColor? = nil,
                   isCurrent: @MainActor () -> Bool) {
        guard lease.browser == ObjectIdentifier(browser), isCurrent() else { return }
        let quiet = lease.role == .quiet
        self.browser = browser; self.quiet = quiet
        setAccessibilityHidden(quiet); browser.setAccessibilityHidden(quiet)
        shield.layer?.backgroundColor = (shieldColor ?? .windowBackgroundColor).withAlphaComponent(1).cgColor
        shield.isHidden = !quiet
        if browser.superview !== self { browser.removeFromSuperview(); addSubview(browser) }
        browser.alphaValue = 1
        browser.autoresizingMask = [.width, .height]
        browser.frame = bounds
        shield.frame = bounds; addSubview(shield, positioned: .above, relativeTo: nil)
    }
    override func layout() {
        super.layout()
        if let browser, browser.superview === self { browser.frame = bounds }
        shield.frame = bounds; addSubview(shield, positioned: .above, relativeTo: nil)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { quiet ? nil : super.hitTest(point) }
    func detachIfOwned() {
        if let browser, browser.superview === self { browser.removeFromSuperview() }
        browser = nil
    }
}
#endif
