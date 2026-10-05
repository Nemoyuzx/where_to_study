import Foundation

/// Completion is a task/locale/layout barrier, never a fixed-delay success.
struct LanguageTransitionLayoutGate {
    private(set) var stableSamples = 0
    private var previous: [Double]?

    mutating func observe(tasksComplete: Bool, localeMatches: Bool, geometry: [Double]) -> Bool {
        guard tasksComplete, localeMatches, !geometry.isEmpty,
              geometry.allSatisfy(\.isFinite) else { reset(); return false }
        if let previous, previous.count == geometry.count,
           zip(previous, geometry).allSatisfy({ abs($0 - $1) <= 0.5 }) {
            stableSamples += 1
        } else { stableSamples = 1 }
        previous = geometry
        return stableSamples >= 3
    }

    mutating func reset() { previous = nil; stableSamples = 0 }
}
