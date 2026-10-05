import Foundation

/// Callback identity only; never carries a URL, account or session material.
struct QMplusLoginSynchronizationGate: Equatable, Sendable {
    enum OwnerKind: Equatable, Sendable { case visible, quiet }
    struct Context: Equatable, Sendable { let presentation: UInt64; let document: UInt64 }
    private(set) var presentation: UInt64 = 0
    private(set) var document: UInt64 = 0
    private(set) var ownerKind: OwnerKind?
    var isPresented: Bool { ownerKind == .visible }
    var isActive: Bool { ownerKind != nil }
    private(set) var hasAttemptedAutomaticSync = false
    private(set) var hasFollowedLoginEntry = false
    private(set) var hasAttemptedLoginRecovery = false

    var context: Context { Context(presentation: presentation, document: document) }
    mutating func beginPresentation() {
        presentation &+= 1; document &+= 1
        ownerKind = .visible; hasAttemptedAutomaticSync = false; hasFollowedLoginEntry = false
        hasAttemptedLoginRecovery = false
    }
    mutating func beginQuietConnection() {
        presentation &+= 1; document &+= 1
        ownerKind = .quiet; hasAttemptedAutomaticSync = false; hasFollowedLoginEntry = false
        hasAttemptedLoginRecovery = false
    }
    mutating func presentExistingConnection() { if isActive { ownerKind = .visible } }
    mutating func hideExistingConnection() { if isActive { ownerKind = .quiet } }
    mutating func beginDocument() { document &+= 1 }
    mutating func endPresentation() { presentation &+= 1; document &+= 1; ownerKind = nil }
    func accepts(_ context: Context) -> Bool { isActive && self.context == context }
    mutating func claimAutomaticSync(authenticated: Bool, context: Context) -> Bool {
        guard authenticated, accepts(context), !hasAttemptedAutomaticSync else { return false }
        hasAttemptedAutomaticSync = true
        return true
    }
    mutating func claimLoginEntry(context: Context) -> Bool {
        guard accepts(context), !hasFollowedLoginEntry else { return false }
        hasFollowedLoginEntry = true
        return true
    }
    mutating func claimLoginRecovery(context: Context) -> Bool {
        guard accepts(context), hasAttemptedAutomaticSync, !hasFollowedLoginEntry,
              !hasAttemptedLoginRecovery else { return false }
        hasAttemptedLoginRecovery = true
        hasAttemptedAutomaticSync = false
        return true
    }
}

enum QMplusOfficialPageStatus: String, Sendable {
    case loading, authenticated, guest, error, unknown
}

enum QMplusConnectionPolicy {
    static func isHTTPSNavigation(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
    }

    static func isOfficialAuthenticationPopup(_ url: URL?) -> Bool {
        guard isHTTPSNavigation(url), let host = url?.host?.lowercased() else { return false }
        return isOfficialAuthenticationOrigin(scheme: "https", host: host, port: url?.port ?? 443)
    }

    static func isOfficialAuthenticationOrigin(scheme: String, host: String, port: Int) -> Bool {
        scheme.lowercased() == "https" && (port == 0 || port == 443)
            && ["qmplus.qmul.ac.uk", "login.microsoftonline.com"].contains(host.lowercased())
    }

    // Only a fixed enum leaves the official main document. Shared with the
    // other clients; error-page text, identities and session material stay local.
    static let pageStatusScript: String = {
        guard let url = Bundle.main.url(forResource: "qmplus-page", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return "'unknown'" }
        return source.trimmingCharacters(in: .whitespacesAndNewlines)
    }()
    static let authenticatedPageScript = "(\(pageStatusScript)) === 'authenticated'"
    static let loginEntryURL = URL(string: "https://qmplus.qmul.ac.uk/login/index.php")!
    static let officialLoginEntryScript = """
        (() => {
            if (window.top !== window || location.origin !== 'https://qmplus.qmul.ac.uk') return false;
            if ((\(pageStatusScript)) !== 'guest') return false;
            return Array.from(document.querySelectorAll('a[href]')).slice(0,512).some(link => {
                try {
                    const url = new URL(link.getAttribute('href'), location.origin);
                    return url.origin === location.origin && !url.username && !url.password
                        && url.pathname === '/login/index.php' && !url.search && !url.hash;
                } catch { return false; }
            });
        })()
        """

    // This only confirms an official entry link; it never follows a page-supplied
    // query or reads credentials. Repeated header/footer links share one target.
    static let officialSSOEntryScript = """
        (() => {
            if (window.top !== window || location.origin !== 'https://qmplus.qmul.ac.uk') return false;
            if ((\(pageStatusScript)) !== 'guest') return false;
            return Array.from(document.querySelectorAll('a[href]')).slice(0,512).some(link => {
                try {
                    const url = new URL(link.getAttribute('href'), location.origin);
                    return url.origin === location.origin && !url.username && !url.password
                        && url.pathname === '/auth/saml2/login.php' && !url.search && !url.hash;
                } catch { return false; }
            });
        })()
        """

    static func officialHTTPFailureCode(status: Int, isMainFrame: Bool, url: URL?) -> String? {
        guard isMainFrame, isHTTPSNavigation(url), url?.host?.lowercased() == "qmplus.qmul.ac.uk",
              (400...599).contains(status) else { return nil }
        return "QM_HTTP_\(status)"
    }
}
