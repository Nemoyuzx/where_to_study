import XCTest
import JavaScriptCore
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class QMplusConnectionPolicyTests: XCTestCase {
    // Specification only: local automated execution is disabled by the user.
    func testFixedLoginEntryHasOnePresentationBudgetAndRejectsStaleDocuments() {
        var gate = QMplusLoginSynchronizationGate()
        gate.beginQuietConnection()
        let first = gate.context
        XCTAssertTrue(gate.claimLoginEntry(context: first))
        gate.beginDocument()
        XCTAssertFalse(gate.claimLoginEntry(context: first))
        XCTAssertFalse(gate.claimLoginEntry(context: gate.context))
        gate.endPresentation()
        gate.beginQuietConnection()
        XCTAssertTrue(gate.claimLoginEntry(context: gate.context))
    }
    func testAutomaticSynchronizationNeedsAuthenticationAndOnlyRunsOncePerPresentation() {
        var gate = QMplusLoginSynchronizationGate()
        gate.beginPresentation()
        let first = gate.context
        XCTAssertFalse(gate.claimAutomaticSync(authenticated: false, context: first))
        XCTAssertFalse(gate.hasAttemptedAutomaticSync)
        XCTAssertTrue(gate.claimAutomaticSync(authenticated: true, context: first))
        XCTAssertFalse(gate.claimAutomaticSync(authenticated: true, context: first))
        gate.beginDocument()
        XCTAssertFalse(gate.claimAutomaticSync(authenticated: true, context: gate.context),
                       "Dashboard/history navigation must not start duplicate business requests")
        gate.endPresentation()
        gate.beginPresentation()
        XCTAssertTrue(gate.claimAutomaticSync(authenticated: true, context: gate.context))
    }

    func testNavigationCloseAndReconnectionRejectOldDOMResults() {
        var gate = QMplusLoginSynchronizationGate()
        gate.beginPresentation()
        let previousDocument = gate.context
        gate.beginDocument()
        XCTAssertFalse(gate.accepts(previousDocument))
        XCTAssertFalse(gate.claimAutomaticSync(authenticated: true, context: previousDocument))
        let previousPresentation = gate.context
        gate.endPresentation()
        XCTAssertFalse(gate.accepts(previousPresentation))
        gate.beginPresentation()
        XCTAssertFalse(gate.claimAutomaticSync(authenticated: true, context: previousPresentation))
        XCTAssertTrue(gate.claimAutomaticSync(authenticated: true, context: gate.context))
    }

    func testQuietOwnerDoesNotNeedASheetAndBecomesVisibleWithoutChangingItsEpoch() {
        var gate = QMplusLoginSynchronizationGate()
        gate.beginQuietConnection()
        let context = gate.context
        XCTAssertTrue(gate.isActive)
        XCTAssertFalse(gate.isPresented)
        XCTAssertTrue(gate.accepts(context))
        gate.presentExistingConnection()
        XCTAssertTrue(gate.isPresented)
        XCTAssertEqual(gate.context, context, "MFA must keep the same isolated connection, not restart login")
        XCTAssertTrue(gate.claimAutomaticSync(authenticated: true, context: context))
        gate.endPresentation()
        XCTAssertFalse(gate.isActive)
        XCTAssertFalse(gate.accepts(context))
        gate.presentExistingConnection()
        XCTAssertFalse(gate.isActive, "A late popup cannot revive a cancelled owner")
    }

    func testAuthenticationPopupOnlyAcceptsExactOfficialOriginsAndSecureDefaultPort() {
        for host in ["qmplus.qmul.ac.uk", "login.microsoftonline.com"] {
            XCTAssertTrue(QMplusConnectionPolicy.isOfficialAuthenticationPopup(URL(string: "https://\(host)/")))
            XCTAssertTrue(QMplusConnectionPolicy.isOfficialAuthenticationOrigin(scheme: "https", host: host, port: 0))
            XCTAssertTrue(QMplusConnectionPolicy.isOfficialAuthenticationOrigin(scheme: "HTTPS", host: host.uppercased(), port: 443))
        }
        for value in ["http://qmplus.qmul.ac.uk/", "https://qmplus.qmul.ac.uk:444/",
                      "https://qmplus.qmul.ac.uk.evil.invalid/", "https://evil.invalid/",
                      "https://fixture:fixture@qmplus.qmul.ac.uk/", "about:blank", "javascript:void(0)"] {
            XCTAssertFalse(QMplusConnectionPolicy.isOfficialAuthenticationPopup(URL(string: value)), value)
        }
        XCTAssertFalse(QMplusConnectionPolicy.isOfficialAuthenticationOrigin(scheme: "https", host: "login.microsoftonline.com", port: 444))
        XCTAssertTrue(QMplusConnectionPolicy.isHTTPSNavigation(URL(string: "https://example.invalid/")),
                      "Ordinary HTTPS page navigation is not permission to create an authentication popup or run sync")
    }

    func testDOMProofIsBooleanAndDoesNotRequireANonexistentLoggedinBodyClass() throws {
        XCTAssertTrue(try authenticationProof(origin: "https://qmplus.qmul.ac.uk", bodyClasses: [], hasUserMenu: true))
        XCTAssertFalse(try authenticationProof(origin: "https://qmplus.qmul.ac.uk", bodyClasses: [], hasUserMenu: false))
        XCTAssertFalse(try authenticationProof(origin: "https://qmplus.qmul.ac.uk", bodyClasses: ["notloggedin"], hasUserMenu: true))
        XCTAssertFalse(try authenticationProof(origin: "https://qmplus.qmul.ac.uk", bodyClasses: ["guestuser"], hasUserMenu: true))
        XCTAssertFalse(try authenticationProof(origin: "https://login.microsoftonline.com", bodyClasses: [], hasUserMenu: true))
        XCTAssertFalse(try authenticationProof(origin: "https://qmplus.qmul.ac.uk.evil.invalid", bodyClasses: [], hasUserMenu: true))
        for field in ["document.cookie", "sesskey", "M.cfg", "localStorage", "sessionStorage", "innerHTML", "location.search"] {
            XCTAssertFalse(QMplusConnectionPolicy.authenticatedPageScript.contains(field))
        }
    }

    func testHTTPFailuresAndFatalDOMCannotBecomeAuthenticatedPages() throws {
        XCTAssertFalse(try authenticationProof(origin: "https://qmplus.qmul.ac.uk", bodyClasses: [], hasUserMenu: true, bodyID: "page-error"))
        XCTAssertFalse(try authenticationProof(origin: "https://qmplus.qmul.ac.uk", bodyClasses: [], hasUserMenu: true, fatal: true))
        XCTAssertFalse(try authenticationProof(origin: "https://qmplus.qmul.ac.uk", bodyClasses: [], hasUserMenu: true, exceptionTitle: "generalexceptionmessage"))
        XCTAssertTrue(try authenticationProof(origin: "https://qmplus.qmul.ac.uk", bodyClasses: [], hasUserMenu: true, exceptionTitle: "Ordinary course announcement"))
        XCTAssertEqual(QMplusConnectionPolicy.officialHTTPFailureCode(status: 500, isMainFrame: true, url: URL(string: "https://qmplus.qmul.ac.uk/auth/saml2/sp/saml2-acs.php")), "QM_HTTP_500")
        XCTAssertNil(QMplusConnectionPolicy.officialHTTPFailureCode(status: 500, isMainFrame: false, url: URL(string: "https://qmplus.qmul.ac.uk/")))
        XCTAssertNil(QMplusConnectionPolicy.officialHTTPFailureCode(status: 200, isMainFrame: true, url: URL(string: "https://qmplus.qmul.ac.uk/")))
        XCTAssertNil(QMplusConnectionPolicy.officialHTTPFailureCode(status: 500, isMainFrame: true, url: URL(string: "https://fixture.invalid/")))
    }

    func testOfficialEntryRequiresAnExactSafeSSOLinkAndAcceptsResponsiveDuplicates() throws {
        for links in [["/auth/saml2/login.php"], ["https://qmplus.qmul.ac.uk/auth/saml2/login.php"],
                      ["/auth/saml2/login.php", "/auth/saml2/login.php"]] {
            XCTAssertTrue(try officialEntry(links))
        }
        for links in [[], ["https://fixture.invalid/auth/saml2/login.php"], ["/auth/saml2/login.php?unknown=1"],
                      ["/auth/saml2/login.php#other"], ["http://qmplus.qmul.ac.uk/auth/saml2/login.php"],
                      ["https://fixture:fixture@qmplus.qmul.ac.uk/auth/saml2/login.php"]] {
            XCTAssertFalse(try officialEntry(links))
        }
    }

    private func officialEntry(_ links: [String]) throws -> Bool {
        let context = try XCTUnwrap(JSContext())
        context.setObject(links, forKeyedSubscript: "fixtureLinks" as NSString)
        context.evaluateScript("""
            var window = this; window.top = window;
            var location = { origin: 'https://qmplus.qmul.ac.uk' };
            function URL(value, base) {
                var href = value.charAt(0) === '/' ? base + value : value;
                var m = href.match(/^(https?:)\\/\\/([^/]+)([^?#]*)(\\?[^#]*)?(#.*)?$/);
                if (!m) throw new Error('fixture URL');
                var auth = m[2].split('@'); this.username = auth.length > 1 ? auth[0] : '';
                this.password = ''; this.origin = m[1] + '//' + auth[auth.length - 1];
                this.pathname = m[3]; this.search = m[4] || ''; this.hash = m[5] || '';
            }
            var document = { defaultView: window, readyState: 'complete',
                body: { id: 'page-login-index', classList: { contains: name => name === 'notloggedin' } },
                querySelector: () => null,
                querySelectorAll: selector => selector === 'a[href]' ? fixtureLinks.map(href => ({getAttribute: () => href})) : [] };
            """)
        let result = try XCTUnwrap(context.evaluateScript(QMplusConnectionPolicy.officialSSOEntryScript))
        XCTAssertNil(context.exception)
        return result.toBool()
    }

    func testExpiredReadOnlySessionGetsOneLoginRecoveryWithoutRestartingPresentation() {
        var gate = QMplusLoginSynchronizationGate()
        gate.beginQuietConnection()
        let first = gate.context
        XCTAssertFalse(gate.claimLoginRecovery(context: first))
        XCTAssertTrue(gate.claimAutomaticSync(authenticated: true, context: first))
        XCTAssertTrue(gate.claimLoginRecovery(context: first))
        XCTAssertTrue(gate.claimLoginEntry(context: first))
        gate.beginDocument()
        XCTAssertFalse(gate.accepts(first))
        XCTAssertFalse(gate.claimLoginEntry(context: gate.context))
        XCTAssertTrue(gate.claimAutomaticSync(authenticated: true, context: gate.context))
        XCTAssertFalse(gate.claimLoginRecovery(context: gate.context))
    }

    private func authenticationProof(origin: String, bodyClasses: [String], hasUserMenu: Bool,
                                     bodyID: String = "page-my-index", fatal: Bool = false, exceptionTitle: String = "") throws -> Bool {
        let context = try XCTUnwrap(JSContext())
        context.setObject(origin, forKeyedSubscript: "fixtureOrigin" as NSString)
        context.setObject(bodyClasses, forKeyedSubscript: "fixtureBodyClasses" as NSString)
        context.setObject(hasUserMenu, forKeyedSubscript: "fixtureHasUserMenu" as NSString)
        context.setObject(bodyID, forKeyedSubscript: "fixtureBodyID" as NSString)
        context.setObject(fatal, forKeyedSubscript: "fixtureFatal" as NSString)
        context.setObject(exceptionTitle, forKeyedSubscript: "fixtureTitle" as NSString)
        context.evaluateScript("""
            var window = this; window.top = window;
            var location = { origin: fixtureOrigin };
            var document = {
                defaultView: window, readyState: 'complete',
                body: { id: fixtureBodyID, classList: { contains: value => fixtureBodyClasses.indexOf(value) >= 0 } },
                querySelector: () => fixtureFatal ? {} : null,
                querySelectorAll: selector => selector === '.usermenu .userbutton'
                    ? (fixtureHasUserMenu ? [{}] : []) : (fixtureTitle ? [{textContent: fixtureTitle}] : [])
            };
            """)
        let value = try XCTUnwrap(context.evaluateScript(QMplusConnectionPolicy.authenticatedPageScript))
        XCTAssertNil(context.exception)
        XCTAssertTrue(value.isBoolean, "Native must receive only Boolean, never an account label, URL or session field")
        return value.toBool()
    }
}
