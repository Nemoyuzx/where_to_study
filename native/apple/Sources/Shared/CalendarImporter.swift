import EventKit
import Foundation

struct CalendarEventDraft: Equatable, Sendable {
    let marker: String
    let title: String
    let location: String
    let notes: String
    let startDate: Date
    let endDate: Date
}

struct CalendarImportResult: Equatable, Sendable {
    let inserted: Int
    let updated: Int
    let unchanged: Int

    var total: Int { inserted + updated + unchanged }
}

enum CalendarImportError: LocalizedError, Equatable {
    case noSchedule
    case invalidTermStartDate
    case invalidCourse(String)
    case permissionDenied
    case noWritableCalendar

    var errorDescription: String? {
        switch self {
        case .noSchedule:
            "请先获取/刷新个人课表。"
        case .invalidTermStartDate:
            "第一周周一日期格式不正确。"
        case let .invalidCourse(name):
            "课程“\(name)”的日期或节次信息不正确。"
        case .permissionDenied:
            "没有日历完整访问权限，请在系统设置中允许后重试。"
        case .noWritableCalendar:
            "系统中没有可写入的默认日历。"
        }
    }
}

enum CalendarImportLogic {
    static let markerPrefix = "where-to-study:event:"

    static func eventDrafts(
        from schedule: ScheduleSnapshot,
        slots: [SlotMetadata] = SlotMetadata.defaults,
        calendar: Calendar = .shanghai
    ) throws -> [CalendarEventDraft] {
        guard let termStart = contractDate(schedule.termStartDate, calendar: calendar) else {
            throw CalendarImportError.invalidTermStartDate
        }

        var drafts = [CalendarEventDraft]()
        var markers = Set<String>()
        for course in schedule.courses {
            guard
                (1 ... 7).contains(course.weekday),
                slots.indices.contains(course.startSlot),
                slots.indices.contains(course.endSlot),
                course.startSlot <= course.endSlot
            else {
                throw CalendarImportError.invalidCourse(course.name)
            }

            let startTime = slots[course.startSlot].start
            let endTime = slots[course.endSlot].end
            for week in Set(course.weekNumbers).filter({ $0 > 0 }).sorted() {
                let dayOffset = (week - 1) * 7 + (course.weekday - 1)
                guard
                    let day = calendar.date(byAdding: .day, value: dayOffset, to: termStart),
                    let startDate = date(on: day, time: startTime, calendar: calendar),
                    let endDate = date(on: day, time: endTime, calendar: calendar),
                    endDate > startDate
                else {
                    throw CalendarImportError.invalidCourse(course.name)
                }

                let marker = eventMarker(termID: schedule.termID, courseID: course.id, week: week)
                guard markers.insert(marker).inserted else { continue }
                let title = course.examWeekNumbers.contains(week) ? "试 \(course.name)" : course.name
                let detailLines = [
                    course.teacher.isEmpty ? nil : "教师：\(course.teacher)",
                    course.sectionText.isEmpty ? nil : "节次：\(course.sectionText)",
                    "由 Where To Study 导入",
                    marker,
                ].compactMap { $0 }
                drafts.append(CalendarEventDraft(
                    marker: marker,
                    title: title,
                    location: course.room,
                    notes: detailLines.joined(separator: "\n"),
                    startDate: startDate,
                    endDate: endDate
                ))
            }
        }

        return drafts.sorted {
            if $0.startDate == $1.startDate { return $0.marker < $1.marker }
            return $0.startDate < $1.startDate
        }
    }

    static func eventMarker(termID: String, courseID: String, week: Int) -> String {
        let identity = "\(termID)\u{0}\(courseID)\u{0}\(week)"
        return markerPrefix + Data(identity.utf8).base64EncodedString()
    }

    static func marker(in notes: String?) -> String? {
        notes?
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .first { $0.hasPrefix(markerPrefix) }
    }

    private static func contractDate(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func date(on day: Date, time: String, calendar: Calendar) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0 ... 23).contains(parts[0]), (0 ... 59).contains(parts[1]) else {
            return nil
        }
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: dayParts.year,
            month: dayParts.month,
            day: dayParts.day,
            hour: parts[0],
            minute: parts[1]
        ))
    }
}

@MainActor
protocol CalendarImporting {
    func importSchedule(_ schedule: ScheduleSnapshot) async throws -> CalendarImportResult
}

@MainActor
final class EventKitCalendarImporter: CalendarImporting {
    func importSchedule(_ schedule: ScheduleSnapshot) async throws -> CalendarImportResult {
        let drafts = try CalendarImportLogic.eventDrafts(from: schedule)
        guard !drafts.isEmpty else { return CalendarImportResult(inserted: 0, updated: 0, unchanged: 0) }
        guard try await requestAccess() else { throw CalendarImportError.permissionDenied }

        return try await Task.detached(priority: .userInitiated) {
            try Self.write(drafts)
        }.value
    }

    private func requestAccess() async throws -> Bool {
        let store = EKEventStore()
        if #available(macOS 14.0, iOS 17.0, *) {
            return try await store.requestFullAccessToEvents()
        }
        return try await Self.requestLegacyAccess(store)
    }

    @available(macOS, introduced: 10.9, obsoleted: 14.0)
    @available(iOS, introduced: 6.0, obsoleted: 17.0)
    private static func requestLegacyAccess(_ store: EKEventStore) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    nonisolated private static func write(_ drafts: [CalendarEventDraft]) throws -> CalendarImportResult {
        let store = EKEventStore()
        guard let destination = store.defaultCalendarForNewEvents else {
            throw CalendarImportError.noWritableCalendar
        }
        guard let first = drafts.first, let last = drafts.last else {
            return CalendarImportResult(inserted: 0, updated: 0, unchanged: 0)
        }

        let searchStart = first.startDate.addingTimeInterval(-86_400)
        let searchEnd = last.endDate.addingTimeInterval(86_400)
        let predicate = store.predicateForEvents(withStart: searchStart, end: searchEnd, calendars: nil)
        let existingByMarker = Dictionary(
            store.events(matching: predicate).compactMap { event in
                CalendarImportLogic.marker(in: event.notes).map { ($0, event) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        var inserted = 0
        var updated = 0
        var unchanged = 0
        for draft in drafts {
            if let event = existingByMarker[draft.marker] {
                if apply(draft, to: event, calendar: destination) {
                    try store.save(event, span: .thisEvent, commit: false)
                    updated += 1
                } else {
                    unchanged += 1
                }
            } else {
                let event = EKEvent(eventStore: store)
                _ = apply(draft, to: event, calendar: destination)
                try store.save(event, span: .thisEvent, commit: false)
                inserted += 1
            }
        }
        if inserted > 0 || updated > 0 { try store.commit() }
        return CalendarImportResult(inserted: inserted, updated: updated, unchanged: unchanged)
    }

    nonisolated private static func apply(
        _ draft: CalendarEventDraft,
        to event: EKEvent,
        calendar: EKCalendar
    ) -> Bool {
        let needsUpdate = event.title != draft.title
            || event.location != draft.location
            || event.notes != draft.notes
            || event.startDate != draft.startDate
            || event.endDate != draft.endDate
            || event.calendar.calendarIdentifier != calendar.calendarIdentifier

        guard needsUpdate else { return false }
        event.calendar = calendar
        event.title = draft.title
        event.location = draft.location
        event.notes = draft.notes
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.timeZone = Calendar.shanghai.timeZone
        event.availability = .busy
        event.alarms = [EKAlarm(relativeOffset: -5 * 60)]
        return true
    }
}
