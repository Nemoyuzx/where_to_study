import Foundation

// A deadline is a point, not a class interval. Keep its source event so taps
// reuse the course-detail route without creating another data request.
struct CalendarDeadlineMoment: Identifiable, Equatable, Sendable {
    let minute: Int
    let events: [CalendarAllDayEvent]
    let anchorMinutes: [Int]
    init(minute: Int, events: [CalendarAllDayEvent], anchorMinutes: [Int]? = nil) {
        self.minute = minute
        self.events = events
        self.anchorMinutes = anchorMinutes ?? [minute]
    }
    var id: Int { minute }
    var time: String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    var hasPendingSubmission: Bool { events.contains { $0.hasPendingSubmission } }
}

enum CalendarDeadlineMomentLogic {
    static func displayMoments(_ moments: [CalendarDeadlineMoment], hourHeight: CGFloat) -> [CalendarDeadlineMoment] {
        var result = [CalendarDeadlineMoment]()
        for moment in moments {
            if let previous = result.last,
               // Reserve the 18pt label plus the 9pt edge correction; nearby
               // points share a badge, but keep all their actual-time lines.
               CGFloat(moment.minute - (previous.anchorMinutes.last ?? previous.minute)) / 60 * hourHeight < 28 {
                result[result.count - 1] = .init(minute: previous.minute, events: previous.events + moment.events,
                    anchorMinutes: previous.anchorMinutes + moment.anchorMinutes)
            } else { result.append(moment) }
        }
        return result
    }

    static func markerWidth(dayWidth: CGFloat) -> CGFloat { max(dayWidth - 8, 1) }

    static func moments(on date: Date, events: [CalendarAllDayEvent]) -> [CalendarDeadlineMoment] {
        var grouped = [Int: [CalendarAllDayEvent]]()
        var seen = Set<String>()
        var seenCloud = Set<TeachingCloudAssignmentDisplayID>()
        for event in events where event.kind == .assignment {
            guard let minute = minute(of: event, on: date) else { continue }
            if let item = event.assignmentItem {
                guard seenCloud.insert(item.teachingCloudDisplayID).inserted else { continue }
            } else { guard seen.insert(event.id).inserted else { continue } }
            grouped[minute, default: []].append(event)
        }
        return grouped.keys.sorted().map { CalendarDeadlineMoment(minute: $0, events: grouped[$0] ?? []) }
    }

    static func minute(of event: CalendarAllDayEvent, on date: Date) -> Int? {
        if let item = event.assignmentItem {
            guard let deadline = explicitDate(item.deadline), Calendar.shanghai.isDate(deadline, inSameDayAs: date) else { return nil }
            let components = Calendar.shanghai.dateComponents([.hour, .minute], from: deadline)
            return (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
        // QMplus events have already been projected from dueAt / closesAt into
        // their Shanghai day. Never infer a time from an untyped title/date.
        guard event.courseSelection?.source == .qmplus, let time = event.time,
              time.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return CalendarTimelineLogic.minute(of: time)
    }

    static func explicitDate(_ value: String) -> Date? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.range(of: #"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})?$"#,
                        options: .regularExpression) != nil,
              let day = StrictContractDateParser.date(from: String(raw.prefix(10))) else { return nil }
        let time = String(raw.dropFirst(11).prefix(5))
        guard let minute = CalendarTimelineLogic.minute(of: time) else { return nil }
        let bytes = Array(raw.utf8)
        if bytes.count > 16, bytes[16] == 58 {
            guard let second = Int(String(raw.dropFirst(17).prefix(2))), (0 ... 59).contains(second) else { return nil }
        }
        if raw.hasSuffix("Z") || raw.dropFirst(16).contains("+") || raw.dropFirst(16).contains("-") {
            // QMplus's snapshot validator deliberately accepts UTC-Z only;
            // cloud timestamps can also carry an explicit numeric offset.
            var timestamp = raw.replacingOccurrences(of: " ", with: "T")
            if bytes[16] != 58 {
                timestamp.insert(contentsOf: ":00", at: timestamp.index(timestamp.startIndex, offsetBy: 16))
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: timestamp) { return parsed }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: timestamp)
        }
        return Calendar.shanghai.date(byAdding: .minute, value: minute, to: day)
    }

    // Only move the small label to protect class titles / viewport edges; the
    // horizontal anchor remains at the actual deadline minute.
    static func badgeCenter(anchor: CGFloat, lower: CGFloat, upper: CGFloat,
                            courseTitleStarts: [CGFloat], previous: CGFloat? = nil) -> CGFloat {
        let half: CGFloat = 9
        var center = max(lower + half, min(anchor, upper - half))
        for start in courseTitleStarts where center + half > start && center - half < start + 32 {
            center = start + 32 + half
        }
        if let previous { center = max(center, previous + 20) }
        return max(lower + half, min(center, upper - half))
    }
}

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
                courseSelection: CourseCatalogSelection(source: .qmplus, courseID: activity.courseID),
                pendingSubmission: CourseListEvidence.submissionCounts(statuses: [activity.status]).pending > 0)
        }
    }

    static func applying(to days: [CalendarTimelineDay], snapshot: QMplusSnapshot?, enabled: Bool,
                         showsOtherTerms: Bool = false, assignments: [AssignmentDeadlineItem]? = nil) -> [CalendarTimelineDay] {
        // The old all-day cache groups raw date prefixes. Read the same owner's
        // account-wide cache for the added time layer, so UTC/offset deadlines
        // still land in their correct Shanghai day without changing that area.
        var timedCloud = [String: [CalendarAllDayEvent]]()
        for item in assignments ?? [] {
            guard let deadline = CalendarDeadlineMomentLogic.explicitDate(item.deadline) else { continue }
            let key = StrictContractDateParser.string(from: deadline)
            timedCloud[key, default: []].append(CalendarAllDayEvent(
                id: "\(key)-assignment-\(item.id)", title: item.title, kind: .assignment, assignmentItem: item))
        }
        return days.map { day in
            let base = day.allDayEvents.filter { !$0.id.hasPrefix("qmplus-calendar|") }
            let events = base + qmplusEvents(on: day.date, snapshot: snapshot, enabled: enabled, showsOtherTerms: showsOtherTerms)
            let points = CalendarDeadlineMomentLogic.moments(on: day.date,
                events: events + (timedCloud[StrictContractDateParser.string(from: day.date)] ?? []))
            return CalendarTimelineDay(copying: day, allDayEvents: events, deadlineMoments: points)
        }
    }
}
