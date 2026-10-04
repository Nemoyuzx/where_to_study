package com.nemoyu.wheretostudy.nativeapp

import java.util.Locale

internal data class CourseSubmissionCounts(val pending: Int?, val submitted: Int?)

internal object CourseDirectoryLogic {
    private enum class Submission { PENDING, SUBMITTED }
    private val pending = setOf("未提交", "not submitted", "nothing submitted", "no submissions have been made yet")
    private val submitted = setOf("已提交", "submitted", "submitted for grading")

    fun teachingCloudAssignments(courseID: String, items: List<AssignmentDeadlineItem>?): List<AssignmentDeadlineItem>? =
        items?.filter { it.courseID == courseID }

    fun teachingCloudCounts(courseID: String, items: List<AssignmentDeadlineItem>?): CourseSubmissionCounts =
        counts(teachingCloudAssignments(courseID, items)?.map { it.id to it.status })

    fun qmplusCounts(courseID: String, items: List<QmplusActivityItem>): CourseSubmissionCounts =
        counts(items.filter { it.courseID == courseID && it.kind == "assignment" }.map { it.id to it.status })

    private fun counts(items: List<Pair<String, String?>>?): CourseSubmissionCounts {
        var pendingCount = 0; var submittedCount = 0
        items.orEmpty().groupBy { it.first }.values.forEach { versions ->
            val evidence = versions.mapNotNull { (_, status) ->
                val normalized = status?.trim()?.lowercase(Locale.ROOT) ?: return@mapNotNull null
                when (normalized) {
                    in pending -> Submission.PENDING
                    in submitted -> Submission.SUBMITTED
                    else -> null
                }
            }.distinct()
            if (evidence.size == 1) when (evidence.single()) {
                Submission.PENDING -> pendingCount++
                Submission.SUBMITTED -> submittedCount++
            }
        }
        return CourseSubmissionCounts(pendingCount.takeIf { it > 0 }, submittedCount.takeIf { it > 0 })
    }
}
