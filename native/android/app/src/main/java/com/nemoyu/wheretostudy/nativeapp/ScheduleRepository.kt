package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class ScheduleRepository(
    context: Context,
    private val credentialStore: SecureCredentialStore,
    private val preferences: AppPreferences,
    private val client: SjdScheduleClient = SjdScheduleClient(),
    private val store: ScheduleStore = ScheduleStore(context.applicationContext),
) {
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val refreshInFlight = AtomicBoolean(false)
    private val dataGeneration = AtomicLong(0)

    @Volatile
    var schedule: ScheduleSnapshot? = runCatching(store::load).getOrNull()
        private set

    val isRefreshing: Boolean
        get() = refreshInFlight.get()

    fun refresh(onComplete: (Result<ScheduleSnapshot>) -> Unit) {
        if (!refreshInFlight.compareAndSet(false, true)) return
        val credentials = credentialStore.load() ?: Credentials("", "")
        val fallbackTermID = preferences.termID
        val fallbackTermStartDate = preferences.termStartDate
        val refreshGeneration = dataGeneration.get()

        worker.execute {
            val result = runCatching {
                client.fetch(credentials, fallbackTermID, fallbackTermStartDate).also { fetched ->
                    if (dataGeneration.get() != refreshGeneration) {
                        throw ScheduleClientException("本地数据已清除，本次课表结果未保存。")
                    }
                    store.save(fetched)
                    schedule = fetched
                    preferences.termID = fetched.termID
                    preferences.termStartDate = fetched.termStartDate
                }
            }
            mainHandler.post {
                refreshInFlight.set(false)
                onComplete(result)
            }
        }
    }

    fun clearLocalData() {
        dataGeneration.incrementAndGet()
        store.clear()
        schedule = null
    }

    fun close() {
        worker.shutdownNow()
    }
}
