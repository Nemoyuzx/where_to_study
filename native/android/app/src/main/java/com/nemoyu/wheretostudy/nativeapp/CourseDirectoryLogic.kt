package com.nemoyu.wheretostudy.nativeapp

import java.util.Locale

internal data class CourseSubmissionCounts(val pending: Int?, val submitted: Int?)
internal data class TeachingCloudCourseGroup(val id: String, val name: String?,
    val teacherNames: List<String>, val courseIDs: Set<String>)

internal object CourseDirectoryLogic {
    private enum class Submission { PENDING, SUBMITTED }
    private val pending = setOf("未提交", "not submitted", "nothing submitted", "no submissions have been made yet")
    private val submitted = setOf("已提交", "submitted", "submitted for grading")

    private fun submission(status: String?): Submission? = when (status?.trim()?.lowercase(Locale.ROOT)) {
        in pending -> Submission.PENDING
        in submitted -> Submission.SUBMITTED
        else -> null
    }

    fun isClearlyPending(statuses: List<String?>): Boolean =
        statuses.mapNotNull(::submission).distinct() == listOf(Submission.PENDING)

    // Input is the current-term directory. This projection never changes source IDs or cached DTOs.
    fun teachingCloudGroups(courses: List<TeachingCloudCourse>): List<TeachingCloudCourseGroup> =
        courses.groupBy { course -> course.name?.trim()?.takeIf { it.isNotEmpty() }?.let { "name:$it" } ?: "id:${course.id}" }
            .values.map { members ->
                val ids = members.map { it.id }.toSortedSet()
                TeachingCloudCourseGroup(ids.first(), members.first().name?.trim()?.takeIf { it.isNotEmpty() },
                    members.flatMap { it.teacherNames + listOfNotNull(it.teacher) }.map(String::trim)
                        .filter(String::isNotEmpty).distinct(), ids)
            }

    fun teachingCloudGroupForKey(courses: List<TeachingCloudCourse>, key: String): TeachingCloudCourseGroup? =
        teachingCloudGroups(courses).firstOrNull { group -> group.courseIDs.any { "teaching-cloud.course.$it" == key } }

    fun teachingCloudAssignments(course: TeachingCloudCourseGroup, items: List<AssignmentDeadlineItem>?): List<AssignmentDeadlineItem>? =
        items?.filter { it.courseID in course.courseIDs }

    fun teachingCloudCounts(course: TeachingCloudCourseGroup, items: List<AssignmentDeadlineItem>?): CourseSubmissionCounts =
        counts(teachingCloudAssignments(course, items)?.map { (it.courseID to it.id) to it.status })

    fun teachingCloudAssignments(courseID: String, items: List<AssignmentDeadlineItem>?): List<AssignmentDeadlineItem>? =
        items?.filter { it.courseID == courseID }

    fun teachingCloudCounts(courseID: String, items: List<AssignmentDeadlineItem>?): CourseSubmissionCounts =
        counts(teachingCloudAssignments(courseID, items)?.map { it.id to it.status })

    fun qmplusCounts(courseID: String, items: List<QmplusActivityItem>): CourseSubmissionCounts =
        counts(QmplusCourseworkPolicy.activities(items)
            .filter { it.courseID == courseID && it.kind == "assignment" }.map { it.id to it.status })

    private fun <Key> counts(items: List<Pair<Key, String?>>?): CourseSubmissionCounts {
        var pendingCount = 0; var submittedCount = 0
        items.orEmpty().groupBy { it.first }.values.forEach { versions ->
            val evidence = versions.mapNotNull { (_, status) -> submission(status) }.distinct()
            if (evidence.size == 1) when (evidence.single()) {
                Submission.PENDING -> pendingCount++
                Submission.SUBMITTED -> submittedCount++
            }
        }
        return CourseSubmissionCounts(pendingCount.takeIf { it > 0 }, submittedCount.takeIf { it > 0 })
    }
}
