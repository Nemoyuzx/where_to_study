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
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

data class SystemCalendarImportResult(
    val calendarName: String,
    val totalEvents: Int,
    val insertedEvents: Int,
    val updatedEvents: Int,
    val removedDuplicates: Int,
    val removedStaleEvents: Int,
    val itemLabel: String = "课程",
)

class SystemCalendarImportException(message: String, cause: Throwable? = null) :
    Exception(message, cause)

internal data class CalendarImportRegistration(val token: Long)

internal sealed interface CalendarImportAttachment<out T> {
    data object Active : CalendarImportAttachment<Nothing>
    data class Completed<T>(val result: Result<T>) : CalendarImportAttachment<T>
    data object Missing : CalendarImportAttachment<Nothing>
}

internal class CalendarImportProcessCoordinator<T> {
    private data class ActiveImport<T>(
        val token: Long,
        val observers: MutableMap<Long, (Long, Result<T>) -> Unit>,
    )

    private data class CompletedImport<T>(val token: Long, val result: Result<T>)

    private val lock = Any()
    private var nextToken = 0L
    private var active: ActiveImport<T>? = null
    private var completed: CompletedImport<T>? = null

    fun isRunning(): Boolean = synchronized(lock) { active != null }

    fun start(
        observerID: Long,
        observer: (Long, Result<T>) -> Unit,
    ): CalendarImportRegistration? = synchronized(lock) {
        if (active != null) return@synchronized null
        nextToken += 1
        completed = null
        active = ActiveImport(nextToken, mutableMapOf(observerID to observer))
        CalendarImportRegistration(nextToken)
    }

    fun attach(
        token: Long,
        observerID: Long,
        observer: (Long, Result<T>) -> Unit,
    ): CalendarImportAttachment<T> = synchronized(lock) {
        val running = active
        if (running?.token == token) {
            running.observers[observerID] = observer
            return@synchronized CalendarImportAttachment.Active
        }
        val finished = completed
        if (finished?.token == token) {
            CalendarImportAttachment.Completed(finished.result)
        } else {
            CalendarImportAttachment.Missing
        }
    }

    fun complete(token: Long, result: Result<T>): List<(Long, Result<T>) -> Unit> = synchronized(lock) {
        val running = active?.takeIf { it.token == token } ?: return@synchronized emptyList()
        active = null
        completed = CompletedImport(token, result)
        running.observers.values.toList()
    }

    fun cancelStart(token: Long) = synchronized(lock) {
        if (active?.token == token) active = null
    }

    fun detach(observerID: Long) = synchronized(lock) {
        active?.observers?.remove(observerID)
    }

}

internal class CalendarImportWorker(
    private val executor: ExecutorService = Executors.newSingleThreadExecutor(),
) : AutoCloseable {
    private val closed = AtomicBoolean(false)

    fun execute(task: () -> Unit): Boolean {
        if (closed.get()) return false
        return try {
            executor.execute(task)
            true
        } catch (_: RejectedExecutionException) {
            false
        }
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) {
            executor.shutdown()
        }
    }

    internal val isShutdown: Boolean
        get() = executor.isShutdown
}

class SystemCalendarImporter(context: Context) {
    private val appContext = context.applicationContext
    private val resolver = appContext.contentResolver
    private val mainHandler = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)
    private val observerID = nextObserverID.incrementAndGet()
    private val processWorker = CalendarImportWorker()

    val isImporting: Boolean
        get() = processCoordinator.isRunning()

    internal fun importSchedule(
        schedule: ScheduleSnapshot,
        onComplete: (Result<SystemCalendarImportResult>) -> Unit,
    ): Result<CalendarImportRegistration> {
        if (closed.get()) {
            return Result.failure(SystemCalendarImportException("日历导入服务已关闭。"))
        }
        val registration = processCoordinator.start(observerID, completion(onComplete))
            ?: return Result.failure(SystemCalendarImportException("课表正在导入系统日历。"))

        val accepted = processWorker.execute {
            val result = runCatching { importOnWorker(schedule) }
            processCoordinator.complete(registration.token, result).forEach { observer ->
                observer(registration.token, result)
            }
        }
        if (!accepted) {
            processCoordinator.cancelStart(registration.token)
            return Result.failure(SystemCalendarImportException("日历导入服务已关闭。"))
        }
        return Result.success(registration)
    }

    internal fun importFavorites(
        favorites: List<PublicDeadlineItem>,
        onComplete: (Result<SystemCalendarImportResult>) -> Unit,
    ): Result<CalendarImportRegistration> {
        if (closed.get()) {
            return Result.failure(SystemCalendarImportException("日历导入服务已关闭。"))
        }
        if (favorites.isEmpty()) {
            return Result.failure(SystemCalendarImportException("暂无已收藏日程。"))
        }
        val registration = processCoordinator.start(observerID, completion(onComplete))
            ?: return Result.failure(SystemCalendarImportException("日历正在导入，请稍后重试。"))
        val accepted = processWorker.execute {
            val result = runCatching { importFavoritesOnWorker(favorites) }
            processCoordinator.complete(registration.token, result).forEach { observer ->
                observer(registration.token, result)
            }
        }
        if (!accepted) {
            processCoordinator.cancelStart(registration.token)
            return Result.failure(SystemCalendarImportException("日历导入服务已关闭。"))
        }
        return Result.success(registration)
    }

    internal fun attach(
        token: Long,
        onComplete: (Result<SystemCalendarImportResult>) -> Unit,
    ): Boolean {
        if (closed.get()) return false
        val observer = completion(onComplete)
        return when (val attachment = processCoordinator.attach(token, observerID, observer)) {
            CalendarImportAttachment.Active -> true
            is CalendarImportAttachment.Completed -> {
                observer(token, attachment.result)
                true
            }
            CalendarImportAttachment.Missing -> false
        }
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        processCoordinator.detach(observerID)
        mainHandler.removeCallbacksAndMessages(null)
        processWorker.close()
    }

    private fun completion(
        onComplete: (Result<SystemCalendarImportResult>) -> Unit,
    ): (Long, Result<SystemCalendarImportResult>) -> Unit = { _, result ->
        if (!closed.get()) {
            mainHandler.post {
                if (!closed.get()) {
                    onComplete(result)
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun importOnWorker(schedule: ScheduleSnapshot): SystemCalendarImportResult {
        if (!hasCalendarPermissions()) {
            throw SystemCalendarImportException("需要日历读写权限才能导入课程。")
        }
        val drafts = ScheduleCalendarLogic.expand(schedule)
        val calendar = findPrimaryWritableCalendar()
        val existingEvents = existingEvents(ScheduleCalendarLogic.markerPrefix)
        val plan = CalendarSyncPlanner.plan(schedule, drafts, existingEvents)
        val operations = mutableListOf<ContentProviderOperation>()

        (plan.duplicateEventIDs + plan.staleEventIDs).distinct().forEach { eventID ->
            operations += ContentProviderOperation.newDelete(
                ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventID),
            ).build()
        }
        plan.updates.forEach { update ->
            operations += ContentProviderOperation.newUpdate(
                ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, update.eventID),
            )
                .withValues(eventValues(update.draft, calendar.id))
                .build()
        }
        plan.inserts.forEach { draft ->
            operations += ContentProviderOperation.newInsert(CalendarContract.Events.CONTENT_URI)
                .withValues(eventValues(draft, calendar.id))
                .build()
        }

        operations.chunked(MAX_OPERATIONS_PER_BATCH).forEach { batch ->
            resolver.applyBatch(CalendarContract.AUTHORITY, ArrayList(batch))
        }
        return SystemCalendarImportResult(
            calendarName = calendar.name,
            totalEvents = drafts.size,
            insertedEvents = plan.inserts.size,
            updatedEvents = plan.updates.size,
            removedDuplicates = plan.duplicateEventIDs.size,
            removedStaleEvents = plan.staleEventIDs.size,
        )
    }

    @SuppressLint("MissingPermission")
    private fun importFavoritesOnWorker(
        favorites: List<PublicDeadlineItem>,
    ): SystemCalendarImportResult {
        if (!hasCalendarPermissions()) {
            throw SystemCalendarImportException("需要日历读写权限才能导入收藏日程。")
        }
        val drafts = FavoriteCalendarLogic.expand(favorites)
        val calendar = findPrimaryWritableCalendar()
        val existingEvents = existingEvents(FavoriteCalendarLogic.markerPrefix)
        val plan = CalendarSyncPlanner.planFavorites(drafts, existingEvents)
        val operations = mutableListOf<ContentProviderOperation>()
        (plan.duplicateEventIDs + plan.staleEventIDs).distinct().forEach { eventID ->
            operations += ContentProviderOperation.newDelete(
                ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventID),
            ).build()
        }
        plan.updates.forEach { update ->
            operations += ContentProviderOperation.newUpdate(
                ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, update.eventID),
            ).withValues(eventValues(update.draft, calendar.id)).build()
        }
        plan.inserts.forEach { draft ->
            operations += ContentProviderOperation.newInsert(CalendarContract.Events.CONTENT_URI)
                .withValues(eventValues(draft, calendar.id))
                .build()
        }
        operations.chunked(MAX_OPERATIONS_PER_BATCH).forEach { batch ->
            resolver.applyBatch(CalendarContract.AUTHORITY, ArrayList(batch))
        }
        return SystemCalendarImportResult(
            calendarName = calendar.name,
            totalEvents = drafts.size,
            insertedEvents = plan.inserts.size,
            updatedEvents = plan.updates.size,
            removedDuplicates = plan.duplicateEventIDs.size,
            removedStaleEvents = plan.staleEventIDs.size,
            itemLabel = "收藏日程",
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
        val selection = "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ? AND " +
            "${CalendarContract.Calendars.VISIBLE} = 1 AND " +
            "${CalendarContract.Calendars.SYNC_EVENTS} = 1"
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
    private fun existingEvents(markerPrefix: String): List<ManagedCalendarEvent> {
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.CUSTOM_APP_URI,
            CalendarContract.Events.DTSTART,
        )
        val selection = "${CalendarContract.Events.CUSTOM_APP_PACKAGE} = ? AND " +
            "${CalendarContract.Events.CUSTOM_APP_URI} LIKE ? AND " +
            "${CalendarContract.Events.DELETED} = 0"
        val selectionArgs = arrayOf(
            appContext.packageName,
            "$markerPrefix%",
        )
        val events = mutableListOf<ManagedCalendarEvent>()
        resolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            CalendarContract.Events._ID,
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(CalendarContract.Events._ID)
            val markerColumn = cursor.getColumnIndexOrThrow(CalendarContract.Events.CUSTOM_APP_URI)
            val startsAtColumn = cursor.getColumnIndexOrThrow(CalendarContract.Events.DTSTART)
            while (cursor.moveToNext()) {
                val marker = cursor.getString(markerColumn) ?: continue
                events += ManagedCalendarEvent(
                    id = cursor.getLong(idColumn),
                    marker = marker,
                    startsAtMillis = cursor.getLong(startsAtColumn),
                )
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
        val processCoordinator = CalendarImportProcessCoordinator<SystemCalendarImportResult>()
        val nextObserverID = AtomicLong(0)
    }
}
