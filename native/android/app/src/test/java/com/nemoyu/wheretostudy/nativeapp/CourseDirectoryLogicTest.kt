package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.*
import org.junit.Test

class CourseDirectoryLogicTest {
    @Test fun sameCurrentCourseNameMergesOnlyPresentationAndKeepsAllTeachersAndSourceAssignments() {
        val first = TeachingCloudCourse("site-2", "  Algorithms  ", " Teacher A ", listOf(" Teacher A ", "Teacher B"))
        val second = TeachingCloudCourse("site-1", "Algorithms", "Teacher C", listOf("Teacher B", "Teacher C"))
        val other = TeachingCloudCourse("site-3", "algorithms", "Teacher D")
        val source = listOf(first, second, other)
        val groups = CourseDirectoryLogic.teachingCloudGroups(source)
        assertEquals(2, groups.size)
        val merged = groups.first()
        assertEquals("site-1", merged.id)
        assertEquals("Algorithms", merged.name)
        assertEquals(setOf("site-1", "site-2"), merged.courseIDs)
        assertEquals(listOf("Teacher A", "Teacher B", "Teacher C"), merged.teacherNames)
        val a = task("shared-assignment-id", "site-1", "已提交")
        val b = task("shared-assignment-id", "site-2", "未提交")
        val outside = task("outside", "site-3", "未提交")
        assertEquals(listOf(a, b), CourseDirectoryLogic.teachingCloudAssignments(merged, listOf(a, b, outside)))
        assertEquals(CourseSubmissionCounts(1, 1), CourseDirectoryLogic.teachingCloudCounts(merged, listOf(a, b, b, outside)))
        assertEquals(merged, CourseDirectoryLogic.teachingCloudGroupForKey(source, "teaching-cloud.course.site-2"))
        assertEquals("  Algorithms  ", first.name)
        assertEquals(listOf(" Teacher A ", "Teacher B"), first.teacherNames)
        assertEquals(3, source.size)
    }

    @Test fun unnamedCoursesStaySeparateAndGroupingDoesNotCollapseInternalSpacesOrCase() {
        val courses = listOf(TeachingCloudCourse("1", null, null), TeachingCloudCourse("2", " ", null),
            TeachingCloudCourse("3", "Data Science", null), TeachingCloudCourse("4", "Data  Science", null),
            TeachingCloudCourse("5", "data Science", null))
        assertEquals(5, CourseDirectoryLogic.teachingCloudGroups(courses).size)
        val group = CourseDirectoryLogic.teachingCloudGroups(courses).first()
        assertNull(CourseDirectoryLogic.teachingCloudAssignments(group, null))
        assertEquals(CourseSubmissionCounts(null, null), CourseDirectoryLogic.teachingCloudCounts(group, null))
    }

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

    @Test fun legacyAdministrativeRequestsNeverInflatePendingOrSubmittedCourseworkCounts() {
        val real = QmplusActivityItem("1", "course", "Real undated assignment", "assignment",
            "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=1", null, null, null, null, null,
            "submitted", "available", "")
        val review = real.copy(id = "2", title = "ＣＯＵＲＳＥＷＯＲＫ　ＭＡＲＫ　ＲＥＶＩＥＷ　ＲＥＱＵＥＳＴ",
            url = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=2")
        val administrative = listOf(review.copy(status = "not submitted"),
            review.copy(id = "3", title = "Coursework-Mark/Review_Request:Form", status = "submitted",
                url = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=3"))
        val essay = real.copy(id = "4", title = "Coursework Mark Review Request Essay", status = "not submitted",
            url = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=4")
        val quiz = real.copy(id = "5", title = review.title, kind = "quiz", status = "submitted",
            url = "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=5")
        assertEquals(CourseSubmissionCounts(1, 1), CourseDirectoryLogic.qmplusCounts("course",
            listOf(real, essay, quiz) + administrative))
        assertEquals(CourseSubmissionCounts(null, null), CourseDirectoryLogic.qmplusCounts("course", administrative))
    }

    private fun task(id: String, courseID: String?, status: String?) =
        AssignmentDeadlineItem(id, "Raw assignment", "Identical course name", "2026-10-03 12:00:00", status, courseID)
}
