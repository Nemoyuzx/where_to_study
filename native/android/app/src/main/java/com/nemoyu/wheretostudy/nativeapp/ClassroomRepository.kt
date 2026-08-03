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
    private val lock = Any()
    private var refreshInFlight = false
    private val completions = mutableListOf<(Result<ClassroomsCache>) -> Unit>()
    val dataGeneration = AtomicLong(0)

    fun isRefreshing(): Boolean = synchronized(lock) { refreshInFlight }

    fun join(completion: (Result<ClassroomsCache>) -> Unit): Boolean = synchronized(lock) {
        completions += completion
        if (refreshInFlight) {
            false
        } else {
            refreshInFlight = true
            true
        }
    }

    fun complete(result: Result<ClassroomsCache>) {
        val pending = synchronized(lock) {
            refreshInFlight = false
            completions.toList().also { completions.clear() }
        }
        pending.forEach { completion -> runCatching { completion(result) } }
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
    private val ownsRefresh = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)

    @Volatile
    var cache: ClassroomsCache? = if (loadCachedData) {
        runCatching(store::load).getOrNull()?.takeIf { it.targetDate == today() }
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
                result.onSuccess { cache = it }
                mainHandler.post {
                    if (!closed.get()) onComplete(result)
                }
            }
        }
        if (!ClassroomRefreshProcessState.join(joinedCompletion)) {
            return
        }
        ownsRefresh.set(true)
        val refreshGeneration = ClassroomRefreshProcessState.dataGeneration.get()
        try {
            worker.execute {
                val result = runCatching {
                    if (closed.get()) {
                        throw ClassroomClientException("空教室获取服务已关闭。")
                    }
                    val credentials = credentialStore.load()
                    if (DailyClassroomRefreshLogic.refreshDecision(
                            credentials?.account,
                            credentials?.password,
                        ) == ClassroomRefreshDecision.SKIP_MISSING_CREDENTIALS
                    ) {
                        throw ClassroomClientException("请先在设置中保存教务账号和密码。")
                    }
                    val targetDate = today()
                    client.fetch(checkNotNull(credentials), targetDate).also { fetched ->
                        if (closed.get() ||
                            ClassroomRefreshProcessState.dataGeneration.get() != refreshGeneration
                        ) {
                            throw ClassroomClientException("本地数据已清除，本次空教室结果未保存。")
                        }
                        store.save(fetched)
                    }
                }
                completeRefresh(result)
            }
        } catch (_: RejectedExecutionException) {
            completeRefresh(Result.failure(ClassroomClientException("空教室获取服务已关闭。")))
        }
    }

    fun clearLocalData() {
        ClassroomRefreshProcessState.dataGeneration.incrementAndGet()
        store.clear()
        cache = null
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        val queuedTasks = worker.shutdownNow()
        if (queuedTasks.isNotEmpty()) {
            completeRefresh(Result.failure(ClassroomClientException("空教室获取服务已关闭。")))
        }
    }

    private fun completeRefresh(result: Result<ClassroomsCache>) {
        if (ownsRefresh.compareAndSet(true, false)) {
            ClassroomRefreshProcessState.complete(result)
        }
    }

    companion object {
        private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

        fun today(date: Date = Date()): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = shanghai
        }.format(date)
    }
}
