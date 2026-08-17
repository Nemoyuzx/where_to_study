package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

internal class HolidayFailureCooldown(
    private val cooldownMillis: Long = DEFAULT_COOLDOWN_MILLIS,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private val failedAtByYear = ConcurrentHashMap<Int, Long>()

    init {
        require(cooldownMillis >= 0) { "cooldownMillis must not be negative" }
    }

    fun shouldAttempt(year: Int, force: Boolean): Boolean {
        if (force) return true
        val failedAt = failedAtByYear[year] ?: return true
        val elapsed = nowMillis() - failedAt
        if (elapsed < cooldownMillis) return false
        failedAtByYear.remove(year, failedAt)
        return true
    }

    fun recordFailure(year: Int) {
        failedAtByYear[year] = nowMillis()
    }

    fun recordSuccess(year: Int) {
        failedAtByYear.remove(year)
    }

    fun clear() {
        failedAtByYear.clear()
    }

    companion object {
        const val DEFAULT_COOLDOWN_MILLIS = 15L * 60L * 1_000L
    }
}

internal class HolidayObserverRegistry {
    private val observers = ConcurrentHashMap<Any, () -> Unit>()

    fun add(owner: Any, observer: () -> Unit) {
        observers[owner] = observer
    }

    fun remove(owner: Any) {
        observers.remove(owner)
    }

    fun snapshot(): List<() -> Unit> = observers.values.toList()

    fun clear() {
        observers.clear()
    }
}

internal object HolidayOfflineFallback {
    fun snapshot(
        year: Int,
        fetchedAt: String = timestamp(),
    ): HolidaysSnapshot? {
        if (year != 2026) return null
        val items = buildList {
            addRange("元旦", "2026-01-01", "2026-01-03", "holiday")
            addRange("元旦补班", "2026-01-04", "2026-01-04", "workday")
            addRange("春节补班", "2026-02-14", "2026-02-14", "workday")
            addRange("春节", "2026-02-15", "2026-02-23", "holiday")
            addRange("春节补班", "2026-02-28", "2026-02-28", "workday")
            addRange("清明节", "2026-04-04", "2026-04-06", "holiday")
            addRange("劳动节", "2026-05-01", "2026-05-05", "holiday")
            addRange("劳动节补班", "2026-05-09", "2026-05-09", "workday")
            addRange("端午节", "2026-06-19", "2026-06-21", "holiday")
            addRange("中秋节", "2026-09-25", "2026-09-27", "holiday")
            addRange("国庆节补班", "2026-09-20", "2026-09-20", "workday")
            addRange("国庆节", "2026-10-01", "2026-10-07", "holiday")
            addRange("国庆节补班", "2026-10-10", "2026-10-10", "workday")
        }
        return HolidaysSnapshot(
            year = year,
            source = HolidayMetadata.fallbackSource,
            fetchedAt = fetchedAt,
            items = items,
        ).also(HolidaySnapshotValidator::validate)
    }

    private fun MutableList<HolidayItem>.addRange(
        name: String,
        start: String,
        end: String,
        type: String,
    ) {
        val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = SHANGHAI
            isLenient = false
        }
        val startDate = checkNotNull(formatter.parse(start))
        val endDate = checkNotNull(formatter.parse(end))
        val calendar = java.util.Calendar.getInstance(SHANGHAI).apply { time = startDate }
        while (!calendar.time.after(endDate)) {
            add(HolidayItem(formatter.format(calendar.time), name, type))
            calendar.add(java.util.Calendar.DAY_OF_MONTH, 1)
        }
    }

    private fun timestamp(date: Date = Date()): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply {
            timeZone = SHANGHAI
        }.format(date)

    private val SHANGHAI = TimeZone.getTimeZone("Asia/Shanghai")
}

class HolidayRepository(
    context: Context,
    private val client: HolidayClient = HolidayClient(),
    private val store: HolidayStore = HolidayStore(context.applicationContext),
    private val deviceCalendarClient: DeviceCalendarHolidayClient = DeviceCalendarHolidayClient(
        context.applicationContext,
    ),
) {
    private val applicationContext = context.applicationContext
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val snapshots = ConcurrentHashMap<Int, HolidaysSnapshot>()
    private val loadedYears = ConcurrentHashMap.newKeySet<Int>()
    private val inFlightYears = ConcurrentHashMap<Int, Long>()
    private val statusByYear = ConcurrentHashMap<Int, String>()
    private val failureCooldown = HolidayFailureCooldown()
    private val observers = HolidayObserverRegistry()
    private val closed = AtomicBoolean(false)

    fun snapshot(year: Int): HolidaysSnapshot? = snapshot(year, LocalDataCoordinator.snapshot())

    private fun snapshot(year: Int, generation: Long): HolidaysSnapshot? {
        return runCatching {
            LocalDataCoordinator.withCurrent(generation) {
                snapshots[year] ?: if (!loadedYears.add(year)) {
                    snapshots[year]
                } else {
                    store.load(year)?.also { snapshots[year] = it }
                }
            }
        }.getOrNull()
    }

    fun items(year: Int): List<HolidayItem> = snapshot(year)?.items.orEmpty()

    fun status(year: Int): String = statusByYear[year].orEmpty()

    fun addObserver(owner: Any, observer: () -> Unit) {
        if (!closed.get()) observers.add(owner, observer)
    }

    fun removeObserver(owner: Any) {
        observers.remove(owner)
    }

    fun ensure(
        year: Int,
        force: Boolean = false,
    ) {
        val refreshGeneration = LocalDataCoordinator.snapshot()
        if (closed.get()) return
        if (year !in HolidayMetadata.minimumYear..HolidayMetadata.maximumYear) return
        val cached = snapshot(year, refreshGeneration)?.takeIf { it.items.isNotEmpty() }
        if (!LocalDataCoordinator.isCurrent(refreshGeneration)) return
        if (!force && cached != null && isFresh(cached)) return
        if (!failureCooldown.shouldAttempt(year, force)) return
        if (inFlightYears.putIfAbsent(year, refreshGeneration) != null) return
        try {
            worker.execute {
                val result = runCatching {
                    fetchSnapshot(year).also { fetched ->
                        LocalDataCoordinator.withCurrent(refreshGeneration) {
                            store.save(fetched)
                            snapshots[year] = fetched
                            statusByYear.remove(year)
                            failureCooldown.recordSuccess(year)
                        }
                    }
                }
                result.onFailure { error ->
                    if (error !is LocalDataInvalidatedException &&
                        LocalDataCoordinator.isCurrent(refreshGeneration)
                    ) {
                        runCatching {
                            LocalDataCoordinator.withCurrent(refreshGeneration) {
                                failureCooldown.recordFailure(year)
                                statusByYear[year] = when {
                                    cached != null -> "节假日更新失败，正在使用本地缓存"
                                    else -> {
                                        val fallback = HolidayOfflineFallback.snapshot(year)
                                        if (fallback == null) {
                                            "节假日数据暂不可用"
                                        } else {
                                            snapshots[year] = fallback
                                            "节假日更新失败，正在使用内置数据"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if (closed.get() || !LocalDataCoordinator.isCurrent(refreshGeneration)) {
                    inFlightYears.remove(year, refreshGeneration)
                    return@execute
                }
                mainHandler.post {
                    if (closed.get() || !LocalDataCoordinator.isCurrent(refreshGeneration)) {
                        inFlightYears.remove(year, refreshGeneration)
                        return@post
                    }
                    inFlightYears.remove(year, refreshGeneration)
                    observers.snapshot().forEach { observer -> observer() }
                }
            }
        } catch (_: RejectedExecutionException) {
            inFlightYears.remove(year, refreshGeneration)
        }
    }

    fun clearLocalData() {
        LocalDataCoordinator.clear(::clearLocalDataCoordinated)
    }

    internal fun clearLocalDataCoordinated() {
        store.clear()
        snapshots.clear()
        loadedYears.clear()
        statusByYear.clear()
        failureCooldown.clear()
        inFlightYears.clear()
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        mainHandler.removeCallbacksAndMessages(null)
        observers.clear()
        inFlightYears.clear()
        worker.shutdownNow()
    }

    private fun fetchSnapshot(year: Int): HolidaysSnapshot {
        // Prefer the device calendar when calendar access is already granted
        // (never prompts). The device calendar marks rest days but not makeup
        // workdays, so supplement those from the remote/offline source.
        if (DeviceCalendarHolidayClient.hasCalendarPermission(applicationContext)) {
            val device = runCatching { deviceCalendarClient.fetch(year) }.getOrNull()
            if (device != null) {
                return DeviceCalendarHolidayLogic.mergingWorkdays(device, workdays(year))
            }
        }
        return client.fetch(year)
    }

    private fun workdays(year: Int): List<HolidayItem> {
        val remote = runCatching { client.fetch(year) }.getOrNull()
        if (remote != null) return remote.items.filter { it.type == "workday" }
        return HolidayOfflineFallback.snapshot(year)?.items?.filter { it.type == "workday" }.orEmpty()
    }

    private fun isFresh(snapshot: HolidaysSnapshot, now: Date = Date()): Boolean {
        if (snapshot.source == HolidayMetadata.fallbackSource) return false
        val fetchedAt = timestampParser().parse(snapshot.fetchedAt) ?: return false
        val age = now.time - fetchedAt.time
        return age in 0..HolidayMetadata.refreshIntervalMillis
    }

    private fun timestampParser(): SimpleDateFormat =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("Asia/Shanghai")
            isLenient = false
        }
}
