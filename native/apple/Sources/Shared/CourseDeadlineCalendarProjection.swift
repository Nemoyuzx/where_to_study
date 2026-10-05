import Foundation

// Pure projection of already loaded, validated caches. Calendar navigation never
// initiates QMplus requests, and unknown deadlines remain absent from the grid.
enum CourseDeadlineCalendarProjection {
    static func selection(for event: CalendarAllDayEvent, roster: [TeachingCloudCourse],
                          snapshot: QMplusSnapshot?, enabled: Bool) -> CourseCatalogSelection? {
        guard event.kind == .assignment else { return nil }
        if let selected = event.courseSelection {
            switch selected.source {
            case .teachingCloud:
                return roster.contains { $0.id == selected.courseID } ? selected : nil
            case .qmplus:
                let hasCourse = snapshot?.courses.contains(where: {
                    $0.id == selected.courseID && QMplusCourseSelection.includesCourse($0)
                }) == true
                return enabled && hasCourse ? selected : nil
            }
        }
        return event.assignmentItem.flatMap { teachingCloudSelection($0, roster: roster) }
    }

    static func teachingCloudSelection(_ item: AssignmentDeadlineItem,
                                      roster: [TeachingCloudCourse]) -> CourseCatalogSelection? {
        guard let id = item.courseID, roster.contains(where: { $0.id == id }) else { return nil }
        return CourseCatalogSelection(source: .teachingCloud, courseID: id)
    }

    static func qmplusEvents(on date: Date, snapshot: QMplusSnapshot?, enabled: Bool,
                             showsOtherTerms: Bool = false) -> [CalendarAllDayEvent] {
        guard enabled, let snapshot else { return [] }
        let selected = QMplusCourseSelection(snapshot: snapshot, showsOtherTerms: showsOtherTerms)
        let target = StrictContractDateParser.string(from: date)
        return selected.activities.compactMap { activity in
            let value = activity.kind == .assignment ? activity.dueAt : activity.closesAt
            guard let formatted = CourseListEvidence.qmplusShanghaiTime(value),
                  String(formatted.prefix(10)) == target else { return nil }
            return CalendarAllDayEvent(
                id: "qmplus-calendar|\(activity.id)",
                title: (activity.kind == .quiz ? "Quiz · " : "Assignment · ") + activity.title,
                time: String(formatted.suffix(5)), kind: .assignment,
                destinationURL: activity.url,
                courseSelection: CourseCatalogSelection(source: .qmplus, courseID: activity.courseID))
        }
    }

    static func applying(to days: [CalendarTimelineDay], snapshot: QMplusSnapshot?, enabled: Bool,
                         showsOtherTerms: Bool = false) -> [CalendarTimelineDay] {
        days.map { day in
            let base = day.allDayEvents.filter { !$0.id.hasPrefix("qmplus-calendar|") }
            return CalendarTimelineDay(copying: day, allDayEvents: base + qmplusEvents(on: day.date,
                snapshot: snapshot, enabled: enabled, showsOtherTerms: showsOtherTerms))
        }
    }
}
