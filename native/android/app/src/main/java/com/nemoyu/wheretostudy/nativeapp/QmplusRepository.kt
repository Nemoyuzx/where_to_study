package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.UUID

internal data class QmplusConnection(val generation: Long, val token: String)

/** Application-owned business cache only. WebView cookies stay in its separate process/profile. */
internal class QmplusRepository(context: Context,
    private val preferencesOverride: SharedPreferences? = null,
    private val beforeReadPublication: (() -> Unit)? = null,
    private val beforeSavePublication: (() -> Unit)? = null,
    private val afterSavePublication: (() -> Unit)? = null,
) {
    private val appContext = context.applicationContext
    private val prefs by lazy { preferencesOverride ?: appContext.getSharedPreferences("qmplus_business_cache", Context.MODE_PRIVATE) }
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val stateLock = Any()
    private val closed = AtomicBoolean(false)
    private var revision = 0L
    @Volatile var generation = 0L
        private set
    @Volatile var snapshot: QmplusSnapshot? = null
        private set
    @Volatile var isLoading = true
        private set
    @Volatile var error: String? = null
        private set
    @Volatile var cookiesNeedClearing = false
        private set
    @Volatile var isClearingSession = false
        private set
    @Volatile var connection: QmplusConnection? = null
        private set
    private val observers = ConcurrentHashMap<Any, () -> Unit>()

    init {
        val readRevision = revision
        worker.execute {
            val result = runCatching {
                val raw = synchronized(prefs) { Triple(prefs.getLong(GENERATION, 0),
                    prefs.getBoolean(COOKIE_CLEAR_PENDING, false), prefs.getString(SNAPSHOT, null)) }
                val cached = raw.third?.toByteArray(StandardCharsets.UTF_8)
                    ?.let(QmplusSnapshotCodec::decode)
                Triple(raw.first, raw.second, cached)
            }
            beforeReadPublication?.invoke()
            synchronized(stateLock) {
                if (closed.get() || revision != readRevision) return@execute
                result.onSuccess { (storedGeneration, pendingClear, cached) ->
                    val latest = prefs.getLong(GENERATION, 0)
                    generation = latest
                    cookiesNeedClearing = if (latest == storedGeneration) pendingClear else prefs.getBoolean(COOKIE_CLEAR_PENDING, false)
                    snapshot = cached.takeIf { latest == storedGeneration }
                }.onFailure { error = "无法读取 QMplus 课程缓存。" }
                isLoading = false
            }
            notifyObservers()
        }
    }

    fun addObserver(owner: Any, observer: () -> Unit) { if (!closed.get()) observers[owner] = observer }
    fun removeObserver(owner: Any) { observers.remove(owner) }
    fun clearUiObservers() { observers.clear() }

    fun beginConnection(): QmplusConnection? = synchronized(stateLock) {
        if (closed.get() || isLoading || isClearingSession || connection != null) return null
        // A second app Activity may have explicitly disconnected the shared QM profile.
        val storedGeneration = prefs.getLong(GENERATION, 0)
        if (storedGeneration != generation) {
            revision++; generation = storedGeneration; snapshot = null
            cookiesNeedClearing = prefs.getBoolean(COOKIE_CLEAR_PENDING, false)
        }
        QmplusConnection(generation, UUID.randomUUID().toString()).also { connection = it; notifyObservers() }
    }

    fun finishConnection(token: String?): Boolean = synchronized(stateLock) {
        val current = connection ?: return false
        if (token != current.token) return false
        connection = null; notifyObservers(); true
    }

    fun accept(bytes: ByteArray, expectedGeneration: Long) {
        val token = synchronized(stateLock) {
            if (closed.get() || isLoading || generation != expectedGeneration ||
                bytes.size > QmplusPolicy.MAXIMUM_SNAPSHOT_BYTES) return
            isLoading = true; error = null; revision
        }
        notifyObservers()
        try {
            worker.execute {
                val result = runCatching {
                    val incoming = QmplusSnapshotCodec.decode(bytes)
                    beforeSavePublication?.invoke()
                    val parsed = QmplusSnapshotCodec.preservingKnownActivities(incoming, snapshot)
                    val canonical = String(QmplusSnapshotCodec.encode(parsed), StandardCharsets.UTF_8)
                    synchronized(stateLock) { synchronized(prefs) {
                            check(!closed.get() && token == revision && expectedGeneration == generation &&
                                prefs.getLong(GENERATION, 0) == expectedGeneration)
                            check(prefs.edit().putString(SNAPSHOT, canonical).putLong(GENERATION, generation)
                                .putBoolean(COOKIE_CLEAR_PENDING, false).commit()) { "QMplus cache save failed." }
                            snapshot = parsed; cookiesNeedClearing = false
                    } }
                }
                val published = synchronized(stateLock) {
                    if (closed.get() || token != revision || expectedGeneration != generation) false else {
                        error = result.exceptionOrNull()?.let { "QMplus 同步或保存失败；保留上次课程缓存。" }
                        isLoading = false
                        true
                    }
                }
                if (published) notifyObservers()
                afterSavePublication?.invoke()
            }
        } catch (_: RejectedExecutionException) {
            synchronized(stateLock) { if (token == revision) isLoading = false }
        }
    }

    fun synchronizationFailed(expectedGeneration: Long) {
        synchronized(stateLock) {
            if (closed.get() || generation != expectedGeneration) return
            error = "QMplus 同步失败；保留上次课程缓存。"
        }
        notifyObservers()
    }

    fun cookiesCleared(expectedGeneration: Long) {
        try {
            worker.execute {
                synchronized(stateLock) { synchronized(prefs) {
                    if (closed.get() || expectedGeneration != generation || prefs.getLong(GENERATION, 0) != expectedGeneration) return@execute
                    if (prefs.edit().putBoolean(COOKIE_CLEAR_PENDING, false).commit()) cookiesNeedClearing = false
                    else error = "无法保存 QMplus 会话清除状态。"
                    isClearingSession = false
                } }
                notifyObservers()
            }
        } catch (_: RejectedExecutionException) { /* Final owner is closed; no view callback. */ }
    }

    fun cookieClearCouldNotStart(expectedGeneration: Long = generation) {
        synchronized(stateLock) {
            if (closed.get() || generation != expectedGeneration) return
            isClearingSession = false
            error = "QMplus 网页会话尚未清除；再次连接前会先清除旧会话。"
        }
        notifyObservers()
    }

    /** Full clear already uses the coordinator; invalidate before the durable removal. */
    fun clear() = synchronized(stateLock) { synchronized(prefs) {
        revision++
        connection = null
        generation = maxOf(generation, prefs.getLong(GENERATION, 0)) + 1
        snapshot = null; isLoading = false; error = null; cookiesNeedClearing = true; isClearingSession = true
        check(prefs.edit().remove(SNAPSHOT).putLong(GENERATION, generation)
            .putBoolean(COOKIE_CLEAR_PENDING, true).commit()) { "QMplus cache clear failed." }
        notifyObservers()
    } }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        synchronized(stateLock) { revision++; snapshot = null; connection = null }
        observers.clear(); handler.removeCallbacksAndMessages(null); worker.shutdownNow()
    }

    private fun notifyObservers() {
        if (!closed.get()) handler.post { if (!closed.get()) observers.values.toList().forEach { it() } }
    }

    private companion object {
        const val SNAPSHOT = "snapshot_v1"
        const val GENERATION = "clear_generation"
        const val COOKIE_CLEAR_PENDING = "cookie_clear_pending"
    }
}
