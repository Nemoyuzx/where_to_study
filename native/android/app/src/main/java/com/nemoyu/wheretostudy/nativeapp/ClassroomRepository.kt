package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class ClassroomRepository(
    context: Context,
    private val credentialStore: SecureCredentialStore,
    private val client: SjdClassroomClient = SjdClassroomClient(),
    private val store: ClassroomStore = ClassroomStore(context.applicationContext),
) {
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val refreshInFlight = AtomicBoolean(false)

    @Volatile
    var cache: ClassroomsCache? = runCatching(store::load).getOrNull()
        ?.takeIf { it.targetDate == today() }
        private set

    val isRefreshing: Boolean
        get() = refreshInFlight.get()

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
        if (!refreshInFlight.compareAndSet(false, true)) {
            mainHandler.post {
                onComplete(Result.failure(ClassroomClientException("正在获取当天空教室，请稍候。")))
            }
            return
        }
        val credentials = credentialStore.load() ?: Credentials("", "")
        val targetDate = today()
        worker.execute {
            val result = runCatching {
                client.fetch(credentials, targetDate).also { fetched ->
                    store.save(fetched)
                    cache = fetched
                }
            }
            mainHandler.post {
                refreshInFlight.set(false)
                onComplete(result)
            }
        }
    }

    fun close() {
        worker.shutdownNow()
    }

    companion object {
        private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

        fun today(date: Date = Date()): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = shanghai
        }.format(date)
    }
}
