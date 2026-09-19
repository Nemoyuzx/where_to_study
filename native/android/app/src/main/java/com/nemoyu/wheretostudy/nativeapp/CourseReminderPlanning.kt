package com.nemoyu.wheretostudy.nativeapp

import java.nio.charset.StandardCharsets
import java.security.MessageDigest

internal enum class CourseNotificationKind { DAILY_SUMMARY, PRE_CLASS }

internal data class CourseReminderDraft(
    val key: String,
    val occurrenceKey: String,
    val title: String,
    val location: String,
    val startsAtMillis: Long,
    val fireAtMillis: Long,
    val expiresAtMillis: Long,
    val leadMinutes: Int,
)

/** Pure planning shared by foreground reconciliation and background delivery. */
internal object CourseReminderPlanning {
    val defaultOffsets = listOf(10)
    const val maximumReminders = 5
    const val maximumLeadMinutes = 1440

    fun validateOffsets(values: List<Int>): List<Int> {
        require(values.size in 1..maximumReminders && values.all { it in 1..maximumLeadMinutes } && values.toSet().size == values.size) {
            "请设置 1–5 次不重复的提醒，每次提前 1–1440 分钟。"
        }
        return values.sortedDescending()
    }

    fun parseInput(values: List<String>): List<Int> = validateOffsets(values.map { value ->
        val text = value.trim()
        require(text.matches(Regex("[0-9]{1,4}"))) { "请设置 1–5 次提醒，每次提前 1–1440 分钟。" }
        text.toInt()
    })

    fun decodeStored(value: String?): List<Int> = runCatching {
        parseInput(requireNotNull(value).split(','))
    }.getOrDefault(defaultOffsets)

    fun expand(schedule: ScheduleSnapshot?, accountKey: String, offsets: List<Int>): List<CourseReminderDraft> {
        if (schedule == null || accountKey.isBlank()) return emptyList()
        val normalized = validateOffsets(offsets)
        return ScheduleCalendarLogic.expand(schedule).filterNot { it.allDay }.flatMap { event ->
            val occurrenceKey = digest("$accountKey\u001f${event.marker}\u001f${event.startsAtMillis}")
            normalized.mapIndexed { index, lead ->
                val fireAt = event.startsAtMillis - lead * 60_000L
                val expiry = normalized.getOrNull(index + 1)?.let { event.startsAtMillis - it * 60_000L }
                    ?: event.startsAtMillis
                CourseReminderDraft(
                    key = digest("$occurrenceKey\u001f$lead"), occurrenceKey = occurrenceKey,
                    title = event.title, location = event.location, startsAtMillis = event.startsAtMillis,
                    fireAtMillis = fireAt, expiresAtMillis = expiry, leadMinutes = lead,
                )
            }
        }.distinctBy { it.key }.sortedWith(compareBy(CourseReminderDraft::fireAtMillis, CourseReminderDraft::key))
    }

    fun nextBatch(drafts: List<CourseReminderDraft>, nowMillis: Long, delivered: Set<String>): List<CourseReminderDraft> {
        val future = drafts.filter { it.fireAtMillis > nowMillis && it.key !in delivered }
        val next = future.minOfOrNull { it.fireAtMillis } ?: return emptyList()
        return future.filter { it.fireAtMillis == next }
    }

    fun deliverable(drafts: List<CourseReminderDraft>, keys: Set<String>, scheduledAt: Long,
        nowMillis: Long, delivered: Set<String>): List<CourseReminderDraft> = drafts.filter {
        it.key in keys && it.key !in delivered && it.fireAtMillis == scheduledAt &&
            nowMillis >= it.fireAtMillis && nowMillis < it.expiresAtMillis
    }

    fun requestMatchesAccount(pending: Boolean, expectedAccountKey: String, currentAccountKey: String): Boolean =
        pending && expectedAccountKey == currentAccountKey

    private fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(StandardCharsets.UTF_8)).joinToString("") { "%02x".format(it.toInt() and 0xff) }
}
