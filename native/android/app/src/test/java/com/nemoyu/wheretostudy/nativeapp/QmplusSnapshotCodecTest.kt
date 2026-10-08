package com.nemoyu.wheretostudy.nativeapp

import java.nio.charset.StandardCharsets
import java.util.TimeZone
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class QmplusSnapshotCodecTest {
    @Test fun restoredSnapshotFooterTimeKeepsItsOriginalMinuteUntilAnotherSnapshotArrives() {
        val cached = sample().copy(fetchedAt = "2026-10-07T15:59:00Z")
        val restored = QmplusSnapshotCodec.ebuOnly(QmplusSnapshotCodec.decode(QmplusSnapshotCodec.encode(cached)))
        assertEquals("2026-10-07 23:59", QmplusActivityPresentation.shanghaiTime(restored.fetchedAt))
        val refreshed = restored.copy(fetchedAt = "2026-10-07T16:01:00.123Z")
        assertEquals("2026-10-08 00:01", QmplusActivityPresentation.shanghaiTime(refreshed.fetchedAt))
        assertEquals(cached.fetchedAt, restored.fetchedAt)
        assertNull(QmplusActivityPresentation.shanghaiTime("invalid"))
    }

    @Test fun api24UTCParserPreservesFractionsAndShanghaiDayBoundary() {
        val previousZone = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
            val base = QmplusSnapshotCodec.parseUTCDate("2024-02-29T16:00:00Z")!!
            assertEquals(100L, QmplusSnapshotCodec.parseUTCDate("2024-02-29T16:00:00.1Z")!!.time - base.time)
            assertEquals(123L, QmplusSnapshotCodec.parseUTCDate("2024-02-29T16:00:00.123456789Z")!!.time - base.time)
            val display = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.US).apply {
                timeZone = TimeZone.getTimeZone("Asia/Shanghai")
            }
            assertEquals("2024-03-01 00:00", display.format(base))
        } finally { TimeZone.setDefault(previousZone) }
    }

    @Test fun api24UTCParserRejectsInvalidDatesTimesOffsetsAndTrailingText() {
        listOf("2023-02-29T12:00:00Z", "2024-02-30T12:00:00Z", "2024-02-29T24:00:00Z",
            "2024-02-29T12:60:00Z", "2024-02-29T12:00:00+08:00", "2024-02-29T12:00:00",
            "2024-02-29T12:00:00.1234567890Z", "2024-02-29T12:00:00Z trailing").forEach {
            assertNull(it, QmplusSnapshotCodec.parseUTCDate(it))
        }
    }

    @Test fun api24CacheDateValidationPreservesExistingDeadlineFormsAndRejectsInvalidLeapDays() {
        listOf("2024-02-29 12:34", "2024-02-29T12:34:56.123Z", "2024-02-29T12:34:56+08:00")
            .forEach { assertTrue(it, CourseDTOCacheStore.validDeadlineDate(it)) }
        listOf("2023-02-29 12:34", "2024-02-30 12:34", "2024-02-29 24:00", "2024-02-29 12:34 trailing")
            .forEach { assertFalse(it, CourseDTOCacheStore.validDeadlineDate(it)) }
    }

    @Test fun injectionIsLimitedToExactHTTPSBusinessPagesAndSnapshotLinksCannotCarrySessionFields() {
        assertTrue(QmplusPolicy.isBusinessPage(QmplusPolicy.START_URL))
        assertTrue(QmplusPolicy.isBusinessPage("https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=7"))
        listOf("https://login.microsoftonline.com/my/", "https://qmplus.qmul.ac.uk.evil.example/my/",
            "https://qmplus.qmul.ac.uk:444/my/", "http://qmplus.qmul.ac.uk/my/",
            "https://name@qmplus.qmul.ac.uk/my/", "https://qmplus.qmul.ac.uk/login/index.php",
            "https://qmplus.qmul.ac.uk/lib/ajax/service.php", "https://qmplus.qmul.ac.uk/%6dy/")
            .forEach { assertFalse(it, QmplusPolicy.isBusinessPage(it)) }
        assertTrue(QmplusPolicy.allowsHTTPSNavigation("https://login.microsoftonline.com/common/oauth2/authorize"))
        assertFalse(QmplusPolicy.allowsHTTPSNavigation("file:///data/data/private"))
        assertFalse(QmplusPolicy.isBusinessPage("https://qmplus.qmul.ac.uk/calendar/view.php"))
        assertFalse(QmplusPolicy.isCourseURL("https://qmplus.qmul.ac.uk/course/view.php?id=1&sesskey=secret"))
        assertFalse(QmplusPolicy.isActivityURL("https://qmplus.qmul.ac.uk/mod/quiz/attempt.php?id=1", "quiz"))
    }

    @Test fun roundTripPreservesUTCNullableTimesRawNamesUnknownTermsAndReadonlyKinds() {
        val previousZone = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("Europe/London"))
            val expected = sample()
            val actual = QmplusSnapshotCodec.decode(QmplusSnapshotCodec.encode(expected))
            assertEquals(expected, actual)
            assertEquals("设置", actual.courses.single().name)
            assertEquals("unknown", actual.courses.single().currentTermStatus)
            assertNull(actual.activities.single().dueAt)
            assertEquals("2026-03-29T01:30:00.000Z", actual.activities.single().opensAt)
            assertEquals(2700L, actual.activities.single().timeLimitSeconds)
        } finally { TimeZone.setDefault(previousZone) }
    }

    @Test fun arbitraryWebpageFieldsAreNotPersistedAndFailedSnapshotsCannotReplaceCache() {
        val root = JSONObject(String(QmplusSnapshotCodec.encode(sample()), StandardCharsets.UTF_8))
            .put("password", "not-a-real-secret").put("sesskey", "synthetic-session")
        val sanitized = String(QmplusSnapshotCodec.encode(QmplusSnapshotCodec.decode(root.toString().toByteArray())), StandardCharsets.UTF_8)
        assertFalse(sanitized.contains("not-a-real-secret")); assertFalse(sanitized.contains("synthetic-session"))
        root.put("ok", false)
        assertThrows(IllegalArgumentException::class.java) { QmplusSnapshotCodec.decode(root.toString().toByteArray()) }
    }

    @Test fun invalidTimeForeignActivityAndOverLimitPayloadAreRejected() {
        fun changed(key: String, value: Any): ByteArray {
            val root = JSONObject(String(QmplusSnapshotCodec.encode(sample())))
            root.getJSONArray("activities").getJSONObject(0).put(key, value)
            return root.toString().toByteArray()
        }
        listOf("2026-02-30T12:00:00Z", "2026-03-29T01:30:00", "2026-03-29T01:30:00+01:00")
            .forEach { value -> assertThrows(IllegalArgumentException::class.java) { QmplusSnapshotCodec.decode(changed("opens_at", value)) } }
        assertThrows(IllegalArgumentException::class.java) { QmplusSnapshotCodec.decode(changed("course_id", "other")) }
        assertThrows(IllegalArgumentException::class.java) { QmplusSnapshotCodec.decode(changed("kind", "attempt")) }
        assertThrows(IllegalArgumentException::class.java) { QmplusSnapshotCodec.decode(ByteArray(QmplusPolicy.MAXIMUM_SNAPSHOT_BYTES + 1)) }
        assertThrows(IllegalArgumentException::class.java) { QmplusSnapshotCodec.decode(("[".repeat(13) + "]".repeat(13)).toByteArray()) }
    }

    @Test fun courseAndActivityIDsMustMatchTheirCanonicalOfficialURLs() {
        fun changed(array: String, key: String, value: String): ByteArray {
            val root = JSONObject(String(QmplusSnapshotCodec.encode(sample()), StandardCharsets.UTF_8))
            root.getJSONArray(array).getJSONObject(0).put(key, value)
            return root.toString().toByteArray(StandardCharsets.UTF_8)
        }
        listOf("0", "other", "99").forEach { id ->
            assertThrows(IllegalArgumentException::class.java) {
                QmplusSnapshotCodec.decode(changed("courses", "id", id))
            }
            assertThrows(IllegalArgumentException::class.java) {
                QmplusSnapshotCodec.decode(changed("activities", "id", id))
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            QmplusSnapshotCodec.decode(changed("courses", "url", "https://qmplus.qmul.ac.uk/course/view.php?id=99"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            QmplusSnapshotCodec.decode(changed("activities", "url", "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=99"))
        }
    }

    @Test fun activityIDsAreGloballyUniqueAcrossKindsIncludingPartialCacheMerges() {
        val previous = sample()
        val assignment = previous.activities.single().copy(kind = "assignment",
            url = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=2")
        val duplicate = previous.copy(activities = previous.activities + assignment)
        assertThrows(IllegalArgumentException::class.java) {
            QmplusSnapshotCodec.decode(QmplusSnapshotCodec.encode(duplicate))
        }
        val incoming = previous.copy(activities = listOf(assignment), partial = true)
        val merged = QmplusSnapshotCodec.preservingKnownActivities(incoming, previous)
        assertEquals(listOf(assignment), merged.activities)
        assertEquals(merged, QmplusSnapshotCodec.decode(QmplusSnapshotCodec.encode(merged)))
    }

    @Test fun partialSyncKeepsKnownActivitiesWhereasVerifiedFullSyncCanReplaceTheCatalog() {
        val old = sample()
        val partial = old.copy(activities = emptyList(), partial = true, warnings = listOf("QM_DETAIL_PARTIAL"))
        val merged = QmplusSnapshotCodec.preservingKnownActivities(partial, old)
        assertEquals(old.activities, merged.activities)
        assertTrue(merged.partial); assertTrue("QM_PREVIOUS_ACTIVITIES_RETAINED" in merged.warnings)
        assertEquals(emptyList<QmplusActivityItem>(), QmplusSnapshotCodec.preservingKnownActivities(partial.copy(partial = false), old).activities)
    }

    @Test fun primaryDestinationsPartitionPublicQueriesAndKeepAllPrivateFunctions() {
        assertEquals(listOf(InformationQueryMode.SHUTTLE, InformationQueryMode.IMPORTANT_EVENTS), InformationQueryMode.queryModes)
        assertEquals(InformationQueryMode.COURSES, InformationQueryMode.courseModes.first())
        assertTrue(InformationQueryMode.courseModes.containsAll(listOf(InformationQueryMode.GRADES, InformationQueryMode.EXAMS,
            InformationQueryMode.ASSIGNMENTS)))
        assertEquals(4, InformationQueryMode.courseModes.size)
        assertFalse(InformationQueryMode.QMPLUS in InformationQueryMode.courseModes)
        assertTrue(InformationQueryMode.queryModes.intersect(InformationQueryMode.courseModes.toSet()).isEmpty())
    }

    private fun sample() = QmplusSnapshot("2026-03-29T01:30:00.000Z", listOf(QmplusCourse("1", "设置", null,
        "https://qmplus.qmul.ac.uk/course/view.php?id=1", null, null, "unknown")),
        listOf(QmplusActivityItem("2", "1", "Raw quiz", "quiz", "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=2",
            null, "2026-03-29T01:30:00.000Z", null, null, 2700, "unknown", "restricted", "Time limit: 45 minutes")), emptyList())

    @Test fun oldSnapshotsExposeOnlyEbuCoursesAndTheirActivitiesWithoutChangingRawNames() {
        val original = sample()
        val ebu = original.courses.single().copy(name = "EBU5303 设置")
        val secondEbu = ebu.copy(id = "4", name = "ebu5405 Raw name", url = "https://qmplus.qmul.ac.uk/course/view.php?id=4")
        val other = ebu.copy(id = "3", name = "Other department", url = "https://qmplus.qmul.ac.uk/course/view.php?id=3")
        val unrelated = original.activities.single().copy(id = "5", courseID = "3", url = "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=5")
        val decoded = QmplusSnapshotCodec.decode(QmplusSnapshotCodec.encode(original.copy(
            courses = listOf(ebu, other, secondEbu), activities = original.activities + unrelated)))
        val visible = QmplusSnapshotCodec.ebuOnly(decoded)
        assertEquals(listOf("1", "4"), visible.courses.map { it.id })
        assertEquals(listOf("2"), visible.activities.map { it.id })
        assertEquals("EBU5303 设置", visible.courses.first().name)
        assertEquals("unknown", visible.courses.first().currentTermStatus)
        assertEquals(3, decoded.courses.size)
        assertTrue(QmplusSnapshotCodec.ebuOnly(original).courses.isEmpty())
    }

    @Test fun assessmentTimeRowsContainOnlyKnownFieldsForTheirActualKind() {
        val item = sample().activities.single()
        val dates = item.copy(dueAt = "2026-10-03T10:00:00Z", cutoffAt = "2026-10-04T10:00:00Z",
            closesAt = "2026-10-03T12:00:00Z")
        assertEquals(listOf("opens_at", "closes_at"), QmplusActivityPresentation.timeFields(dates).map { it.first })
        assertEquals(listOf("due_at", "cutoff_at"), QmplusActivityPresentation.timeFields(dates.copy(kind = "assignment")).map { it.first })
        assertTrue(QmplusActivityPresentation.timeFields(item.copy(opensAt = null, closesAt = null)).isEmpty())
    }

    @Test fun courseDetailsUseShanghaiTimeAndKeepMissingPrimaryTimesVisibleLikeIos() {
        val item = sample().activities.single()
        assertEquals("2026-10-04 02:30", QmplusActivityPresentation.shanghaiTime("2026-10-03T18:30:00Z"))
        assertEquals("2026-01-01 08:00", QmplusActivityPresentation.shanghaiTime("2026-01-01T00:00:00.123Z"))
        assertNull(QmplusActivityPresentation.shanghaiTime(null))
        assertNull(QmplusActivityPresentation.shanghaiTime("2026-02-30T12:00:00Z"))
        assertEquals(listOf("开放时间" to null, "关闭时间" to null),
            QmplusActivityPresentation.displayTimeFields(item.copy(opensAt = null, closesAt = null)))
        assertEquals(listOf("截止时间" to null), QmplusActivityPresentation.displayTimeFields(
            item.copy(kind = "assignment", dueAt = null, cutoffAt = null)))
        assertEquals(listOf("截止时间", "最终提交时间"), QmplusActivityPresentation.displayTimeFields(
            item.copy(kind = "assignment", cutoffAt = "2026-10-03T18:30:00Z")).map { it.first })
    }

    @Test fun unknownTermCoursesRemainInTheDefaultCourseListAndOnlyConfirmedOtherTermsAreHidden() {
        val base = sample().courses.single()
        val courses = listOf(base.copy(id = "current", currentTermStatus = "current"),
            base.copy(id = "unknown", currentTermStatus = "unknown"),
            base.copy(id = "other", currentTermStatus = "other"))
        assertEquals(listOf("current", "unknown"), QmplusActivityPresentation.currentCourses(courses).map { it.id })
        assertEquals(courses.map { it.currentTermStatus }, listOf("current", "unknown", "other"))
    }

    @Test fun onlyTheExactAdministrativeAssignmentTitleIsExcludedWithConservativeNormalization() {
        val excluded = listOf("COURSEWORK MARK REVIEW REQUEST", " coursework\tmark  review\nrequest ",
            "Coursework-Mark/Review_Request:Form", "COURSEWORK\u0085MARK\u202FREVIEW\u00A0REQUEST",
            "COURSEWORK\u2010MARK\u2011REVIEW\u2012REQUEST\u2015FORM", "COURSEWORK\u2212MARK REVIEW REQUEST",
            "\uFEFFＣＯＵＲＳＥＷＯＲＫ　ＭＡＲＫ　ＲＥＶＩＥＷ　ＲＥＱＵＥＳＴ　ＦＯＲＭ\uFEFF")
        excluded.forEach { title ->
            assertTrue(title, QmplusCourseworkPolicy.isMarkReviewRequest("assignment", title))
            assertFalse(title, QmplusCourseworkPolicy.isMarkReviewRequest("quiz", title))
        }
        listOf("Essay: Coursework Mark Review Request", "Coursework Mark Review Request Essay",
            "Coursework Mark Review Request Formative Essay", "Coursework Mark Review Requests",
            "Coursework Mark Review", "Peer review assignment", "Feedback report",
            "Coursework Mark Review Request (Form)", "Coursework.Mark.Review.Request").forEach { title ->
            assertFalse(title, QmplusCourseworkPolicy.isMarkReviewRequest("assignment", title))
        }
    }

    @Test fun decodedAndLegacyDisplayedSnapshotsRetainRealUndatedAssignmentsAndSameNamedQuiz() {
        val base = sample()
        val assignment = base.activities.single().copy(kind = "assignment", title = "Real undated assignment",
            url = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=2", opensAt = null, timeLimitSeconds = null)
        val review = assignment.copy(id = "3", title = "COURSEWORK MARK REVIEW REQUEST",
            url = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=3")
        val sameNamedQuiz = base.activities.single().copy(id = "4", title = review.title,
            url = "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=4")
        val legacy = base.copy(courses = listOf(base.courses.single().copy(name = "EBU Synthetic")),
            activities = listOf(review, assignment, sameNamedQuiz))
        val decoded = QmplusSnapshotCodec.decode(QmplusSnapshotCodec.encode(legacy))
        assertEquals(listOf("2", "4"), decoded.activities.map { it.id })
        assertEquals(listOf("2", "4"), QmplusSnapshotCodec.ebuOnly(legacy).activities.map { it.id })
        assertNull(decoded.activities.first().dueAt)
        assertEquals(review.title, decoded.activities.last().title)
        assertEquals(legacy.fetchedAt, decoded.fetchedAt)
    }

    @Test fun partialCacheMergesCannotRestoreAdministrativeRequestsFromEitherSnapshot() {
        val base = sample()
        val review = base.activities.single().copy(id = "3", title = "Coursework Mark Review Request Form",
            kind = "assignment", url = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=3")
        val previous = base.copy(activities = listOf(review) + base.activities)
        val partial = base.copy(activities = listOf(review), partial = true)
        val merged = QmplusSnapshotCodec.preservingKnownActivities(partial, previous)
        assertEquals(base.activities, merged.activities)
        assertTrue(merged.partial)
        assertTrue("QM_PREVIOUS_ACTIVITIES_RETAINED" in merged.warnings)
        assertTrue(QmplusSnapshotCodec.preservingKnownActivities(partial, null).activities.isEmpty())
        assertTrue(QmplusSnapshotCodec.preservingKnownActivities(partial.copy(partial = false), previous).activities.isEmpty())
    }

    @Test fun excludedTitlesStillRequireValidDTOFieldsUniqueIDsAndWarningsBeforeFiltering() {
        val base = sample()
        val review = base.activities.single().copy(title = "COURSEWORK MARK REVIEW REQUEST", kind = "assignment",
            url = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=2")
        fun changed(key: String, value: Any): ByteArray {
            val root = JSONObject(String(QmplusSnapshotCodec.encode(base.copy(activities = listOf(review)))))
            root.getJSONArray("activities").getJSONObject(0).put(key, value)
            return root.toString().toByteArray(StandardCharsets.UTF_8)
        }
        assertThrows(IllegalArgumentException::class.java) { QmplusSnapshotCodec.decode(changed("course_id", "999")) }
        assertThrows(IllegalArgumentException::class.java) { QmplusSnapshotCodec.decode(changed("due_at", "invalid")) }
        assertThrows(IllegalArgumentException::class.java) {
            QmplusSnapshotCodec.decode(changed("url", "https://evil.example/mod/assign/view.php?id=2"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            QmplusSnapshotCodec.decode(QmplusSnapshotCodec.encode(base.copy(activities = listOf(review, review))))
        }
        assertThrows(IllegalArgumentException::class.java) {
            QmplusSnapshotCodec.decode(QmplusSnapshotCodec.encode(base.copy(activities = listOf(review), warnings = listOf("invalid-warning"))))
        }
    }
}
