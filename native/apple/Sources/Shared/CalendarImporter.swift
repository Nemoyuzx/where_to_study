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

struct CalendarImportScope: Equatable, Sendable {
    let startDate: Date
    let endDate: Date

    func contains(_ date: Date) -> Bool {
        date >= startDate && date < endDate
    }
}

struct CalendarScheduleImportPlan: Equatable, Sendable {
    let scope: CalendarImportScope
    let drafts: [CalendarEventDraft]
}

struct CalendarExistingEvent: Equatable, Sendable {
    let identifier: String
    let marker: String?
    let title: String
    let location: String
    let notes: String
    let startDate: Date
    let endDate: Date
    let calendarIdentifier: String
    let timeZoneIdentifier: String?
    let isBusy: Bool
    let alarmOffsets: [TimeInterval]
}

struct CalendarSyncMatch: Equatable, Sendable {
    let existingIdentifier: String
    let draft: CalendarEventDraft
    let needsUpdate: Bool
}

struct CalendarSyncPlan: Equatable, Sendable {
    let inserts: [CalendarEventDraft]
    let matches: [CalendarSyncMatch]
    let deleteIdentifiers: [String]
}

struct CalendarImportResult: Equatable, Sendable {
    let inserted: Int
    let updated: Int
    let deleted: Int
    let unchanged: Int

    var total: Int { inserted + updated + deleted + unchanged }
}

enum CalendarImportError: LocalizedError, Equatable {
    case noSchedule
    case invalidTermStartDate
    case invalidCourse(String)
    case permissionDenied
    case noWritableCalendar
    case eventStoreChanged

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
        case .eventStoreChanged:
            "系统日历在同步期间发生变化，请重试。"
        }
    }
}

enum CalendarImportLogic {
    static let markerPrefix = "where-to-study:event:"
    static let minimumTermWeeks = 18
    static let reminderOffset: TimeInterval = -5 * 60

    static func schedulePlan(
        from schedule: ScheduleSnapshot,
        slots: [SlotMetadata] = SlotMetadata.defaults,
        calendar: Calendar = .shanghai
    ) throws -> CalendarScheduleImportPlan {
        guard let termStart = StrictContractDateParser.date(
            from: schedule.termStartDate,
            calendar: calendar
        ) else {
            throw CalendarImportError.invalidTermStartDate
        }

        let positiveWeeks = schedule.courses.flatMap(\.weekNumbers).filter { $0 > 0 }
        let maximumWeek = positiveWeeks.max() ?? minimumTermWeeks
        if maximumWeek > 53 {
            let courseName = schedule.courses.first(where: { course in
                course.weekNumbers.contains(where: { $0 > 53 })
            })?.name ?? "未知课程"
            throw CalendarImportError.invalidCourse(courseName)
        }
        let termWeeks = max(minimumTermWeeks, maximumWeek)
        guard let termEnd = calendar.date(byAdding: .day, value: termWeeks * 7, to: termStart) else {
            throw CalendarImportError.invalidTermStartDate
        }

        let drafts = try eventDrafts(
            from: schedule,
            termStart: termStart,
            slots: slots,
            calendar: calendar
        )
        return CalendarScheduleImportPlan(
            scope: CalendarImportScope(startDate: termStart, endDate: termEnd),
            drafts: drafts
        )
    }

    static func eventDrafts(
        from schedule: ScheduleSnapshot,
        slots: [SlotMetadata] = SlotMetadata.defaults,
        calendar: Calendar = .shanghai
    ) throws -> [CalendarEventDraft] {
        try schedulePlan(from: schedule, slots: slots, calendar: calendar).drafts
    }

    static func syncPlan(
        drafts: [CalendarEventDraft],
        scope: CalendarImportScope,
        existingEvents: [CalendarExistingEvent],
        destinationCalendarIdentifier: String
    ) -> CalendarSyncPlan {
        let ownedEvents = existingEvents.filter { event in
            event.marker?.hasPrefix(markerPrefix) ?? false
        }
        let scopedOwnedEvents = ownedEvents.filter { scope.contains($0.startDate) }
        let desiredMarkers = Set(drafts.map(\.marker))
        var eventsByMarker = [String: [CalendarExistingEvent]]()
        for event in ownedEvents {
            guard let marker = event.marker else { continue }
            eventsByMarker[marker, default: []].append(event)
        }
        for marker in eventsByMarker.keys {
            eventsByMarker[marker]?.sort { $0.identifier < $1.identifier }
        }

        var inserts = [CalendarEventDraft]()
        var matches = [CalendarSyncMatch]()
        var deleteIdentifiers = Set<String>()
        for draft in drafts {
            let candidates = eventsByMarker[draft.marker] ?? []
            guard !candidates.isEmpty else {
                inserts.append(draft)
                continue
            }
            let selected = candidates.first(where: {
                eventMatches(
                    $0,
                    draft: draft,
                    destinationCalendarIdentifier: destinationCalendarIdentifier
                )
            }) ?? candidates[0]
            let needsUpdate = !eventMatches(
                selected,
                draft: draft,
                destinationCalendarIdentifier: destinationCalendarIdentifier
            )
            matches.append(CalendarSyncMatch(
                existingIdentifier: selected.identifier,
                draft: draft,
                needsUpdate: needsUpdate
            ))
            for duplicate in candidates where duplicate.identifier != selected.identifier {
                deleteIdentifiers.insert(duplicate.identifier)
            }
        }

        for event in scopedOwnedEvents {
            guard let marker = event.marker, !desiredMarkers.contains(marker) else { continue }
            deleteIdentifiers.insert(event.identifier)
        }

        return CalendarSyncPlan(
            inserts: inserts,
            matches: matches,
            deleteIdentifiers: deleteIdentifiers.sorted()
        )
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

    private static func eventDrafts(
        from schedule: ScheduleSnapshot,
        termStart: Date,
        slots: [SlotMetadata],
        calendar: Calendar
    ) throws -> [CalendarEventDraft] {
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

    private static func eventMatches(
        _ event: CalendarExistingEvent,
        draft: CalendarEventDraft,
        destinationCalendarIdentifier: String
    ) -> Bool {
        event.title == draft.title
            && event.location == draft.location
            && event.notes == draft.notes
            && event.startDate == draft.startDate
            && event.endDate == draft.endDate
            && event.calendarIdentifier == destinationCalendarIdentifier
            && event.timeZoneIdentifier == Calendar.shanghai.timeZone.identifier
            && event.isBusy
            && event.alarmOffsets == [reminderOffset]
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
        let importPlan = try CalendarImportLogic.schedulePlan(from: schedule)
        guard try await requestAccess() else { throw CalendarImportError.permissionDenied }

        return try await Task.detached(priority: .userInitiated) {
            try Self.write(importPlan)
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

    nonisolated private static func write(
        _ importPlan: CalendarScheduleImportPlan
    ) throws -> CalendarImportResult {
        let store = EKEventStore()
        guard let destination = store.defaultCalendarForNewEvents else {
            throw CalendarImportError.noWritableCalendar
        }

        let searchStart = importPlan.scope.startDate.addingTimeInterval(-366 * 24 * 60 * 60)
        let searchEnd = importPlan.scope.endDate.addingTimeInterval(366 * 24 * 60 * 60)
        let predicate = store.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: nil
        )
        let existingEvents = store.events(matching: predicate)
        let indexedEvents = existingEvents.enumerated().map { index, event in
            let identifier = String(index)
            let snapshot = CalendarExistingEvent(
                identifier: identifier,
                marker: CalendarImportLogic.marker(in: event.notes),
                title: event.title ?? "",
                location: event.location ?? "",
                notes: event.notes ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                calendarIdentifier: event.calendar.calendarIdentifier,
                timeZoneIdentifier: event.timeZone?.identifier,
                isBusy: event.availability == .busy,
                alarmOffsets: (event.alarms ?? []).map(\.relativeOffset).sorted()
            )
            return (identifier: identifier, event: event, snapshot: snapshot)
        }
        let eventsByIdentifier = Dictionary(
            uniqueKeysWithValues: indexedEvents.map { ($0.identifier, $0.event) }
        )
        let syncPlan = CalendarImportLogic.syncPlan(
            drafts: importPlan.drafts,
            scope: importPlan.scope,
            existingEvents: indexedEvents.map(\.snapshot),
            destinationCalendarIdentifier: destination.calendarIdentifier
        )

        for identifier in syncPlan.deleteIdentifiers {
            guard let event = eventsByIdentifier[identifier] else {
                throw CalendarImportError.eventStoreChanged
            }
            try store.remove(event, span: .thisEvent, commit: false)
        }

        var updated = 0
        var unchanged = 0
        for match in syncPlan.matches {
            guard let event = eventsByIdentifier[match.existingIdentifier] else {
                throw CalendarImportError.eventStoreChanged
            }
            if match.needsUpdate {
                apply(match.draft, to: event, calendar: destination)
                try store.save(event, span: .thisEvent, commit: false)
                updated += 1
            } else {
                unchanged += 1
            }
        }

        for draft in syncPlan.inserts {
            let event = EKEvent(eventStore: store)
            apply(draft, to: event, calendar: destination)
            try store.save(event, span: .thisEvent, commit: false)
        }

        let deleted = syncPlan.deleteIdentifiers.count
        let inserted = syncPlan.inserts.count
        if inserted > 0 || updated > 0 || deleted > 0 {
            try store.commit()
        }
        return CalendarImportResult(
            inserted: inserted,
            updated: updated,
            deleted: deleted,
            unchanged: unchanged
        )
    }

    nonisolated private static func apply(
        _ draft: CalendarEventDraft,
        to event: EKEvent,
        calendar: EKCalendar
    ) {
        event.calendar = calendar
        event.title = draft.title
        event.location = draft.location
        event.notes = draft.notes
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.timeZone = Calendar.shanghai.timeZone
        event.availability = .busy
        event.alarms = [EKAlarm(relativeOffset: CalendarImportLogic.reminderOffset)]
    }
}
