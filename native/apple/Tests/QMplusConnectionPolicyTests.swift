import XCTest
import JavaScriptCore
#if os(macOS)
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class QMplusConnectionPolicyTests: XCTestCase {
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
        for field in ["document.cookie", "sesskey", "M.cfg", "localStorage", "sessionStorage", "textContent", "innerHTML", "location.search"] {
            XCTAssertFalse(QMplusConnectionPolicy.authenticatedPageScript.contains(field))
        }
    }

    private func authenticationProof(origin: String, bodyClasses: [String], hasUserMenu: Bool) throws -> Bool {
        let context = try XCTUnwrap(JSContext())
        context.setObject(origin, forKeyedSubscript: "fixtureOrigin" as NSString)
        context.setObject(bodyClasses, forKeyedSubscript: "fixtureBodyClasses" as NSString)
        context.setObject(hasUserMenu, forKeyedSubscript: "fixtureHasUserMenu" as NSString)
        context.evaluateScript("""
            var location = { origin: fixtureOrigin };
            var document = {
                body: { classList: { contains: value => fixtureBodyClasses.indexOf(value) >= 0 } },
                querySelector: selector => selector === '.usermenu .userbutton' && fixtureHasUserMenu ? {} : null
            };
            """)
        let value = try XCTUnwrap(context.evaluateScript(QMplusConnectionPolicy.authenticatedPageScript))
        XCTAssertNil(context.exception)
        XCTAssertTrue(value.isBoolean, "Native must receive only Boolean, never an account label, URL or session field")
        return value.toBool()
    }
}
