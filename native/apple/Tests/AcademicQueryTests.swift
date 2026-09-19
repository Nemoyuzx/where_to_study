import XCTest
#if os(macOS)
import AppKit
import SwiftUI
@testable import WhereToStudyMac
#else
@testable import WhereToStudyiOS
#endif

final class AcademicQueryTests: XCTestCase {
    private let owner = CourseDeletionLogic.accountKey("synthetic-account")
    private let day = StrictContractDateParser.date(from: "2026-09-07")!
    private var lesson: Course {
        Course(id: "lesson", name: "合成课程", teacher: "", room: "示例教室", weekText: "1-2", weekNumbers: [1, 2],
               examWeekNumbers: [], weekday: 1, startSlot: 0, endSlot: 1, sectionText: "1-2", timeRange: "08:00-09:35")
    }
    private func exam(_ id: String = "exam", date: String = "2026-09-07", start: String = "09:20", end: String = "10:20") -> ExamArrangement {
        .init(id: id, name: "合成考试", date: date, startTime: start, endTime: end, room: "示例考场", seat: "", timeText: "\(date) \(start)-\(end)")
    }
    private func schedule(_ exams: [ExamArrangement]) -> ScheduleSnapshot {
        .init(termID: "2026-2027-1", termStartDate: "2026-09-07", fetchedAt: "2026-09-07T00:00:00+08:00", courses: [lesson],
              examSchedule: .init(termID: "2026-2027-1", accountKey: owner, fetchedAt: "2026-09-07T00:00:00+08:00", status: "fresh", message: "", items: exams))
    }

    func testVerifiedGradeFieldsPreserveZeroTextAndMissingValues() throws {
        let data = Data(#"{"code":1,"data":[{"pjxfjd":"3.75","achievement":[{"courseName":"合成零分","fraction":0,"credit":0,"kcbh":"DEMO-1"},{"courseName":"合成文字成绩","fraction":"合格","credit":"2"},{"courseName":"合成未公布"}]}]}"#.utf8)
        let grades = try AcademicResponseParser.grades(data, termID: "2026-2027-1", recordType: "1")
        XCTAssertEqual(grades.averageGradePoint, "3.75")
        XCTAssertEqual(grades.items[0].score, "0")
        XCTAssertEqual(grades.items[0].credits, "0")
        XCTAssertEqual(grades.items[1].score, "合格")
        XCTAssertNil(grades.items[2].score)
        XCTAssertEqual(grades.items, try AcademicResponseParser.grades(data, termID: "2026-2027-1", recordType: "1").items)
    }

    func testAcademicResponsesRejectMalformedOrFailureInsteadOfEmpty() throws {
        for response in [#"{"code":0,"data":[]}"#, #"{"code":true,"data":[]}"#, #"{"code":1}"#, #"{"code":1,"data":{}}"#, "<html>login</html>"] {
            XCTAssertThrowsError(try AcademicResponseParser.rows(Data(response.utf8)))
        }
        XCTAssertEqual(try AcademicResponseParser.grades(Data(#"{"code":"1","data":[]}"#.utf8), termID: "", recordType: "").items, [])
        XCTAssertThrowsError(try AcademicResponseParser.grades(Data(#"{"code":1,"data":[{}]}"#.utf8), termID: "", recordType: "1"))
    }

    func testAllSemesterRecordsKeepSchoolIdentitySemesterAndGradeStatus() throws {
        let data = Data(#"{"code":1,"data":[{"achievement":[{"courseName":"合成课程","fraction":"合格","cj0708id":"synthetic-1","curSemesterName":"示例学期一","cjbs":"示例标记"},{"courseName":"合成课程","fraction":"合格","cj0708id":"synthetic-2","curSemesterName":"示例学期二"}]}]}"#.utf8)
        let all = try AcademicResponseParser.grades(data, termID: "", recordType: "")
        XCTAssertEqual(all.items.count, 2)
        XCTAssertNotEqual(all.items[0].id, all.items[1].id)
        XCTAssertEqual(all.items[0].semesterName, "示例学期一")
        XCTAssertEqual(all.items[0].gradeStatus, "示例标记")
        XCTAssertEqual(all.items[0].id, try AcademicResponseParser.grades(data, termID: "different-query", recordType: "1").items[0].id)
    }

    func testExamFieldsUseVerifiedPlaceAndUnknownTimeRemainsPending() throws {
        let data = Data(#"{"code":1,"data":[{"courseName":"合成考试","examinationPlace":"示例真实字段","examAddress":"不使用","time":"2026-09-07 09:20-10:20"},{"courseName":"待定考试","time":"另行通知"}]}"#.utf8)
        let result = try AcademicResponseParser.exams(data, termID: "2026-2027-1", accountKey: owner)
        XCTAssertEqual(result.items[0].room, "示例真实字段")
        XCTAssertEqual(result.items[0].startTime, "09:20")
        XCTAssertEqual(result.items[1].date, "")
        XCTAssertEqual(result.items[1].timeText, "另行通知")
        XCTAssertEqual(result.items.map(\.id), try AcademicResponseParser.exams(data, termID: result.termID, accountKey: owner).items.map(\.id))
        XCTAssertEqual(AcademicResponseParser.examTime("2026-02-30 09:00-10:00").date, "")
        XCTAssertEqual(AcademicResponseParser.examTime("2026-09-07 25:00-26:00").start, "")
        XCTAssertEqual(AcademicResponseParser.examTime("2026-09-07 10:00-09:00").start, "")
    }

    func testExamOverlapSuppressesOnlyThatOccurrenceAndRetainsRawCourse() {
        let snapshot = schedule([exam()])
        let today = ScheduleLogic.courses(on: day, termStart: day, courses: snapshot.courses, exams: snapshot.examSchedule)
        XCTAssertEqual(today.map(\.id), ["exam"])
        XCTAssertEqual(snapshot.courses, [lesson])
        let nextWeek = Calendar.shanghai.date(byAdding: .day, value: 7, to: day)!
        XCTAssertEqual(ScheduleLogic.courses(on: nextWeek, termStart: day, courses: snapshot.courses, exams: snapshot.examSchedule), [lesson])
        XCTAssertEqual(ScheduleLogic.coursesByDate(for: [day], termStart: day, courses: snapshot.courses, exams: snapshot.examSchedule)["2026-09-07"], today)
    }

    func testOrdinaryCoursesKeepSlotBoundariesWhenDisplayTimeDisagrees() throws {
        let course = Course(id: "slot-course", name: "Slot course", teacher: "", room: "", weekText: "1", weekNumbers: [1],
            examWeekNumbers: [], weekday: 1, startSlot: 2, endSlot: 2, sectionText: "3", timeRange: "08:00-09:35",
            startTime: "08:00", endTime: "09:35")
        XCTAssertEqual(course.minuteInterval, (9 * 60 + 50) ..< (10 * 60 + 35))
        XCTAssertEqual(ScheduleLogic.busySlots(on: day, termStart: day, courses: [course]), [2])
        let examination = exam(start: "09:40", end: "09:55")
        XCTAssertEqual(try XCTUnwrap(examination.course()).minuteInterval, (9 * 60 + 40) ..< (9 * 60 + 55))
        let exams = schedule([examination]).examSchedule
        XCTAssertEqual(ScheduleLogic.courses(on: day, termStart: day, courses: [course], exams: exams).map(\.id), [examination.id])
    }

    func testSeparateExamDateAndClocksAreUsedOnlyWhenPrimaryTimeIsEmpty() throws {
        let data = Data(#"{"code":1,"data":[{"courseName":"合成辅助考试","time":"","ksqssj":"2026-09-07","zssj1":"09:20","zssj2":"11:00"},{"courseName":"主字段待定","time":"另行通知","ksqssj":"2026-09-07","zssj1":"09:20","zssj2":"11:00"},{"courseName":"非法跨日","ksqssj":"2026-09-07","zssj1":"23:00","zssj2":"01:00"},{"courseName":"非法日期","ksqssj":"2026-02-30","zssj1":"09:20","zssj2":"11:00"},{"courseName":"非法分钟","ksqssj":"2026-09-07","zssj1":"09:60","zssj2":"11:00"}]}"#.utf8)
        let items = try AcademicResponseParser.exams(data, termID: "2026-2027-1", accountKey: owner).items
        XCTAssertEqual(items[0].date, "2026-09-07")
        XCTAssertEqual(items[0].startTime, "09:20")
        XCTAssertEqual(items[0].endTime, "11:00")
        XCTAssertEqual(items[0].timeText, "2026-09-07 09:20 11:00")
        XCTAssertEqual(items[1].timeText, "另行通知")
        XCTAssertTrue(items[1].date.isEmpty)
        XCTAssertTrue(items[2].startTime.isEmpty)
        XCTAssertTrue(items[3].date.isEmpty)
        XCTAssertTrue(items[4].startTime.isEmpty)
    }

    func testAdjacentAndPendingExamsDoNotSuppressCoursesAndExamOnlyDatesWork() {
        let snapshot = schedule([exam(start: "09:35", end: "10:20"), exam("pending", start: "", end: ""), exam("outside", date: "2026-12-21")])
        let courses = ScheduleLogic.courses(on: day, termStart: day, courses: snapshot.courses, exams: snapshot.examSchedule)
        XCTAssertEqual(courses.count, 3)
        let pending = courses.first { $0.id == "pending" }!
        XCTAssertNil(pending.minuteInterval)
        let timeline = CalendarTimelineDay(date: day, courses: courses, holidays: [])
        XCTAssertEqual(timeline.coursePlacements.count, 2)
        XCTAssertEqual(timeline.allDayEvents.first?.kind, .exam)
        let future = StrictContractDateParser.date(from: "2026-12-21")!
        XCTAssertEqual(ScheduleLogic.courses(on: future, termStart: day, courses: snapshot.courses, exams: snapshot.examSchedule).map(\.id), ["outside"])
    }

    func testBusySlotsAndTimelineUseActualExamMinutes() {
        let snapshot = schedule([exam(start: "07:10", end: "08:10"), exam("late", start: "22:30", end: "23:10")])
        let courses = ScheduleLogic.courses(on: day, termStart: day, courses: snapshot.courses, exams: snapshot.examSchedule)
        XCTAssertEqual(ScheduleLogic.busySlots(on: day, termStart: day, courses: snapshot.courses, exams: snapshot.examSchedule), [0])
        XCTAssertEqual(CalendarTimelineLogic.bounds(for: courses), 420 ... 1440)
        XCTAssertEqual(CalendarTimelineLogic.placeCourses(courses).map(\.track), [0, 0])
    }

    func testCalendarExportSuppressesOverlapAndExportsPendingAsAllDay() throws {
        let snapshot = schedule([exam(), exam("pending", date: "2026-09-08", start: "", end: "")])
        let drafts = try CalendarImportLogic.eventDrafts(from: snapshot)
        XCTAssertEqual(drafts.count, 3) // Next week's course and two exams.
        let timed = try XCTUnwrap(drafts.first { $0.title == "考试 · 合成考试" })
        XCTAssertEqual(Calendar.shanghai.component(.minute, from: timed.startDate), 20)
        let pending = try XCTUnwrap(drafts.first { $0.isAllDay })
        XCTAssertTrue(pending.title.contains("时间待定"))
        XCTAssertEqual(Calendar.shanghai.dateComponents([.day], from: pending.startDate, to: pending.endDate).day, 1)
    }

    func testWidgetAndMorningSummaryUseEffectiveExams() {
        let snapshot = schedule([exam(), exam("pending", start: "", end: "")])
        let archive = TodayCourseWidgetData.Archive(termStartDate: snapshot.termStartDate, fetchedAt: snapshot.fetchedAt,
            courses: [.init(id: lesson.id, name: lesson.name, room: lesson.room, timeRange: lesson.timeRange, weekday: 1, weekNumbers: [1, 2], startSlot: 0, endSlot: 1)],
            examSchedule: snapshot.examSchedule)
        let projected = TodayCourseWidgetData.courses(on: day, archive: archive)
        XCTAssertEqual(Set(projected.map(\.id)), ["exam", "pending"])
        XCTAssertNil(TodayCourseWidgetData.coursePhase(projected.first { $0.id == "pending" }!, at: day))
        let requests = DailyCourseNotificationPlanner.requests(for: snapshot, after: day)
        XCTAssertTrue(requests.first?.body.contains("考试 · 时间待定") == true)
        XCTAssertFalse(requests.first?.body.contains("合成课程") == true)
    }

    func testLegacySnapshotDecodesWithoutExams() throws {
        let snapshot = try JSONDecoder().decode(ScheduleSnapshot.self, from: Data(#"{"term_id":"2026-2027-1","term_start_date":"2026-09-07","fetched_at":"","courses":[]}"#.utf8))
        XCTAssertNil(snapshot.examSchedule)
    }

    func testExamFailureReusesOnlyMatchingValidatedCacheAndSuccessfulEmptyClearsIt() {
        let previous = schedule([exam()]).examSchedule!
        var incoming = previous
        incoming.status = "failed"
        XCTAssertEqual(ExamScheduleCachePolicy.resolve(incoming, previous: previous, termID: previous.termID, accountKey: owner)?.status, "stale")
        XCTAssertNil(ExamScheduleCachePolicy.resolve(incoming, previous: previous, termID: "different-term", accountKey: owner))
        XCTAssertNil(ExamScheduleCachePolicy.resolve(incoming, previous: previous, termID: previous.termID, accountKey: "other-account"))
        let empty = schedule([]).examSchedule!
        XCTAssertEqual(ExamScheduleCachePolicy.resolve(empty, previous: previous, termID: previous.termID, accountKey: owner)?.items, [])
    }

    func testAcademicPostUsesFixedSchoolHostTokenAndNoStudentOverride() async throws {
        let transport = AcademicRequestRecorder()
        let api = SJDAPIClient(transport: transport)
        _ = try await api.academic(token: "synthetic-token", endpoint: .grades, parameters: ["semester": "2026-2027-1", "type": "1"])
        let request = await transport.request
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.host, "jwglweixin.bupt.edu.cn")
        XCTAssertEqual(request?.url?.path, "/bjyddx/student/termGPA")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "token"), "synthetic-token")
        XCTAssertFalse(request?.url?.absoluteString.contains("xs0101id") == true)
    }

    @MainActor
    func testGradeResetRejectsLateResponseAndClearsMemory() async {
        let client = DelayedGradeClient()
        let store = GradeQueryStore(client: client)
        let load = Task { await store.load(credentials: Credentials(account: "synthetic", password: "synthetic"), ownerRevision: 1, termID: nil, recordType: "1", force: false) }
        while !(await client.started) { await Task.yield() }
        store.reset()
        await client.finish()
        await load.value
        XCTAssertNil(store.snapshot)
        XCTAssertTrue(store.terms.isEmpty)
        XCTAssertFalse(store.isLoading)
    }

    #if os(macOS)
    @MainActor
    func testMacSyntheticGradeViewRendersForVisualReview() async throws {
        let model = AppLaunchConfiguration.makeModel()
        await model.loadGrades()
        let view = GradeQueryView(store: model.gradeStore)
            .environmentObject(model)
            .environment(\.appTheme, AppTheme(configuration: model.colorTheme))
            .padding(24)
            .frame(width: 900, height: 650, alignment: .topLeading)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 650)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "mac-synthetic-grades-native-view"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #endif
}

private actor AcademicRequestRecorder: SJDHTTPTransport {
    private(set) var request: URLRequest?
    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        self.request = request
        XCTAssertEqual(maximumBytes, SJDResponseLimits.maximumCurriculumBytes)
        return (Data(#"{"code":1,"data":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor DelayedGradeClient: GradeFetching {
    private var continuation: CheckedContinuation<GradeQueryResult, Never>?
    var started: Bool { continuation != nil }
    func fetch(credentials: Credentials, termID: String?, recordType: String) async throws -> GradeQueryResult {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        continuation?.resume(returning: .init(currentTermID: "2026-2027-1", terms: [],
            snapshot: .init(termID: "2026-2027-1", recordType: "1", fetchedAt: "", averageGradePoint: nil, items: [])))
        continuation = nil
    }
}
