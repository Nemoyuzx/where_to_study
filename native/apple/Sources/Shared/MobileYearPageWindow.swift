import Foundation

/// A bounded, rotating year window. Keep the incoming slot through recentering
/// and preserve Feb 29 as the preferred date across non-leap years.
struct MobileYearPageWindow: Equatable, Sendable {
    struct Page: Identifiable, Equatable, Sendable {
        let yearStart: Date
        let offset: Int
        let slot: Int
        var id: Int { slot }
    }
    struct Transition: Equatable, Sendable {
        let generation: UInt64
        let sourceYear: Date
        let targetYear: Date
        let targetDate: Date
        let direction: Int
    }
    private let calendar: Calendar
    private var generation: UInt64 = 0
    private var centerSlot = 1
    private var preferredMonth: Int
    private var preferredDay: Int
    private(set) var centerYear: Date
    private(set) var selectedDate: Date
    private(set) var requestedDate: Date
    private(set) var transition: Transition?

    init(selectedDate: Date, calendar: Calendar) {
        self.calendar = calendar
        self.selectedDate = selectedDate
        requestedDate = selectedDate
        centerYear = calendar.dateInterval(of: .year, for: selectedDate)?.start ?? selectedDate
        preferredMonth = calendar.component(.month, from: selectedDate)
        preferredDay = calendar.component(.day, from: selectedDate)
    }
    var pages: [Page] {
        (-1...1).compactMap { offset in
            let slot = Self.wrap(centerSlot + offset)
            if let transition, offset == transition.direction {
                return Page(yearStart: transition.targetYear, offset: offset, slot: slot)
            }
            guard let year = calendar.date(byAdding: .year, value: offset, to: centerYear) else { return nil }
            return Page(yearStart: year, offset: offset, slot: slot)
        }
    }
    var hasPendingNavigation: Bool { requestedDate != selectedDate }

    func selectionDate(in year: Date) -> Date {
        guard let month = calendar.date(byAdding: .month, value: preferredMonth - 1, to: year),
              let range = calendar.range(of: .day, in: .month, for: month) else { return year }
        var components = calendar.dateComponents([.era, .year, .month], from: month)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: requestedDate)
        components.timeZone = calendar.timeZone
        components.day = min(preferredDay, range.count)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        return calendar.date(from: components) ?? month
    }
    @discardableResult
    mutating func request(direction: Int, animated: Bool = true) -> Transition? {
        guard direction != 0,
              let year = calendar.dateInterval(of: .year, for: requestedDate)?.start,
              let target = calendar.date(byAdding: .year, value: direction < 0 ? -1 : 1, to: year)
        else { return nil }
        requestedDate = selectionDate(in: target)
        return beginPendingNavigation(animated: animated)
    }
    @discardableResult
    mutating func request(to date: Date, animated: Bool = true) -> Transition? {
        preferredMonth = calendar.component(.month, from: date)
        preferredDay = calendar.component(.day, from: date)
        requestedDate = date
        return beginPendingNavigation(animated: animated)
    }
    @discardableResult
    mutating func beginPendingNavigation(animated: Bool = true) -> Transition? {
        if !animated { rebase(to: requestedDate, preservingYearDayAnchor: true); return nil }
        guard transition == nil,
              let target = calendar.dateInterval(of: .year, for: requestedDate)?.start else { return nil }
        guard target != centerYear else { selectedDate = requestedDate; return nil }
        generation &+= 1
        let next = Transition(generation: generation, sourceYear: centerYear, targetYear: target,
                              targetDate: requestedDate, direction: target < centerYear ? -1 : 1)
        transition = next
        selectedDate = requestedDate
        return next
    }
    @discardableResult
    mutating func settle(generation completed: UInt64) -> Bool {
        guard let transition, transition.generation == completed else { return false }
        centerYear = transition.targetYear
        centerSlot = Self.wrap(centerSlot + transition.direction)
        selectedDate = transition.targetDate
        self.transition = nil
        return true
    }
    mutating func rebase(to date: Date, preservingYearDayAnchor: Bool = false) {
        generation &+= 1
        transition = nil
        centerYear = calendar.dateInterval(of: .year, for: date)?.start ?? date
        selectedDate = date
        requestedDate = date
        if !preservingYearDayAnchor {
            preferredMonth = calendar.component(.month, from: date)
            preferredDay = calendar.component(.day, from: date)
        }
    }
    private static func wrap(_ slot: Int) -> Int { (slot % 3 + 3) % 3 }
}
