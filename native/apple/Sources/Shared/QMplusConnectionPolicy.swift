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

    var context: Context { Context(presentation: presentation, document: document) }
    mutating func beginPresentation() {
        presentation &+= 1; document &+= 1
        ownerKind = .visible; hasAttemptedAutomaticSync = false
    }
    mutating func beginQuietConnection() {
        presentation &+= 1; document &+= 1
        ownerKind = .quiet; hasAttemptedAutomaticSync = false
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

    // Only a Boolean leaves the official QM page. Do not inspect configuration,
    // cookies, credentials, storage, account labels, or the URL's query string.
    static let authenticatedPageScript = """
        (() => {
            if (location.origin !== 'https://qmplus.qmul.ac.uk') return false;
            const body = document.body;
            // Moodle's core only guarantees the negative body class. Its
            // authenticated user menu renders userbutton; guests do not.
            return !!body && !body.classList.contains('notloggedin')
                && !body.classList.contains('guestuser')
                && !!document.querySelector('.usermenu .userbutton');
        })()
        """
}
