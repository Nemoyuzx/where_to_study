package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

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
    private var activeRefreshToken: Long? = null

    @Volatile
    var schedule: ScheduleSnapshot? = loadCachedSchedule()
        private set

    val isRefreshing: Boolean
        get() = synchronized(refreshLock) { activeRefreshToken != null }

    fun refresh(onComplete: (Result<ScheduleSnapshot>) -> Unit) {
        val refreshGeneration = LocalDataCoordinator.snapshot()
        if (closed.get()) {
            mainHandler.post {
                onComplete(Result.failure(ScheduleClientException("个人课表获取服务已关闭。")))
            }
            return
        }
        val refreshToken = beginRefresh() ?: return

        try {
            worker.execute {
                val result = runCatching {
                    if (closed.get()) {
                        throw ScheduleClientException("个人课表获取服务已关闭。")
                    }
                    val request = LocalDataCoordinator.withCurrent(refreshGeneration) {
                        Triple(
                            credentialStore.load() ?: Credentials("", ""),
                            preferences.termID,
                            preferences.termStartDate,
                        )
                    }
                    client.fetch(request.first, request.second, request.third).let { fetched ->
                        val resolved = if (preferences.automaticTermDetectionEnabled) {
                            fetched
                        } else {
                            fetched.copy(termID = request.second, termStartDate = request.third)
                        }
                        LocalDataCoordinator.withCurrent(refreshGeneration) {
                            if (closed.get() || !isActiveRefresh(refreshToken)) {
                                throw ScheduleClientException("个人课表获取服务已关闭。")
                            }
                            store.save(resolved)
                            schedule = resolved
                            runCatching { TodayCourseWidgetProvider.refresh(appContext) }
                            preferences.termID = resolved.termID
                            preferences.termStartDate = resolved.termStartDate
                        }
                        resolved
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
        }
    }

    fun clearLocalData() {
        LocalDataCoordinator.clear(::clearLocalDataCoordinated)
    }

    internal fun clearLocalDataCoordinated() {
        store.clear()
        schedule = null
        runCatching { TodayCourseWidgetProvider.refresh(appContext) }
        synchronized(refreshLock) { activeRefreshToken = null }
    }

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
