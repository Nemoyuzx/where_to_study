package com.nemoyu.wheretostudy.nativeapp

import java.util.Calendar
import java.util.TimeZone

enum class ClassroomRefreshDecision {
    FETCH,
    SKIP_MISSING_CREDENTIALS,
}

object DailyClassroomRefreshLogic {
    const val timeZoneID = "Asia/Shanghai"

    private val shanghai = TimeZone.getTimeZone(timeZoneID)

    fun nextRunAt(nowMillis: Long): Long {
        val next = Calendar.getInstance(shanghai).apply {
            timeInMillis = nowMillis
            set(Calendar.HOUR_OF_DAY, REFRESH_HOUR)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (next.timeInMillis <= nowMillis) {
            next.add(Calendar.DAY_OF_MONTH, 1)
        }
        return next.timeInMillis
    }

    fun refreshDecision(account: String?, password: String?): ClassroomRefreshDecision =
        if (!account.isNullOrBlank() && !password.isNullOrEmpty()) {
            ClassroomRefreshDecision.FETCH
        } else {
            ClassroomRefreshDecision.SKIP_MISSING_CREDENTIALS
        }

    private const val REFRESH_HOUR = 7
}
