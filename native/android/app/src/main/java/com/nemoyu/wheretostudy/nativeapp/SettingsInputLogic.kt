package com.nemoyu.wheretostudy.nativeapp

import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

internal class SettingsValidationException(message: String) : IllegalArgumentException(message)

internal object StrictContractDate {
    private val pattern = Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}")

    fun isValid(value: String): Boolean {
        if (!pattern.matches(value)) return false
        val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("Asia/Shanghai")
            isLenient = false
        }
        val parsed = runCatching { formatter.parse(value) }.getOrNull() ?: return false
        return formatter.format(parsed) == value
    }
}

internal object SettingsInputLogic {
    fun resolveTermStartDate(
        requestedValue: String,
        fallbackValue: String = AppMetadata.defaultTermStartDate,
    ): String {
        val normalized = requestedValue.trim().ifEmpty { fallbackValue }
        if (!StrictContractDate.isValid(normalized)) {
            throw SettingsValidationException("第一周周一日期格式不正确，请使用 YYYY-MM-DD。")
        }
        return normalized
    }
}
