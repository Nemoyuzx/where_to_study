package com.nemoyu.wheretostudy.nativeapp

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal object DeviceCalendarHolidayLogic {
    const val sourceLabel = "device-calendar"

    fun kindFromTitle(title: String): String {
        val trimmed = title.trim()
        if (listOf("补班", "调休", "上班").any(trimmed::contains)) return "workday"
        return "holiday"
    }

    fun normalizedName(title: String, maxLength: Int = HolidayInputLimits.maxNameLength): String? {
        val trimmed = title.trim()
        if (trimmed.isEmpty()) return null
        return trimmed.take(maxLength)
    }

    fun isHolidayCalendar(displayName: String?, accountType: String?): Boolean {
        val name = displayName?.trim().orEmpty()
        val candidateTitles = listOf(
            "中国大陆节假日",
            "中国节假日",
            "中国法定节假日",
            "中国大陆法定节假日",
            "Chinese Holidays",
            "China Holidays",
            "Holidays in China",
        )
        if (candidateTitles.any { name.contains(it, ignoreCase = true) }) return true
        val holidayKeyword = name.contains("节假日") || name.contains("Holiday", ignoreCase = true)
        val chinaKeyword = name.contains("中国") || name.contains("China", ignoreCase = true)
        return holidayKeyword && chinaKeyword
    }

    fun mergingWorkdays(snapshot: HolidaysSnapshot, workdays: List<HolidayItem>): HolidaysSnapshot {
        val existingIds = snapshot.items.map(HolidayItem::id).toMutableSet()
        val additions = mutableListOf<HolidayItem>()
        for (workday in workdays) {
            if (workday.type != "workday") continue
            if (!existingIds.add(workday.id())) continue
            additions.add(workday)
        }
        if (additions.isEmpty()) return snapshot
        return snapshot.copy(
            items = (snapshot.items + additions).sortedWith(
                compareBy(HolidayItem::date, HolidayItem::type, HolidayItem::name),
            ),
        )
    }

    private fun HolidayItem.id(): String = "$date|$type|$name"
}

class DeviceCalendarHolidayClient(
    private val context: Context,
) {
    fun fetch(year: Int): HolidaysSnapshot {
        if (year !in HolidayMetadata.minimumYear..HolidayMetadata.maximumYear) {
            throw HolidayClientException("节假日年份不在支持范围内。")
        }
        if (!hasCalendarPermission()) {
            throw HolidayClientException("未获得系统日历访问权限。")
        }
        val calendarIDs = queryHolidayCalendars()
        if (calendarIDs.isEmpty()) {
            throw HolidayClientException("设备日历中未找到中国节假日日历。")
        }
        val items = queryHolidayItems(year, calendarIDs)
        if (items.isEmpty()) {
            throw HolidayClientException("设备日历中该年份没有节假日记录。")
        }
        if (items.size > HolidayInputLimits.maxExpandedItems) {
            throw HolidayClientException("设备日历节假日记录过多。")
        }
        return HolidaysSnapshot(
            year = year,
            source = DeviceCalendarHolidayLogic.sourceLabel,
            fetchedAt = timestamp(),
            items = items.sortedWith(compareBy(HolidayItem::date, HolidayItem::type, HolidayItem::name)),
        )
    }

    private fun hasCalendarPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED

    private fun queryHolidayCalendars(): List<Long> {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE,
        )
        val result = mutableListOf<Long>()
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            null,
            null,
            null,
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
            val accountColumn = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_TYPE)
            while (cursor.moveToNext()) {
                val displayName = cursor.getString(nameColumn)
                val accountType = cursor.getString(accountColumn)
                if (DeviceCalendarHolidayLogic.isHolidayCalendar(displayName, accountType)) {
                    result.add(cursor.getLong(idColumn))
                }
            }
        }
        return result
    }

    private fun queryHolidayItems(year: Int, calendarIDs: List<Long>): List<HolidayItem> {
        val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
        val start = Calendar.getInstance(shanghai).apply {
            clear()
            set(year, Calendar.JANUARY, 1, 0, 0, 0)
        }
        val end = Calendar.getInstance(shanghai).apply {
            clear()
            set(year + 1, Calendar.JANUARY, 1, 0, 0, 0)
        }
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, start.timeInMillis)
        ContentUris.appendId(builder, end.timeInMillis)

        val selection = CalendarContract.Instances.CALENDAR_ID + " IN (" +
            calendarIDs.joinToString(",") { it.toString() } + ")"
        val projection = arrayOf(
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
        )
        val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = shanghai
            isLenient = false
        }
        val items = mutableListOf<HolidayItem>()
        context.contentResolver.query(
            builder.build(),
            projection,
            selection,
            null,
            null,
        )?.use { cursor ->
            val titleColumn = cursor.getColumnIndexOrThrow(CalendarContract.Instances.TITLE)
            val beginColumn = cursor.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN)
            while (cursor.moveToNext()) {
                val title = cursor.getString(titleColumn) ?: continue
                val name = DeviceCalendarHolidayLogic.normalizedName(title) ?: continue
                val beginMillis = cursor.getLong(beginColumn)
                val beginCalendar = Calendar.getInstance(shanghai).apply { timeInMillis = beginMillis }
                if (beginCalendar.get(Calendar.YEAR) != year) continue
                items.add(
                    HolidayItem(
                        date = formatter.format(Date(beginMillis)),
                        name = name,
                        type = DeviceCalendarHolidayLogic.kindFromTitle(title),
                    ),
                )
            }
        }
        return items
    }

    private fun timestamp(date: Date = Date()): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        }.format(date)

    companion object {
        fun hasCalendarPermission(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) ==
                PackageManager.PERMISSION_GRANTED
    }
}
