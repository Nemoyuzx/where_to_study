import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

@MainActor
final class PrivacyConsentTests: XCTestCase {
    func testConsentMustBeAcceptedAndPersistsForCurrentPolicyVersion() {
        let suiteName = "PrivacyConsentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = PrivacyConsentState(defaults: defaults)
        XCTAssertFalse(state.hasAccepted)

        state.decline()
        XCTAssertTrue(state.hasDeclined)
        XCTAssertFalse(state.hasAccepted)

        state.reconsider()
        XCTAssertFalse(state.hasDeclined)

        state.accept()
        XCTAssertTrue(state.hasAccepted)
        XCTAssertEqual(
            defaults.integer(forKey: PrivacyConsentState.storageKey),
            PrivacyConsentState.currentVersion
        )

        let restored = PrivacyConsentState(defaults: defaults)
        XCTAssertTrue(restored.hasAccepted)
    }

    func testUITestBypassDoesNotPersistConsent() {
        let suiteName = "PrivacyConsentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = PrivacyConsentState(defaults: defaults, bypassesConsent: true)
        XCTAssertTrue(state.hasAccepted)
        XCTAssertNil(defaults.object(forKey: PrivacyConsentState.storageKey))
    }
}
