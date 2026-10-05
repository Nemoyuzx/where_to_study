import Foundation
import WebKit

enum QMplusAuthStage: String, Hashable, Sendable {
    case loading, authenticated, account, username, password, manual, challenge
    case continuation = "continue"
}
enum QMplusAuthReason: String, Sendable {
    case ready = "READY", authenticated = "AUTHENTICATED", loading = "LOADING"
    case invalidNonce = "INVALID_NONCE", staleDocument = "STALE_DOCUMENT", untrusted = "UNTRUSTED_CONTEXT"
    case unsupported = "UNSUPPORTED_PAGE", chooser = "ACCOUNT_CHOOSER", form = "FORM_UNTRUSTED"
    case interference = "INTERFERENCE", absent = "KNOWN_FORM_ABSENT", mismatch = "ACCOUNT_MISMATCH"
    case priorUsername = "USERNAME_NOT_SUBMITTED", attempted = "ALREADY_ATTEMPTED"
    case accountHintRequired = "ACCOUNT_HINT_REQUIRED"
    case currentAccountVerified = "CURRENT_ACCOUNT_VERIFIED"
    case captchaRequired = "CAPTCHA_REQUIRED", mfaRequired = "MFA_REQUIRED"
}

struct QMplusAuthInspection: Equatable, Sendable {
    let stage: QMplusAuthStage
    let document: String
    let accountMatch: Bool
    let reason: QMplusAuthReason

    static func decode(_ value: Any) -> Self? {
        guard let object = value as? [String: Any], Set(object.keys) == ["v", "stage", "document", "accountMatch", "reason"],
              let version = object["v"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let rawStage = object["stage"] as? String, let stage = QMplusAuthStage(rawValue: rawStage),
              let document = object["document"] as? String, QMplusAutofillPolicy.isValidNonce(document),
              let match = object["accountMatch"] as? NSNumber, CFGetTypeID(match) == CFBooleanGetTypeID(),
              let rawReason = object["reason"] as? String, let reason = QMplusAuthReason(rawValue: rawReason) else { return nil }
        return Self(stage: stage, document: document, accountMatch: match.boolValue, reason: reason)
    }
}

enum QMplusAuthInstallResult: Equatable, Sendable { case installed, conflict, unavailable }
enum QMplusAuthSubmissionResult: String, Sendable {
    case accountSelected = "ACCOUNT_SELECTED"
    case usernameSubmitted = "USERNAME_SUBMITTED", passwordSubmitted = "PASSWORD_SUBMITTED"
    case continuationSubmitted = "CONTINUE_SUBMITTED"
    case manual = "MANUAL_REQUIRED", rejected = "REJECTED", stale = "STALE_DOCUMENT"
}
enum QMplusAuthSubmission: Sendable {
    case account(document: String, account: String)
    case username(document: String, account: String)
    case password(document: String, account: String, password: String, identityAcknowledged: Bool = false)
    case continuation(document: String, account: String, identityAcknowledged: Bool)
}

enum QMplusAutofillPolicy {
    static let tenant = "569df091-b013-40e3-86ee-bd9cb9e25814"
    static let ssoURL = URL(string: "https://qmplus.qmul.ac.uk/auth/saml2/login.php")!
    static func isTrustedMicrosoftDocument(_ url: URL?) -> Bool {
        guard QMplusConnectionPolicy.isHTTPSNavigation(url), url?.host?.lowercased() == "login.microsoftonline.com",
              let url, let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return false }
        return ["/\(tenant)/saml2", "/\(tenant)/login", "/kmsi"].contains(path)
    }
    static func isQMplusLoginDocument(_ url: URL?) -> Bool {
        guard QMplusConnectionPolicy.isHTTPSNavigation(url), url?.host?.lowercased() == "qmplus.qmul.ac.uk", let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.fragment == nil else { return false }
        if components.percentEncodedPath == "/login/index.php" { return components.percentEncodedQuery == nil }
        return ["/", "/my", "/my/"].contains(components.percentEncodedPath)
            && (components.percentEncodedQuery == nil || components.percentEncodedQuery == "redirect=0")
    }
    static func isValidNonce(_ nonce: String) -> Bool {
        (8...64).contains(nonce.utf8.count) && nonce.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
    static func accountKey(_ account: String) -> String? {
        let key = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, key.utf16.count <= 320,
              !key.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              key.split(separator: "@", omittingEmptySubsequences: false).count == 2,
              !key.hasPrefix("@"), !key.hasSuffix("@") else { return nil }
        return key
    }
}

// One ledger survives real documents and main/popup swaps in this connection.
// It holds no account, password, URL or server session identifier.
@MainActor
final class QMplusAutofillLedger {
    private var presentation: UInt64 = 0
    private var credentialRevision: UInt64 = 0
    private var isActive = false
    private(set) var accountAttempted = false
    private(set) var usernameAttempted = false
    private(set) var passwordAttempted = false
    private(set) var usernameSubmittedDocument: String?
    private(set) var accountSelectedDocument: String?
    private var claimedAccountDocument: String?
    private var claimedUsernameDocument: String?
    private var ssoAttempted = false
    private(set) var continuationAttempted = false
    private var verifiedIdentityDocument: String?
    private var claimedPasswordDocument: String?
    private var passwordAcknowledged = false
    private var claimedContinuationDocument: String?
    private var continuationAcknowledgedDocument: String?

    func begin(presentation: UInt64, credentialRevision: UInt64) {
        self.presentation = presentation; self.credentialRevision = credentialRevision
        isActive = true; accountAttempted = false; usernameAttempted = false; passwordAttempted = false
        accountSelectedDocument = nil; claimedAccountDocument = nil
        usernameSubmittedDocument = nil; claimedUsernameDocument = nil; ssoAttempted = false
        continuationAttempted = false; verifiedIdentityDocument = nil
        claimedPasswordDocument = nil; passwordAcknowledged = false
        claimedContinuationDocument = nil; continuationAcknowledgedDocument = nil
    }
    func stop() {
        isActive = false; usernameSubmittedDocument = nil; claimedUsernameDocument = nil
        accountSelectedDocument = nil; claimedAccountDocument = nil
        verifiedIdentityDocument = nil; claimedPasswordDocument = nil; passwordAcknowledged = false
        claimedContinuationDocument = nil; continuationAcknowledgedDocument = nil
    }
    func accepts(presentation: UInt64, credentialRevision: UInt64) -> Bool {
        isActive && self.presentation == presentation && self.credentialRevision == credentialRevision
    }
    func claimSSO(presentation: UInt64, credentialRevision: UInt64) -> Bool {
        guard canStartOfficialLogin(presentation: presentation, credentialRevision: credentialRevision) else { return false }
        ssoAttempted = true; return true
    }
    func canStartOfficialLogin(presentation: UInt64, credentialRevision: UInt64) -> Bool {
        canNavigateLoginEntry(presentation: presentation, credentialRevision: credentialRevision) && !ssoAttempted
    }
    // Following the official Login GET is not permission to read or submit a
    // password. Its own presentation budget survives a previous SSO redirect.
    func canNavigateLoginEntry(presentation: UInt64, credentialRevision: UInt64) -> Bool {
        accepts(presentation: presentation, credentialRevision: credentialRevision) &&
            !accountAttempted && !usernameAttempted && !passwordAttempted && !continuationAttempted
    }
    func claim(_ state: QMplusAuthInspection, presentation: UInt64, credentialRevision: UInt64) -> Bool {
        guard accepts(presentation: presentation, credentialRevision: credentialRevision), state.reason == .ready,
              QMplusAutofillPolicy.isValidNonce(state.document) else { return false }
        switch state.stage {
        case .account:
            guard !accountAttempted, !usernameAttempted, !passwordAttempted, !continuationAttempted, state.accountMatch else { return false }
            accountAttempted = true; claimedAccountDocument = state.document; return true
        case .username:
            guard !usernameAttempted, !passwordAttempted, !continuationAttempted else { return false }
            usernameAttempted = true; claimedUsernameDocument = state.document; return true
        case .password:
            guard !passwordAttempted, !continuationAttempted, state.accountMatch, hasIdentityAcknowledgement(for: state.document) else { return false }
            passwordAttempted = true; claimedPasswordDocument = state.document; return true
        case .continuation:
            guard !continuationAttempted, state.accountMatch, hasIdentityAcknowledgement(for: state.document) else { return false }
            continuationAttempted = true; claimedContinuationDocument = state.document; return true
        default: return false
        }
    }
    func hasIdentityAcknowledgement(for document: String) -> Bool {
        usernameSubmittedDocument != nil || accountSelectedDocument != nil || passwordAcknowledged || verifiedIdentityDocument == document
    }
    func recordVerifiedIdentity(_ state: QMplusAuthInspection, presentation: UInt64, credentialRevision: UInt64) -> Bool {
        guard accepts(presentation: presentation, credentialRevision: credentialRevision), state.accountMatch,
              state.reason == .currentAccountVerified, QMplusAutofillPolicy.isValidNonce(state.document),
              (state.stage == .password && !passwordAttempted && !continuationAttempted) ||
                (state.stage == .continuation && !continuationAttempted) else { return false }
        verifiedIdentityDocument = state.document
        return true
    }
    func recordPasswordSubmission(document: String, presentation: UInt64, credentialRevision: UInt64) {
        guard accepts(presentation: presentation, credentialRevision: credentialRevision),
              passwordAttempted, claimedPasswordDocument == document else { return }
        passwordAcknowledged = true
    }
    func recordContinuationSubmission(document: String, presentation: UInt64, credentialRevision: UInt64) {
        guard accepts(presentation: presentation, credentialRevision: credentialRevision),
              continuationAttempted, claimedContinuationDocument == document else { return }
        continuationAcknowledgedDocument = document
    }
    func isAwaitingNavigation(from document: String) -> Bool {
        (passwordAcknowledged && claimedPasswordDocument == document) || continuationAcknowledgedDocument == document
    }
    func recordAccountSelection(document: String, presentation: UInt64, credentialRevision: UInt64) {
        guard accepts(presentation: presentation, credentialRevision: credentialRevision),
              accountAttempted, claimedAccountDocument == document else { return }
        accountSelectedDocument = document
    }
    func recordUsernameSubmission(document: String, presentation: UInt64, credentialRevision: UInt64) {
        guard accepts(presentation: presentation, credentialRevision: credentialRevision),
              usernameAttempted, claimedUsernameDocument == document else { return }
        usernameSubmittedDocument = document
    }
}

@MainActor
protocol QMplusAutofillEvaluating: AnyObject {
    func install(_ source: String, completion: @escaping @MainActor @Sendable (QMplusAuthInstallResult) -> Void)
    func inspect(nonce: String, accountHint: String, completion: @escaping @MainActor @Sendable (QMplusAuthInspection?) -> Void)
    func inspect(nonce: String, accountHint: String, identityAcknowledged: Bool,
                 completion: @escaping @MainActor @Sendable (QMplusAuthInspection?) -> Void)
    func submit(_ submission: QMplusAuthSubmission, completion: @escaping @MainActor @Sendable (QMplusAuthSubmissionResult?) -> Void)
}

extension QMplusAutofillEvaluating {
    func inspect(nonce: String, accountHint: String, identityAcknowledged: Bool,
                 completion: @escaping @MainActor @Sendable (QMplusAuthInspection?) -> Void) {
        inspect(nonce: nonce, accountHint: accountHint, completion: completion)
    }
}

@MainActor
final class QMplusWebKitAutofillEvaluator: QMplusAutofillEvaluating {
    private weak var browser: WKWebView?
    // Not page/defaultClient: each owned document has an app-private namespace.
    private let world = WKContentWorld.world(name: "com.nemoyu.wheretostudy.qmplus-auth.\(UUID().uuidString)")
    init(browser: WKWebView) { self.browser = browser }
    func install(_ source: String, completion: @escaping @MainActor @Sendable (QMplusAuthInstallResult) -> Void) {
        guard let browser else { completion(.unavailable); return }
        browser.evaluateJavaScript(source, in: nil, in: world) { result in
            guard case let .success(value) = result, let code = value as? String else { completion(.unavailable); return }
            completion(code == "AUTH_INSTALLED" ? .installed : code == "AUTH_CONFLICT" ? .conflict : .unavailable)
        }
    }
    func inspect(nonce: String, accountHint: String, completion: @escaping @MainActor @Sendable (QMplusAuthInspection?) -> Void) {
        inspect(nonce: nonce, accountHint: accountHint, identityAcknowledged: false, completion: completion)
    }
    func inspect(nonce: String, accountHint: String, identityAcknowledged: Bool,
                 completion: @escaping @MainActor @Sendable (QMplusAuthInspection?) -> Void) {
        guard let browser else { completion(nil); return }
        browser.callAsyncJavaScript("return WTSQmAuth.inspect(documentNonce, accountHint, identityAcknowledged);",
            arguments: ["documentNonce": nonce, "accountHint": accountHint, "identityAcknowledged": identityAcknowledged], in: nil, in: world) { result in
                guard case let .success(value) = result else { completion(nil); return }
                completion(QMplusAuthInspection.decode(value))
            }
    }
    func submit(_ submission: QMplusAuthSubmission, completion: @escaping @MainActor @Sendable (QMplusAuthSubmissionResult?) -> Void) {
        guard let browser else { completion(nil); return }
        let call = Self.submissionCall(submission)
        browser.callAsyncJavaScript(call.function, arguments: call.arguments, in: nil, in: world) { result in
            guard case let .success(value) = result, let code = value as? String else { completion(nil); return }
            completion(QMplusAuthSubmissionResult(rawValue: code))
        }
    }
    static func submissionCall(_ submission: QMplusAuthSubmission) -> (function: String, arguments: [String: Any]) {
        let arguments: [String: Any]
        let function: String
        switch submission {
        case let .account(nonce, account):
            // Account selection sends no password key or value into WebKit.
            arguments = ["documentNonce": nonce, "account": account]
            function = "return WTSQmAuth.fillAndSubmit({document:documentNonce, stage:'account', account});"
        case let .username(nonce, account):
            // No password key, even as undefined/null, enters the username call.
            arguments = ["documentNonce": nonce, "account": account]
            function = "return WTSQmAuth.fillAndSubmit({document:documentNonce, stage:'username', account});"
        case let .password(nonce, account, password, identityAcknowledged):
            arguments = ["documentNonce": nonce, "account": account, "password": password, "identityAcknowledged": identityAcknowledged]
            function = "return WTSQmAuth.fillAndSubmit({document:documentNonce, stage:'password', account, password, identityAcknowledged});"
        case let .continuation(nonce, account, identityAcknowledged):
            arguments = ["documentNonce": nonce, "account": account, "identityAcknowledged": identityAcknowledged]
            function = "return WTSQmAuth.fillAndSubmit({document:documentNonce, stage:'continue', account, identityAcknowledged});"
        }
        return (function, arguments)
    }
}

@MainActor
final class QMplusAutofillPipeline {
    enum Progress: Sendable { case username, password, continuation, waiting }
    private let evaluator: any QMplusAutofillEvaluating
    private let ledger: QMplusAutofillLedger
    private let presentation: UInt64
    private let credentialRevision: UInt64
    private let nonce: String
    private let isCurrent: @MainActor () -> Bool
    private let viewportReady: @MainActor () -> Bool
    private let credentials: @MainActor () -> QMplusSavedCredentials?
    private let manual: @MainActor () -> Void
    private let challenge: @MainActor () -> Void
    private let identityMismatch: @MainActor () -> Void
    private let progress: @MainActor (Progress) -> Void
    private var waitTask: Task<Void, Never>?
    private var cancelled = false
    private var started = false
    private var accountHint: String?
    private var awaitingChallenge = false
    private var viewportWaitCount = 0
    private var completedSubmissionStages = Set<QMplusAuthStage>()
    private let wait: @MainActor (Duration) async throws -> Void

    init(evaluator: any QMplusAutofillEvaluating, ledger: QMplusAutofillLedger, presentation: UInt64,
         credentialRevision: UInt64, nonce: String, isCurrent: @escaping @MainActor () -> Bool,
         viewportReady: @escaping @MainActor () -> Bool = { true },
         credentials: @escaping @MainActor () -> QMplusSavedCredentials?, manual: @escaping @MainActor () -> Void,
         challenge: @escaping @MainActor () -> Void = {},
         identityMismatch: @escaping @MainActor () -> Void = {},
         progress: @escaping @MainActor (Progress) -> Void = { _ in },
         wait: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.evaluator = evaluator; self.ledger = ledger; self.presentation = presentation
        self.credentialRevision = credentialRevision; self.nonce = nonce; self.isCurrent = isCurrent
        self.viewportReady = viewportReady
        self.credentials = credentials; self.manual = manual; self.identityMismatch = identityMismatch
        self.challenge = challenge
        self.progress = progress; self.wait = wait
    }

    private var accepts: Bool {
        !cancelled && isCurrent() && ledger.accepts(presentation: presentation, credentialRevision: credentialRevision)
    }
    func cancel() { cancelled = true; waitTask?.cancel(); waitTask = nil; accountHint = nil }
    func start(source: String) {
        guard !started, accepts, QMplusAutofillPolicy.isValidNonce(nonce) else { return }
        guard viewportReady() else { requireManual(); return }
        started = true
        evaluator.install(source) { [weak self] result in
            guard let self, self.accepts else { return }
            guard result == .installed else { self.requireManual(); return }
            self.inspect(attempt: 0)
        }
    }
    private func inspect(attempt: Int) {
        guard accepts else { return }
        guard viewportReady() else { waitForViewport(attempt: attempt); return }
        viewportWaitCount = 0
        if accountHint == nil {
            if let saved = credentials(), accepts { accountHint = QMplusAutofillPolicy.accountKey(saved.account) }
        }
        guard accepts else { return }
        evaluator.inspect(nonce: nonce, accountHint: accountHint ?? "",
                          identityAcknowledged: ledger.hasIdentityAcknowledgement(for: nonce)) { [weak self] state in
            guard let self, self.accepts else { return }
            guard self.viewportReady() else { self.waitForViewport(attempt: attempt); return }
            guard let state, state.document == self.nonce else { self.requireManual(); return }
            if state.stage == .challenge && [.captchaRequired, .mfaRequired].contains(state.reason) {
                if !self.awaitingChallenge { self.awaitingChallenge = true; self.challenge() }
                self.waitForChallenge(); return
            }
            self.awaitingChallenge = false
            if state.stage == .loading && state.reason == .loading {
                // The verification form may not have mounted yet. A missing
                // saved identity must not stop read-only challenge detection.
                self.scheduleInspection(attempt: attempt); return
            }
            guard self.accountHint != nil else { self.requireManual(); return }
            if state.reason == .currentAccountVerified {
                guard self.ledger.recordVerifiedIdentity(state, presentation: self.presentation,
                    credentialRevision: self.credentialRevision) else { self.requireManual(); return }
                self.scheduleInspection(attempt: attempt); return
            }
            if self.ledger.isAwaitingNavigation(from: self.nonce), state.stage == .manual,
               [.attempted, .form, .absent, .interference].contains(state.reason) {
                // A successful submit can leave its old form visible while
                // Microsoft prepares MFA/KMSI. Poll only; never submit again.
                self.scheduleInspection(attempt: attempt, maximumAttempts: 36); return
            }
            if state.stage == .account && state.reason == .accountHintRequired && !self.ledger.accountAttempted {
                self.accountHint = nil
                self.scheduleInspection(attempt: attempt); return
            }
            if state.stage == .manual && [.form, .absent].contains(state.reason) && !self.ledger.passwordAttempted {
                // A document can finish before the official form's first layout.
                // Wait finitely; no credential submission happens in this state.
                self.scheduleInspection(attempt: attempt); return
            }
            if state.stage == .manual && [.attempted, .chooser].contains(state.reason)
                && self.ledger.hasIdentityAcknowledgement(for: self.nonce) && !self.ledger.passwordAttempted {
                // The observed chooser briefly retains its empty container
                // after selection. Wait finitely without selecting or filling.
                self.scheduleInspection(attempt: attempt); return
            }
            guard self.ledger.claim(state, presentation: self.presentation, credentialRevision: self.credentialRevision),
                  self.accepts, let saved = self.credentials(), self.accepts,
                  QMplusAutofillPolicy.accountKey(saved.account) == self.accountHint,
                  saved.password.utf16.count <= 2048 else {
                if [.chooser, .mismatch].contains(state.reason) { self.identityMismatch() }
                self.requireManual(); return
            }
            let submission: QMplusAuthSubmission
            switch state.stage {
            case .account:
                submission = .account(document: self.nonce, account: saved.account)
            case .username:
                self.progress(.username)
                submission = .username(document: self.nonce, account: saved.account)
            case .password:
                self.progress(.password)
                submission = .password(document: self.nonce, account: saved.account, password: saved.password,
                    identityAcknowledged: self.ledger.hasIdentityAcknowledgement(for: self.nonce))
            case .continuation:
                self.progress(.continuation)
                submission = .continuation(document: self.nonce, account: saved.account,
                    identityAcknowledged: self.ledger.hasIdentityAcknowledgement(for: self.nonce))
            default: self.requireManual(); return
            }
            guard self.accepts else { return }
            guard self.viewportReady() else { self.requireManual(); return }
            let ledger = self.ledger, presentation = self.presentation, credentialRevision = self.credentialRevision, nonce = self.nonce
            self.evaluator.submit(submission) { [weak self, ledger] result in
                // A successful click may navigate before its ACK arrives.
                // Record only the originally claimed nonce/owner/revision;
                // UI polling still requires the live document below.
                if state.stage == .account && result == .accountSelected {
                    ledger.recordAccountSelection(document: nonce, presentation: presentation, credentialRevision: credentialRevision)
                } else if state.stage == .username && result == .usernameSubmitted {
                    ledger.recordUsernameSubmission(document: nonce, presentation: presentation, credentialRevision: credentialRevision)
                } else if state.stage == .password && result == .passwordSubmitted {
                    ledger.recordPasswordSubmission(document: nonce, presentation: presentation, credentialRevision: credentialRevision)
                } else if state.stage == .continuation && result == .continuationSubmitted {
                    ledger.recordContinuationSubmission(document: nonce, presentation: presentation, credentialRevision: credentialRevision)
                }
                guard let self, self.accepts, self.completedSubmissionStages.insert(state.stage).inserted else { return }
                if state.stage == .account && result == .accountSelected {
                    self.ledger.recordAccountSelection(document: self.nonce, presentation: self.presentation,
                        credentialRevision: self.credentialRevision)
                    self.progress(.waiting)
                    self.scheduleInspection(attempt: 0)
                } else if state.stage == .username && result == .usernameSubmitted {
                    self.ledger.recordUsernameSubmission(document: self.nonce, presentation: self.presentation,
                        credentialRevision: self.credentialRevision)
                    self.progress(.waiting)
                    self.scheduleInspection(attempt: 0)
                } else if state.stage == .password && result == .passwordSubmitted {
                    self.progress(.waiting)
                    self.scheduleInspection(attempt: 0)
                } else if state.stage == .continuation && result == .continuationSubmitted {
                    self.progress(.waiting)
                    self.scheduleInspection(attempt: 0)
                } else { self.requireManual() }
            }
        }
    }
    private func waitForChallenge() {
        guard accepts else { return }
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.wait(.seconds(1)) } catch { return }
            guard self.accepts else { return }
            self.inspect(attempt: 0)
        }
    }
    private func waitForViewport(attempt: Int) {
        guard accepts else { return }
        guard viewportWaitCount < 12 else { requireManual(); return }
        viewportWaitCount += 1
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.wait(.milliseconds(250)) } catch { return }
            guard self.accepts else { return }
            self.inspect(attempt: attempt)
        }
    }
    private func scheduleInspection(attempt: Int, maximumAttempts: Int = 8) {
        guard accepts else { return }
        guard attempt < maximumAttempts else { requireManual(); return }
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.wait(.milliseconds(attempt == 0 ? 250 : 500)) } catch { return }
            guard self.accepts else { return }
            self.inspect(attempt: attempt + 1)
        }
    }
    private func requireManual() {
        guard !cancelled else { return }
        cancel(); ledger.stop(); manual()
    }
}
