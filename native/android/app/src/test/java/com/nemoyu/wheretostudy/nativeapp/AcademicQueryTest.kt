package com.nemoyu.wheretostudy.nativeapp

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.Calendar

class AcademicQueryTest {
    private val course = Course("ordinary", "Synthetic course", "Teacher", "Room", "1,2", listOf(1, 2),
        emptyList(), 1, 0, 1, "1-2", "08:00-09:35")
    private fun schedule(vararg exams: ExamArrangement) = ScheduleSnapshot("2026-2027-1", "2026-09-07", "fixture",
        listOf(course), ExamSchedule("2026-2027-1", CourseDeletionLogic.accountKey("fixture"), "fixture", "fresh", "", exams.toList()))
    private fun exam(date: String = "2026-09-07", start: String = "09:00", end: String = "11:00") =
        ExamArrangement("synthetic-exam", "Synthetic exam", date, start, end, "Exam room", timeText = "$date $start-$end")
    private fun day(value: String) = AcademicScheduleLogic.parseDate(value)!!

    @Test fun parsesOfficialGradeFieldsWithoutLosingZeroOrText() {
        val grades = AcademicResponseParser.grades(JSONObject("""{"code":1,"data":[{"pjxfjd":0,"achievement":[
          {"courseName":"Synthetic zero","fraction":0,"credit":0,"kcbh":"C1"},
          {"courseName":"Synthetic text","fraction":"通过","credit":"2.5"}]}]}"""), "2026-2027-1", "1")
        assertEquals("0", grades.averageGradePoint)
        assertEquals(listOf("0", "通过"), grades.items.map { it.score })
        assertEquals("0", grades.items[0].credits)
    }
    @Test fun successfulEmptyIsDistinctFromMalformedOrFailed() {
        assertTrue(AcademicResponseParser.grades(JSONObject("""{"code":"1","data":[]}"""), "", "").items.isEmpty())
        listOf("""{"code":0,"data":[]}""", """{"code":1}""", """{"code":1,"data":[{}]}""").forEach {
            assertThrows(ScheduleClientException::class.java) { AcademicResponseParser.grades(JSONObject(it), "", "1") }
        }
        assertThrows(ScheduleClientException::class.java) {
            AcademicResponseParser.exams(JSONObject("""{"code":1,"data":{}}"""), "term", "owner")
        }
        assertThrows(ScheduleClientException::class.java) {
            AcademicResponseParser.grades(JSONObject("""{"code":1,"data":[{"achievement":[{"courseName":"Synthetic","fraction":{}}]}]}"""), "", "1")
        }
    }
    @Test fun historicalSemesterAndStatusArePreservedWithStableSchoolRecordIdentity() {
        val payload = JSONObject("""{"code":1,"data":[{"achievement":[{"courseName":"Synthetic",
          "fraction":"通过","curSemesterName":"2025-2026-2","cjbs":"合成标识","cj0708id":"synthetic-record-id"}]}]}""")
        val first = AcademicResponseParser.grades(payload, "", "").items.single()
        payload.getJSONArray("data").getJSONObject(0).getJSONArray("achievement").getJSONObject(0).put("fraction", "良好")
        val updated = AcademicResponseParser.grades(payload, "", "").items.single()
        assertEquals("2025-2026-2", first.semesterName)
        assertEquals("合成标识", first.gradeStatus)
        assertEquals(first.id, updated.id)
    }
    @Test fun termCatalogComesOnlyFromSchoolAndPreservesCurrentID() {
        val terms = AcademicResponseParser.terms(JSONObject("""{"code":1,"data":[{"semesterId":"2026-2027-1"}]}"""),
            JSONObject("""{"code":1,"data":[{"semesterId":"2025-2026-2","semesterName":"Synthetic semester"}]}"""))
        assertEquals("2026-2027-1", terms.currentTermID)
        assertEquals(listOf("2025-2026-2"), terms.terms.map { it.id })
    }
    @Test fun officialExamTimesParseAndInvalidTimesStayPending() {
        val snapshot = AcademicResponseParser.exams(JSONObject("""{"code":1,"data":[
          {"courseName":"Synthetic exam","examinationPlace":"Confirmed room","examAddress":"Wrong room","time":"2026-12-21 9:00—11:00"},
          {"courseName":"Pending exam","time":"2026-02-30 26:00-27:00"}]}"""), "term", "owner")
        assertEquals("Confirmed room", snapshot.items[0].room)
        assertEquals("09:00", snapshot.items[0].startTime)
        assertEquals("2026-12-21", snapshot.items[0].date)
        assertEquals("", snapshot.items[1].date)
        assertEquals("", snapshot.items[1].startTime)
    }
    @Test fun conflictsAffectOnlyThatDateAndExactHalfOpenInterval() {
        val snapshot = schedule(exam())
        assertEquals(listOf("exam:synthetic-exam"), ScheduleLogic.courses(snapshot, day("2026-09-07")).map { it.id })
        assertEquals(listOf("ordinary"), ScheduleLogic.courses(snapshot, day("2026-09-14")).map { it.id })
        assertEquals(2, ScheduleLogic.courses(schedule(exam(start = "09:35", end = "11:00")), day("2026-09-07")).size)
        assertEquals(listOf(course), snapshot.courses)
    }
    @Test fun pendingTimesNeverHideCoursesAndUndatedExamsNeverAppearToday() {
        val snapshot = schedule(exam(start = "", end = ""), exam(date = "").copy(id = "undated"))
        val courses = ScheduleLogic.courses(snapshot, day("2026-09-07"))
        assertEquals(2, courses.size)
        assertNull(AcademicScheduleLogic.interval(courses.last()))
        assertEquals(setOf(0, 1), ScheduleLogic.busySlots(snapshot, day("2026-09-07")))
    }
    @Test fun examinationsOutsideTeachingWeeksStillAppearWithoutInventingWeekNumber() {
        val snapshot = schedule(exam(date = "2027-01-04"))
        assertEquals("exam", ScheduleLogic.courses(snapshot, day("2027-01-04")).single().eventKind)
        assertNull(ScheduleLogic.weekNumber(snapshot, day("2027-01-04")))
    }
    @Test fun failureFallbackRequiresOwnerAndTermAndEmptySuccessClearsExams() {
        val previous = schedule(exam())
        val failed = schedule().copy(examSchedule = schedule().examSchedule!!.copy(status = "failed"))
        assertEquals("stale", AcademicScheduleLogic.mergeFailure(failed, previous).examSchedule!!.status)
        assertEquals(1, AcademicScheduleLogic.mergeFailure(failed, previous).examSchedule!!.items.size)
        val otherOwner = previous.copy(examSchedule = previous.examSchedule!!.copy(accountKey = "other"))
        assertTrue(AcademicScheduleLogic.mergeFailure(failed, otherOwner).examSchedule!!.items.isEmpty())
        val otherTerm = previous.copy(examSchedule = previous.examSchedule!!.copy(termID = "other"))
        assertTrue(AcademicScheduleLogic.mergeFailure(failed, otherTerm).examSchedule!!.items.isEmpty())
        assertTrue(AcademicScheduleLogic.mergeFailure(schedule(), previous).examSchedule!!.items.isEmpty())
        assertNull(AcademicScheduleLogic.usableExams(previous, "other").examSchedule)
    }
    @Test fun codecPreservesNewExamsAndOldSchedulesStillDecode() {
        val original = schedule(exam())
        assertEquals(original, ScheduleJsonCodec.decode(ScheduleJsonCodec.encode(original)))
        val old = JSONObject(ScheduleJsonCodec.encode(original)).apply { remove("exam_schedule") }.toString()
        assertNull(ScheduleJsonCodec.decode(old).examSchedule)
    }
    @Test fun deletionNeverDeletesAnExam() {
        val snapshot = schedule(exam())
        val deletion = CourseDeletionLogic.create("fixture", snapshot, course, day("2026-09-07"), CourseDeletionScope.WHOLE_COURSE)
        val filtered = CourseDeletionLogic.apply(snapshot, "fixture", listOf(deletion))
        assertEquals(1, ScheduleLogic.courses(filtered, day("2026-09-07")).size)
        assertFalse(CourseDeletionLogic.matchesCourse(deletion, ScheduleLogic.courses(filtered, day("2026-09-07")).single()))
    }
    @Test fun calendarAndWidgetUseExactExamTimesAndPendingAllDayDates() {
        val snapshot = schedule(exam(start = "09:07", end = "10:43"))
        val drafts = ScheduleCalendarLogic.expand(snapshot)
        assertEquals(2, drafts.size)
        val timed = drafts.first { it.title.startsWith("考试") }
        val start = day("2026-09-07").apply { set(Calendar.HOUR_OF_DAY, 9); set(Calendar.MINUTE, 7) }
        assertEquals(start.timeInMillis, timed.startsAtMillis)
        assertEquals(96 * 60_000L, timed.endsAtMillis - timed.startsAtMillis)
        val widget = TodayCourseWidgetLogic.content(snapshot, start.timeInMillis)
        assertEquals(WidgetCoursePhase.IN_PROGRESS, widget.highlightedCoursePhase)
        val pending = ScheduleCalendarLogic.expand(schedule(exam(start = "", end = ""))).first { it.allDay }
        assertEquals("UTC", pending.timeZoneID)
        assertEquals(86_400_000L, pending.endsAtMillis - pending.startsAtMillis)
    }
    @Test fun axisExpandsForExamsAndPendingTimesDoNotCreateBlocks() {
        assertEquals(8..22, CalendarTimelineLogic.hourBounds(listOf(course)))
        val courses = ScheduleLogic.courses(schedule(exam(start = "06:30", end = "23:30")), day("2026-09-07"))
        assertEquals(6..24, CalendarTimelineLogic.hourBounds(courses))
    }
}
