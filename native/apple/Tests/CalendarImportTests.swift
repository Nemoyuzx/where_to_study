import XCTest
#if os(macOS)
@testable import WhereToStudyMac
#elseif os(iOS)
@testable import WhereToStudyiOS
#endif

final class CalendarImportTests: XCTestCase {
    func testStrictContractDateParserRejectsNormalizedAndNonCanonicalDates() throws {
        let leapDay = try XCTUnwrap(StrictContractDateParser.date(from: "2024-02-29"))
        XCTAssertEqual(StrictContractDateParser.string(from: leapDay), "2024-02-29")

        for value in [
            "2026-02-30",
            "2026-13-01",
            "2026-00-01",
            "2025-02-29",
            "2026-2-03",
            "2026-02-3",
            "2026-02-03-extra",
            "0000-01-01",
        ] {
            XCTAssertNil(StrictContractDateParser.date(from: value), value)
        }
    }

    func testEventDraftsExpandActualWeeksAndUseSlotBoundaries() throws {
        let schedule = fixtureSchedule(
            weeks: [1, 3],
            examWeeks: [3],
            weekday: 1,
            startSlot: 2,
            endSlot: 4
        )

        let drafts = try CalendarImportLogic.eventDrafts(from: schedule)

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts.map(\.title), ["数据挖掘", "试 数据挖掘"])
        XCTAssertEqual(drafts.map(\.location), ["教二楼-3-335", "教二楼-3-335"])
        XCTAssertEqual(Self.formatter.string(from: drafts[0].startDate), "2026-03-02 09:50")
        XCTAssertEqual(Self.formatter.string(from: drafts[0].endDate), "2026-03-02 12:15")
        XCTAssertEqual(Self.formatter.string(from: drafts[1].startDate), "2026-03-16 09:50")
    }

    func testEventMarkersAreStableDistinctAndRecoverableFromNotes() throws {
        let schedule = fixtureSchedule(weeks: [1, 1, 2], examWeeks: [])

        let drafts = try CalendarImportLogic.eventDrafts(from: schedule)

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(Set(drafts.map(\.marker)).count, 2)
        XCTAssertEqual(CalendarImportLogic.marker(in: drafts[0].notes), drafts[0].marker)
        XCTAssertEqual(
            CalendarImportLogic.eventMarker(termID: schedule.termID, courseID: "course-1", week: 1),
            drafts[0].marker
        )
    }

    func testInvalidTermDateAndSlotFailInsteadOfCreatingWrongEvents() {
        for value in ["not-a-date", "2026-02-30", "2026-13-01"] {
            let invalidDate = ScheduleSnapshot(
                termID: "2025-2026-2",
                termStartDate: value,
                fetchedAt: "2026-03-01T00:00:00Z",
                courses: []
            )
            XCTAssertThrowsError(try CalendarImportLogic.eventDrafts(from: invalidDate), value) { error in
                XCTAssertEqual(error as? CalendarImportError, .invalidTermStartDate)
            }
        }

        let invalidSlot = fixtureSchedule(weeks: [1], examWeeks: [], startSlot: 14, endSlot: 14)
        XCTAssertThrowsError(try CalendarImportLogic.eventDrafts(from: invalidSlot)) { error in
            XCTAssertEqual(error as? CalendarImportError, .invalidCourse("数据挖掘"))
        }
    }

    func testSchedulePlanCoversTheFullEighteenWeekTerm() throws {
        let plan = try CalendarImportLogic.schedulePlan(
            from: fixtureSchedule(weeks: [1], examWeeks: [])
        )

        XCTAssertEqual(Self.formatter.string(from: plan.scope.startDate), "2026-03-02 00:00")
        XCTAssertEqual(Self.formatter.string(from: plan.scope.endDate), "2026-07-06 00:00")
        XCTAssertTrue(plan.scope.contains(try XCTUnwrap(Self.formatter.date(from: "2026-07-05 23:59"))))
        XCTAssertFalse(plan.scope.contains(plan.scope.endDate))
    }

    func testSyncPlanRemovesStaleAndDuplicateEventsButKeepsOutsideAndUnownedEvents() throws {
        let schedulePlan = try CalendarImportLogic.schedulePlan(
            from: fixtureSchedule(weeks: [1, 2], examWeeks: [])
        )
        let firstDraft = try XCTUnwrap(schedulePlan.drafts.first)
        let secondDraft = try XCTUnwrap(schedulePlan.drafts.last)
        let staleMarker = CalendarImportLogic.eventMarker(
            termID: "2025-2026-2",
            courseID: "removed-course",
            week: 1
        )
        let outsideDate = schedulePlan.scope.endDate.addingTimeInterval(60)
        let existingEvents = [
            existingEvent(
                identifier: "a-duplicate",
                marker: firstDraft.marker,
                draft: firstDraft,
                title: "旧标题"
            ),
            existingEvent(identifier: "z-exact", marker: firstDraft.marker, draft: firstDraft),
            existingEvent(identifier: "stale", marker: staleMarker, draft: firstDraft),
            existingEvent(
                identifier: "outside-history",
                marker: staleMarker,
                draft: firstDraft,
                startDate: outsideDate
            ),
            existingEvent(identifier: "other-app", marker: nil, draft: firstDraft),
        ]

        let syncPlan = CalendarImportLogic.syncPlan(
            drafts: schedulePlan.drafts,
            scope: schedulePlan.scope,
            existingEvents: existingEvents,
            destinationCalendarIdentifier: "destination"
        )

        XCTAssertEqual(syncPlan.inserts, [secondDraft])
        XCTAssertEqual(
            syncPlan.matches,
            [CalendarSyncMatch(existingIdentifier: "z-exact", draft: firstDraft, needsUpdate: false)]
        )
        XCTAssertEqual(syncPlan.deleteIdentifiers, ["a-duplicate", "stale"])
        XCTAssertFalse(syncPlan.deleteIdentifiers.contains("outside-history"))
        XCTAssertFalse(syncPlan.deleteIdentifiers.contains("other-app"))
    }

    func testSyncPlanUpdatesChangedEventWithoutCreatingAnotherCopy() throws {
        let schedulePlan = try CalendarImportLogic.schedulePlan(
            from: fixtureSchedule(weeks: [1], examWeeks: [])
        )
        let draft = try XCTUnwrap(schedulePlan.drafts.first)
        let changed = existingEvent(
            identifier: "changed",
            marker: draft.marker,
            draft: draft,
            location: "旧地点"
        )

        let syncPlan = CalendarImportLogic.syncPlan(
            drafts: [draft],
            scope: schedulePlan.scope,
            existingEvents: [changed],
            destinationCalendarIdentifier: "destination"
        )

        XCTAssertTrue(syncPlan.inserts.isEmpty)
        XCTAssertEqual(
            syncPlan.matches,
            [CalendarSyncMatch(existingIdentifier: "changed", draft: draft, needsUpdate: true)]
        )
        XCTAssertTrue(syncPlan.deleteIdentifiers.isEmpty)
    }

    func testExpectedMarkerOutsideTheTermIsPreservedAndInsertedInsideTheTerm() throws {
        let schedulePlan = try CalendarImportLogic.schedulePlan(
            from: fixtureSchedule(weeks: [1], examWeeks: [])
        )
        let draft = try XCTUnwrap(schedulePlan.drafts.first)
        let movedDate = schedulePlan.scope.endDate.addingTimeInterval(60)
        let moved = existingEvent(
            identifier: "moved",
            marker: draft.marker,
            draft: draft,
            startDate: movedDate
        )

        let syncPlan = CalendarImportLogic.syncPlan(
            drafts: [draft],
            scope: schedulePlan.scope,
            existingEvents: [moved],
            destinationCalendarIdentifier: "destination"
        )

        XCTAssertEqual(syncPlan.inserts, [draft])
        XCTAssertTrue(syncPlan.matches.isEmpty)
        XCTAssertTrue(syncPlan.deleteIdentifiers.isEmpty)
    }

    func testEmptyScheduleStillRemovesOwnedEventsInsideTheTerm() throws {
        let populatedPlan = try CalendarImportLogic.schedulePlan(
            from: fixtureSchedule(weeks: [1], examWeeks: [])
        )
        let oldDraft = try XCTUnwrap(populatedPlan.drafts.first)
        let emptySchedule = ScheduleSnapshot(
            termID: "2025-2026-2",
            termStartDate: "2026-03-02",
            fetchedAt: "2026-03-01T00:00:00Z",
            courses: []
        )
        let emptyPlan = try CalendarImportLogic.schedulePlan(from: emptySchedule)

        let syncPlan = CalendarImportLogic.syncPlan(
            drafts: emptyPlan.drafts,
            scope: emptyPlan.scope,
            existingEvents: [
                existingEvent(identifier: "old-event", marker: oldDraft.marker, draft: oldDraft),
            ],
            destinationCalendarIdentifier: "destination"
        )

        XCTAssertTrue(syncPlan.inserts.isEmpty)
        XCTAssertTrue(syncPlan.matches.isEmpty)
        XCTAssertEqual(syncPlan.deleteIdentifiers, ["old-event"])
    }

    func testDailyRefreshUsesNextSevenOClockWithoutPolling() throws {
        let before = try XCTUnwrap(Self.formatter.date(from: "2026-08-03 06:59"))
        let atTarget = try XCTUnwrap(Self.formatter.date(from: "2026-08-03 07:00"))
        let after = try XCTUnwrap(Self.formatter.date(from: "2026-08-03 07:01"))

        XCTAssertEqual(Self.formatter.string(from: DailyRefreshLogic.nextRefresh(after: before)), "2026-08-03 07:00")
        XCTAssertEqual(Self.formatter.string(from: DailyRefreshLogic.nextRefresh(after: atTarget)), "2026-08-04 07:00")
        XCTAssertEqual(Self.formatter.string(from: DailyRefreshLogic.nextRefresh(after: after)), "2026-08-04 07:00")
    }

    private func fixtureSchedule(
        weeks: [Int],
        examWeeks: [Int],
        weekday: Int = 1,
        startSlot: Int = 0,
        endSlot: Int = 1
    ) -> ScheduleSnapshot {
        ScheduleSnapshot(
            termID: "2025-2026-2",
            termStartDate: "2026-03-02",
            fetchedAt: "2026-03-01T00:00:00Z",
            courses: [
                Course(
                    id: "course-1",
                    name: "数据挖掘",
                    teacher: "测试教师",
                    room: "教二楼-3-335",
                    weekText: "测试周",
                    weekNumbers: weeks,
                    examWeekNumbers: examWeeks,
                    weekday: weekday,
                    startSlot: startSlot,
                    endSlot: endSlot,
                    sectionText: "第 1-2 节",
                    timeRange: ""
                ),
            ]
        )
    }

    private func existingEvent(
        identifier: String,
        marker: String?,
        draft: CalendarEventDraft,
        title: String? = nil,
        location: String? = nil,
        startDate: Date? = nil
    ) -> CalendarExistingEvent {
        let resolvedStart = startDate ?? draft.startDate
        let duration = draft.endDate.timeIntervalSince(draft.startDate)
        let resolvedNotes = marker.map {
            draft.notes.replacingOccurrences(of: draft.marker, with: $0)
        } ?? "其他应用事件"
        return CalendarExistingEvent(
            identifier: identifier,
            marker: marker,
            title: title ?? draft.title,
            location: location ?? draft.location,
            notes: resolvedNotes,
            startDate: resolvedStart,
            endDate: resolvedStart.addingTimeInterval(duration),
            calendarIdentifier: "destination",
            timeZoneIdentifier: Calendar.shanghai.timeZone.identifier,
            isBusy: true,
            alarmOffsets: [CalendarImportLogic.reminderOffset]
        )
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.shanghai.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
