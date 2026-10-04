package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.*
import org.junit.Test

class CourseDirectoryLogicTest {
    @Test fun countsUseOnlyExplicitSubmissionEvidenceAndNeverProduceZeroBadges() {
        val statuses = listOf(null, "unknown", "complete", "finished", "已完成", "已批改", "已驳回", "0")
        val unknown = statuses.mapIndexed { index, status -> task("$index", "one", status) }
        assertEquals(CourseSubmissionCounts(null, null), CourseDirectoryLogic.teachingCloudCounts("one", unknown))
        assertEquals(CourseSubmissionCounts(null, null), CourseDirectoryLogic.teachingCloudCounts("one", null))
        assertEquals(CourseSubmissionCounts(null, null), CourseDirectoryLogic.teachingCloudCounts("one", emptyList()))
        val explicit = listOf("未提交", " NOT SUBMITTED ", "nothing submitted", "no submissions have been made yet",
            "已提交", "Submitted", "submitted for grading").mapIndexed { index, status -> task("known-$index", "one", status) }
        assertEquals(CourseSubmissionCounts(4, 3), CourseDirectoryLogic.teachingCloudCounts("one", explicit + unknown))
    }

    @Test fun courseIdentityIsRealIDNotNameAndConflictingDuplicateVersionsDoNotInventBadges() {
        val own = task("own", "one", "已提交")
        val sameNameOtherCourse = task("other", "two", "未提交")
        val noID = task("missing", null, "未提交")
        assertEquals(listOf(own), CourseDirectoryLogic.teachingCloudAssignments("one", listOf(own, sameNameOtherCourse, noID)))
        assertEquals(CourseSubmissionCounts(null, 1), CourseDirectoryLogic.teachingCloudCounts("one", listOf(own, own)))
        assertEquals(CourseSubmissionCounts(null, null), CourseDirectoryLogic.teachingCloudCounts("one",
            listOf(own, own.copy(status = "未提交"))))
    }

    @Test fun quizCompletionNeverCountsAsSubmittedAssignments() {
        val base = QmplusActivityItem("1", "course", "Raw", "assignment", "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=1",
            null, null, null, null, null, "Submitted for grading", "available", "")
        assertEquals(CourseSubmissionCounts(null, 1), CourseDirectoryLogic.qmplusCounts("course", listOf(base)))
        assertEquals(CourseSubmissionCounts(null, null), CourseDirectoryLogic.qmplusCounts("course",
            listOf(base.copy(kind = "quiz", status = "submitted"), base.copy(id = "2", status = "finished"))))
    }

    private fun task(id: String, courseID: String?, status: String?) =
        AssignmentDeadlineItem(id, "Raw assignment", "Identical course name", "2026-10-03 12:00:00", status, courseID)
}
