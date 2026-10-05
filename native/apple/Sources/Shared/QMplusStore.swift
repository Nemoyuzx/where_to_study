import Foundation
import Combine
import WebKit
#if os(macOS)
import AppKit
#endif

struct QMplusBrowserMountLease: Equatable, Sendable {
    enum Role: Equatable, Sendable { case quiet, visible }
    let presentation: UInt64
    let role: Role
    let browser: ObjectIdentifier
}

/// WebKit owns site cookies/session keys. Optional saved credentials remain in
/// a separate on-device Keychain record, never in the typed business snapshot.
@MainActor
final class QMplusStore: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let loginURL = URL(string: "https://qmplus.qmul.ac.uk/my/")!
    static func dashboardRequest() -> URLRequest {
        var request = URLRequest(url: loginURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        return request
    }
    let credentialAuthorization: QMplusCredentialAuthorization
    let credentialDraft = QMplusCredentialDraft()
    private static let identifierKey = "qmplusWebsiteDataStoreIdentifier"
    @Published var isShowingConnection = false
    @Published private(set) var snapshot: QMplusSnapshot?
    @Published private(set) var isSyncing = false
    @Published private(set) var isPartial = false
    @Published private(set) var isRetainingPreviousSnapshot = false
    @Published private(set) var statusKey = "QMplus 尚未连接"
    @Published private(set) var currentHost = "qmplus.qmul.ac.uk"
    @Published private(set) var canSynchronize = false
    @Published private(set) var navigationFailureCode: String?
    @Published private(set) var featureEnabled = true
    private var preservingAutomaticSheetDismissal = false
    func setFeatureEnabled(_ enabled: Bool) {
        guard featureEnabled != enabled else { return }
        featureEnabled = enabled
        if !enabled { endPresentation() }
    }

    func connectionSheetDidDismiss() {
        if preservingAutomaticSheetDismissal {
            preservingAutomaticSheetDismissal = false
            return
        }
        // A delayed dismissal from the old sheet is not permission to cancel
        // a newer visible owner or an owner already transferred to quiet sync.
        if isShowingConnection || isQuietConnection { return }
        endPresentation()
    }

    func hideVerifiedConnectionForSynchronization() {
        guard featureEnabled, hasActiveConnection, isSyncing, isShowingConnection else { return }
        preservingAutomaticSheetDismissal = true
        loginGate.hideExistingConnection()
        isShowingConnection = false
    }
    @Published private(set) var webView: WKWebView?
    @Published private(set) var popupWebView: WKWebView?
    private let defaults: UserDefaults
    private var generation: UInt64 = 0
    private var timeoutTask: Task<Void, Never>?
    private var dataStore: WKWebsiteDataStore?
    private var loginGate = QMplusLoginSynchronizationGate()
    private var authenticationProbeTask: Task<Void, Never>?
    private var quietPreflightTimeoutTask: Task<Void, Never>?
    private var urlObservation: NSKeyValueObservation?
    private var activeNavigation: WKNavigation?
    private var activePopupNavigation: WKNavigation?
    private var mainHTTPFailureCode: String?
    private var popupHTTPFailureCode: String?
    private var popupDocument: UInt64 = 0
    private var authenticationProbeContext: QMplusLoginSynchronizationGate.Context?
    // Ephemeral WebKit navigation identity, never encoded or persisted.
    private var lastReviewedDocumentURL: URL?
    private let autofillLedger = QMplusAutofillLedger()
    private var automaticLoginSuspended = false
    private var authenticationRecognitionSuspended = false
    private var autofillPipeline: QMplusAutofillPipeline?
    private var autofillDocument: OwnedAutofillDocument?
    private var viewportWaitTask: Task<Void, Never>?
    private var viewportWaitDocument: OwnedAutofillDocument?
    private struct OwnedAutofillDocument: Equatable {
        let connection: QMplusLoginSynchronizationGate.Context
        let credentialRevision: UInt64
        let popupDocument: UInt64?
        let browser: ObjectIdentifier
        let url: URL
    }
    var hasActiveConnection: Bool { loginGate.isActive }
    var hasActiveAuthenticationRecognition: Bool { hasActiveConnection && !authenticationRecognitionSuspended }
    var hasActiveAutofillLedger: Bool {
        !automaticLoginSuspended && hasActiveConnection && autofillLedger.accepts(
            presentation: loginGate.presentation, credentialRevision: credentialAuthorization.credentialRevision)
    }
    private var isQuietConnection: Bool { loginGate.ownerKind == .quiet }
    var quietBrowser: WKWebView? { isQuietConnection ? webView : nil }

    func browserMountLease(for browser: WKWebView, role: QMplusBrowserMountLease.Role) -> QMplusBrowserMountLease? {
        guard hasActiveConnection else { return nil }
        switch role {
        case .quiet:
            guard isQuietConnection, popupWebView == nil, browser === webView else { return nil }
        case .visible:
            guard loginGate.isPresented, isShowingConnection, browser === (popupWebView ?? webView) else { return nil }
        }
        return QMplusBrowserMountLease(presentation: loginGate.presentation, role: role, browser: ObjectIdentifier(browser))
    }

    func acceptsBrowserMountLease(_ lease: QMplusBrowserMountLease, for browser: WKWebView) -> Bool {
        browserMountLease(for: browser, role: lease.role) == lease
    }

    var supportsPersistentIsolation: Bool {
        if #available(iOS 17, macOS 14, *) { return true }
        return false
    }

    init(defaults: UserDefaults = .standard,
         credentialStore: any QMplusCredentialStoring = QMplusKeychainCredentialStore(),
         authorizationJournal: (any QMplusCredentialAuthorizationJournaling)? = nil,
         allowsCredentialStorage: Bool = !AppLaunchConfiguration.isXCTestRunning && !AppLaunchConfiguration.isUITesting && !AppLaunchConfiguration.isReviewDemo) {
        self.defaults = defaults
        credentialAuthorization = QMplusCredentialAuthorization(storage: credentialStore,
            journal: authorizationJournal ?? QMplusDefaultsAuthorizationJournal(defaults: defaults), allowsStorage: allowsCredentialStorage)
        super.init()
    }

    @discardableResult
    func saveCredentials(account: String, password: String) -> Bool {
        endPresentation()
        let saved = credentialAuthorization.saveAndAuthorize(account: account, password: password)
        credentialDraft.clear()
        if saved { clearOfficialSession() }
        return saved
    }

    func disableCredentialAutofill() {
        endPresentation()
        credentialAuthorization.disableAndDelete()
        credentialDraft.clear()
    }

    func connect(sampleMode: Bool) {
        guard featureEnabled, !sampleMode else { return }
        if hasActiveConnection {
            if isQuietConnection { presentExistingConnection(stopAutofill: false) }
            return
        }
        credentialAuthorization.restoreAuthorization()
        let hasIsolatedSession = defaults.string(forKey: Self.identifierKey).flatMap(UUID.init(uuidString:)) != nil
        let quiet = supportsPersistentIsolation && (hasIsolatedSession || credentialAuthorization.isEnabled)
        guard beginConnectionOwner(quiet: quiet) else { return }
        if quiet {
            let context = loginGate.context
            quietPreflightTimeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard let self, self.hasActiveConnection, self.loginGate.presentation == context.presentation,
                      self.isQuietConnection, !self.isSyncing else { return }
                self.statusKey = "QMplus 会话核查超时，请在官方网页继续登录。"
                self.presentExistingConnection()
            }
        }
        navigationFailureCode = nil
        canSynchronize = false
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
            browser.uiDelegate = self
            dataStore = store
            webView = browser
        }
        if let browser = webView {
            observeCurrentBrowser(browser)
            // Reconnection is a fresh dashboard GET, not a reload of a stale
            // welcome/error document or a replay of the SAML ACS POST.
            activeNavigation = browser.load(Self.dashboardRequest())
        }
    }

    // A logical connection owner is independent of sheet visibility. This
    // same pure boundary lets tests exercise quiet cancellation without WK.
    @discardableResult
    func beginConnectionOwner(quiet: Bool) -> Bool {
        guard featureEnabled, !hasActiveConnection else { return false }
        if quiet { loginGate.beginQuietConnection() } else { loginGate.beginPresentation() }
        automaticLoginSuspended = false
        authenticationRecognitionSuspended = false
        autofillLedger.begin(presentation: loginGate.presentation, credentialRevision: credentialAuthorization.credentialRevision)
        statusKey = "正在确认 QMplus 登录状态…"
        isShowingConnection = !quiet
        return true
    }

    private func presentExistingConnection(stopAutofill: Bool = true) {
        guard hasActiveConnection else { return }
        if let browser = popupWebView ?? webView, isAutofillApplicationInactive(browser) {
            stopAutomaticLoginForInactiveScene(); return
        }
        if stopAutofill { cancelAutofill(); autofillLedger.stop() }
        quietPreflightTimeoutTask?.cancel(); quietPreflightTimeoutTask = nil
        loginGate.presentExistingConnection()
        isShowingConnection = true
    }

    func cancelQuietConnection() {
        if isQuietConnection { endPresentation() }
    }

    func stopAutomaticLoginForInactiveScene() {
        guard hasActiveConnection else { return }
        automaticLoginSuspended = true
        authenticationRecognitionSuspended = true
        cancelAutofill()
        autofillLedger.stop()
        cancelAuthenticationProbe()
        quietPreflightTimeoutTask?.cancel(); quietPreflightTimeoutTask = nil
        if isQuietConnection {
            endPresentation()
        } else {
            // Retire late DOM/sync callbacks without closing or stopping the
            // visible official MFA page, changing focus, or clearing its cache.
            loginGate.beginDocument()
            endPendingSync(stopLoading: false)
            if credentialAuthorization.isEnabled {
                statusKey = "QMplus 自动填写已停止，请在官方网页手动完成登录或验证。"
            }
        }
    }

    // Returning to the foreground may inspect the current official session.
    // The credential ledger stays stopped; never reload or resubmit the MFA page.
    func resumeAuthenticationRecognitionForActiveScene() {
        guard hasActiveConnection, authenticationRecognitionSuspended else { return }
        authenticationRecognitionSuspended = false
        guard let browser = popupWebView ?? webView else { return }
        if isAutofillApplicationInactive(browser) { stopAutomaticLoginForInactiveScene(); return }
        if browser === popupWebView { reviewAuthenticationPopup(browser) }
        else { reviewCurrentDocument(in: browser) }
    }

    func reloadOfficialPage() {
        guard featureEnabled, let browser = webView else { return }
        // This explicit user action starts a new owner and once-only ledger.
        // An automatic response/error callback never restarts authentication.
        endPresentation()
        credentialAuthorization.restoreAuthorization()
        guard beginConnectionOwner(quiet: false) else { return }
        navigationFailureCode = nil
        observeCurrentBrowser(browser)
        activeNavigation = browser.load(Self.dashboardRequest())
    }

    func synchronize() {
        guard featureEnabled, canSynchronize, !isSyncing, hasActiveConnection, let browser = webView,
              popupWebView == nil, !browser.isLoading, Self.isSyncOrigin(browser.url) else { return }
        guard let resource = Bundle.main.url(forResource: "qmplus-sync", withExtension: "js"),
              let script = try? String(contentsOf: resource, encoding: .utf8) else {
            isRetainingPreviousSnapshot = snapshot != nil
            statusKey = "QMplus 同步组件不可用"
            presentExistingConnection()
            return
        }
        guard let request = beginSynchronization() else { return }
        hideVerifiedConnectionForSynchronization()
        quietPreflightTimeoutTask?.cancel(); quietPreflightTimeoutTask = nil
        let context = loginGate.context
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            // The shared script owns its 120-second deadline and may return
            // a partial snapshot; let it finish before the native watchdog.
            do { try await Task.sleep(for: .seconds(125)) } catch { return }
            guard let self, self.generation == request, self.isSyncing else { return }
            self.endPendingSync()
            self.statusKey = "QMplus 同步超时，请重试"
            self.presentExistingConnection()
        }
        browser.evaluateJavaScript(script) { [weak self, weak browser] _, error in
            guard let self, let browser, self.accepts(request: request, browser: browser, context: context) else { return }
            guard error == nil else { self.finishFailure(request: request); return }
            browser.callAsyncJavaScript("""
                const result = await WTSQmSync();
                const text = JSON.stringify(result);
                if (new TextEncoder().encode(text).byteLength > 524288) throw new Error('QM_SNAPSHOT_TOO_LARGE');
                return text;
                """, arguments: [:], in: nil, in: .page) { [weak self, weak browser] result in
                guard let self, let browser, self.accepts(request: request, browser: browser, context: context) else { return }
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
        guard featureEnabled, !isSyncing else { return nil }
        generation &+= 1
        isSyncing = true
        statusKey = "正在同步 QMplus 课程与活动…"
        return generation
    }

    func receive(_ data: Data, request: UInt64) {
        guard featureEnabled else { return }
        guard request == generation, isSyncing, data.count <= QMplusSnapshotPolicy.maximumBytes else {
            if request == generation, isSyncing { finishFailure(request: request) }
            return
        }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.ok else {
                if ["QM_LOGIN_REQUIRED", "QM_ERROR_PAGE"].contains(envelope.errorCode ?? "") {
                    canSynchronize = false
                }
                finishFailure(request: request)
                if envelope.errorCode == "QM_LOGIN_REQUIRED" { statusKey = "请先在 QMplus 官方网页完成登录" }
                if envelope.errorCode == "QM_ERROR_PAGE" {
                    navigationFailureCode = "QM_OFFICIAL_EXCEPTION"
                    statusKey = "QMplus 官方网页登录失败，请重试"
                }
                return
            }
            let next = try QMplusSnapshotPolicy.decode(data)
            // Partial, restricted or missing data is never evidence of deletion.
            // Restricted modules are a normal permission fact, not a failed
            // request. They must not freeze unrelated new courses/deadlines.
            isPartial = envelope.partial || !next.warnings.isEmpty
            let hasPrevious = snapshot != nil
            isRetainingPreviousSnapshot = isPartial && hasPrevious
            if !isPartial || !hasPrevious { snapshot = next }
            statusKey = isPartial
                ? (hasPrevious ? "QMplus 同步不完整，保留上次快照并请重试" : "QMplus 同步不完整，部分信息尚未获取，请重试")
                : "QMplus 同步完成"
            finish(request: request)
        } catch { finishFailure(request: request) }
    }

    private func accepts(request: UInt64, browser: WKWebView, context: QMplusLoginSynchronizationGate.Context) -> Bool {
        request == generation && isSyncing && hasActiveConnection && browser === webView
            && popupWebView == nil && loginGate.accepts(context) && Self.isSyncOrigin(browser.url)
    }

    private func finish(request: UInt64) {
        guard request == generation, isSyncing else { return }
        timeoutTask?.cancel(); timeoutTask = nil
        isSyncing = false
        if isQuietConnection {
            if statusKey == "QMplus 同步完成" { endPresentation() }
            else { presentExistingConnection() }
        }
    }

    // Same terminal boundary for WebKit errors and deterministic callback tests.
    // A completed flight cannot be changed by another result with its old ID.
    func finishFailure(request: UInt64) {
        guard request == generation, isSyncing else { return }
        isRetainingPreviousSnapshot = snapshot != nil
        statusKey = "QMplus 同步失败，请检查官方网页登录状态后重试"
        finish(request: request)
    }

    private func endPendingSync(stopLoading: Bool = true) {
        if isSyncing {
            isRetainingPreviousSnapshot = snapshot != nil
            statusKey = "QMplus 同步已取消，可重新连接后重试"
        }
        generation &+= 1
        timeoutTask?.cancel(); timeoutTask = nil
        isSyncing = false
        if let browser = webView, Self.isSyncOrigin(browser.url) {
            browser.evaluateJavaScript("globalThis.WTSQmCancel?.();", completionHandler: nil)
        }
        if stopLoading { webView?.stopLoading() }
    }

    func endPresentation() {
        preservingAutomaticSheetDismissal = false
        loginGate.endPresentation()
        cancelAutofill()
        autofillLedger.stop()
        isShowingConnection = false
        quietPreflightTimeoutTask?.cancel(); quietPreflightTimeoutTask = nil
        cancelAuthenticationProbe()
        urlObservation = nil
        activeNavigation = nil
        lastReviewedDocumentURL = nil
        canSynchronize = false
        closeAuthenticationPopup(reloadMain: false)
        let wasSyncing = isSyncing
        endPendingSync()
        if wasSyncing { statusKey = "QMplus 同步已取消，可重新连接后重试" }
    }

    func suspend() {
        endPresentation()
        credentialAuthorization.suspendInMemory()
        credentialDraft.clear()
        isShowingConnection = false
        snapshot = nil
        isPartial = false
        isRetainingPreviousSnapshot = false
        statusKey = "QMplus 尚未连接"
    }

    func disconnect() {
        disableCredentialAutofill()
        clearOfficialSession()
    }

    private func clearOfficialSession() {
        endPresentation()
        isShowingConnection = false
        snapshot = nil
        isPartial = false
        isRetainingPreviousSnapshot = false
        statusKey = "QMplus 尚未连接"
        canSynchronize = false
        navigationFailureCode = nil
        var previousStore = dataStore
        if #available(iOS 17, macOS 14, *), previousStore == nil,
           let identifier = defaults.string(forKey: Self.identifierKey).flatMap(UUID.init(uuidString:)) {
            previousStore = WKWebsiteDataStore(forIdentifier: identifier)
        }
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
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
        guard (webView === self.webView || webView === popupWebView), hasActiveConnection,
              QMplusConnectionPolicy.isHTTPSNavigation(navigationAction.request.url) else {
            decisionHandler(.cancel); return
        }
        // SSO/MFA stays in the official webpage; only QM's own origin can run
        // the explicit business synchronization, never a Microsoft login page.
        if webView === self.webView, navigationAction.targetFrame?.isMainFrame == true {
            loginGate.beginDocument()
            cancelAuthenticationProbe()
            cancelAutofill()
            canSynchronize = false
            if isSyncing { endPendingSync(stopLoading: false) }
        } else if webView === popupWebView, navigationAction.targetFrame?.isMainFrame == true {
            popupDocument &+= 1
            cancelAutofill()
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        guard hasActiveConnection, navigationResponse.isForMainFrame,
              webView === self.webView || webView === popupWebView else {
            decisionHandler(.allow); return
        }
        let response = navigationResponse.response as? HTTPURLResponse
        let failure = response.flatMap {
            QMplusConnectionPolicy.officialHTTPFailureCode(status: $0.statusCode, isMainFrame: true, url: $0.url)
        }
        if webView === self.webView { mainHTTPFailureCode = failure }
        else { popupHTTPFailureCode = failure }
        if let failure {
            canSynchronize = false
            navigationFailureCode = failure
            isRetainingPreviousSnapshot = snapshot != nil
            statusKey = "QMplus 官方网页登录失败，请重试"
            cancelAuthenticationProbe()
            cancelAutofill()
            autofillLedger.stop()
            if isSyncing { endPendingSync(stopLoading: false) }
        }
        // Preserve the official response for the user. Never reconstruct a
        // callback as GET, repeat an ACS POST, or silently erase its cookies.
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard hasActiveConnection else { return }
        if webView === popupWebView {
            guard navigation != nil, navigation === activePopupNavigation else { return }
            currentHost = webView.url?.host ?? ""
            navigationFailureCode = popupHTTPFailureCode
            reviewAuthenticationPopup(webView)
            return
        }
        guard webView === self.webView, navigation != nil, navigation === activeNavigation else { return }
        currentHost = webView.url?.host ?? ""
        canSynchronize = false
        navigationFailureCode = mainHTTPFailureCode
        reviewCurrentDocument(in: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard hasActiveConnection, navigation != nil,
              (webView === self.webView && navigation === activeNavigation)
                || (webView === popupWebView && navigation === activePopupNavigation) else { return }
        if QMplusAutofillPolicy.isTrustedMicrosoftDocument(webView.url), credentialAuthorization.isEnabled {
            startAutofill(in: webView)
        } else if !Self.isSyncOrigin(webView.url) {
            currentHost = webView.url?.host ?? ""
            presentExistingConnection()
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard hasActiveConnection else { return }
        if webView === popupWebView {
            popupHTTPFailureCode = nil
            cancelAutofill()
            activePopupNavigation = navigation
            popupDocument &+= 1
            return
        }
        guard webView === self.webView else { return }
        mainHTTPFailureCode = nil
        activeNavigation = navigation
        loginGate.beginDocument()
        cancelAuthenticationProbe()
        cancelAutofill()
        canSynchronize = false
        lastReviewedDocumentURL = nil
        if isSyncing { endPendingSync(stopLoading: false) }
    }

    private func observeCurrentBrowser(_ browser: WKWebView) {
        let presentation = loginGate.presentation
        urlObservation = browser.observe(\.url, options: [.new]) { [weak self, weak browser] _, _ in
            Task { @MainActor in
                guard let self, let browser, browser === self.webView, self.hasActiveConnection,
                      self.loginGate.presentation == presentation, !browser.isLoading,
                      browser.url != self.lastReviewedDocumentURL else { return }
                // Also covers same-document dashboard/history navigation. The
                // new document identity revokes an older DOM result.
                self.loginGate.beginDocument()
                self.cancelAuthenticationProbe()
                self.cancelAutofill()
                if self.isSyncing { self.endPendingSync(stopLoading: false) }
                self.reviewCurrentDocument(in: browser)
            }
        }
    }

    private func cancelAuthenticationProbe() {
        authenticationProbeTask?.cancel()
        authenticationProbeTask = nil
        authenticationProbeContext = nil
    }

    private func cancelAutofill() {
        viewportWaitTask?.cancel(); viewportWaitTask = nil; viewportWaitDocument = nil
        autofillPipeline?.cancel()
        autofillPipeline = nil
        autofillDocument = nil
    }

    private func ownsAutofillDocument(_ document: OwnedAutofillDocument, browser: WKWebView) -> Bool {
        guard hasActiveConnection, loginGate.accepts(document.connection),
              (popupWebView ?? webView) === browser, ObjectIdentifier(browser) == document.browser else { return false }
        return document.popupDocument == nil ? popupWebView == nil : popupDocument == document.popupDocument
    }

    private func acceptsAutofillDocument(_ document: OwnedAutofillDocument, browser: WKWebView) -> Bool {
        hasActiveAutofillLedger && ownsAutofillDocument(document, browser: browser) && browser.url == document.url
            && QMplusAutofillPolicy.isTrustedMicrosoftDocument(browser.url)
            && credentialAuthorization.isEnabled && credentialAuthorization.credentialRevision == document.credentialRevision
    }

    private func hasUsableAutofillViewport(_ browser: WKWebView) -> Bool {
        guard browser.bounds.width >= 80, browser.bounds.height >= 80, let window = browser.window else { return false }
        #if os(iOS)
        return !window.isHidden && window.windowScene?.activationState == .foregroundActive
        #else
        return NSApp?.isActive == true && window.isVisible && !window.isMiniaturized
        #endif
    }

    private func isAutofillApplicationInactive(_ browser: WKWebView) -> Bool {
        #if os(iOS)
        if let scene = browser.window?.windowScene { return scene.activationState != .foregroundActive }
        return false // First mounting still uses the bounded viewport wait.
        #else
        return NSApp?.isActive != true
        #endif
    }

    private func startAutofill(in browser: WKWebView) {
        guard !automaticLoginSuspended else { return }
        if isAutofillApplicationInactive(browser) { stopAutomaticLoginForInactiveScene(); return }
        guard hasActiveConnection, (popupWebView ?? webView) === browser, credentialAuthorization.isEnabled,
              QMplusAutofillPolicy.isTrustedMicrosoftDocument(browser.url), let url = browser.url,
              hasActiveAutofillLedger else {
            presentExistingConnection(); return
        }
        let document = OwnedAutofillDocument(connection: loginGate.context,
            credentialRevision: credentialAuthorization.credentialRevision,
            popupDocument: browser === popupWebView ? popupDocument : nil, browser: ObjectIdentifier(browser), url: url)
        lastReviewedDocumentURL = browser === webView ? url : lastReviewedDocumentURL
        guard autofillDocument != document else { return }
        if !hasUsableAutofillViewport(browser) {
            guard viewportWaitDocument != document else { return }
            cancelAutofill()
            viewportWaitDocument = document
            viewportWaitTask = Task { [weak self, weak browser] in
                for attempt in 0..<8 {
                    do { try await Task.sleep(for: .milliseconds(attempt == 0 ? 250 : 500)) } catch { return }
                    guard let self, let browser, self.acceptsAutofillDocument(document, browser: browser) else { return }
                    if self.isAutofillApplicationInactive(browser) { self.stopAutomaticLoginForInactiveScene(); return }
                    if self.hasUsableAutofillViewport(browser) {
                        self.viewportWaitTask = nil; self.viewportWaitDocument = nil
                        self.startAutofill(in: browser); return
                    }
                }
                guard let self, let browser, self.ownsAutofillDocument(document, browser: browser) else { return }
                if self.isAutofillApplicationInactive(browser) { self.stopAutomaticLoginForInactiveScene(); return }
                self.statusKey = "QMplus 自动填写已停止，请在官方网页手动完成登录或验证。"
                self.presentExistingConnection()
            }
            return
        }
        cancelAutofill()
        guard let resource = Bundle.main.url(forResource: "qmplus-auth", withExtension: "js"),
              let source = try? String(contentsOf: resource, encoding: .utf8), source.utf8.count <= 65_536 else {
            statusKey = "QMplus 自动填写组件不可用，请手动登录。"
            presentExistingConnection(); return
        }
        autofillDocument = document
        let pipeline = QMplusAutofillPipeline(evaluator: QMplusWebKitAutofillEvaluator(browser: browser), ledger: autofillLedger,
            presentation: document.connection.presentation, credentialRevision: document.credentialRevision,
            nonce: UUID().uuidString,
            isCurrent: { [weak self, weak browser] in
                guard let self, let browser else { return false }
                return self.autofillDocument == document && self.acceptsAutofillDocument(document, browser: browser)
            }, viewportReady: { [weak self, weak browser] in
                guard let self, let browser else { return false }
                return self.hasUsableAutofillViewport(browser)
            }, credentials: { [weak self, weak browser] in
                guard let self, let browser, self.acceptsAutofillDocument(document, browser: browser),
                      self.hasUsableAutofillViewport(browser) else { return nil }
                let saved = self.credentialAuthorization.loadAuthorizedCredentials(expectedRevision: document.credentialRevision)
                guard self.acceptsAutofillDocument(document, browser: browser), self.hasUsableAutofillViewport(browser) else { return nil }
                return saved
            }, manual: { [weak self, weak browser] in
                guard let self, let browser, self.ownsAutofillDocument(document, browser: browser) else { return }
                if self.isAutofillApplicationInactive(browser) { self.stopAutomaticLoginForInactiveScene(); return }
                self.statusKey = "QMplus 自动填写已停止，请在官方网页手动完成登录或验证。"
                self.presentExistingConnection()
            }, progress: { [weak self, weak browser] state in
                guard let self, let browser, self.acceptsAutofillDocument(document, browser: browser) else { return }
                switch state {
                case .username: self.statusKey = "正在填写 QMplus 官方登录账号…"
                case .password: self.statusKey = "正在填写 QMplus 官方登录密码…"
                case .waiting: self.statusKey = "已提交 QMplus 官方登录步骤，正在等待页面确认…"
                }
            })
        autofillPipeline = pipeline
        pipeline.start(source: source)
    }

    private func beginOfficialSSOIfAllowed(in browser: WKWebView,
                                          context: QMplusLoginSynchronizationGate.Context) -> Bool {
        guard hasActiveConnection, browser === webView, popupWebView == nil, !browser.isLoading,
              loginGate.accepts(context), hasActiveAutofillLedger,
              QMplusAutofillPolicy.isQMplusLoginDocument(browser.url), credentialAuthorization.isEnabled,
              autofillLedger.claimSSO(presentation: loginGate.presentation,
                  credentialRevision: credentialAuthorization.credentialRevision) else { return false }
        cancelAuthenticationProbe()
        statusKey = "正在打开 QMplus 官方 SSO 登录…"
        activeNavigation = browser.load(URLRequest(url: QMplusAutofillPolicy.ssoURL))
        return true
    }

    private func reviewCurrentDocument(in browser: WKWebView) {
        guard hasActiveAuthenticationRecognition, browser === webView, popupWebView == nil,
              browser.url != nil, !browser.isLoading else { return }
        guard Self.isSyncOrigin(browser.url) else {
            if QMplusAutofillPolicy.isTrustedMicrosoftDocument(browser.url), credentialAuthorization.isEnabled {
                startAutofill(in: browser)
            } else { presentExistingConnection() }
            return
        }
        let context = loginGate.context
        lastReviewedDocumentURL = browser.url
        guard authenticationProbeContext != context else { return }
        authenticationProbeContext = context
        if snapshot == nil, !isSyncing, !loginGate.hasAttemptedAutomaticSync {
            statusKey = "正在确认 QMplus 登录状态…"
        }
        probeAuthentication(in: browser, context: context, attempt: 0)
    }

    private func probeAuthentication(in browser: WKWebView, context: QMplusLoginSynchronizationGate.Context, attempt: Int) {
        guard hasActiveAuthenticationRecognition else { return }
        if isAutofillApplicationInactive(browser) { stopAutomaticLoginForInactiveScene(); return }
        browser.evaluateJavaScript(QMplusConnectionPolicy.pageStatusScript) { [weak self, weak browser] result, error in
            guard let self, let browser, browser === self.webView, self.popupWebView == nil,
                  self.hasActiveAuthenticationRecognition, self.loginGate.accepts(context), !browser.isLoading,
                  Self.isSyncOrigin(browser.url) else { return }
            if self.isAutofillApplicationInactive(browser) { self.stopAutomaticLoginForInactiveScene(); return }
            let state = error == nil ? QMplusOfficialPageStatus(rawValue: result as? String ?? "unknown") ?? .unknown : .unknown
            guard self.acceptOfficialPageStatus(state, context: context) else { return }
            if state == .authenticated && self.canSynchronize {
                if self.loginGate.claimAutomaticSync(authenticated: true, context: context) {
                    // A DOM proof starts an attempt, not a connected claim.
                    // Only receive() can publish a validated business result.
                    self.synchronize()
                }
            } else if state == .error || self.mainHTTPFailureCode != nil {
                self.presentExistingConnection()
            } else if state == .guest, self.hasActiveAutofillLedger,
                      QMplusAutofillPolicy.isQMplusLoginDocument(browser.url) {
                browser.evaluateJavaScript(QMplusConnectionPolicy.officialSSOEntryScript) { [weak self, weak browser] eligible, linkError in
                    guard let self, let browser, self.loginGate.accepts(context), self.hasActiveAuthenticationRecognition,
                          browser === self.webView, !browser.isLoading else { return }
                    if linkError == nil, eligible as? Bool == true,
                       self.beginOfficialSSOIfAllowed(in: browser, context: context) { return }
                    self.continueAuthenticationReview(in: browser, context: context, attempt: attempt)
                }
            } else {
                self.continueAuthenticationReview(in: browser, context: context, attempt: attempt)
            }
        }
    }

    // This boundary also drives deterministic cold/error/late-callback tests.
    var currentConnectionContext: QMplusLoginSynchronizationGate.Context { loginGate.context }
    @discardableResult
    func acceptOfficialPageStatus(_ state: QMplusOfficialPageStatus,
                                  context: QMplusLoginSynchronizationGate.Context) -> Bool {
        guard featureEnabled, hasActiveAuthenticationRecognition, loginGate.accepts(context) else { return false }
        canSynchronize = state == .authenticated && mainHTTPFailureCode == nil
        if state == .error || mainHTTPFailureCode != nil {
            if isSyncing { endPendingSync(stopLoading: false) }
            canSynchronize = false
            isRetainingPreviousSnapshot = snapshot != nil
            navigationFailureCode = mainHTTPFailureCode ?? "QM_OFFICIAL_EXCEPTION"
            statusKey = "QMplus 官方网页登录失败，请重试"
            cancelAuthenticationProbe()
            cancelAutofill()
            autofillLedger.stop()
        }
        return true
    }

    private func continueAuthenticationReview(in browser: WKWebView,
                                             context: QMplusLoginSynchronizationGate.Context, attempt: Int) {
        guard loginGate.accepts(context), hasActiveAuthenticationRecognition else { return }
        if attempt < 3 {
                self.authenticationProbeTask?.cancel()
                self.authenticationProbeTask = Task { [weak self, weak browser] in
                    do { try await Task.sleep(for: .milliseconds(250 * (attempt + 1))) } catch { return }
                    guard let self, let browser, self.loginGate.accepts(context), self.hasActiveConnection else { return }
                    self.probeAuthentication(in: browser, context: context, attempt: attempt + 1)
                }
        } else if !self.isSyncing {
                self.statusKey = "请先在 QMplus 官方网页完成登录"
                self.presentExistingConnection()
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
        guard webView === self.webView, hasActiveConnection, popupWebView == nil,
              navigationAction.targetFrame == nil,
              QMplusConnectionPolicy.isOfficialAuthenticationPopup(navigationAction.request.url),
              sameIsolatedStore(configuration.websiteDataStore, webView.configuration.websiteDataStore) else { return nil }
        let source = navigationAction.sourceFrame.securityOrigin
        guard navigationAction.sourceFrame.isMainFrame,
              QMplusConnectionPolicy.isOfficialAuthenticationOrigin(scheme: source.protocol, host: source.host, port: source.port) else { return nil }
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        cancelAuthenticationProbe()
        cancelAutofill()
        canSynchronize = false
        if isSyncing { endPendingSync() }
        popupWebView = popup
        presentExistingConnection(stopAutofill: false)
        currentHost = navigationAction.request.url?.host ?? ""
        popupDocument &+= 1
        activePopupNavigation = nil
        // WebKit loads its original request (including POST body) in this
        // exact supplied configuration; do not reconstruct the request.
        return popup
    }

    private func sameIsolatedStore(_ candidate: WKWebsiteDataStore, _ owner: WKWebsiteDataStore) -> Bool {
        if candidate === owner { return true }
        if #available(iOS 17, macOS 14, *), let identifier = owner.identifier {
            return candidate.identifier == identifier && candidate.isPersistent == owner.isPersistent
        }
        return false
    }

    private func reviewAuthenticationPopup(_ popup: WKWebView) {
        guard hasActiveAuthenticationRecognition else { return }
        if QMplusAutofillPolicy.isTrustedMicrosoftDocument(popup.url), credentialAuthorization.isEnabled {
            startAutofill(in: popup); return
        }
        guard Self.isSyncOrigin(popup.url) else { return }
        let context = loginGate.context
        let document = popupDocument
        popup.evaluateJavaScript(QMplusConnectionPolicy.pageStatusScript) { [weak self, weak popup] result, error in
            guard let self, let popup, self.popupWebView === popup, self.hasActiveConnection,
                  self.hasActiveAuthenticationRecognition,
                  self.loginGate.accepts(context), self.popupDocument == document,
                  !popup.isLoading, Self.isSyncOrigin(popup.url) else { return }
            let state = error == nil ? QMplusOfficialPageStatus(rawValue: result as? String ?? "unknown") ?? .unknown : .unknown
            if state == .authenticated && self.popupHTTPFailureCode == nil {
                self.closeAuthenticationPopup(reloadMain: true)
            } else if state == .error || self.popupHTTPFailureCode != nil {
                self.canSynchronize = false
                self.navigationFailureCode = self.popupHTTPFailureCode ?? "QM_OFFICIAL_EXCEPTION"
                self.statusKey = "QMplus 官方网页登录失败，请重试"
                self.isRetainingPreviousSnapshot = self.snapshot != nil
                self.presentExistingConnection()
            }
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else { return }
        // DOM window.close is not proof that the parent ACS navigation has
        // finished. Leave any original parent POST/redirect untouched.
        closeAuthenticationPopup(reloadMain: false)
        if let browser = self.webView, !browser.isLoading { reviewCurrentDocument(in: browser) }
    }

    func closeAuthenticationPopup(reloadMain: Bool = true) {
        guard let popup = popupWebView else { return }
        cancelAutofill()
        popup.navigationDelegate = nil; popup.uiDelegate = nil; popup.stopLoading()
        popupWebView = nil
        popupDocument &+= 1
        activePopupNavigation = nil
        popupHTTPFailureCode = nil
        currentHost = webView?.url?.host ?? "qmplus.qmul.ac.uk"
        if reloadMain, hasActiveConnection, let browser = webView, !browser.isLoading {
            activeNavigation = browser.load(Self.dashboardRequest())
        }
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

    private func navigationFailed(in browser: WKWebView, navigation: WKNavigation?, error: Error) {
        guard (browser === webView || browser === popupWebView), hasActiveConnection,
              navigation != nil, navigation === (browser === webView ? activeNavigation : activePopupNavigation),
              let code = Self.safeNavigationFailureCode(error) else { return }
        cancelAuthenticationProbe()
        cancelAutofill()
        endPendingSync()
        canSynchronize = false
        navigationFailureCode = code
        statusKey = "QMplus 官方网页登录失败，请重试"
        presentExistingConnection()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(in: webView, navigation: navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(in: webView, navigation: navigation, error: error)
    }
}
