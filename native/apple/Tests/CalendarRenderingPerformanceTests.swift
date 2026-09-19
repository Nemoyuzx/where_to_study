import XCTest
#if os(macOS)
import AppKit
import SwiftUI
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

#if os(macOS)
@MainActor
final class DesktopCalendarPinnedHeaderTests: XCTestCase {
    func testMonthWeekdaysRemainVisibleWhileDatesAndDetailsScroll() async throws {
        let suite = "DesktopCalendarPinnedMonthTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            runtimeMode: .sample(review: false),
            credentialStore: EmptyCalendarCredentialStore(),
            scheduleStore: EmptyCalendarScheduleStore(),
            classroomStore: EmptyCalendarClassroomStore(),
            defaults: defaults
        )
        let session = TeachingCalendarSessionState()
        session.selectedDate = try XCTUnwrap(StrictContractDateParser.date(from: "2026-09-14"))
        session.modeRawValue = "月"
        let host = NSHostingView(rootView: TeachingCalendarView(session: session)
            .environmentObject(model)
            .environmentObject(DailyInfoStore())
            .environmentObject(CalendarDeadlineStore())
            .frame(width: 640, height: 640))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 640),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.orderFront(nil)
        try await settle(host)
        let vertical = try XCTUnwrap(scrollViews(in: host).first {
            ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 100
        })
        let scrollFrame = vertical.convert(vertical.bounds, to: host)
        let before = try bitmap(host)
        vertical.contentView.scroll(to: CGPoint(x: 0, y: 240))
        vertical.reflectScrolledClipView(vertical.contentView)
        try await settle(host)
        let after = try bitmap(host)
        XCTAssertGreaterThan(vertical.contentView.bounds.minY, 200)
        XCTAssertLessThan(difference(before, after, region: CGRect(
            x: scrollFrame.minX, y: scrollFrame.minY - 30, width: scrollFrame.width - 18, height: 30
        )), 0.005, "The month weekday row must remain above the scrolling dates and details")
        try attach(after, name: "desktop-pinned-month-weekdays")
    }

    func testDayAndWeekHeadersAndAllDayEventsRemainVisibleAfterScrolling() async throws {
        let suite = "DesktopCalendarPinnedHeaderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            runtimeMode: .sample(review: false),
            credentialStore: EmptyCalendarCredentialStore(),
            scheduleStore: EmptyCalendarScheduleStore(),
            classroomStore: EmptyCalendarClassroomStore(),
            defaults: defaults
        )
        let first = try XCTUnwrap(StrictContractDateParser.date(from: "2026-09-14"))
        for count in [1, 7] {
            let dates = (0..<count).compactMap { Calendar.shanghai.date(byAdding: .day, value: $0, to: first) }
            let event = CalendarAllDayEvent(id: "pinned-ddl", title: "Pinned deadline", kind: .assignment)
            let course = Course(id: "course", name: "Visible course", teacher: "Teacher", room: "Room",
                                weekText: "1-16", weekNumbers: [1], examWeekNumbers: [], weekday: 1,
                                startSlot: 4, endSlot: 5, sectionText: "5-6", timeRange: "13:00-14:35")
            let days = dates.map { CalendarTimelineDay(date: $0, courses: [course], holidays: [], allDayEvents: [event]) }
            let host = NSHostingView(rootView: CalendarTimelineView(
                days: days,
                selectedDate: first,
                onSelectDay: { _ in },
                onSelectAllDayEvent: { _, _ in }
            ).environmentObject(model).frame(width: 640, height: 380))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 380),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            window.orderFront(nil)
            try await settle(host)

            let before = try bitmap(host)
            let vertical = try XCTUnwrap(scrollViews(in: host).first {
                ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 100
            })
            vertical.contentView.scroll(to: CGPoint(x: 0, y: 240))
            vertical.reflectScrolledClipView(vertical.contentView)
            try await settle(host)

            XCTAssertGreaterThan(vertical.contentView.bounds.minY, 200)
            let scrolled = try bitmap(host)
            XCTAssertLessThan(difference(before, scrolled, region: CGRect(x: 0, y: 0, width: 620, height: 72)), 0.005,
                              "The date, course count and axis headers must remain fixed")
            XCTAssertLessThan(difference(before, scrolled, region: CGRect(x: 0, y: 72, width: 620, height: 22)), 0.005,
                              "The complete all-day row must remain fixed")
            XCTAssertGreaterThan(difference(before, scrolled, region: CGRect(x: 0, y: 100, width: 620, height: 260)), 0.01,
                                 "The time grid and course cards must scroll beneath the header")
            try attach(scrolled, name: "desktop-pinned-\(count == 1 ? "day" : "week")")

            if count == 7 {
                XCTAssertEqual(firstHeaderInkRow(scrolled, column: 1), firstHeaderInkRow(scrolled, column: 2), accuracy: 1,
                               "Weekday titles must share the same header baseline")
                let horizontal = try XCTUnwrap(scrollViews(in: host).first {
                    ($0.documentView?.frame.width ?? 0) > $0.contentView.bounds.width + 100
                })
                horizontal.contentView.scroll(to: CGPoint(x: 180, y: 0))
                horizontal.reflectScrolledClipView(horizontal.contentView)
                try await settle(host)
                XCTAssertEqual(horizontal.contentView.bounds.minX, 180, accuracy: 1)
                let shifted = try bitmap(host)
                XCTAssertLessThan(difference(scrolled, shifted,
                    region: CGRect(x: 340, y: 0, width: 280, height: 94), translation: CGPoint(x: -180, y: 0)), 0.005,
                    "Date and all-day columns must follow horizontal scrolling")
                XCTAssertLessThan(difference(scrolled, shifted,
                    region: CGRect(x: 340, y: 100, width: 280, height: 240), translation: CGPoint(x: -180, y: 0)), 0.005,
                    "Courses must move by the same amount as their headers")
            }
        }
    }

    private func settle(_ view: NSView) async throws {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func bitmap(_ view: NSView) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func difference(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep,
                            region: CGRect, translation: CGPoint = .zero) -> Double {
        let scale = CGFloat(first.pixelsWide) / 640
        var total = 0.0
        var count = 0
        for y in stride(from: region.minY + 1, to: region.maxY, by: 2) {
            for x in stride(from: region.minX + 1, to: region.maxX, by: 2) {
                guard let a = first.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB),
                      let b = second.colorAt(x: Int((x + translation.x) * scale),
                                             y: Int((y + translation.y) * scale))?.usingColorSpace(.sRGB)
                else { return 1 }
                total += abs(a.redComponent - b.redComponent)
                    + abs(a.greenComponent - b.greenComponent)
                    + abs(a.blueComponent - b.blueComponent)
                count += 3
            }
        }
        return total / Double(max(count, 1))
    }

    private func attach(_ bitmap: NSBitmapImageRep, name: String) throws {
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func firstHeaderInkRow(_ bitmap: NSBitmapImageRep, column: Int) -> Double {
        let scale = CGFloat(bitmap.pixelsWide) / 640
        let startX = 156 + column * 118 + 8
        guard let background = bitmap.colorAt(x: Int(CGFloat(startX) * scale), y: Int(4 * scale))?.usingColorSpace(.sRGB)
        else { return -1 }
        for y in 8..<65 {
            for x in startX..<(startX + 102) {
                guard let color = bitmap.colorAt(x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))?.usingColorSpace(.sRGB)
                else { continue }
                if abs(color.redComponent - background.redComponent)
                    + abs(color.greenComponent - background.greenComponent)
                    + abs(color.blueComponent - background.blueComponent) > 0.3 { return Double(y) }
            }
        }
        return -1
    }
}
#endif
