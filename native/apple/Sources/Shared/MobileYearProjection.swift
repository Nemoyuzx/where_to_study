import Foundation

/// Only the values rendered by a miniature year-calendar day. Full courses,
/// deadline items and agenda event presentations stay out of the mounted grid.
struct MobileYearDayProjection: Identifiable, Equatable, Sendable {
    let date: Date
    let dateKey: String
    let dayNumberText: String
    let accessibilityLabel: String
    let courseCount: Int
    let deadlineKinds: [CalendarAllDayEventKind]

    var id: Date { date }
}

struct MobileYearMonthProjection: Identifiable, Equatable, Sendable {
    let monthStart: Date
    let monthKey: String
    let monthTitle: String
    /// Monday is column zero. Adjacent-month placeholders contain no day data.
    let leadingBlankCount: Int
    let days: [MobileYearDayProjection]

    var id: Date { monthStart }
    var trailingBlankCount: Int { 42 - leadingBlankCount - days.count }
}

actor MobileYearProjectionWorker {
    /// The caller captures one complete year's real dates and source values on
    /// the UI actor, using the same input contract as the month projection.
    /// A year is projected once (365/366 days), rather than twelve 42-day grids.
    func build(input: MobileMonthProjectionInput) async throws -> [MobileYearMonthProjection] {
        try Task.checkCancellation()
        let calendar = Calendar.shanghai
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = input.language.locale
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateFormat = input.language.resolvedResourceName == "en"
            ? "EEEE, MMMM d, yyyy"
            : "yyyy年M月d日 EEEE"
        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.locale = input.language.locale
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.dateFormat = input.language.resolvedResourceName == "en" ? "MMM" : "M月"
        let todayKey = StrictContractDateParser.string(from: input.today, calendar: calendar)
        let todayLabel = AppLocalization.string("今天", language: input.language)
        let coursesByDate: [String: [Course]]
        if let schedule = input.schedule,
           let termStart = StrictContractDateParser.date(from: schedule.termStartDate) {
            coursesByDate = ScheduleLogic.coursesByDate(
                for: input.days, termStart: termStart, courses: schedule.courses, calendar: calendar
            )
        } else {
            coursesByDate = [:]
        }
        let holidaysByDate = Dictionary(grouping: input.holidays, by: \.date)
        let favoritesByDate = Dictionary(grouping: input.favorites) { String($0.deadline.prefix(10)) }
        let datesByMonth = Dictionary(grouping: input.days) {
            calendar.dateInterval(of: .month, for: $0)?.start ?? calendar.startOfDay(for: $0)
        }
        var months = [MobileYearMonthProjection]()
        months.reserveCapacity(datesByMonth.count)

        for month in datesByMonth.keys.sorted() {
            try Task.checkCancellation()
            var projectedDays = [MobileYearDayProjection]()
            let dates = (datesByMonth[month] ?? []).sorted()
            projectedDays.reserveCapacity(dates.count)
            for date in dates {
                try Task.checkCancellation()
                let dateKey = StrictContractDateParser.string(from: date, calendar: calendar)
                let courses = coursesByDate[dateKey] ?? []
                let holidays = holidaysByDate[dateKey] ?? []
                var kinds = Self.visibleDeadlineKinds(
                    dateKey: dateKey, input: input, favorites: favoritesByDate[dateKey] ?? []
                )
                if !(input.assignmentsByDate[dateKey] ?? []).isEmpty {
                    kinds.append(.assignment)
                }
                projectedDays.append(MobileYearDayProjection(
                    date: date,
                    dateKey: dateKey,
                    dayNumberText: String(calendar.component(.day, from: date)),
                    accessibilityLabel: TeachingCalendarLogic.dayAccessibilityLabel(
                        todayText: dateKey == todayKey ? todayLabel : "",
                        formattedDate: dateFormatter.string(from: date),
                        holidayNames: holidays.map(\.name),
                        courseDescriptions: courses.map { "\($0.timeRange)\($0.name)" }
                    ),
                    courseCount: courses.count,
                    deadlineKinds: CalendarDeadlinePresentation.topTwoDeadlineKinds(in: kinds)
                ))
            }
            months.append(MobileYearMonthProjection(
                monthStart: month,
                monthKey: String(StrictContractDateParser.string(from: month, calendar: calendar).prefix(7)),
                monthTitle: monthFormatter.string(from: month),
                leadingBlankCount: (calendar.component(.weekday, from: month) + 5) % 7,
                days: projectedDays
            ))
        }
        try Task.checkCancellation()
        return months
    }

    private static func visibleDeadlineKinds(
        dateKey: String,
        input: MobileMonthProjectionInput,
        favorites: [PublicDeadlineItem]
    ) -> [CalendarAllDayEventKind] {
        // Preserve the existing merge/deduplication and 100-live-item cap before
        // source visibility is applied. Favorites are then restored, and the
        // first visible item for each favoriteID retains its current kind.
        let liveItems = PublicDeadlineClient.merge([
            input.publicByDate[dateKey]?.items ?? [],
            input.customByDate[dateKey]?.items ?? []
        ])
        var seen = Set<String>()
        return (liveItems.filter(input.visibility.includes) + favorites)
            .filter { seen.insert($0.favoriteID).inserted }
            .map(CalendarDeadlinePresentation.eventKind)
    }
}
