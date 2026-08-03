package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

private object ClassroomRefreshProcessState {
    private val registry = GenerationSingleFlight<ClassroomsCache> { LocalDataInvalidatedException() }

    fun isRefreshing(): Boolean = registry.isRunning()

    fun join(
        generation: Long,
        completion: (Result<ClassroomsCache>) -> Unit,
    ): GenerationSingleFlightRegistration = registry.join(generation, completion)

    fun complete(token: Long, result: Result<ClassroomsCache>) {
        registry.complete(token, result)
    }

    fun cancel(token: Long, error: Throwable) {
        registry.cancel(token, error)
    }

    fun invalidate() {
        registry.invalidate()
    }
}

class ClassroomRepository(
    context: Context,
    private val credentialStore: SecureCredentialStore,
    private val client: SjdClassroomClient = SjdClassroomClient(),
    private val store: ClassroomStore = ClassroomStore(context.applicationContext),
    loadCachedData: Boolean = true,
) {
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ownedRefreshToken = AtomicLong(NO_REFRESH_TOKEN)
    private val closed = AtomicBoolean(false)

    @Volatile
    var cache: ClassroomsCache? = if (loadCachedData) {
        loadCachedClassrooms()?.takeIf { it.targetDate == today() }
    } else {
        null
    }
        private set

    val isRefreshing: Boolean
        get() = ClassroomRefreshProcessState.isRefreshing()

    fun campus(campusID: String): CampusClassrooms? = cache?.campuses
        ?.firstOrNull { it.campusID == campusID }

    fun refresh(
        force: Boolean,
        onComplete: (Result<ClassroomsCache>) -> Unit,
    ) {
        val refreshGeneration = LocalDataCoordinator.snapshot()
        val current = cache
        if (!force && current?.targetDate == today()) {
            mainHandler.post { onComplete(Result.success(current)) }
            return
        }
        if (closed.get()) {
            mainHandler.post {
                onComplete(Result.failure(ClassroomClientException("空教室获取服务已关闭。")))
            }
            return
        }
        val joinedCompletion: (Result<ClassroomsCache>) -> Unit = { result ->
            if (!closed.get()) {
                mainHandler.post {
                    if (!closed.get()) {
                        val delivered = result.fold(
                            onSuccess = { fetched ->
                                runCatching {
                                    LocalDataCoordinator.withCurrent(refreshGeneration) {
                                        cache = fetched
                                        fetched
                                    }
                                }
                            },
                            onFailure = { Result.failure(it) },
                        )
                        onComplete(delivered)
                    }
                }
            }
        }
        val registration = ClassroomRefreshProcessState.join(
            refreshGeneration,
            joinedCompletion,
        )
        if (!registration.shouldStart) {
            return
        }
        ownedRefreshToken.set(registration.token)
        try {
            worker.execute {
                val result = runCatching {
                    if (closed.get()) {
                        throw ClassroomClientException("空教室获取服务已关闭。")
                    }
                    val credentials = LocalDataCoordinator.withCurrent(refreshGeneration) {
                        credentialStore.load()
                    }
                    if (DailyClassroomRefreshLogic.refreshDecision(
                            credentials?.account,
                            credentials?.password,
                    ) == ClassroomRefreshDecision.SKIP_MISSING_CREDENTIALS
                    ) {
                        throw ClassroomClientException(
                            "请先在设置中保存教务账号和密码。",
                            retryable = false,
                        )
                    }
                    val targetDate = today()
                    client.fetch(checkNotNull(credentials), targetDate).also { fetched ->
                        if (closed.get()) {
                            throw ClassroomClientException("空教室获取服务已关闭。")
                        }
                        LocalDataCoordinator.withCurrent(refreshGeneration) {
                            store.save(fetched)
                        }
                    }
                }
                val delivered = if (LocalDataCoordinator.isCurrent(refreshGeneration)) {
                    result
                } else {
                    Result.failure(LocalDataInvalidatedException())
                }
                completeRefresh(registration.token, delivered)
            }
        } catch (_: RejectedExecutionException) {
            completeRefresh(
                registration.token,
                Result.failure(ClassroomClientException("空教室获取服务已关闭。")),
            )
        }
    }

    fun clearLocalData() {
        LocalDataCoordinator.clear(::clearLocalDataCoordinated)
    }

    internal fun clearLocalDataCoordinated() {
        ClassroomRefreshProcessState.invalidate()
        ownedRefreshToken.set(NO_REFRESH_TOKEN)
        store.clear()
        cache = null
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        mainHandler.removeCallbacksAndMessages(null)
        val token = ownedRefreshToken.getAndSet(NO_REFRESH_TOKEN)
        if (token != NO_REFRESH_TOKEN) {
            ClassroomRefreshProcessState.cancel(
                token,
                ClassroomClientException("空教室获取服务已关闭。"),
            )
        }
        worker.shutdownNow()
    }

    private fun completeRefresh(token: Long, result: Result<ClassroomsCache>) {
        if (ownedRefreshToken.compareAndSet(token, NO_REFRESH_TOKEN)) {
            ClassroomRefreshProcessState.complete(token, result)
        }
    }

    private fun loadCachedClassrooms(): ClassroomsCache? {
        val generation = LocalDataCoordinator.snapshot()
        return runCatching {
            LocalDataCoordinator.withCurrent(generation, store::load)
        }.getOrNull()
    }

    companion object {
        private const val NO_REFRESH_TOKEN = 0L
        private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

        fun today(date: Date = Date()): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = shanghai
        }.format(date)
    }
}
