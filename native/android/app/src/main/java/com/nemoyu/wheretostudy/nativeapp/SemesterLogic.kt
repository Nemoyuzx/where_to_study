package com.nemoyu.wheretostudy.nativeapp

import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

internal data class SuggestedTerm(
    val termId: String,
    val termStartDate: String,
)

/**
 * Term (semester) auto-detection, mirroring the Tauri planner-domain helpers
 * (suggestTermForDate / isValidTermId / isValidTermStartDate /
 * termMatchesCurrentPeriod). BUPT academic calendar: spring (term 2) starts
 * early March, fall (term 1) starts early September, and January still
 * belongs to the fall term that started the previous year. The authoritative
 * values come back in the schedule fetch response and are applied
 * automatically after a successful fetch, so these helpers only suggest and
 * validate local settings.
 */
internal object SemesterLogic {
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
    private val termIdPattern = Regex("\\d{4}-\\d{4}-[12]")
    private val springMonths = 2..7

    /**
     * Suggest the current term id and term start date for the given calendar
     * date. Defaults to the current date in the Asia/Shanghai timezone, which
     * is what the app uses for all calendar math.
     */
    fun suggestTermForDate(date: Calendar = Calendar.getInstance(shanghai)): SuggestedTerm {
        val month = date.get(Calendar.MONTH) + 1
        val year = date.get(Calendar.YEAR)
        return if (month in springMonths) {
            // Spring semester starts around March 1-3; the week of March 2 is
            // a stable anchor (2026-03-02, 2025-02-24, 2024-02-26 all match).
            SuggestedTerm(
                termId = "${year - 1}-$year-2",
                termStartDate = mondayOfWeekContaining(year, 3, 2),
            )
        } else {
            // Fall semester starts around September 1; January still belongs
            // to the fall term that started in the previous year.
            val fallStartYear = if (month == 1) year - 1 else year
            SuggestedTerm(
                termId = "$fallStartYear-${fallStartYear + 1}-1",
                termStartDate = mondayOfWeekContaining(fallStartYear, 9, 1),
            )
        }
    }

    /**
     * Resolve the automatic term shown after a cold start. The current
     * Shanghai calendar period is the baseline. A cached schedule may refine
     * the real first-week Monday only when it belongs to that same period;
     * an old-term cache must never roll the automatic setting backwards.
     */
    fun resolveAutomaticLaunchTerm(
        cachedTermId: String?,
        cachedTermStartDate: String?,
        date: Calendar = Calendar.getInstance(shanghai),
    ): SuggestedTerm {
        val suggested = suggestTermForDate(date)
        val cachedId = cachedTermId?.trim().orEmpty()
        val cachedStart = cachedTermStartDate?.trim().orEmpty()
        return if (canUseAutomaticCachedSchedule(cachedId, cachedStart, date)) {
            SuggestedTerm(cachedId, cachedStart)
        } else {
            suggested
        }
    }

    fun canUseAutomaticCachedSchedule(
        cachedTermId: String?,
        cachedTermStartDate: String?,
        date: Calendar = Calendar.getInstance(shanghai),
    ): Boolean {
        val suggested = suggestTermForDate(date)
        return cachedTermId?.trim() == suggested.termId &&
            isValidTermStartDate(cachedTermStartDate?.trim().orEmpty())
    }

    fun shouldRefreshAutomatically(
        automaticTermDetectionEnabled: Boolean,
        credentials: Credentials?,
    ): Boolean = automaticTermDetectionEnabled &&
        !credentials?.account.isNullOrBlank() &&
        !credentials?.password.isNullOrEmpty()

    /** Validate a term id like "2025-2026-2" or "2026-2027-1". */
    fun isValidTermId(value: String): Boolean = termIdPattern.matches(value.trim())

    /** Validate a term start date as yyyy-MM-dd that is a real calendar date. */
    fun isValidTermStartDate(value: String): Boolean = StrictContractDate.isValid(value.trim())

    /**
     * True when the given term is the one suggested for the given date, i.e.
     * both the term id and the term start date match the suggestion exactly.
     */
    fun termMatchesCurrentPeriod(
        termId: String,
        termStartDate: String,
        date: Calendar = Calendar.getInstance(shanghai),
    ): Boolean {
        if (!isValidTermId(termId)) return false
        val suggested = suggestTermForDate(date)
        return termId.trim() == suggested.termId &&
            termStartDate.trim() == suggested.termStartDate
    }

    /**
     * Monday of the week that contains the given date, formatted yyyy-MM-dd.
     * Calendar.DAY_OF_WEEK is 1=Sunday..7=Saturday, so (day + 5) % 7 is the
     * number of days since Monday.
     */
    private fun mondayOfWeekContaining(year: Int, month: Int, day: Int): String {
        val date = Calendar.getInstance(shanghai).apply {
            isLenient = false
            set(year, month - 1, day, 12, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val daysSinceMonday = (date.get(Calendar.DAY_OF_WEEK) + 5) % 7
        date.add(Calendar.DAY_OF_MONTH, -daysSinceMonday)
        return String.format(
            Locale.US,
            "%04d-%02d-%02d",
            date.get(Calendar.YEAR),
            date.get(Calendar.MONTH) + 1,
            date.get(Calendar.DAY_OF_MONTH),
        )
    }
}
