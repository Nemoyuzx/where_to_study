import Foundation

/// A bounded set of mounted month pages. The UI prepares `pages`, animates its
/// offset using `transition`, then recenters without animation after `settle`.
struct MobileMonthPageWindow: Equatable, Sendable {
    struct Page: Identifiable, Equatable, Sendable {
        let monthStart: Date
        let offset: Int
        let slot: Int

        var id: Int { slot }
    }

    struct Transition: Equatable, Sendable {
        let generation: UInt64
        let sourceMonth: Date
        let targetMonth: Date
        let targetDate: Date
        let direction: Int
    }

    private let calendar: Calendar
    private var generation: UInt64 = 0
    private(set) var centerSlot = 1
    private(set) var centerMonth: Date
    private(set) var selectedDate: Date
    private(set) var requestedDate: Date
    private(set) var preferredDayOfMonth: Int
    private(set) var transition: Transition?

    init(selectedDate: Date, calendar: Calendar) {
        self.calendar = calendar
        self.selectedDate = selectedDate
        requestedDate = selectedDate
        centerMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start
            ?? calendar.startOfDay(for: selectedDate)
        preferredDayOfMonth = calendar.component(.day, from: selectedDate)
    }

    var pages: [Page] {
        (-1 ... 1).compactMap { offset in
            let slot = Self.wrappedSlot(centerSlot + offset)
            if let transition, offset == transition.direction {
                // A distant date selection uses the incoming slot, rather than
                // inserting a fourth page or dropping the horizontal animation.
                return Page(monthStart: transition.targetMonth, offset: offset, slot: slot)
            }
            guard let month = calendar.date(byAdding: .month, value: offset, to: centerMonth) else {
                return nil
            }
            return Page(monthStart: month, offset: offset, slot: slot)
        }
    }

    var hasPendingNavigation: Bool { requestedDate != selectedDate }

    /// Relative requests accumulate from the latest requested date, including
    /// requests arriving while the current transition is still on screen.
    @discardableResult
    mutating func request(direction: Int, animated: Bool = true) -> Transition? {
        guard direction != 0,
              let target = anchoredMonthDate(
                  from: requestedDate,
                  direction: direction < 0 ? -1 : 1
              )
        else { return nil }
        requestedDate = target
        return beginPendingNavigation(animated: animated)
    }

    /// An explicit day selection establishes a new preferred day for subsequent
    /// relative paging. Month-end clamping never changes that preferred day.
    @discardableResult
    mutating func request(to date: Date, animated: Bool = true) -> Transition? {
        preferredDayOfMonth = calendar.component(.day, from: date)
        requestedDate = date
        return beginPendingNavigation(animated: animated)
    }

    /// Call after the unanimated recenter has been rendered. Queued requests are
    /// coalesced into the latest target; an active transition keeps its pages.
    @discardableResult
    mutating func beginPendingNavigation(animated: Bool = true) -> Transition? {
        if !animated {
            rebase(to: requestedDate, preservingMonthDayAnchor: true)
            return nil
        }
        guard transition == nil else { return nil }
        let targetMonth = monthStart(containing: requestedDate)
        guard targetMonth != centerMonth else {
            selectedDate = requestedDate
            return nil
        }

        generation &+= 1
        let next = Transition(
            generation: generation,
            sourceMonth: centerMonth,
            targetMonth: targetMonth,
            targetDate: requestedDate,
            direction: targetMonth < centerMonth ? -1 : 1
        )
        transition = next
        selectedDate = next.targetDate
        return next
    }

    /// Completion of an old/cancelled transition must not move a newer window.
    /// Starting a queued transition is deliberately a separate UI update.
    @discardableResult
    mutating func settle(generation completedGeneration: UInt64) -> Bool {
        guard let transition, transition.generation == completedGeneration else { return false }
        // The incoming page keeps its mounted slot. For adjacent moves, only
        // the page that left the window receives a new month.
        centerSlot = Self.wrappedSlot(centerSlot + transition.direction)
        centerMonth = transition.targetMonth
        selectedDate = transition.targetDate
        self.transition = nil
        return true
    }

    /// Cancel outstanding completions and immediately center the supplied day.
    /// Preserve the anchor when ending motion; reset it for a new day selection.
    mutating func rebase(to date: Date, preservingMonthDayAnchor: Bool = false) {
        generation &+= 1
        transition = nil
        centerMonth = monthStart(containing: date)
        selectedDate = date
        requestedDate = date
        if !preservingMonthDayAnchor {
            preferredDayOfMonth = calendar.component(.day, from: date)
        }
    }

    private func monthStart(containing date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private static func wrappedSlot(_ value: Int) -> Int {
        (value % 3 + 3) % 3
    }

    private func anchoredMonthDate(from date: Date, direction: Int) -> Date? {
        guard let month = calendar.date(byAdding: .month, value: direction, to: monthStart(containing: date)),
              let validDays = calendar.range(of: .day, in: .month, for: month)
        else { return nil }
        var components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let destination = calendar.dateComponents([.era, .year, .month], from: month)
        components.timeZone = calendar.timeZone
        components.era = destination.era
        components.year = destination.year
        components.month = destination.month
        components.day = min(max(preferredDayOfMonth, validDays.lowerBound), validDays.upperBound - 1)
        return calendar.date(from: components)
    }
}
