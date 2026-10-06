import Foundation
import Combine
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
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
    let credentialDraft: QMplusCredentialDraft
    private static let identifierKey = "qmplusWebsiteDataStoreIdentifier"
    private static var warmedBusinessScopes = Set<CourseBusinessCacheScope>()
    private let businessCache: CourseBusinessCacheStorage
    private var businessCacheRevision: UInt64 = 0
    private var businessCacheBlocked = false
    private var cachedSnapshotScope: CourseBusinessCacheScope?
    private var requestBusinessScope: CourseBusinessCacheScope?
    private var cachedSnapshotPartial = false
    private var businessCacheRestoreTask: Task<Void, Never>?
    @Published var isShowingConnection = false
    @Published private(set) var requiresManualContinuation = false
    @Published private(set) var automaticLoginDiagnostic: String?
    private var manualContinuationRequested = false
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
    private var connectionPreparationTask: Task<Void, Never>?
    private var foregroundReadinessTask: Task<Void, Never>?
    private var urlObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var activeNavigation: WKNavigation?
    private var committedMainDocumentContext: QMplusLoginSynchronizationGate.Context?
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
    private var backgroundOnly = false
    private var autofillPipeline: QMplusAutofillPipeline?
    private var autofillDocument: OwnedAutofillDocument?
    private var pausedAutofillDocument: OwnedAutofillDocument?
    private var autofillCommittedNavigation: WKNavigation?
    private var pausedAutofillNavigation: WKNavigation?
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
    var isPreparingConnection: Bool { connectionPreparationTask != nil }
    var hasActiveAuthenticationRecognition: Bool { hasActiveConnection && !authenticationRecognitionSuspended }
    var hasActiveAutofillLedger: Bool {
        !automaticLoginSuspended && hasActiveConnection && autofillLedger.accepts(
            presentation: loginGate.presentation, credentialRevision: credentialAuthorization.credentialRevision)
    }
    private var isQuietConnection: Bool { loginGate.ownerKind == .quiet }
    var quietBrowser: WKWebView? { isQuietConnection && !requiresManualContinuation ? (popupWebView ?? webView) : nil }

    func browserMountLease(for browser: WKWebView, role: QMplusBrowserMountLease.Role) -> QMplusBrowserMountLease? {
        guard hasActiveConnection else { return nil }
        switch role {
        case .quiet:
            guard isQuietConnection, !requiresManualContinuation, browser === (popupWebView ?? webView) else { return nil }
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
         allowsCredentialStorage: Bool = !AppLaunchConfiguration.isXCTestRunning && !AppLaunchConfiguration.isUITesting && !AppLaunchConfiguration.isReviewDemo,
         businessCache: CourseBusinessCacheStorage = .shared) {
        self.defaults = defaults
        self.businessCache = businessCache
        credentialDraft = QMplusCredentialDraft(defaults: allowsCredentialStorage ? defaults : nil)
        credentialAuthorization = QMplusCredentialAuthorization(storage: credentialStore,
            journal: authorizationJournal ?? QMplusDefaultsAuthorizationJournal(defaults: defaults), allowsStorage: allowsCredentialStorage)
        super.init()
        businessCacheRestoreTask = Task { [weak self] in
            guard let self else { return }
            await self.restoreCachedBusinessSnapshot()
        }
    }

    /// Await this before Root's independent startup warm job. No credentials or
    /// browser state are read by cache restore; decoding runs off the main actor.
    func prepareCachedSnapshot() async {
        if let task = businessCacheRestoreTask { await task.value }
        else { await restoreCachedBusinessSnapshot() }
    }

    func launchWarmOnce(sampleMode: Bool, canStart: @MainActor () -> Bool = { true }) async {
        guard featureEnabled, !sampleMode else { return }
        await prepareCachedSnapshot()
        guard !Task.isCancelled, canStart(), featureEnabled, !businessCacheBlocked,
              let scope = try? currentBusinessScope(), !Self.warmedBusinessScopes.contains(scope) else { return }
        connect(sampleMode: sampleMode, background: true)
    }

    private func currentBusinessScope() throws -> CourseBusinessCacheScope {
        guard !businessCacheBlocked else { throw CancellationError() }
        let owner = defaults.string(forKey: Self.identifierKey).flatMap(UUID.init(uuidString:))?.uuidString ?? "legacy"
        return try businessCache.scope(kind: .qmplus, owner: owner)
    }

    private func restoreCachedBusinessSnapshot() async {
        let revision = businessCacheRevision
        let storage = businessCache
        let owner = defaults.string(forKey: Self.identifierKey).flatMap(UUID.init(uuidString:))?.uuidString ?? "legacy"
        let value = await Task.detached(priority: .utility) { () -> CourseBusinessCachedValue<QMplusSnapshot>? in
            guard let scope = try? storage.scope(kind: .qmplus, owner: owner),
                  let cached = try? storage.load(kind: .qmplus, scope: scope,
                    maximumBytes: QMplusSnapshotPolicy.maximumBytes + 2048, as: QMplusSnapshot.self),
                  let data = try? JSONEncoder().encode(cached.payload),
                  let validated = try? QMplusSnapshotPolicy.decode(data), storage.isCurrent(scope, kind: .qmplus) else { return nil }
            return .init(schemaVersion: 1, scope: scope, fetchedAt: validated.fetchedAt,
                         partial: cached.partial, payload: validated)
        }.value
        guard !Task.isCancelled, revision == businessCacheRevision, let value,
              let current = try? currentBusinessScope(), current == value.scope,
              businessCache.isCurrent(current, kind: .qmplus), snapshot == nil else { return }
        snapshot = value.payload
        cachedSnapshotScope = current
        cachedSnapshotPartial = value.partial
        isPartial = value.partial
        isRetainingPreviousSnapshot = true
    }

    /// A proven identity mismatch retires only business data. Keep the visible
    /// official page and its navigation intact; never reload or submit a form.
    @discardableResult
    func invalidateBusinessCacheForIdentityChange() -> Bool {
        businessCacheRevision &+= 1
        businessCacheRestoreTask?.cancel(); businessCacheRestoreTask = nil
        endPendingSync(stopLoading: false)
        snapshot = nil; cachedSnapshotScope = nil; requestBusinessScope = nil
        cachedSnapshotPartial = false; isPartial = false; isRetainingPreviousSnapshot = false
        businessCacheBlocked = true
        do {
            try businessCache.rotateQMplusEpoch()
            businessCacheBlocked = false
            return true
        } catch {
            statusKey = "QMplus 同步组件不可用"
            return false
        }
    }

    @discardableResult
    func saveCredentials(account: String, password: String) -> Bool {
        endPresentation()
        guard credentialAuthorization.allowsCredentialStorage else { credentialDraft.clear(); return false }
        let disposition = credentialAuthorization.saveAndAuthorizeWithDisposition(account: account, password: password)
        credentialDraft.clear()
        // Only a verified unchanged authorization may retain this profile.
        // Failed verification/replacement must not keep an old signed-in identity.
        if disposition != .unchanged { clearOfficialSession() }
        return disposition != .failed
    }

    func disableCredentialAutofill() {
        endPresentation()
        credentialAuthorization.disableAndDelete()
        credentialDraft.disableSaving()
    }

    func connect(sampleMode: Bool, background: Bool = false) {
        guard featureEnabled, !sampleMode else { return }
        if hasActiveConnection {
            if background { return }
            // Upgrade interaction permission on the same active owner. Do not
            // restart a live SSO/password flow just because Connect was tapped.
            backgroundOnly = false
            if isQuietConnection, !hasActiveAutofillLedger, !isSyncing, webView?.isLoading != true {
                endPresentation()
            } else {
                if isQuietConnection, let browser = webView, !isSyncing, !browser.isLoading {
                    cancelAuthenticationProbe()
                    reviewCurrentDocument(in: browser)
                }
                return
            }
        }
        backgroundOnly = background
        requiresManualContinuation = false
        manualContinuationRequested = false
        if connectionPreparationTask != nil { return }
        guard isApplicationReadyForConnection else {
            prepareConnectionWhenReady(); return
        }
        credentialAuthorization.restoreAuthorization()
        guard !credentialAuthorization.isTemporarilyUnavailable else {
            prepareConnectionWhenReady(); return
        }
        startPreparedConnection()
    }

    private var isApplicationReadyForConnection: Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .active && UIApplication.shared.isProtectedDataAvailable
        #else
        NSApp?.isActive == true
        #endif
    }

    private func prepareConnectionWhenReady() {
        guard connectionPreparationTask == nil, featureEnabled else { return }
        statusKey = "正在确认 QMplus 登录状态…"
        connectionPreparationTask = Task { [weak self] in
            for _ in 0..<40 {
                guard !Task.isCancelled, let self, self.featureEnabled else { return }
                if self.isApplicationReadyForConnection {
                    self.credentialAuthorization.restoreAuthorization()
                    if !self.credentialAuthorization.isTemporarilyUnavailable {
                        self.connectionPreparationTask = nil
                        self.startPreparedConnection()
                        return
                    }
                }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
            guard let self, !Task.isCancelled else { return }
            self.connectionPreparationTask = nil
            self.statusKey = "QMplus 官方网页登录失败，请重试"
            self.isRetainingPreviousSnapshot = self.snapshot != nil
        }
    }

    private func startPreparedConnection() {
        guard featureEnabled, !hasActiveConnection, isApplicationReadyForConnection else { return }
        // The dashboard and ordinary official Login entry never require a
        // user gesture. Reveal the same web view only at a manual step.
        guard beginConnectionOwner(quiet: true) else { return }
        scheduleQuietPreflightTimeout()
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
            // Use the final persistent profile ID, not the pre-creation legacy
            // scope. A cancelled scene must never consume this warm-once mark.
            if backgroundOnly, let scope = try? currentBusinessScope() { Self.warmedBusinessScopes.insert(scope) }
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
        automaticLoginDiagnostic = nil
        pausedAutofillDocument = nil
        pausedAutofillNavigation = nil
        autofillCommittedNavigation = nil
        autofillLedger.begin(presentation: loginGate.presentation, credentialRevision: credentialAuthorization.credentialRevision)
        statusKey = "正在确认 QMplus 登录状态…"
        isShowingConnection = !quiet
        return true
    }

    private func presentExistingConnection(stopAutofill: Bool = true, verificationRequired: Bool = false,
                                           explicitlyRequested: Bool = false, callerLine: Int = #line) {
        guard hasActiveConnection else { return }
        if let browser = popupWebView ?? webView, isAutofillApplicationInactive(browser) {
            stopAutomaticLoginForInactiveScene(); return
        }
        guard verificationRequired || explicitlyRequested || manualContinuationRequested else {
            #if DEBUG
            if ProcessInfo.processInfo.environment["WTS_QMPLUS_AUTH_TRACE"] == "1" {
                let browser = popupWebView ?? webView
                FileHandle.standardError.write(Data("WTS_QM_PAUSE caller=\(callerLine) ledger=\(hasActiveAutofillLedger) suspended=\(automaticLoginSuspended) host=\(browser?.url?.host ?? "none") scheme=\(browser?.url?.scheme ?? "none")\n".utf8))
            }
            #endif
            pauseForManualContinuation()
            return
        }
        if stopAutofill { suspendAutofillForCurrentDocument() }
        quietPreflightTimeoutTask?.cancel(); quietPreflightTimeoutTask = nil
        requiresManualContinuation = false
        loginGate.presentExistingConnection()
        isShowingConnection = true
    }

    private func pauseForManualContinuation() {
        guard hasActiveConnection else { return }
        #if DEBUG
        traceMicrosoftRouteForQA(popupWebView ?? webView)
        #endif
        suspendAutofillForCurrentDocument(); cancelAuthenticationProbe()
        quietPreflightTimeoutTask?.cancel(); quietPreflightTimeoutTask = nil
        requiresManualContinuation = true
        if isShowingConnection {
            preservingAutomaticSheetDismissal = true
            isShowingConnection = false
        }
        loginGate.hideExistingConnection()
    }

    // Transport documents may commit before Microsoft's recognized login/MFA
    // page. Await navigation under the same deadline without filling/clicking.
    private func waitForMicrosoftTransit(_ browser: WKWebView) -> Bool {
        guard hasActiveAutofillLedger, QMplusAutofillPolicy.isPassiveMicrosoftTransit(browser.url) else { return false }
        cancelAutofill()
        cancelAuthenticationProbe()
        currentHost = browser.url?.host ?? "login.microsoftonline.com"
        statusKey = "正在确认 QMplus 登录状态…"
        resumeSilentAuthentication()
        if isQuietConnection, quietPreflightTimeoutTask == nil { scheduleQuietPreflightTimeout() }
        return true
    }

    #if DEBUG
    private func traceMicrosoftRouteForQA(_ browser: WKWebView?) {
        guard ProcessInfo.processInfo.environment["WTS_QMPLUS_AUTH_TRACE"] == "1", let browser,
              browser.url?.host?.lowercased() == "login.microsoftonline.com", let path = browser.url?.path else { return }
        let known = Set(["common", "organizations", "saml2", "login", "kmsi", "sas", "beginauth",
                         "processauth", "endauth", "oauth2", "v2.0", "authorize"])
        let route = path.split(separator: "/").map { component -> String in
            let part = component.lowercased()
            if part == QMplusAutofillPolicy.tenant { return "tenant" }
            return known.contains(part) ? part : "other"
        }.joined(separator: "/")
        FileHandle.standardError.write(Data("WTS_QM_ROUTE \(route)\n".utf8))
        browser.evaluateJavaScript("""
            JSON.stringify({titleID:!!document.querySelector('#idDiv_SAOTCS_Title'),
                titleTextID:!!document.querySelector('#idDiv_SAOTCS_Title_Text'),
                proofs:!!document.querySelector('#idDiv_SAOTCS_Proofs'),
                proofsSection:!!document.querySelector('#idDiv_SAOTCS_Proofs_Section'),
                challengeTitle:Array.from(document.querySelectorAll('h1,h2,[role="heading"],#idDiv_SAOTCS_Title,#idDiv_SAOTCS_Title_Text'))
                    .some(node=>['verify your identity','验证您的身份','驗證您的身分','驗證您的身份'].includes(node.textContent.trim().toLowerCase())),
                chooser:document.querySelectorAll('#tilesHolder').length,
                otp:document.querySelectorAll('input[name="otc"],input[autocomplete="one-time-code"]').length})
            """) { value, _ in
                guard let text = value as? String, text.utf8.count <= 1024 else { return }
                FileHandle.standardError.write(Data("WTS_QM_SAFE_DOM \(text)\n".utf8))
            }
    }
    #endif

    func continueManually(sampleMode: Bool) {
        guard featureEnabled, !sampleMode else { return }
        if !hasActiveConnection { connect(sampleMode: false) }
        manualContinuationRequested = true
        // Showing the paused page does not reset its once-only ledger. A new
        // verified Microsoft document can resume the remaining steps below.
        presentExistingConnection(stopAutofill: false, explicitlyRequested: true)
    }

    private func showVerification() {
        statusKey = "请在官方窗口完成验证码或 MFA，完成后将继续同步。"
        currentHost = (popupWebView ?? webView)?.url?.host ?? currentHost
        presentExistingConnection(stopAutofill: false, verificationRequired: true)
    }

    private func resumeSilentAuthentication() {
        guard hasActiveConnection, !manualContinuationRequested, isShowingConnection else { return }
        preservingAutomaticSheetDismissal = true
        loginGate.hideExistingConnection()
        isShowingConnection = false
    }

    private func scheduleQuietPreflightTimeout() {
        guard isQuietConnection, !isSyncing else { return }
        quietPreflightTimeoutTask?.cancel()
        let presentation = loginGate.presentation
        quietPreflightTimeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, self.hasActiveConnection, self.loginGate.presentation == presentation,
                  self.isQuietConnection, !self.isSyncing else { return }
            self.statusKey = "QMplus 会话核查超时，请在官方网页继续登录。"
            self.presentExistingConnection()
        }
    }

    func cancelQuietConnection() {
        if isQuietConnection { endPresentation() }
    }

    func stopAutomaticLoginForInactiveScene() {
        foregroundReadinessTask?.cancel(); foregroundReadinessTask = nil
        // Preparation has no login owner yet, but still belongs to this scene.
        // Cancel it even when another window keeps the application active.
        connectionPreparationTask?.cancel(); connectionPreparationTask = nil
        guard hasActiveConnection else { return }
        let wasSyncing = isSyncing
        automaticLoginSuspended = true
        authenticationRecognitionSuspended = true
        cancelAutofill()
        cancelAuthenticationProbe()
        quietPreflightTimeoutTask?.cancel(); quietPreflightTimeoutTask = nil
        // A user may switch to Messages/Authenticator. Keep the same owner and
        // once-only ledger; cancel injection work without replaying its form.
        let hasCommittedDocument = committedMainDocumentContext == loginGate.context
        loginGate.beginDocument()
        if hasCommittedDocument { committedMainDocumentContext = loginGate.context }
        if wasSyncing { loginGate.allowSyncAfterCancellation(context: loginGate.context) }
        endPendingSync(stopLoading: false)
    }

    // Returning to the foreground may inspect the current official session.
    // Keep prior stage claims; never reload or resubmit the MFA page.
    func resumeAuthenticationRecognitionForActiveScene() {
        guard hasActiveConnection, authenticationRecognitionSuspended else { return }
        if let browser = popupWebView ?? webView, isAutofillApplicationInactive(browser) {
            waitForForegroundReadiness(); return
        }
        foregroundReadinessTask?.cancel(); foregroundReadinessTask = nil
        authenticationRecognitionSuspended = false
        automaticLoginSuspended = false
        guard let browser = popupWebView ?? webView else { return }
        if isQuietConnection { scheduleQuietPreflightTimeout() }
        if browser === popupWebView { reviewAuthenticationPopup(browser) }
        else { reviewCurrentDocument(in: browser) }
    }

    private func waitForForegroundReadiness() {
        guard foregroundReadinessTask == nil else { return }
        let presentation = loginGate.presentation
        foregroundReadinessTask = Task { [weak self] in
            for _ in 0..<20 {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, self.hasActiveConnection, self.loginGate.presentation == presentation,
                      self.featureEnabled, self.authenticationRecognitionSuspended else { return }
                guard let browser = self.popupWebView ?? self.webView else { return }
                if !self.isAutofillApplicationInactive(browser), self.isApplicationReadyForConnection {
                    self.foregroundReadinessTask = nil
                    self.resumeAuthenticationRecognitionForActiveScene()
                    return
                }
            }
            guard let self, !Task.isCancelled, self.loginGate.presentation == presentation else { return }
            self.foregroundReadinessTask = nil
            self.automaticLoginDiagnostic = "FOREGROUND_WINDOW_NOT_READY"
        }
    }

    func reloadOfficialPage() {
        guard featureEnabled, webView != nil else { return }
        // This explicit user action starts a new owner and once-only ledger.
        // An automatic response/error callback never restarts authentication.
        endPresentation()
        connect(sampleMode: false)
    }

    func synchronize() {
        guard featureEnabled, canSynchronize, !isSyncing, hasActiveConnection, let browser = webView,
              popupWebView == nil, committedMainDocumentContext == loginGate.context,
              Self.isSyncOrigin(browser.url) else { return }
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
        guard let scope = try? currentBusinessScope() else { statusKey = "QMplus 同步组件不可用"; return nil }
        requestBusinessScope = scope
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
                if envelope.errorCode == "QM_LOGIN_REQUIRED" {
                    recoverExpiredSession(request: request)
                    return
                }
                if ["QM_LOGIN_REQUIRED", "QM_ERROR_PAGE"].contains(envelope.errorCode ?? "") {
                    canSynchronize = false
                }
                finishFailure(request: request)
                if envelope.errorCode == "QM_ERROR_PAGE" {
                    navigationFailureCode = "QM_OFFICIAL_EXCEPTION"
                    statusKey = "QMplus 官方网页登录失败，请重试"
                }
                return
            }
            let next = try QMplusSnapshotPolicy.decode(data)
            guard let scope = requestBusinessScope, !businessCacheBlocked,
                  let current = try? currentBusinessScope(), current == scope,
                  businessCache.isCurrent(scope, kind: .qmplus) else { finishFailure(request: request); return }
            // Partial, restricted or missing data is never evidence of deletion.
            // Restricted modules are a normal permission fact, not a failed
            // request. They must not freeze unrelated new courses/deadlines.
            isPartial = envelope.partial || !next.warnings.isEmpty
            let hasPrevious = snapshot != nil && cachedSnapshotScope == scope
            isRetainingPreviousSnapshot = isPartial && hasPrevious
            let replacesSnapshot = !isPartial || !hasPrevious
            if replacesSnapshot {
                businessCacheRevision &+= 1
                snapshot = next; cachedSnapshotScope = scope; cachedSnapshotPartial = isPartial
            }
            statusKey = isPartial
                ? (hasPrevious ? "QMplus 同步不完整，保留上次快照并请重试" : "QMplus 同步不完整，部分信息尚未获取，请重试")
                : "QMplus 同步完成"
            finish(request: request)
            if replacesSnapshot {
                do {
                    try businessCache.save(CourseBusinessCachedValue(schemaVersion: 1, scope: scope,
                        fetchedAt: next.fetchedAt, partial: cachedSnapshotPartial, payload: next),
                        kind: .qmplus, maximumBytes: QMplusSnapshotPolicy.maximumBytes + 2048)
                } catch {
                    if businessCache.isCurrent(scope, kind: .qmplus) {
                        statusKey = "本次课程数据已读取，但本地缓存未更新。重启后可能显示此前缓存。"
                    }
                }
            }
        } catch { finishFailure(request: request) }
    }

    private func recoverExpiredSession(request: UInt64) {
        guard request == generation, isSyncing else { return }
        timeoutTask?.cancel(); timeoutTask = nil
        isSyncing = false; canSynchronize = false
        isRetainingPreviousSnapshot = snapshot != nil
        let context = loginGate.context
        if let browser = webView, popupWebView == nil,
           committedMainDocumentContext == context, Self.isSyncOrigin(browser.url),
           !isAutofillApplicationInactive(browser), hasActiveAutofillLedger,
           autofillLedger.canNavigateLoginEntry(presentation: context.presentation,
                credentialRevision: credentialAuthorization.credentialRevision),
           loginGate.claimLoginRecovery(context: context), loginGate.claimLoginEntry(context: context) {
            // A validated read-only sync explicitly requested sign-in. One
            // ordinary GET may renew the session; credential budgets stay put.
            statusKey = "正在确认 QMplus 登录状态…"
            loadAutomaticLoginEntry(in: browser, url: QMplusConnectionPolicy.loginEntryURL)
        } else {
            endPresentation()
            statusKey = "QMplus 官方网页登录失败，请重试"
        }
    }

    private func accepts(request: UInt64, browser: WKWebView, context: QMplusLoginSynchronizationGate.Context) -> Bool {
        request == generation && isSyncing && hasActiveConnection && browser === webView
            && popupWebView == nil && loginGate.accepts(context) && Self.isSyncOrigin(browser.url)
    }

    private func finish(request: UInt64) {
        guard request == generation, isSyncing else { return }
        timeoutTask?.cancel(); timeoutTask = nil
        isSyncing = false
        #if DEBUG
        if ProcessInfo.processInfo.environment["WTS_QMPLUS_AUTH_TRACE"] == "1" {
            FileHandle.standardError.write(Data("WTS_QM_SYNC completed=\(statusKey == "QMplus 同步完成") retained=\(isRetainingPreviousSnapshot) courses=\(snapshot?.courses.count ?? 0)\n".utf8))
        }
        #endif
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
        foregroundReadinessTask?.cancel(); foregroundReadinessTask = nil
        automaticLoginDiagnostic = nil
        connectionPreparationTask?.cancel(); connectionPreparationTask = nil
        backgroundOnly = false
        requiresManualContinuation = false
        manualContinuationRequested = false
        preservingAutomaticSheetDismissal = false
        loginGate.endPresentation()
        cancelAutofill()
        autofillLedger.stop()
        pausedAutofillDocument = nil
        pausedAutofillNavigation = nil
        autofillCommittedNavigation = nil
        isShowingConnection = false
        quietPreflightTimeoutTask?.cancel(); quietPreflightTimeoutTask = nil
        cancelAuthenticationProbe()
        urlObservation = nil
        loadingObservation = nil
        activeNavigation = nil
        committedMainDocumentContext = nil
        lastReviewedDocumentURL = nil
        canSynchronize = false
        closeAuthenticationPopup(reloadMain: false)
        let wasSyncing = isSyncing
        endPendingSync()
        if wasSyncing { statusKey = "QMplus 同步已取消，可重新连接后重试" }
    }

    func suspend() {
        businessCacheRevision &+= 1
        businessCacheRestoreTask?.cancel(); businessCacheRestoreTask = nil
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
        _ = invalidateBusinessCacheForIdentityChange()
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
            let sameDocument = committedMainDocumentContext == loginGate.context
                && isFragmentNavigation(navigationAction, in: webView)
            loginGate.beginDocument()
            if sameDocument { committedMainDocumentContext = loginGate.context }
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

    private func isFragmentNavigation(_ action: WKNavigationAction, in browser: WKWebView) -> Bool {
        guard action.navigationType == .linkActivated, action.request.httpMethod == "GET",
              let currentURL = browser.url, let targetURL = action.request.url,
              var current = URLComponents(url: currentURL, resolvingAgainstBaseURL: false),
              var target = URLComponents(url: targetURL, resolvingAgainstBaseURL: false),
              current.fragment != target.fragment else { return false }
        current.fragment = nil; target.fragment = nil
        return current == target
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
        navigationFailureCode = mainHTTPFailureCode
        reviewCurrentDocument(in: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard hasActiveConnection, navigation != nil,
              (webView === self.webView && navigation === activeNavigation)
                || (webView === popupWebView && navigation === activePopupNavigation) else { return }
        autofillCommittedNavigation = navigation
        if webView === self.webView {
            committedMainDocumentContext = loginGate.context
            // Loading completion belongs to this same main document, including
            // Microsoft pages whose autofill starts before didFinish.
            lastReviewedDocumentURL = webView.url
        }
        if QMplusAutofillPolicy.isInspectableMicrosoftDocument(webView.url) {
            startAutofill(in: webView)
        } else if webView === self.webView, Self.isSyncOrigin(webView.url) {
            // The official DOM may be ready while analytics, images or other
            // subresources still keep isLoading true and delay didFinish.
            reviewCurrentDocument(in: webView)
        } else if !Self.isSyncOrigin(webView.url), !waitForMicrosoftTransit(webView) {
            currentHost = webView.url?.host ?? ""
            presentExistingConnection()
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard hasActiveConnection else { return }
        if webView === popupWebView {
            popupHTTPFailureCode = nil
            cancelAutofill()
            autofillCommittedNavigation = nil
            activePopupNavigation = navigation
            popupDocument &+= 1
            return
        }
        guard webView === self.webView else { return }
        mainHTTPFailureCode = nil
        activeNavigation = navigation
        autofillCommittedNavigation = nil
        committedMainDocumentContext = nil
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
                      self.loginGate.presentation == presentation else { return }
                self.reviewObservedDocument(in: browser)
            }
        }
        loadingObservation = browser.observe(\.isLoading, options: [.new]) { [weak self, weak browser] _, _ in
            Task { @MainActor in
                guard let self, let browser, browser === self.webView, self.hasActiveConnection,
                      self.loginGate.presentation == presentation else { return }
                // Recover a loading/finish callback ordering gap without
                // renewing the credential ledger or its document nonce.
                self.reviewObservedDocument(in: browser)
            }
        }
    }

    private func reviewObservedDocument(in browser: WKWebView) {
        guard !browser.isLoading, committedMainDocumentContext == loginGate.context else { return }
        if browser.url != lastReviewedDocumentURL {
            // Also covers a same-document/history URL change observed before
            // loading settled. Its old DOM result must no longer be accepted.
            loginGate.beginDocument()
            committedMainDocumentContext = loginGate.context
            cancelAuthenticationProbe()
            cancelAutofill()
            canSynchronize = false
            if isSyncing { endPendingSync(stopLoading: false) }
        }
        reviewCurrentDocument(in: browser)
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

    private func suspendAutofillForCurrentDocument() {
        guard let browser = popupWebView ?? webView, let url = browser.url,
              QMplusAutofillPolicy.isResumableOfficialDocument(url) else {
            cancelAutofill(); autofillLedger.stop()
            pausedAutofillDocument = nil; pausedAutofillNavigation = nil
            return
        }
        if pausedAutofillDocument == nil {
            pausedAutofillDocument = OwnedAutofillDocument(connection: loginGate.context,
                credentialRevision: credentialAuthorization.credentialRevision,
                popupDocument: browser === popupWebView ? popupDocument : nil,
                browser: ObjectIdentifier(browser), url: url)
            pausedAutofillNavigation = browser === popupWebView ? activePopupNavigation : activeNavigation
        }
        cancelAutofill()
        autofillLedger.suspend()
    }

    private func resumeAutofillForNewDocument(_ document: OwnedAutofillDocument) {
        guard !hasActiveAutofillLedger, let paused = pausedAutofillDocument,
              QMplusAutofillPolicy.isNewCommittedNavigation(autofillCommittedNavigation,
                  active: popupWebView == nil ? activeNavigation : activePopupNavigation,
                  paused: pausedAutofillNavigation),
              document.connection.presentation == paused.connection.presentation,
              document.credentialRevision == paused.credentialRevision,
              // URL/history changes alone do not establish a new document.
              document.connection != paused.connection || document.popupDocument != paused.popupDocument,
              credentialDraft.wantsToSave, credentialAuthorization.isEnabled,
              QMplusAutofillPolicy.isInspectableMicrosoftDocument(document.url),
              autofillLedger.resume(presentation: document.connection.presentation,
                  credentialRevision: document.credentialRevision) else { return }
        pausedAutofillDocument = nil
        pausedAutofillNavigation = nil
        requiresManualContinuation = false
    }

    private func acceptsAutofillDocument(_ document: OwnedAutofillDocument, browser: WKWebView) -> Bool {
        hasActiveAutofillLedger && ownsAutofillDocument(document, browser: browser) && browser.url == document.url
            && QMplusAutofillPolicy.isInspectableMicrosoftDocument(browser.url)
            && credentialAuthorization.credentialRevision == document.credentialRevision
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
        guard hasActiveConnection, (popupWebView ?? webView) === browser,
              QMplusAutofillPolicy.isInspectableMicrosoftDocument(browser.url), let url = browser.url else {
            presentExistingConnection(); return
        }
        let document = OwnedAutofillDocument(connection: loginGate.context,
            credentialRevision: credentialAuthorization.credentialRevision,
            popupDocument: browser === popupWebView ? popupDocument : nil, browser: ObjectIdentifier(browser), url: url)
        // The recorded navigation must have really committed after the paused
        // page. Foreground/history epochs alone cannot authorize resumption.
        resumeAutofillForNewDocument(document)
        guard hasActiveAutofillLedger else { presentExistingConnection(); return }
        lastReviewedDocumentURL = browser === webView ? url : lastReviewedDocumentURL
        guard autofillDocument != document else { return }
        if !hasUsableAutofillViewport(browser) {
            guard viewportWaitDocument != document else { return }
            cancelAutofill()
            viewportWaitDocument = document
            viewportWaitTask = Task { [weak self, weak browser] in
                for attempt in 0..<QMplusAutofillPolicy.maximumPageWaits {
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
                self.statusKey = "自动登录已暂停，可选择“手动继续”查看官方页面。"
                self.automaticLoginDiagnostic = "VIEWPORT_WAIT_EXHAUSTED"
                self.presentExistingConnection()
            }
            return
        }
        cancelAutofill()
        guard let resource = Bundle.main.url(forResource: "qmplus-auth", withExtension: "js"),
              let source = try? String(contentsOf: resource, encoding: .utf8), source.utf8.count <= 65_536 else {
            statusKey = "QMplus 自动填写组件不可用，请手动登录。"
            automaticLoginDiagnostic = "RESOURCE_UNAVAILABLE"
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
            }, verificationOnly: QMplusAutofillPolicy.isMicrosoftVerificationDocument(document.url),
            credentials: { [weak self, weak browser] in
                guard let self, let browser, self.credentialDraft.wantsToSave,
                      QMplusAutofillPolicy.isTrustedMicrosoftDocument(browser.url),
                      self.acceptsAutofillDocument(document, browser: browser),
                      self.hasUsableAutofillViewport(browser) else { return nil }
                let saved = self.credentialAuthorization.loadAuthorizedCredentials(expectedRevision: document.credentialRevision)
                guard self.acceptsAutofillDocument(document, browser: browser), self.hasUsableAutofillViewport(browser) else { return nil }
                return saved
            }, manual: { [weak self, weak browser] in
                guard let self, let browser, self.ownsAutofillDocument(document, browser: browser) else { return }
                if self.isAutofillApplicationInactive(browser) { self.stopAutomaticLoginForInactiveScene(); return }
                self.statusKey = "自动登录已暂停，可选择“手动继续”查看官方页面。"
                self.presentExistingConnection()
            }, challenge: { [weak self, weak browser] in
                guard let self, let browser, self.acceptsAutofillDocument(document, browser: browser) else { return }
                self.showVerification()
            }, identityMismatch: { [weak self, weak browser] in
                guard let self, let browser, self.ownsAutofillDocument(document, browser: browser) else { return }
                _ = self.invalidateBusinessCacheForIdentityChange()
                self.autofillLedger.stop()
                self.pausedAutofillDocument = nil
            }, onFailure: { [weak self, weak browser] failure in
                guard let self, let browser, self.ownsAutofillDocument(document, browser: browser) else { return }
                self.automaticLoginDiagnostic = failure.diagnosticCode
            }, progress: { [weak self, weak browser] state in
                guard let self, let browser, self.acceptsAutofillDocument(document, browser: browser) else { return }
                // These are once-only, validated login steps. A slow
                // preflight must not consume the next step's entire deadline.
                switch state {
                case .username: self.statusKey = "正在填写 QMplus 官方登录账号…"
                case .password: self.statusKey = "正在填写 QMplus 官方登录密码…"
                case .continuation: self.statusKey = "正在确认 QMplus 登录状态…"
                case .waiting:
                    self.manualContinuationRequested = false
                    self.resumeSilentAuthentication()
                    self.statusKey = "已提交 QMplus 官方登录步骤，正在等待页面确认…"
                }
                self.scheduleQuietPreflightTimeout()
            })
        autofillPipeline = pipeline
        pipeline.start(source: source)
    }

    private func beginOfficialSSOIfAllowed(in browser: WKWebView,
                                          context: QMplusLoginSynchronizationGate.Context) -> Bool {
        guard hasActiveConnection, browser === webView, popupWebView == nil,
              loginGate.accepts(context), committedMainDocumentContext == context, hasActiveAutofillLedger,
              QMplusAutofillPolicy.isQMplusLoginDocument(browser.url),
              autofillLedger.claimSSO(presentation: loginGate.presentation,
                  credentialRevision: credentialAuthorization.credentialRevision) else { return false }
        statusKey = "正在打开 QMplus 官方 SSO 登录…"
        loadAutomaticLoginEntry(in: browser, url: QMplusAutofillPolicy.ssoURL)
        return true
    }

    private func loadAutomaticLoginEntry(in browser: WKWebView, url: URL) {
        // Retire the previous DOM synchronously. WKNavigation delegate events
        // arrive later; a second pending JS callback must not replace this GET.
        loginGate.beginDocument()
        committedMainDocumentContext = nil
        canSynchronize = false
        cancelAuthenticationProbe()
        cancelAutofill()
        scheduleQuietPreflightTimeout()
        activeNavigation = browser.load(URLRequest(url: url))
    }

    private func reviewCurrentDocument(in browser: WKWebView) {
        guard hasActiveAuthenticationRecognition, browser === webView, popupWebView == nil,
              browser.url != nil, committedMainDocumentContext == loginGate.context else { return }
        lastReviewedDocumentURL = browser.url
        guard Self.isSyncOrigin(browser.url) else {
            if QMplusAutofillPolicy.isInspectableMicrosoftDocument(browser.url) {
                startAutofill(in: browser)
            } else if waitForMicrosoftTransit(browser) {
                return
            } else {
                if !credentialAuthorization.isEnabled, !credentialAuthorization.statusKey.isEmpty {
                    statusKey = credentialAuthorization.statusKey
                }
                presentExistingConnection()
            }
            return
        }
        let context = loginGate.context
        guard authenticationProbeContext != context else { return }
        authenticationProbeContext = context
        if snapshot == nil, !isSyncing, !loginGate.hasAttemptedAutomaticSync {
            statusKey = "正在确认 QMplus 登录状态…"
        }
        probeAuthentication(in: browser, context: context, attempt: 0)
    }

    private func probeAuthentication(in browser: WKWebView, context: QMplusLoginSynchronizationGate.Context, attempt: Int) {
        guard hasActiveAuthenticationRecognition, loginGate.accepts(context), committedMainDocumentContext == context,
              let documentURL = browser.url, Self.isSyncOrigin(documentURL) else { return }
        if isAutofillApplicationInactive(browser) { stopAutomaticLoginForInactiveScene(); return }
        browser.evaluateJavaScript(QMplusConnectionPolicy.pageStatusScript) { [weak self, weak browser] result, error in
            guard let self, let browser, browser === self.webView, self.popupWebView == nil,
                  self.hasActiveAuthenticationRecognition, self.loginGate.accepts(context),
                  self.committedMainDocumentContext == context, browser.url == documentURL,
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
                self.advanceOfficialLogin(in: browser, context: context, documentURL: documentURL, attempt: attempt)
            } else {
                self.continueAuthenticationReview(in: browser, context: context, attempt: attempt,
                    waitingForDocument: state == .loading, knownGuest: state == .guest)
            }
        }
    }

    private func advanceOfficialLogin(in browser: WKWebView,
                                      context: QMplusLoginSynchronizationGate.Context,
                                      documentURL: URL, attempt: Int) {
        // Prefer the normal Login page, then its verified SSO entry. These two
        // GET budgets are independent from authorization to fill credentials.
        browser.evaluateJavaScript(QMplusConnectionPolicy.officialLoginEntryScript) { [weak self, weak browser] entry, error in
            guard let self, let browser,
                  self.acceptsLoginEntry(in: browser, context: context, documentURL: documentURL) else { return }
            if error == nil, entry as? Bool == true, documentURL.path != "/login/index.php",
               self.autofillLedger.canNavigateLoginEntry(presentation: context.presentation,
                    credentialRevision: self.credentialAuthorization.credentialRevision),
               self.loginGate.claimLoginEntry(context: context) {
                self.loadAutomaticLoginEntry(in: browser, url: QMplusConnectionPolicy.loginEntryURL)
                return
            }
            browser.evaluateJavaScript(QMplusConnectionPolicy.officialSSOEntryScript) { [weak self, weak browser] eligible, error in
                guard let self, let browser,
                      self.acceptsLoginEntry(in: browser, context: context, documentURL: documentURL) else { return }
                if error == nil, eligible as? Bool == true,
                   self.beginOfficialSSOIfAllowed(in: browser, context: context) { return }
                browser.evaluateJavaScript("document.readyState === 'loading'") { [weak self, weak browser] loading, _ in
                    guard let self, let browser,
                          self.acceptsLoginEntry(in: browser, context: context, documentURL: documentURL) else { return }
                    self.continueAuthenticationReview(in: browser, context: context, attempt: attempt,
                        waitingForDocument: loading as? Bool == true, knownGuest: true)
                }
            }
        }
    }

    private func acceptsLoginEntry(in browser: WKWebView,
                                   context: QMplusLoginSynchronizationGate.Context, documentURL: URL) -> Bool {
        browser === webView && popupWebView == nil && browser.url == documentURL &&
            committedMainDocumentContext == context && loginGate.accepts(context) &&
            hasActiveAuthenticationRecognition && hasActiveAutofillLedger && !isAutofillApplicationInactive(browser)
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
                                             context: QMplusLoginSynchronizationGate.Context, attempt: Int,
                                             waitingForDocument: Bool = false, knownGuest: Bool = false) {
        guard loginGate.accepts(context), hasActiveAuthenticationRecognition else { return }
        if attempt < (waitingForDocument ? 20 : 3) {
                self.authenticationProbeTask?.cancel()
                self.authenticationProbeTask = Task { [weak self, weak browser] in
                    do { try await Task.sleep(for: .milliseconds(waitingForDocument ? 500 : 250 * (attempt + 1))) } catch { return }
                    guard let self, let browser, self.loginGate.accepts(context), self.hasActiveConnection else { return }
                    self.probeAuthentication(in: browser, context: context, attempt: attempt + 1)
                }
        } else if !self.isSyncing {
                if knownGuest, QMplusAutofillPolicy.isQMplusLoginDocument(browser.url) {
                    // An exhausted ordinary entry is a retryable connection
                    // failure, not a form the user should have to click.
                    self.endPresentation()
                    self.statusKey = "QMplus 官方网页登录失败，请重试"
                    self.isRetainingPreviousSnapshot = self.snapshot != nil
                    return
                }
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
        // WebKit's ordinary SSO popup stays in the hidden host. Only its
        // verified challenge can promote it to the visible sheet.
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
        if QMplusAutofillPolicy.isInspectableMicrosoftDocument(popup.url) {
            startAutofill(in: popup); return
        }
        if waitForMicrosoftTransit(popup) { return }
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
                self.autofillLedger.stop()
                self.pausedAutofillDocument = nil
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
        autofillLedger.stop()
        pausedAutofillDocument = nil
        presentExistingConnection()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(in: webView, navigation: navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(in: webView, navigation: navigation, error: error)
    }
}
