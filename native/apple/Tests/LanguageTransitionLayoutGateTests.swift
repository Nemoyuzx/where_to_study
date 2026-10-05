import XCTest
#if os(iOS)
@testable import WhereToStudyiOS
#else
@testable import WhereToStudyMac
#endif

// Added as regression specifications only. Not executed in this change:
// the user has prohibited automated tests on this machine.
final class LanguageTransitionLayoutGateTests: XCTestCase {
    func testCompletionRequiresAllTasksLocaleAndThreeValidStableSamples() {
        var gate = LanguageTransitionLayoutGate()
        let frame = [390.0, 844.0, 16.0, 320.0, 358.0, 140.0]
        for _ in 0..<6 { XCTAssertFalse(gate.observe(tasksComplete: false, localeMatches: true, geometry: frame)) }
        XCTAssertFalse(gate.observe(tasksComplete: true, localeMatches: false, geometry: frame))
        XCTAssertFalse(gate.observe(tasksComplete: true, localeMatches: true, geometry: frame))
        XCTAssertFalse(gate.observe(tasksComplete: true, localeMatches: true, geometry: frame))
        XCTAssertTrue(gate.observe(tasksComplete: true, localeMatches: true, geometry: frame))
        gate.reset()
        XCTAssertEqual(gate.stableSamples, 0)
    }
    func testInvalidGeometryAndLateScrollMovementResetTheCompletionBarrier() {
        var gate = LanguageTransitionLayoutGate()
        XCTAssertFalse(gate.observe(tasksComplete: true, localeMatches: true, geometry: [1, 2]))
        XCTAssertFalse(gate.observe(tasksComplete: true, localeMatches: true, geometry: [1, 2]))
        XCTAssertFalse(gate.observe(tasksComplete: true, localeMatches: true, geometry: [1, 20]))
        XCTAssertFalse(gate.observe(tasksComplete: true, localeMatches: true, geometry: []))
        XCTAssertFalse(gate.observe(tasksComplete: true, localeMatches: true, geometry: [.nan, 2]))
        XCTAssertEqual(gate.stableSamples, 0)
    }
}
