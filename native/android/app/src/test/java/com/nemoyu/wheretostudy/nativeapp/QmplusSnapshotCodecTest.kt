package com.nemoyu.wheretostudy.nativeapp

import java.nio.charset.StandardCharsets
import java.util.TimeZone
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class QmplusSnapshotCodecTest {
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
}
