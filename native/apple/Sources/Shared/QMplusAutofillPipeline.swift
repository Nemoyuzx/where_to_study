import Foundation
import WebKit
#if DEBUG
import OSLog
#endif

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

enum QMplusAuthInstallResult: Equatable, Sendable { case installed, notReady, conflict, unavailable }
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

enum QMplusAutofillFailureCode: String, CaseIterable, Sendable {
    case installConflict = "INSTALL_CONFLICT"
    case installUnavailable = "INSTALL_UNAVAILABLE"
    case documentWaitExhausted = "DOCUMENT_WAIT_EXHAUSTED"
    case inspectionUnavailable = "INSPECTION_UNAVAILABLE"
    case inspectionStale = "INSPECTION_STALE"
    case verificationStageRejected = "VERIFICATION_STAGE_REJECTED"
    case missingAccountHint = "ACCOUNT_HINT_UNAVAILABLE"
    case identityEvidenceRejected = "IDENTITY_EVIDENCE_REJECTED"
    case pageRejected = "PAGE_REJECTED"
    case claimRejected = "CLAIM_REJECTED"
    case credentialsUnavailable = "CREDENTIALS_UNAVAILABLE"
    case credentialsRejected = "CREDENTIALS_REJECTED"
    case pageWaitExhausted = "PAGE_WAIT_EXHAUSTED"
    case viewportWaitExhausted = "VIEWPORT_WAIT_EXHAUSTED"
    case viewportLostAfterClaim = "VIEWPORT_LOST_AFTER_CLAIM"
    case accountSelectionNoAdvance = "ACCOUNT_CLICK_NO_ADVANCE"
    case submissionUnavailable = "SUBMISSION_UNAVAILABLE"
    case submissionRejected = "SUBMISSION_REJECTED"
    case submissionStale = "SUBMISSION_STALE"
    case submissionManual = "SUBMISSION_MANUAL_REQUIRED"
    case unexpectedSubmissionACK = "SUBMISSION_ACK_UNEXPECTED"
}

// Only native enum values can enter this production-visible diagnostic. Never
// retain or interpolate an account, nonce, URL, DOM text or evaluator error.
struct QMplusAutofillFailure: Equatable, Sendable {
    let code: QMplusAutofillFailureCode
    let stage: QMplusAuthStage?
    let reason: QMplusAuthReason?

    var diagnosticCode: String {
        [code.rawValue, stage?.rawValue, reason?.rawValue].compactMap { $0 }.joined(separator: ":")
    }
}

enum QMplusAutofillPolicy {
    // Stay inside the Store's existing 20-second owner watchdog. Slow real
    // devices must not lose an otherwise valid picker after only four seconds.
    static let maximumPageWaits = 36
    static let maximumViewportWaits = 72
    static let tenant = "569df091-b013-40e3-86ee-bd9cb9e25814"
    static let ssoURL = URL(string: "https://qmplus.qmul.ac.uk/auth/saml2/login.php")!
    static func isResumableOfficialDocument(_ url: URL?) -> Bool {
        QMplusConnectionPolicy.isOfficialAuthenticationPopup(url) || isPassiveMicrosoftTransit(url)
    }
    static func isNewCommittedNavigation(_ committed: AnyObject?, active: AnyObject?, paused: AnyObject?) -> Bool {
        guard let committed, let active, let paused else { return false }
        return committed === active && committed !== paused
    }
    static func isTrustedMicrosoftDocument(_ url: URL?) -> Bool {
        guard QMplusConnectionPolicy.isHTTPSNavigation(url), url?.host?.lowercased() == "login.microsoftonline.com",
              let url, let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return false }
        return ["/\(tenant)/saml2", "/\(tenant)/login", "/kmsi"].contains(path)
    }
    static func isMicrosoftVerificationDocument(_ url: URL?) -> Bool {
        guard QMplusConnectionPolicy.isHTTPSNavigation(url), url?.host?.lowercased() == "login.microsoftonline.com",
              let url, let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return false }
        return path.lowercased() == "/common/deviceauthtls/reprocess"
    }
    static func isInspectableMicrosoftDocument(_ url: URL?) -> Bool {
        isTrustedMicrosoftDocument(url) || isMicrosoftVerificationDocument(url)
    }
    static func isPassiveMicrosoftTransit(_ url: URL?) -> Bool {
        guard QMplusConnectionPolicy.isHTTPSNavigation(url) else { return false }
        return ["login.microsoftonline.com", "device.login.microsoftonline.com"].contains(url?.host?.lowercased() ?? "")
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
        let normalizedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAccount.isEmpty, normalizedAccount.utf16.count <= 320,
              !normalizedAccount.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              normalizedAccount.split(separator: "@", omittingEmptySubsequences: false).count == 2,
              !normalizedAccount.hasPrefix("@"), !normalizedAccount.hasSuffix("@") else { return nil }
        return normalizedAccount
    }
}

// One ledger survives real documents and main/popup swaps in this connection.
// It holds no account, password, URL or server session identifier.
@MainActor
final class QMplusAutofillLedger {
    private var presentation: UInt64 = 0
    private var credentialRevision: UInt64 = 0
    private var isActive = false
    private var isSuspended = false
    private var resumptionAvailable = true
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
        isActive = true; isSuspended = false; resumptionAvailable = true
        accountAttempted = false; usernameAttempted = false; passwordAttempted = false
        accountSelectedDocument = nil; claimedAccountDocument = nil
        usernameSubmittedDocument = nil; claimedUsernameDocument = nil; ssoAttempted = false
        continuationAttempted = false; verifiedIdentityDocument = nil
        claimedPasswordDocument = nil; passwordAcknowledged = false
        claimedContinuationDocument = nil; continuationAcknowledgedDocument = nil
    }
    func stop() {
        isActive = false; isSuspended = false; resumptionAvailable = false
        usernameSubmittedDocument = nil; claimedUsernameDocument = nil
        accountSelectedDocument = nil; claimedAccountDocument = nil
        verifiedIdentityDocument = nil; claimedPasswordDocument = nil; passwordAcknowledged = false
        claimedContinuationDocument = nil; continuationAcknowledgedDocument = nil
    }
    // Pause only the unrecognized document. A later verified real document may
    // resume once without resetting any submission claim or identity ACK.
    func suspend() {
        guard isActive else { return }
        isActive = false
        isSuspended = resumptionAvailable
    }
    @discardableResult
    func resume(presentation: UInt64, credentialRevision: UInt64) -> Bool {
        guard isSuspended, resumptionAvailable, self.presentation == presentation,
              self.credentialRevision == credentialRevision else { return false }
        isSuspended = false; resumptionAvailable = false; isActive = true
        return true
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
    func canClaim(_ state: QMplusAuthInspection, presentation: UInt64, credentialRevision: UInt64) -> Bool {
        guard accepts(presentation: presentation, credentialRevision: credentialRevision), state.reason == .ready,
              QMplusAutofillPolicy.isValidNonce(state.document) else { return false }
        switch state.stage {
        case .account:
            return !accountAttempted && !usernameAttempted && !passwordAttempted && !continuationAttempted && state.accountMatch
        case .username:
            return !usernameAttempted && !passwordAttempted && !continuationAttempted
        case .password:
            return !passwordAttempted && !continuationAttempted && state.accountMatch && hasIdentityAcknowledgement(for: state.document)
        case .continuation:
            return !continuationAttempted && state.accountMatch && hasIdentityAcknowledgement(for: state.document)
        default: return false
        }
    }
    func claim(_ state: QMplusAuthInspection, presentation: UInt64, credentialRevision: UInt64) -> Bool {
        guard canClaim(state, presentation: presentation, credentialRevision: credentialRevision) else { return false }
        switch state.stage {
        case .account: accountAttempted = true; claimedAccountDocument = state.document
        case .username: usernameAttempted = true; claimedUsernameDocument = state.document
        case .password: passwordAttempted = true; claimedPasswordDocument = state.document
        case .continuation: continuationAttempted = true; claimedContinuationDocument = state.document
        default: return false
        }
        return true
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
        guard let browser, let url = browser.url, let call = Self.installationCall(source, url: url) else {
            completion(.unavailable); return
        }
        browser.callAsyncJavaScript(call.function, arguments: call.arguments, in: nil, in: world) { [weak browser] result in
            guard let browser, browser.url == url, QMplusAutofillPolicy.isInspectableMicrosoftDocument(browser.url) else {
                completion(.unavailable); return
            }
            guard case let .success(value) = result, let code = value as? String else { completion(.unavailable); return }
            switch code {
            case "AUTH_INSTALLED": completion(.installed)
            case "AUTH_NOT_READY": completion(.notReady)
            case "AUTH_CONFLICT": completion(.conflict)
            default: completion(.unavailable)
            }
        }
    }
    static func installationCall(_ source: String, url: URL?) -> (function: String, arguments: [String: Any])? {
        guard QMplusAutofillPolicy.isInspectableMicrosoftDocument(url), let url,
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return nil }
        // Readiness and installation are one call in the same private world.
        // The guarded branch reads no account, nonce, storage or cookie. A
        // loading DOM is observed again; a ready but untrusted one fails closed.
        let function = """
            if (document.readyState === 'loading') return 'AUTH_NOT_READY';
            if (window.top !== window || document.defaultView !== window) return 'AUTH_UNAVAILABLE';
            let current;
            try { current = new URL(location.href); } catch { return 'AUTH_UNAVAILABLE'; }
            if (current.protocol !== 'https:' || current.username || current.password ||
                (current.port && current.port !== '443') || current.origin !== location.origin) return 'AUTH_UNAVAILABLE';
            const path = expectedPath === '/common/deviceauthtls/reprocess' ? current.pathname.toLowerCase() : current.pathname;
            if (current.origin !== expectedOrigin || path !== expectedPath) return 'AUTH_UNAVAILABLE';
            const installed = \(source)
            return installed;
            """
        let expectedPath = QMplusAutofillPolicy.isMicrosoftVerificationDocument(url) ? path.lowercased() : path
        return (function, ["expectedOrigin": "https://login.microsoftonline.com", "expectedPath": expectedPath])
    }
    func inspect(nonce: String, accountHint: String, completion: @escaping @MainActor @Sendable (QMplusAuthInspection?) -> Void) {
        inspect(nonce: nonce, accountHint: accountHint, identityAcknowledged: false, completion: completion)
    }
    func inspect(nonce: String, accountHint: String, identityAcknowledged: Bool,
                 completion: @escaping @MainActor @Sendable (QMplusAuthInspection?) -> Void) {
        guard let browser else { completion(nil); return }
        browser.callAsyncJavaScript("return WTSQmAuth.inspect(documentNonce, accountHint, identityAcknowledged);",
            arguments: ["documentNonce": nonce, "accountHint": accountHint, "identityAcknowledged": identityAcknowledged], in: nil, in: world) { [weak self] result in
                guard case let .success(value) = result else { completion(nil); return }
                let state = QMplusAuthInspection.decode(value)
                #if DEBUG
                self?.traceAccountLayout(state, hint: accountHint)
                #endif
                completion(state)
            }
    }
    #if DEBUG
    private static let qaLayoutLogger = Logger(subsystem: "com.nemoyu.wheretostudy.qa.qm-auth", category: "layout")

    // Read-only QA metadata: DOM identity text is reduced to equality in-page.
    // Styles and hit ownership are closed enums, never arbitrary DOM strings.
    static let identityLayoutTraceScript = """
        const key = accountHint.trim().toLowerCase();
        const count = selector => Math.min(document.querySelectorAll(selector).length, 999);
        const identities = document.querySelectorAll('#displayName');
        const identity = identities.length === 1 ? identities[0] : null;
        const submits = document.querySelectorAll('input#idSIButton9[type="submit"]');
        const submit = submits.length === 1 ? submits[0] : null;
        const metric = value => Number.isFinite(value) ? Math.round(Math.max(-100000, Math.min(100000, value))) : 0;
        const rectangle = node => {
            const r = node?.getBoundingClientRect();
            return r ? [r.x, r.y, r.width, r.height].map(metric) : [];
        };
        const choice = (value, allowed) => allowed.includes(value) ? value : 'other';
        const style = node => {
            const s = window.getComputedStyle(node);
            const opacity = Number(s.opacity);
            return {display:choice(s.display, ['none','block','inline','inline-block','flex','inline-flex','grid','inline-grid','contents']),
                visibility:choice(s.visibility, ['visible','hidden','collapse']),
                pointerEvents:choice(s.pointerEvents, ['auto','none']),
                opacity:!Number.isFinite(opacity) ? 'invalid' : opacity <= 0.01 ? 'transparent' : opacity < 1 ? 'translucent' : 'opaque',
                hidden:node.hidden === true, inert:node.inert === true, ariaHidden:node.getAttribute('aria-hidden') === 'true'};
        };
        const hitKind = node => {
            if (!node) return 'missing';
            const r = node.getBoundingClientRect();
            const hit = document.elementFromPoint(r.left+r.width/2, r.top+r.height/2);
            if (!hit) return 'none';
            if (hit === node) return 'self';
            if (node.contains(hit)) return 'descendant';
            if (hit === node.parentElement) return 'parent';
            if (hit.contains(node)) return 'ancestor';
            return 'unrelated';
        };
        const ancestors = [];
        for (let node = identity; node && ancestors.length < 12; node = node.parentElement) {
            ancestors.push({rect:rectangle(node), style:style(node)});
        }
        return JSON.stringify({ready:choice(document.readyState, ['loading','interactive','complete']),
            viewport:[metric(innerWidth),metric(innerHeight)], identities:Math.min(identities.length,999),
            forms:count('form#i0281'), submits:Math.min(submits.length,999),
            passwords:count('input#i0118[name="passwd"][type="password"]'), usernames:count('#i0116'),
            identityMatches:!!key && !!identity && typeof identity.textContent === 'string' && identity.textContent.trim().toLowerCase() === key,
            identityHit:hitKind(identity), submitHit:hitKind(submit), ancestors});
        """

    // Opt-in simulator diagnostics contain only fixed status codes, counts,
    // geometry and equality booleans. Never return DOM text, identities or URLs.
    private func traceAccountLayout(_ state: QMplusAuthInspection?, hint: String) {
        guard ProcessInfo.processInfo.environment["WTS_QMPLUS_AUTH_TRACE"] == "1",
              let browser, let state else { return }
        FileHandle.standardError.write(Data("WTS_QM_AUTH stage=\(state.stage.rawValue) reason=\(state.reason.rawValue) match=\(state.accountMatch) savedHint=\(!hint.isEmpty)\n".utf8))
        guard QMplusAutofillPolicy.isInspectableMicrosoftDocument(browser.url) else { return }
        if state.stage == .manual && state.reason == .mismatch {
            browser.callAsyncJavaScript(Self.identityLayoutTraceScript, arguments: ["accountHint": hint], in: nil, in: world) { result in
                guard case let .success(value) = result, let text = value as? String, text.utf8.count <= 4096 else { return }
                FileHandle.standardError.write(Data("WTS_QM_IDENTITY_LAYOUT \(text)\n".utf8))
                Self.qaLayoutLogger.notice("WTS_QM_IDENTITY_LAYOUT \(text, privacy: .public)")
            }
            return
        }
        guard state.stage == .account || state.reason == .chooser || state.stage == .loading else { return }
        browser.callAsyncJavaScript("""
            const key = accountHint.trim().toLowerCase();
            const norm = value => typeof value === 'string' ? value.trim().toLowerCase() : '';
            const holder = document.querySelector('#tilesHolder');
            const rows = Array.from(document.querySelectorAll('#tilesHolder div.table[role="button"][data-test-id]')).slice(0, 4);
            const rectangle = node => {
                const r = node?.getBoundingClientRect();
                return r ? [r.x, r.y, r.width, r.height].map(value => Math.round(value)) : [];
            };
            return JSON.stringify({ready:document.readyState, viewport:[innerWidth,innerHeight],
                holders:document.querySelectorAll('#tilesHolder').length,
                asyncPending:holder?.getAttribute('data-test-asynctilesloaded') === 'false',
                rows:rows.map(row => {
                    const content = row.querySelector('div.table-cell.text-left.content');
                    const r = row.getBoundingClientRect();
                    const hit = document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);
                    const leaves = content ? Array.from(content.querySelectorAll('*')).filter(node =>
                        node.childElementCount === 0 && norm(node.textContent) === key) : [];
                    return {attributeMatch:norm(row.getAttribute('data-test-id'))===key,
                        contentMatch:norm(content?.textContent)===key,
                        contentChildren:content?.childElementCount ?? 0,
                        emailLeaves:leaves.length, rowRect:rectangle(row), contentRect:rectangle(content),
                        emailRects:leaves.map(rectangle),
                        centerOwned:hit?.closest('button,a,[role="button"]')===row,
                        emailOwned:leaves.map(node=>{
                            const r=node.getBoundingClientRect();
                            return document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.closest('button,a,[role="button"]')===row;
                        })};
                })});
            """, arguments: ["accountHint": hint], in: nil, in: world) { result in
                guard case let .success(value) = result, let text = value as? String, text.utf8.count <= 4096 else { return }
                FileHandle.standardError.write(Data("WTS_QM_LAYOUT \(text)\n".utf8))
            }
    }
    #endif
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
    private let verificationOnly: Bool
    private let credentials: @MainActor () -> QMplusSavedCredentials?
    private let manual: @MainActor () -> Void
    private let challenge: @MainActor () -> Void
    private let identityMismatch: @MainActor () -> Void
    private let onFailure: @MainActor (QMplusAutofillFailure) -> Void
    private let progress: @MainActor (Progress) -> Void
    private var waitTask: Task<Void, Never>?
    private var cancelled = false
    private var started = false
    private var accountHint: String?
    private var awaitingChallenge = false
    private var viewportWaitCount = 0
    private var documentWaitCount = 0
    private var lastStage: QMplusAuthStage?
    private var lastReason: QMplusAuthReason?
    private var completedSubmissionStages = Set<QMplusAuthStage>()
    private let wait: @MainActor (Duration) async throws -> Void

    init(evaluator: any QMplusAutofillEvaluating, ledger: QMplusAutofillLedger, presentation: UInt64,
         credentialRevision: UInt64, nonce: String, isCurrent: @escaping @MainActor () -> Bool,
         viewportReady: @escaping @MainActor () -> Bool = { true },
         verificationOnly: Bool = false,
         credentials: @escaping @MainActor () -> QMplusSavedCredentials?, manual: @escaping @MainActor () -> Void,
         challenge: @escaping @MainActor () -> Void = {},
         identityMismatch: @escaping @MainActor () -> Void = {},
         onFailure: @escaping @MainActor (QMplusAutofillFailure) -> Void = { _ in },
         progress: @escaping @MainActor (Progress) -> Void = { _ in },
         wait: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.evaluator = evaluator; self.ledger = ledger; self.presentation = presentation
        self.credentialRevision = credentialRevision; self.nonce = nonce; self.isCurrent = isCurrent
        self.viewportReady = viewportReady
        self.verificationOnly = verificationOnly
        self.credentials = credentials; self.manual = manual; self.identityMismatch = identityMismatch
        self.challenge = challenge
        self.onFailure = onFailure
        self.progress = progress; self.wait = wait
    }

    private var accepts: Bool {
        !cancelled && isCurrent() && ledger.accepts(presentation: presentation, credentialRevision: credentialRevision)
    }
    func cancel() { cancelled = true; waitTask?.cancel(); waitTask = nil; accountHint = nil }
    func start(source: String) {
        guard !started, accepts, QMplusAutofillPolicy.isValidNonce(nonce) else { return }
        started = true
        installWhenReady(source: source)
    }
    private func installWhenReady(source: String) {
        guard accepts else { return }
        guard viewportReady() else { waitForViewport(attempt: 0, beforeInstall: source); return }
        evaluator.install(source) { [weak self] result in
            guard let self, self.accepts else { return }
            if result == .notReady { self.waitForDocument(source: source); return }
            guard result == .installed else {
                self.requireManual(code: result == .conflict ? .installConflict : .installUnavailable); return
            }
            self.inspect(attempt: 0)
        }
    }
    private func waitForDocument(source: String) {
        guard accepts else { return }
        guard documentWaitCount < QMplusAutofillPolicy.maximumPageWaits else {
            requireManual(code: .documentWaitExhausted, resumable: true); return
        }
        let delay = documentWaitCount == 0 ? 250 : 500
        documentWaitCount += 1
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.wait(.milliseconds(delay)) } catch { return }
            guard self.accepts else { return }
            self.installWhenReady(source: source)
        }
    }
    private func inspect(attempt: Int) {
        guard accepts else { return }
        guard viewportReady() else { waitForViewport(attempt: attempt); return }
        if !verificationOnly && accountHint == nil {
            if let saved = credentials(), accepts { accountHint = QMplusAutofillPolicy.accountKey(saved.account) }
        }
        guard accepts else { return }
        evaluator.inspect(nonce: nonce, accountHint: accountHint ?? "",
                          identityAcknowledged: ledger.hasIdentityAcknowledgement(for: nonce)) { [weak self] state in
            guard let self, self.accepts else { return }
            if let state, state.document == self.nonce {
                self.lastStage = state.stage; self.lastReason = state.reason
            }
            guard self.viewportReady() else { self.waitForViewport(attempt: attempt); return }
            guard let state else { self.requireManual(code: .inspectionUnavailable); return }
            guard state.document == self.nonce else { self.requireManual(code: .inspectionStale); return }
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
            guard !self.verificationOnly else { self.requireManual(code: .verificationStageRejected); return }
            guard self.accountHint != nil else { self.requireManual(code: .missingAccountHint); return }
            if state.reason == .currentAccountVerified {
                guard self.ledger.recordVerifiedIdentity(state, presentation: self.presentation,
                    credentialRevision: self.credentialRevision) else { self.requireManual(code: .identityEvidenceRejected); return }
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
            if state.stage == .manual && state.reason == .chooser && !self.ledger.accountAttempted &&
                !self.ledger.usernameAttempted && !self.ledger.passwordAttempted && !self.ledger.continuationAttempted {
                // Microsoft's first account tile can arrive after its holder.
                // Inspect finitely before pausing; no identity is inferred.
                self.scheduleInspection(attempt: attempt); return
            }
            if state.stage == .manual && [.attempted, .chooser].contains(state.reason)
                && self.ledger.hasIdentityAcknowledgement(for: self.nonce) && !self.ledger.passwordAttempted {
                // The observed chooser briefly retains its empty container
                // after selection. Wait finitely without selecting or filling.
                self.scheduleInspection(attempt: attempt); return
            }
            guard self.ledger.canClaim(state, presentation: self.presentation, credentialRevision: self.credentialRevision) else {
                if state.reason == .mismatch { self.identityMismatch() }
                self.requireManual(code: state.stage == .manual ? .pageRejected : .claimRejected); return
            }
            guard self.accepts else { return }
            let saved = self.credentials()
            guard self.accepts else { return }
            guard self.viewportReady() else { self.waitForViewport(attempt: attempt); return }
            guard let saved else { self.requireManual(code: .credentialsUnavailable); return }
            guard QMplusAutofillPolicy.accountKey(saved.account) == self.accountHint,
                  saved.password.utf16.count <= 2048 else {
                self.requireManual(code: .credentialsRejected); return
            }
            // Do not consume a stage merely because a later secure-store read
            // or viewport check is not ready. A resumed wait re-inspects the
            // page and reads credentials afresh instead of retaining a password.
            guard self.viewportReady() else { self.waitForViewport(attempt: attempt); return }
            guard self.ledger.claim(state, presentation: self.presentation, credentialRevision: self.credentialRevision) else {
                self.requireManual(code: .claimRejected); return
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
            default: self.requireManual(code: .claimRejected); return
            }
            guard self.accepts else { return }
            guard self.viewportReady() else { self.requireManual(code: .viewportLostAfterClaim); return }
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
                } else {
                    let code: QMplusAutofillFailureCode
                    switch result {
                    case .none: code = .submissionUnavailable
                    case .some(.manual): code = .submissionManual
                    case .some(.rejected): code = .submissionRejected
                    case .some(.stale): code = .submissionStale
                    default: code = .unexpectedSubmissionACK
                    }
                    self.requireManual(code: code)
                }
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
    private func waitForViewport(attempt: Int, beforeInstall source: String? = nil) {
        guard accepts else { return }
        guard viewportWaitCount < QMplusAutofillPolicy.maximumViewportWaits else {
            requireManual(code: .viewportWaitExhausted, resumable: true); return
        }
        viewportWaitCount += 1
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.wait(.milliseconds(250)) } catch { return }
            guard self.accepts else { return }
            if let source { self.installWhenReady(source: source) }
            else { self.inspect(attempt: attempt) }
        }
    }
    private func scheduleInspection(attempt: Int, maximumAttempts: Int = QMplusAutofillPolicy.maximumPageWaits) {
        guard accepts else { return }
        guard attempt < maximumAttempts else {
            let accountDidNotAdvance = ledger.accountSelectedDocument == nonce && !ledger.passwordAttempted &&
                lastStage == .manual && (lastReason == .attempted || lastReason == .chooser)
            requireManual(code: accountDidNotAdvance ? .accountSelectionNoAdvance : .pageWaitExhausted, resumable: true)
            return
        }
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.wait(.milliseconds(attempt == 0 ? 250 : 500)) } catch { return }
            guard self.accepts else { return }
            self.inspect(attempt: attempt + 1)
        }
    }
    private func requireManual(code: QMplusAutofillFailureCode, resumable: Bool = false) {
        guard !cancelled else { return }
        let failure = QMplusAutofillFailure(code: code, stage: lastStage, reason: lastReason)
        cancel()
        if resumable { ledger.suspend() } else { ledger.stop() }
        onFailure(failure)
        manual()
    }
}
