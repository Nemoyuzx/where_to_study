import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class CalendarRenderingPerformanceTests: XCTestCase {
    func testCachedTimelinePlacementsPreserveOverlapAndInclusiveSlotBoundaries() {
        let courses = [
            course("later", start: 3, end: 4),
            course("overlap", start: 1, end: 2),
            course("first", start: 0, end: 1),
            course("adjacent", start: 2, end: 2),
        ]
        let day = CalendarTimelineDay(date: .now, courses: courses, holidays: [])

        XCTAssertEqual(day.courses, courses, "Projection must preserve the original courses")
        XCTAssertEqual(day.coursePlacements.map(\.course.id), ["first", "overlap", "adjacent", "later"])
        XCTAssertEqual(day.coursePlacements.map(\.track), [0, 1, 0, 0])
        XCTAssertEqual(day.courseTrackCount, 2)
        XCTAssertEqual(
            day.coursePlacements,
            CalendarTimelineLogic.placeCourses(Array(courses.reversed()))
        )
        for track in 0 ..< day.courseTrackCount {
            let placements = day.coursePlacements.filter { $0.track == track }
            for (previous, next) in zip(placements, placements.dropFirst()) {
                XCTAssertLessThan(previous.course.endSlot, next.course.startSlot)
            }
        }
        XCTAssertEqual(CalendarTimelineDay(date: .now, courses: [], holidays: []).courseTrackCount, 1)
    }

    func testDateFormatterCacheReusesFormatsWithoutLeakingLanguageOrTimeZone() throws {
        let cache = CalendarDateFormatterCache()
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-04T18:00:00Z"))
        let chinese = cache.formatter(format: "yyyy-MM-dd EEEE", locale: Locale(identifier: "zh_CN"))
        let english = cache.formatter(format: "yyyy-MM-dd EEEE", locale: Locale(identifier: "en_US"))

        XCTAssertTrue(chinese === cache.formatter(format: "yyyy-MM-dd EEEE", locale: Locale(identifier: "zh_CN")))
        XCTAssertFalse(chinese === english)
        XCTAssertEqual(chinese.string(from: date), "2026-09-05 星期六")
        XCTAssertEqual(english.string(from: date), "2026-09-05 Saturday")
        XCTAssertEqual(cache.formatter(format: "HH:mm", locale: Locale(identifier: "en_US")).string(from: date), "02:00")
    }

    @MainActor
    func testSessionRetainsOnlyBoundedProjectionsAndInvalidatesWhilePageIsAbsent() async throws {
        let suiteName = "CalendarSessionLifetime.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            runtimeMode: .sample(review: false),
            credentialStore: EmptyCalendarCredentialStore(),
            scheduleStore: EmptyCalendarScheduleStore(),
            classroomStore: EmptyCalendarClassroomStore(),
            defaults: defaults
        )
        let deadlines = CalendarDeadlineStore()
        let session = TeachingCalendarSessionState()
        weak var retainedCache: TeachingCalendarRenderingCache?
        do {
            let cache = session.renderingCache
            retainedCache = cache
            _ = cache.timelineSnapshots.value(for: "before-subscription") { [] }
            await deadlines.loadPublic(dates: ["2026-09-05"], sampleMode: true)
            cache.bind(model: model, deadlineStore: deadlines)
            XCTAssertTrue(
                cache.timelineSnapshots.isEmpty,
                "Initial binding must discard a projection built before the store published its first data"
            )
            for period in 0 ..< 8 {
                _ = cache.timelineSnapshots.value(for: "period-\(period)") { [] }
            }
        }

        XCTAssertNotNil(retainedCache, "Leaving a page must keep its bounded projections in the session")
        XCTAssertTrue(retainedCache === session.renderingCache)
        XCTAssertEqual(session.renderingCache.timelineSnapshots.count, 6)
        _ = session.renderingCache.timelineSnapshots.value(for: "period-7") {
            XCTFail("Returning to a cached period must not rebuild it")
            return []
        }

        model.termStartDate = "2026-09-14"
        for _ in 0 ..< 100 where !session.renderingCache.timelineSnapshots.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(session.renderingCache.timelineSnapshots.isEmpty)

        _ = session.renderingCache.timelineSnapshots.value(for: "live-period") { [] }
        session.renderingCache.bind(model: model, deadlineStore: CalendarDeadlineStore())
        XCTAssertTrue(session.renderingCache.timelineSnapshots.isEmpty, "A new mode store cannot reuse old mode data")
    }

    @MainActor
    func testSnapshotInvalidationCoalescesChangesAndRebindsToReplacementStore() async throws {
        let suiteName = "CalendarSnapshotInvalidation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            runtimeMode: .sample(review: false),
            credentialStore: EmptyCalendarCredentialStore(),
            scheduleStore: EmptyCalendarScheduleStore(),
            classroomStore: EmptyCalendarClassroomStore(),
            defaults: defaults
        )
        let original = CalendarDeadlineStore()
        let replacement = CalendarDeadlineStore()
        let observer = CalendarSnapshotInvalidationObserver()
        var invalidationCount = 0
        var observedTerm = ""

        observer.bind(model: model, deadlineStore: original) {
            invalidationCount += 1
            observedTerm = model.termID
        }
        XCTAssertEqual(invalidationCount, 1, "Initial subscription must clear projections built before binding")
        model.termID = "2026-2027-1"
        model.termStartDate = "2026-09-07"
        XCTAssertEqual(invalidationCount, 1, "Published willSet must not rebuild from pre-change state")
        for _ in 0 ..< 100 where invalidationCount == 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(invalidationCount, 2, "One settings batch should invalidate the projections once")
        XCTAssertEqual(observedTerm, "2026-2027-1")

        observer.bind(model: model, deadlineStore: original) {
            XCTFail("Rebinding the same instances must retain the existing subscription")
        }
        XCTAssertEqual(invalidationCount, 2)
        observer.bind(model: model, deadlineStore: replacement) {
            invalidationCount += 1
        }
        XCTAssertEqual(invalidationCount, 3, "A replacement store must immediately drop old projections")

        await original.loadPublic(dates: ["2026-09-05"], sampleMode: true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(invalidationCount, 3, "The old store must no longer invalidate the current calendar")

        await replacement.loadPublic(dates: ["2026-09-05"], sampleMode: true)
        for _ in 0 ..< 100 where invalidationCount == 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(invalidationCount, 4)
    }

    private func course(_ id: String, start: Int, end: Int) -> Course {
        Course(
            id: id, name: id, teacher: "Teacher", room: "Room", weekText: "1-16",
            weekNumbers: Array(1 ... 16), examWeekNumbers: [], weekday: 1,
            startSlot: start, endSlot: end, sectionText: "", timeRange: "08:00-09:35"
        )
    }
}

private struct EmptyCalendarCredentialStore: CredentialStoring {
    func load() throws -> Credentials? { nil }
    func save(_: Credentials) throws {}
    func clear() throws {}
}

private struct EmptyCalendarScheduleStore: ScheduleStoring {
    func load() throws -> ScheduleSnapshot? { nil }
    func save(_: ScheduleSnapshot) throws {}
    func clear() throws {}
}

private struct EmptyCalendarClassroomStore: ClassroomStoring {
    func load() throws -> ClassroomsCache? { nil }
    func save(_: ClassroomsCache) throws {}
    func clear() throws {}
}
