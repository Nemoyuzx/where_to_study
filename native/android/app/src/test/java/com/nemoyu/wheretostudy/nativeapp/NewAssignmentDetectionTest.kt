package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NewAssignmentDetectionTest {
    private fun item(id: String, deadline: String = "2026-10-10") = NewAssignmentNotice(id, "Homework", "Course", deadline)
    @Test fun noticeRouteOpensTheExistingSourceSection() {
        assertEquals(InformationQueryMode.COURSES, NewAssignmentNoticeBatch(1, "qmplus", "qm", listOf(item("a"))).destination)
        assertEquals(InformationQueryMode.ASSIGNMENTS, NewAssignmentNoticeBatch(2, "ucloud", "cloud", listOf(item("b"))).destination)
    }
    @Test fun firstFetchAndCacheRestorationEstablishBaseline() {
        assertTrue(NewAssignmentDetection.additions(null, listOf(item("a")), false, 10).isEmpty())
        assertTrue(NewAssignmentDetection.additions(setOf("a"), listOf(item("b")), true, 10).isEmpty())
    }
    @Test fun newIdsAreDistinctAndDeadlineEditsDoNotAlert() {
        assertEquals(listOf(item("b")), NewAssignmentDetection.additions(setOf("a"),
            listOf(item("a", "2026-11-01"), item("b"), item("b")), false, 10))
    }
    @Test fun historicalIdsAndRepeatedPublicationDoNotAlert() {
        val history = setOf("a", "b")
        assertTrue(NewAssignmentDetection.additions(history, listOf(item("a")), false, 10).isEmpty())
        assertTrue(NewAssignmentDetection.additions(history, listOf(item("b")), false, 10).isEmpty())
    }
    @Test fun saturatedHistoryDoesNotEvictAndRealert() {
        assertTrue(NewAssignmentDetection.additions(setOf("a"), listOf(item("b")), false, 1).isEmpty())
    }
    @Test fun batchSurvivesReclaimAndOnlyMatchingDismissalConsumesIt() {
        val queue = NewAssignmentNoticeQueue()
        queue.add("ucloud", "first", listOf(item("a")))
        val displayed = queue.current()!!
        assertEquals(displayed, queue.current()) // recreated Activity reclaims the same session batch
        queue.add("qmplus", "qm", listOf(item("b")))
        queue.acknowledge(displayed.id)
        assertEquals("b", queue.current()!!.items.single().id)
        queue.acknowledge(displayed.id) // duplicate/late dismissal cannot consume the next batch
        assertEquals("b", queue.current()!!.items.single().id)
    }
    @Test fun accountResetDropsItsDisplayedBatchAndKeepsOtherSource() {
        val queue = NewAssignmentNoticeQueue()
        queue.add("ucloud", "old", listOf(item("old")))
        val oldID = queue.current()!!.id
        queue.add("qmplus", "qm", listOf(item("qm")))
        queue.retainIdentity("ucloud", "new")
        queue.add("ucloud", "new", listOf(item("new")))
        queue.acknowledge(oldID)
        assertEquals("qm", queue.current()!!.items.single().id)
        queue.clear("qmplus")
        assertEquals("new", queue.current()!!.items.single().id)
    }
    @Test fun largeBatchPreviewIsBounded() {
        assertEquals((0 until 8).map { it.toString() }, NewAssignmentNotice.preview((0 until 5000).map { item(it.toString()) }).map { it.id })
    }
    @Test fun qmplusIncludesEbuAssignmentsAndQuizzesButNotMarkReviewOrOtherTerms() {
        fun course(id: String, name: String, term: String = "current") = QmplusCourse(id, name, null,
            "https://qmplus.qmul.ac.uk/course/view.php?id=$id", null, null, term)
        fun activity(id: String, course: String = "ebu", kind: String = "assignment", title: String = "Homework") =
            QmplusActivityItem(id, course, title, kind, "https://qmplus.qmul.ac.uk/mod/$kind/view.php?id=$id",
                null, null, null, null, null, null, null, null)
        val snapshot = QmplusSnapshot("2026-10-06T00:00:00Z",
            listOf(course("ebu", "EBU Test"), course("other", "Other course"), course("old", "EBU Old", "other")),
            listOf(activity("assignment"), activity("quiz", kind = "quiz"),
                activity("review", title = "COURSEWORK MARK REVIEW REQUEST"),
                activity("other", course = "other"), activity("old", course = "old")), emptyList())
        assertEquals(listOf("ebu:assignment:assignment", "ebu:quiz:quiz"), NewAssignmentNotice.qmplus(snapshot).map { it.id })
    }
}
