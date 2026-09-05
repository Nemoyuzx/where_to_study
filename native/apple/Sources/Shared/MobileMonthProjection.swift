import Foundation

struct MobileMonthSourceVisibility: Equatable, Sendable {
    let competitionEnabled: Bool
    let schoolNoticeEnabled: Bool
    let conferenceEnabled: Bool
    let summerCampEnabled: Bool
    let hackathonEnabled: Bool
    let customEnabled: Bool

    func includes(_ item: PublicDeadlineItem) -> Bool {
        CalendarDeadlinePresentation.isVisible(
            item,
            competitionEnabled: competitionEnabled,
            schoolNoticeEnabled: schoolNoticeEnabled,
            conferenceEnabled: conferenceEnabled,
            summerCampEnabled: summerCampEnabled,
            hackathonEnabled: hackathonEnabled,
            customEnabled: customEnabled
        )
    }
}

/// Capture these values on the UI actor. The worker never reads a model, store,
/// view, or a DateFormatter shared with the UI while building the projection.
struct MobileMonthProjectionInput: Sendable {
    let days: [Date]
    let schedule: ScheduleSnapshot?
    let holidays: [HolidayItem]
    let favorites: [PublicDeadlineItem]
    let publicByDate: [String: PublicDeadlineSnapshot]
    let customByDate: [String: PublicDeadlineSnapshot]
    let assignmentsByDate: [String: [AssignmentDeadlineItem]]
    let visibility: MobileMonthSourceVisibility
    let language: AppLanguage
    let today: Date
}

struct MobileMonthEventProjection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let categoryKey: String
    /// Courses use the normal course tint; other events use their deadline kind.
    let kind: CalendarAllDayEventKind?
    let deadlineItem: PublicDeadlineItem?
}

struct MobileMonthDayProjection: Identifiable, Equatable, Sendable {
    let date: Date
    let dateKey: String
    let dayNumberText: String
    let accessibilityLabel: String
    let courses: [Course]
    let holidays: [HolidayItem]
    let assignments: [AssignmentDeadlineItem]
    let publicItems: [PublicDeadlineItem]
    let events: [MobileMonthEventProjection]
    let allDayEvents: [CalendarAllDayEvent]
    let deadlineKinds: [CalendarAllDayEventKind]

    var id: Date { date }
    var holiday: HolidayItem? { holidays.first }
}

actor MobileMonthProjectionWorker {
    func build(input: MobileMonthProjectionInput) async throws -> [MobileMonthDayProjection] {
        try Task.checkCancellation()
        let calendar = Calendar.shanghai
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = input.language.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = input.language.resolvedResourceName == "en"
            ? "EEEE, MMMM d, yyyy"
            : "yyyy年M月d日 EEEE"
        let todayKey = StrictContractDateParser.string(from: input.today, calendar: calendar)
        let todayLabel = AppLocalization.string("今天", language: input.language)
        let holidayLabel = AppLocalization.string("休", language: input.language)
        let workdayLabel = AppLocalization.string("班", language: input.language)
        let coursesByDate = Self.coursesByDate(input: input, calendar: calendar)
        let holidaysByDate = Dictionary(grouping: input.holidays, by: \.date)
        let favoritesByDate = Dictionary(grouping: input.favorites) { String($0.deadline.prefix(10)) }
        var result = [MobileMonthDayProjection]()
        result.reserveCapacity(input.days.count)

        for date in input.days {
            try Task.checkCancellation()
            let dateKey = StrictContractDateParser.string(from: date, calendar: calendar)
            let courses = coursesByDate[dateKey] ?? []
            let holidays = holidaysByDate[dateKey] ?? []
            let assignments = input.assignmentsByDate[dateKey] ?? []
            let publicItems = Self.visibleItems(
                dateKey: dateKey,
                input: input,
                favorites: favoritesByDate[dateKey] ?? []
            )
            let schoolNotices = publicItems.filter { $0.source == .schoolNotice }
            let publicDeadlines = publicItems.filter { $0.source != .schoolNotice }
            let allDayEvents = Self.allDayEvents(
                dateKey: dateKey,
                holidays: holidays,
                assignments: assignments,
                schoolNotices: schoolNotices,
                publicDeadlines: publicDeadlines,
                holidayLabel: holidayLabel,
                workdayLabel: workdayLabel
            )
            let events = Self.monthEvents(
                dateKey: dateKey,
                holidays: holidays,
                assignments: assignments,
                schoolNotices: schoolNotices,
                publicDeadlines: publicDeadlines,
                courses: courses,
                holidayLabel: holidayLabel,
                workdayLabel: workdayLabel
            )
            result.append(MobileMonthDayProjection(
                date: date,
                dateKey: dateKey,
                dayNumberText: String(calendar.component(.day, from: date)),
                accessibilityLabel: TeachingCalendarLogic.dayAccessibilityLabel(
                    todayText: dateKey == todayKey ? todayLabel : "",
                    formattedDate: formatter.string(from: date),
                    holidayNames: holidays.map(\.name),
                    courseDescriptions: courses.map { "\($0.timeRange)\($0.name)" }
                ),
                courses: courses,
                holidays: holidays,
                assignments: assignments,
                publicItems: publicItems,
                events: events,
                allDayEvents: allDayEvents,
                deadlineKinds: CalendarDeadlinePresentation.topTwoDeadlineKinds(in: allDayEvents)
            ))
        }
        try Task.checkCancellation()
        return result
    }

    private static func coursesByDate(
        input: MobileMonthProjectionInput,
        calendar: Calendar
    ) -> [String: [Course]] {
        guard let schedule = input.schedule,
              let termStart = StrictContractDateParser.date(from: schedule.termStartDate)
        else { return [:] }
        return ScheduleLogic.coursesByDate(
            for: input.days, termStart: termStart, courses: schedule.courses, calendar: calendar
        )
    }

    private static func visibleItems(
        dateKey: String,
        input: MobileMonthProjectionInput,
        favorites: [PublicDeadlineItem]
    ) -> [PublicDeadlineItem] {
        // Keep the existing two-stage contract: public/custom merge applies its
        // source/name/date deduplication and 100-item cap before visibility;
        // favorites are then restored regardless of the source switches.
        let liveItems = PublicDeadlineClient.merge([
            input.publicByDate[dateKey]?.items ?? [],
            input.customByDate[dateKey]?.items ?? []
        ])
        var seen = Set<String>()
        return (liveItems.filter(input.visibility.includes) + favorites)
            .filter { seen.insert($0.favoriteID).inserted }
            .sorted { ($0.deadline, $0.name) < ($1.deadline, $1.name) }
    }

    private static func allDayEvents(
        dateKey: String,
        holidays: [HolidayItem],
        assignments: [AssignmentDeadlineItem],
        schoolNotices: [PublicDeadlineItem],
        publicDeadlines: [PublicDeadlineItem],
        holidayLabel: String,
        workdayLabel: String
    ) -> [CalendarAllDayEvent] {
        let holidayEvents = holidays.map { item in
            CalendarAllDayEvent(
                id: "\(dateKey)-holiday-\(item.id)",
                title: "\(item.type == "holiday" ? holidayLabel : workdayLabel) \(item.name)",
                kind: item.type == "holiday" ? .holiday : .workday
            )
        }
        let assignmentEvents = assignments.map { item in
            CalendarAllDayEvent(
                id: "\(dateKey)-assignment-\(item.id)", title: item.title,
                time: deadlineTime(item.deadline), kind: .assignment,
                destinationURL: CalendarDeadlineSources.assignments
            )
        }
        let schoolEvents = schoolNotices.map { item in
            CalendarAllDayEvent(
                id: "\(dateKey)-school-\(item.id)", title: item.name,
                time: deadlineTime(item.deadline), kind: .schoolNotice,
                deadlineItem: item
            )
        }
        let publicEvents = publicDeadlines.map { item in
            CalendarAllDayEvent(
                id: "\(dateKey)-public-\(item.id)", title: item.name,
                time: deadlineTime(item.deadline),
                kind: CalendarDeadlinePresentation.eventKind(for: item), deadlineItem: item
            )
        }
        return holidayEvents + assignmentEvents + schoolEvents + publicEvents
    }

    private static func monthEvents(
        dateKey: String,
        holidays: [HolidayItem],
        assignments: [AssignmentDeadlineItem],
        schoolNotices: [PublicDeadlineItem],
        publicDeadlines: [PublicDeadlineItem],
        courses: [Course],
        holidayLabel: String,
        workdayLabel: String
    ) -> [MobileMonthEventProjection] {
        let holidayEvents = holidays.map { item in
            MobileMonthEventProjection(
                id: "holiday-\(item.id)",
                title: "\(item.type == "holiday" ? holidayLabel : workdayLabel) \(item.name)",
                categoryKey: item.type == "holiday" ? "法定节假日" : "调休工作日",
                kind: item.type == "holiday" ? .holiday : .workday, deadlineItem: nil
            )
        }
        let assignmentEvents = assignments.map { item in
            MobileMonthEventProjection(
                id: "\(dateKey)-assignment-\(item.id)", title: item.title,
                categoryKey: "课程作业 DDL", kind: .assignment, deadlineItem: nil
            )
        }
        let schoolEvents = schoolNotices.map { item in
            MobileMonthEventProjection(
                id: "\(dateKey)-school-\(item.id)", title: item.name,
                categoryKey: "校内竞赛通知", kind: .schoolNotice, deadlineItem: item
            )
        }
        let publicEvents = publicDeadlines.map { item in
            MobileMonthEventProjection(
                id: "\(dateKey)-public-\(item.id)", title: item.name,
                categoryKey: item.kind.title,
                kind: CalendarDeadlinePresentation.eventKind(for: item), deadlineItem: item
            )
        }
        let courseEvents = courses.map { course in
            MobileMonthEventProjection(
                id: "course-\(course.id)", title: course.name,
                categoryKey: "课程详情", kind: nil, deadlineItem: nil
            )
        }
        return holidayEvents + assignmentEvents + schoolEvents + publicEvents + courseEvents
    }

    private static func deadlineTime(_ value: String) -> String {
        guard value.count >= 16 else { return value }
        let start = value.index(value.startIndex, offsetBy: 11)
        return String(value[start...].prefix(5))
    }
}
