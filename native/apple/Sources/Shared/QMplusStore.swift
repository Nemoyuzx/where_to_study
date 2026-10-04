import Foundation
import Combine
import WebKit

/// Only WebKit owns the official site's credentials, cookies and session key.
/// Native owns a bounded, typed business snapshot and a revocable request ID.
@MainActor
final class QMplusStore: NSObject, ObservableObject, WKNavigationDelegate {
    static let loginURL = URL(string: "https://qmplus.qmul.ac.uk/my/")!
    private static let identifierKey = "qmplusWebsiteDataStoreIdentifier"
    @Published var isShowingConnection = false
    @Published private(set) var snapshot: QMplusSnapshot?
    @Published private(set) var isSyncing = false
    @Published private(set) var isPartial = false
    @Published private(set) var statusKey = "QMplus 尚未连接"
    @Published private(set) var currentHost = "qmplus.qmul.ac.uk"
    @Published private(set) var canSynchronize = false
    @Published private(set) var navigationFailureCode: String?
    @Published private(set) var webView: WKWebView?
    private let defaults: UserDefaults
    private var generation: UInt64 = 0
    private var timeoutTask: Task<Void, Never>?
    private var dataStore: WKWebsiteDataStore?

    var supportsPersistentIsolation: Bool {
        if #available(iOS 17, macOS 14, *) { return true }
        return false
    }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults; super.init() }

    func connect(sampleMode: Bool) {
        guard !sampleMode else { return }
        navigationFailureCode = nil
        if webView == nil {
            let configuration = WKWebViewConfiguration()
            let store: WKWebsiteDataStore
            if #available(iOS 17, macOS 14, *) {
                let identifier = defaults.string(forKey: Self.identifierKey).flatMap(UUID.init(uuidString:)) ?? UUID()
                defaults.set(identifier.uuidString, forKey: Self.identifierKey)
                store = WKWebsiteDataStore(forIdentifier: identifier)
            } else { store = .nonPersistent() }
            configuration.websiteDataStore = store
            // No script message handler and no credential-reading injection.
            let browser = WKWebView(frame: .zero, configuration: configuration)
            browser.navigationDelegate = self
            dataStore = store
            webView = browser
            browser.load(URLRequest(url: Self.loginURL))
        }
        isShowingConnection = true
    }

    func reloadOfficialPage() {
        endPendingSync()
        navigationFailureCode = nil
        webView?.load(URLRequest(url: Self.loginURL))
    }

    func synchronize() {
        guard !isSyncing, isShowingConnection, let browser = webView,
              Self.isSyncOrigin(browser.url) else { return }
        guard let resource = Bundle.main.url(forResource: "qmplus-sync", withExtension: "js"),
              let script = try? String(contentsOf: resource, encoding: .utf8) else {
            statusKey = "QMplus 同步组件不可用"
            return
        }
        guard let request = beginSynchronization() else { return }
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            // The shared script owns its 120-second deadline and may return
            // a partial snapshot; let it finish before the native watchdog.
            do { try await Task.sleep(for: .seconds(125)) } catch { return }
            guard let self, self.generation == request, self.isSyncing else { return }
            self.endPendingSync()
            self.statusKey = "QMplus 同步超时，请重试"
        }
        browser.evaluateJavaScript(script) { [weak self, weak browser] _, error in
            guard let self, let browser, self.accepts(request: request, browser: browser) else { return }
            guard error == nil else { self.finishFailure(request: request); return }
            browser.callAsyncJavaScript("""
                const result = await WTSQmSync();
                const text = JSON.stringify(result);
                if (new TextEncoder().encode(text).byteLength > 524288) throw new Error('QM_SNAPSHOT_TOO_LARGE');
                return text;
                """, arguments: [:], in: nil, in: .page) { [weak self, weak browser] result in
                guard let self, let browser, self.accepts(request: request, browser: browser) else { return }
                switch result {
                case let .success(value):
                    guard let text = value as? String, let data = text.data(using: .utf8) else {
                        self.finishFailure(request: request); return
                    }
                    self.receive(data, request: request)
                case .failure: self.finishFailure(request: request)
                }
            }
        }
    }

    private struct Envelope: Decodable {
        let ok: Bool
        let partial: Bool
        let errorCode: String?
        enum CodingKeys: String, CodingKey { case ok, partial; case errorCode = "error_code" }
    }

    // Shared by the WebKit entry point and deterministic business-state tests.
    // Starting a flight does not log in, touch cookies or launch a browser.
    func beginSynchronization() -> UInt64? {
        guard !isSyncing else { return nil }
        generation &+= 1
        isSyncing = true
        statusKey = "正在同步 QMplus 课程与活动…"
        return generation
    }

    func receive(_ data: Data, request: UInt64) {
        guard request == generation, isSyncing, data.count <= QMplusSnapshotPolicy.maximumBytes else {
            if request == generation, isSyncing { finishFailure(request: request) }
            return
        }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.ok else {
                finishFailure(request: request)
                if envelope.errorCode == "QM_LOGIN_REQUIRED" { statusKey = "请先在 QMplus 官方网页完成登录" }
                return
            }
            let next = try QMplusSnapshotPolicy.decode(data)
            // Partial, restricted or missing data is never evidence of deletion.
            // Restricted modules are a normal permission fact, not a failed
            // request. They must not freeze unrelated new courses/deadlines.
            isPartial = envelope.partial || !next.warnings.isEmpty
            let hasPrevious = snapshot != nil
            if !isPartial || !hasPrevious { snapshot = next }
            statusKey = isPartial
                ? (hasPrevious ? "QMplus 同步不完整，保留上次快照并请重试" : "QMplus 同步不完整，部分信息尚未获取，请重试")
                : "QMplus 同步完成"
            finish(request: request)
        } catch { finishFailure(request: request) }
    }

    private func accepts(request: UInt64, browser: WKWebView) -> Bool {
        request == generation && isSyncing && isShowingConnection && browser === webView
            && Self.isSyncOrigin(browser.url)
    }

    private func finish(request: UInt64) {
        guard request == generation else { return }
        timeoutTask?.cancel(); timeoutTask = nil
        isSyncing = false
    }

    private func finishFailure(request: UInt64) {
        guard request == generation else { return }
        statusKey = "QMplus 同步失败，请检查官方网页登录状态后重试"
        finish(request: request)
    }

    private func endPendingSync() {
        generation &+= 1
        timeoutTask?.cancel(); timeoutTask = nil
        isSyncing = false
        if let browser = webView, Self.isSyncOrigin(browser.url) {
            browser.evaluateJavaScript("globalThis.WTSQmCancel?.();", completionHandler: nil)
        }
        webView?.stopLoading()
    }

    func endPresentation() { endPendingSync() }

    func suspend() {
        endPendingSync()
        isShowingConnection = false
        snapshot = nil
        isPartial = false
        statusKey = "QMplus 尚未连接"
    }

    func disconnect() {
        endPendingSync()
        isShowingConnection = false
        snapshot = nil
        isPartial = false
        statusKey = "QMplus 尚未连接"
        canSynchronize = false
        navigationFailureCode = nil
        var previousStore = dataStore
        if #available(iOS 17, macOS 14, *), previousStore == nil,
           let identifier = defaults.string(forKey: Self.identifierKey).flatMap(UUID.init(uuidString:)) {
            previousStore = WKWebsiteDataStore(forIdentifier: identifier)
        }
        webView?.navigationDelegate = nil
        webView = nil
        dataStore = nil
        // Rotate the isolated store before asynchronous erasure, so an old
        // browser/late completion can never become the next connection owner.
        defaults.removeObject(forKey: Self.identifierKey)
        previousStore?.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }

    static func isSyncOrigin(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == "qmplus.qmul.ac.uk"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.request.url?.scheme?.lowercased() == "https" else {
            decisionHandler(.cancel); return
        }
        // SSO/MFA stays in the official webpage; only QM's own origin can run
        // the explicit business synchronization, never a Microsoft login page.
        if navigationAction.targetFrame?.isMainFrame != false {
            canSynchronize = false
            if isSyncing { endPendingSync() }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        guard webView === self.webView else { return }
        currentHost = webView.url?.host ?? ""
        canSynchronize = Self.isSyncOrigin(webView.url)
        navigationFailureCode = nil
    }

    static func safeNavigationFailureCode(_ error: Error) -> String? {
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain {
            if failure.code == NSURLErrorCancelled { return nil }
            return "URL_ERROR_\(failure.code)"
        }
        if failure.domain == WKErrorDomain { return "WEBKIT_ERROR_\(failure.code)" }
        return "WEB_NAVIGATION_FAILED"
    }

    private func navigationFailed(in browser: WKWebView, error: Error) {
        guard browser === webView, isShowingConnection,
              let code = Self.safeNavigationFailureCode(error) else { return }
        endPendingSync()
        canSynchronize = false
        navigationFailureCode = code
        statusKey = "QMplus 官方网页登录失败，请重试"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        navigationFailed(in: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        navigationFailed(in: webView, error: error)
    }
}
