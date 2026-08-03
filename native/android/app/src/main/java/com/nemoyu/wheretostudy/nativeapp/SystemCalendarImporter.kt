package com.nemoyu.wheretostudy.nativeapp

import android.Manifest
import android.annotation.SuppressLint
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

data class SystemCalendarImportResult(
    val calendarName: String,
    val totalEvents: Int,
    val insertedEvents: Int,
    val updatedEvents: Int,
    val removedDuplicates: Int,
)

class SystemCalendarImportException(message: String, cause: Throwable? = null) :
    Exception(message, cause)

class SystemCalendarImporter(context: Context) {
    private val appContext = context.applicationContext
    private val resolver = appContext.contentResolver
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val importInFlight = AtomicBoolean(false)

    val isImporting: Boolean
        get() = importInFlight.get()

    fun importSchedule(
        schedule: ScheduleSnapshot,
        onComplete: (Result<SystemCalendarImportResult>) -> Unit,
    ) {
        if (!importInFlight.compareAndSet(false, true)) {
            onComplete(Result.failure(SystemCalendarImportException("课表正在导入系统日历。")))
            return
        }

        try {
            worker.execute {
                val result = runCatching { importOnWorker(schedule) }
                mainHandler.post {
                    importInFlight.set(false)
                    onComplete(result)
                }
            }
        } catch (error: RejectedExecutionException) {
            importInFlight.set(false)
            onComplete(Result.failure(SystemCalendarImportException("日历导入服务已关闭。", error)))
        }
    }

    fun close() {
        worker.shutdownNow()
    }

    @SuppressLint("MissingPermission")
    private fun importOnWorker(schedule: ScheduleSnapshot): SystemCalendarImportResult {
        if (!hasCalendarPermissions()) {
            throw SystemCalendarImportException("需要日历读写权限才能导入课程。")
        }
        val drafts = ScheduleCalendarLogic.expand(schedule)
        if (drafts.isEmpty()) {
            throw SystemCalendarImportException("本地课表中没有可导入的课程。")
        }
        val calendar = findPrimaryWritableCalendar()
        val existingEvents = existingEvents()
        val operations = mutableListOf<ContentProviderOperation>()
        var inserted = 0
        var updated = 0
        var duplicates = 0

        drafts.forEach { draft ->
            val existingIDs = existingEvents[draft.marker].orEmpty().sorted()
            if (existingIDs.isEmpty()) {
                operations += ContentProviderOperation.newInsert(CalendarContract.Events.CONTENT_URI)
                    .withValues(eventValues(draft, calendar.id))
                    .build()
                inserted += 1
            } else {
                operations += ContentProviderOperation.newUpdate(
                    ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, existingIDs.first()),
                )
                    .withValues(eventValues(draft, calendar.id))
                    .build()
                updated += 1
                existingIDs.drop(1).forEach { duplicateID ->
                    operations += ContentProviderOperation.newDelete(
                        ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, duplicateID),
                    ).build()
                    duplicates += 1
                }
            }
        }

        operations.chunked(MAX_OPERATIONS_PER_BATCH).forEach { batch ->
            resolver.applyBatch(CalendarContract.AUTHORITY, ArrayList(batch))
        }
        return SystemCalendarImportResult(
            calendarName = calendar.name,
            totalEvents = drafts.size,
            insertedEvents = inserted,
            updatedEvents = updated,
            removedDuplicates = duplicates,
        )
    }

    private fun hasCalendarPermissions(): Boolean =
        appContext.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
            appContext.checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    private fun findPrimaryWritableCalendar(): WritableCalendar {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
        )
        val selection = "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ?"
        val selectionArgs = arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString())
        val order = "${CalendarContract.Calendars.IS_PRIMARY} DESC, " +
            "${CalendarContract.Calendars.VISIBLE} DESC, ${CalendarContract.Calendars._ID} ASC"
        resolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            order,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID))
                val name = cursor.getString(
                    cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME),
                ).orEmpty().ifBlank { "系统日历" }
                return WritableCalendar(id, name)
            }
        }
        throw SystemCalendarImportException("未找到可写的系统日历。")
    }

    @SuppressLint("MissingPermission")
    private fun existingEvents(): Map<String, List<Long>> {
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.CUSTOM_APP_URI,
        )
        val selection = "${CalendarContract.Events.CUSTOM_APP_PACKAGE} = ? AND " +
            "${CalendarContract.Events.CUSTOM_APP_URI} LIKE ? AND " +
            "${CalendarContract.Events.DELETED} = 0"
        val selectionArgs = arrayOf(
            appContext.packageName,
            "${ScheduleCalendarLogic.markerPrefix}%",
        )
        val events = linkedMapOf<String, MutableList<Long>>()
        resolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            CalendarContract.Events._ID,
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(CalendarContract.Events._ID)
            val markerColumn = cursor.getColumnIndexOrThrow(CalendarContract.Events.CUSTOM_APP_URI)
            while (cursor.moveToNext()) {
                val marker = cursor.getString(markerColumn) ?: continue
                events.getOrPut(marker) { mutableListOf() }.add(cursor.getLong(idColumn))
            }
        }
        return events
    }

    private fun eventValues(draft: CalendarEventDraft, calendarID: Long): ContentValues = ContentValues().apply {
        put(CalendarContract.Events.CALENDAR_ID, calendarID)
        put(CalendarContract.Events.TITLE, draft.title)
        put(CalendarContract.Events.EVENT_LOCATION, draft.location)
        put(CalendarContract.Events.DESCRIPTION, draft.description)
        put(CalendarContract.Events.DTSTART, draft.startsAtMillis)
        put(CalendarContract.Events.DTEND, draft.endsAtMillis)
        put(CalendarContract.Events.EVENT_TIMEZONE, draft.timeZoneID)
        put(CalendarContract.Events.EVENT_END_TIMEZONE, draft.timeZoneID)
        put(CalendarContract.Events.ALL_DAY, 0)
        put(CalendarContract.Events.AVAILABILITY, CalendarContract.Events.AVAILABILITY_BUSY)
        put(CalendarContract.Events.CUSTOM_APP_PACKAGE, appContext.packageName)
        put(CalendarContract.Events.CUSTOM_APP_URI, draft.marker)
    }

    private data class WritableCalendar(val id: Long, val name: String)

    private companion object {
        const val MAX_OPERATIONS_PER_BATCH = 100
    }
}
