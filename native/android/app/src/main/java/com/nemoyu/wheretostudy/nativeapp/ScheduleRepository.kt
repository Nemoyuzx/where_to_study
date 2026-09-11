package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.Calendar

private data class ScheduleRefreshRequest(
    val credentials: Credentials,
    val termID: String,
    val termStartDate: String,
    val automaticTermDetectionEnabled: Boolean,
)

internal data class AutomaticScheduleLaunchRefreshKey(
    val account: String,
    val termID: String,
)

internal class AutomaticScheduleLaunchRefreshGate {
    private val inFlight = mutableSetOf<AutomaticScheduleLaunchRefreshKey>()
    private val completed = mutableSetOf<AutomaticScheduleLaunchRefreshKey>()

    @Synchronized
    fun begin(account: String, termID: String): AutomaticScheduleLaunchRefreshKey? {
        val key = AutomaticScheduleLaunchRefreshKey(account.trim(), termID.trim())
        if (key.account.isEmpty() || key.termID.isEmpty() || key in inFlight || key in completed) {
            return null
        }
        inFlight += key
        return key
    }

    @Synchronized
    fun finish(key: AutomaticScheduleLaunchRefreshKey, succeeded: Boolean) {
        if (!inFlight.remove(key)) return
        if (succeeded) completed += key
    }
}

internal object ProcessAutomaticScheduleLaunchRefreshGate {
    private val gate = AutomaticScheduleLaunchRefreshGate()

    fun begin(account: String, termID: String): AutomaticScheduleLaunchRefreshKey? =
        gate.begin(account, termID)

    fun finish(key: AutomaticScheduleLaunchRefreshKey, succeeded: Boolean) =
        gate.finish(key, succeeded)
}

class ScheduleRepository(
    context: Context,
    private val credentialStore: SecureCredentialStore,
    private val preferences: AppPreferences,
    private val client: SjdScheduleClient = SjdScheduleClient(),
    private val store: ScheduleStore = ScheduleStore(context.applicationContext),
) {
    private val appContext = context.applicationContext
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val refreshLock = Any()
    private val nextRefreshToken = AtomicLong(0)
    private val closed = AtomicBoolean(false)
    private val deletionStore = CourseDeletionStore(appContext)
    private var activeRefreshToken: Long? = null
    private var rawSchedule: ScheduleSnapshot? = null

    @Volatile
    var schedule: ScheduleSnapshot? = null
        private set

    init {
        rawSchedule = loadUsableCachedSchedule()
        schedule = runCatching { rawSchedule?.let(::effectiveSchedule) }.getOrNull()
        reconcileAutomaticTermAfterLaunch()
    }

    val isRefreshing: Boolean
        get() = synchronized(refreshLock) { activeRefreshToken != null }

    fun refresh(onComplete: (Result<ScheduleSnapshot>) -> Unit): Boolean {
        val refreshGeneration = LocalDataCoordinator.snapshot()
        if (closed.get()) {
            mainHandler.post {
                onComplete(Result.failure(ScheduleClientException("个人课表获取服务已关闭。")))
            }
            return false
        }
        val refreshToken = beginRefresh() ?: return false

        try {
            worker.execute {
                val result = runCatching {
                    if (closed.get()) {
                        throw ScheduleClientException("个人课表获取服务已关闭。")
                    }
                    val request = LocalDataCoordinator.withCurrent(refreshGeneration) {
                        val automatic = preferences.automaticTermDetectionEnabled
                        val fallback = if (automatic) {
                            // A refresh always targets the current Shanghai
                            // period. A same-term cache may retain the real
                            // first-week Monday; old persisted values cannot.
                            automaticTermForCurrentLaunch()
                        } else {
                            SuggestedTerm(preferences.termID, preferences.termStartDate)
                        }
                        ScheduleRefreshRequest(
                            credentials = credentialStore.load() ?: Credentials("", ""),
                            termID = fallback.termId,
                            termStartDate = fallback.termStartDate,
                            automaticTermDetectionEnabled = automatic,
                        )
                    }
                    if (!request.automaticTermDetectionEnabled) {
                        if (!SemesterLogic.isValidTermId(request.termID)) {
                            throw ScheduleClientException("学期编号格式不正确，请使用 YYYY-YYYY-1/2。")
                        }
                        if (!SemesterLogic.isValidTermStartDate(request.termStartDate)) {
                            throw ScheduleClientException("第一周周一日期格式不正确，请使用 YYYY-MM-DD。")
                        }
                    }
                    client.fetch(request.credentials, request.termID, request.termStartDate).let { fetched ->
                        val resolved = if (request.automaticTermDetectionEnabled) {
                            fetched
                        } else {
                            fetched.copy(termID = request.termID, termStartDate = request.termStartDate)
                        }
                        LocalDataCoordinator.withCurrent(refreshGeneration) {
                            if (closed.get() || !isActiveRefresh(refreshToken)) {
                                throw ScheduleClientException("个人课表获取服务已关闭。")
                            }
                            val effective = effectiveSchedule(resolved)
                            store.save(resolved)
                            rawSchedule = resolved
                            schedule = effective
                            runCatching { TodayCourseWidgetProvider.refresh(appContext) }
                            preferences.termID = resolved.termID
                            preferences.termStartDate = resolved.termStartDate
                            effective
                        }
                    }
                }
                mainHandler.post {
                    finishRefresh(refreshToken)
                    if (!closed.get()) {
                        val delivered = if (LocalDataCoordinator.isCurrent(refreshGeneration)) {
                            result
                        } else {
                            Result.failure(LocalDataInvalidatedException())
                        }
                        onComplete(delivered)
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            finishRefresh(refreshToken)
            mainHandler.post {
                if (!closed.get()) {
                    onComplete(Result.failure(ScheduleClientException("个人课表获取服务已关闭。")))
                }
            }
            return false
        }
        return true
    }

    fun refreshAutomatically(onComplete: (Result<ScheduleSnapshot>) -> Unit): Boolean {
        val credentials = credentialStore.load()
        if (!SemesterLogic.shouldRefreshAutomatically(
                preferences.automaticTermDetectionEnabled,
                credentials,
            )
        ) {
            return false
        }
        // refresh() owns the in-flight token, so a simultaneous user refresh
        // and launch refresh cannot issue duplicate requests.
        return refresh(onComplete)
    }

    fun clearLocalData() {
        LocalDataCoordinator.clear(::clearLocalDataCoordinated)
    }

    internal fun clearLocalDataCoordinated(clearCourseDeletions: Boolean = true) {
        if (clearCourseDeletions) deletionStore.clear()
        store.clear()
        rawSchedule = null
        schedule = null
        runCatching { TodayCourseWidgetProvider.refresh(appContext) }
        synchronized(refreshLock) { activeRefreshToken = null }
    }

    internal fun deletedCourses(): List<CourseDeletion> = CourseDeletionLogic.records(
        credentialStore.load()?.account.orEmpty(),
        rawSchedule?.termID ?: preferences.termID,
        deletionStore.load(),
    )

    internal fun deleteCourse(
        course: Course,
        date: Calendar,
        scope: CourseDeletionScope,
        expectedTermID: String,
    ) {
        val generation = LocalDataCoordinator.snapshot()
        LocalDataCoordinator.withCurrent(generation) {
            val raw = rawSchedule ?: throw IllegalStateException("请先获取个人课表。")
            check(raw.termID == expectedTermID) { "课表已更新，请重新选择课程。" }
            val account = credentialStore.load()?.account.orEmpty()
            val existing = deletionStore.load()
            val deletion = CourseDeletionLogic.create(account, raw, course, date, scope)
            val visible = CourseDeletionLogic.apply(raw, account, existing)
            check(ScheduleLogic.courses(visible, date).any {
                CourseDeletionLogic.matchesCourse(deletion, it) &&
                    it.startSlot == course.startSlot && it.endSlot == course.endSlot
            }) { "课表已更新，请重新选择课程。" }
            val updated = existing + deletion
            deletionStore.save(updated)
            schedule = CourseDeletionLogic.apply(raw, account, updated)
        }
        runCatching { TodayCourseWidgetProvider.refresh(appContext) }
    }

    internal fun restoreCourse(deletionID: String) {
        val generation = LocalDataCoordinator.snapshot()
        LocalDataCoordinator.withCurrent(generation) {
            val account = credentialStore.load()?.account.orEmpty()
            val existing = deletionStore.load()
            val current = CourseDeletionLogic.records(
                account, rawSchedule?.termID ?: preferences.termID, existing,
            )
            check(current.any { it.id == deletionID }) { "课程删除记录已更新，请重试。" }
            val updated = existing.filterNot { it.id == deletionID }
            deletionStore.save(updated)
            schedule = rawSchedule?.let { CourseDeletionLogic.apply(it, account, updated) }
        }
        runCatching { TodayCourseWidgetProvider.refresh(appContext) }
    }

    private fun effectiveSchedule(raw: ScheduleSnapshot): ScheduleSnapshot = CourseDeletionLogic.apply(
        raw,
        credentialStore.load()?.account.orEmpty(),
        deletionStore.load(),
    )

    internal fun automaticTermForCurrentLaunch(): SuggestedTerm =
        SemesterLogic.resolveAutomaticLaunchTerm(
            cachedTermId = schedule?.termID,
            cachedTermStartDate = schedule?.termStartDate,
        )

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        mainHandler.removeCallbacksAndMessages(null)
        synchronized(refreshLock) { activeRefreshToken = null }
        worker.shutdownNow()
    }

    private fun loadCachedSchedule(): ScheduleSnapshot? {
        val generation = LocalDataCoordinator.snapshot()
        return runCatching {
            LocalDataCoordinator.withCurrent(generation, store::load)
        }.getOrNull()
    }

    private fun loadUsableCachedSchedule(): ScheduleSnapshot? {
        val loaded = loadCachedSchedule()
        val usable = selectUsableSchedule(loaded, preferences.automaticTermDetectionEnabled)
        if (loaded == null || usable != null) return usable
        store.clear()
        runCatching { TodayCourseWidgetProvider.refresh(appContext) }
        return null
    }

    private fun reconcileAutomaticTermAfterLaunch() {
        if (!preferences.automaticTermDetectionEnabled) return
        val resolved = automaticTermForCurrentLaunch()
        preferences.termID = resolved.termId
        preferences.termStartDate = resolved.termStartDate
    }

    private fun beginRefresh(): Long? = synchronized(refreshLock) {
        if (activeRefreshToken != null) return@synchronized null
        nextRefreshToken.incrementAndGet().also { activeRefreshToken = it }
    }

    private fun finishRefresh(token: Long) {
        synchronized(refreshLock) {
            if (activeRefreshToken == token) activeRefreshToken = null
        }
    }

    private fun isActiveRefresh(token: Long): Boolean = synchronized(refreshLock) {
        activeRefreshToken == token
    }
}
