package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import java.lang.ref.WeakReference
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.UUID

internal data class QmplusConnection(val generation: Long, val token: String, val featureRevision: Long = 0)
internal data class QmplusCookieClearAttempt(val generation: Long, val token: Long)

/** Application-owned business cache only. WebView cookies stay in its separate process/profile. */
internal class QmplusRepository(context: Context,
    private val preferencesOverride: SharedPreferences? = null,
    private val beforeReadPublication: (() -> Unit)? = null,
    private val beforeSavePublication: (() -> Unit)? = null,
    private val afterSavePublication: (() -> Unit)? = null,
    private val cookieClearDeadlineMillis: Long = 10_000,
    credentialStoreOverride: QmplusCredentialStore? = null,
    featureStoreOverride: QmplusFeatureStore? = null,
    stopFeatureOwnerOverride: ((String?, Long?) -> Unit)? = null,
) {
    private val appContext = context.applicationContext
    private val prefs by lazy { preferencesOverride ?: appContext.getSharedPreferences("qmplus_business_cache", Context.MODE_PRIVATE) }
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val stateLock = Any()
    private val closed = AtomicBoolean(false)
    private val savedLoginStore = credentialStoreOverride ?: if (preferencesOverride == null) QmplusCredentialStore(appContext) else null
    private val featureStore = featureStoreOverride ?: if (preferencesOverride == null) QmplusFeatureStore(appContext.noBackupFilesDir) else null
    private val stopFeatureOwner = stopFeatureOwnerOverride
    private var featureRecord: QmplusFeatureRecord? = null
    private var featureMutationRevision = 0L
    private var restoringSnapshot = true
    @Volatile var isFeatureEnabled = preferencesOverride != null
        private set
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
    @Volatile var manualContinuationRequired = false
        private set
    @Volatile var pendingCookieClearAttempt: QmplusCookieClearAttempt? = null
        private set
    @Volatile var savedLoginStatus = QmplusCredentialStatus()
        private set
    @Volatile var isSavingLogin = false
        private set
    private var cookieClearDeadline: Runnable? = null
    private var pendingLoginPassword: CharArray? = null
    private var warmRefreshStarted = false
    private val observers = ConcurrentHashMap<Any, () -> Unit>()

    init {
        val readRevision = revision
        val readFeatureRevision = featureMutationRevision
        worker.execute {
            val result = runCatching {
                // A broken optional saved-login record must not erase readable course data.
                val loginStatus = runCatching { savedLoginStore?.status() }.getOrNull() ?: QmplusCredentialStatus()
                val raw = synchronized(prefs) { Triple(prefs.getLong(GENERATION, 0),
                    prefs.getBoolean(COOKIE_CLEAR_PENDING, false), prefs.getString(SNAPSHOT, null)) }
                val cached = raw.third?.toByteArray(StandardCharsets.UTF_8)
                    ?.let(QmplusSnapshotCodec::decode)
                Pair(Triple(raw.first, raw.second, cached), loginStatus)
            }
            beforeReadPublication?.invoke()
            synchronized(stateLock) {
                if (closed.get() || revision != readRevision) return@execute
                result.onSuccess { (business, loginStatus) ->
                    val (storedGeneration, pendingClear, cached) = business
                    val latest = prefs.getLong(GENERATION, 0)
                    generation = latest
                    cookiesNeedClearing = if (latest == storedGeneration) pendingClear else prefs.getBoolean(COOKIE_CLEAR_PENDING, false)
                    snapshot = cached.takeIf { latest == storedGeneration }
                    savedLoginStatus = loginStatus
                    if (preferencesOverride == null && featureMutationRevision == readFeatureRevision) {
                        val featureResult = runCatching {
                            val appPreferences = AppPreferences(appContext)
                            val mirror = checkNotNull(featureStore).status()
                            val enabled = QmplusFeatureMigrationPolicy.resolve(mirror, cached != null, loginStatus.enabled,
                                appPreferences::resolveQMplusMigration)
                            featureStore.setEnabled(enabled)
                        }
                        featureRecord = featureResult.getOrNull()
                        isFeatureEnabled = featureRecord?.enabled == true
                        if (featureResult.isFailure) error = "QMplus 同步失败；保留上次课程缓存。"
                    }
                }.onFailure { error = "无法读取 QMplus 课程缓存。" }
                restoringSnapshot = false
                isLoading = false
            }
            notifyObservers()
        }
    }

    fun addObserver(owner: Any, observer: () -> Unit) { if (!closed.get()) observers[owner] = observer }
    fun removeObserver(owner: Any) { observers.remove(owner) }
    fun clearUiObservers() { observers.clear() }

    fun setFeatureEnabled(enabled: Boolean): Boolean {
        var retiredToken: String? = null
        var retiredRevision: Long? = null
        val result = synchronized(stateLock) {
            if (closed.get()) return false
            featureMutationRevision++
            retiredToken = connection?.token
            retiredRevision = featureRecord?.revision ?: runCatching { featureStore?.status()?.revision }.getOrNull()
            val persisted = runCatching { featureStore?.setEnabled(enabled, renewOwner = enabled && !isFeatureEnabled)
                ?: QmplusFeatureRecord(featureMutationRevision, enabled) }
            featureRecord = persisted.getOrNull()
            isFeatureEnabled = persisted.isSuccess && enabled
            if (!isFeatureEnabled) {
                connection = null
                // Startup cache restoration is independent of network publication.
                if (!restoringSnapshot) { revision++; isLoading = false }
            }
            if (persisted.isFailure) error = "QMplus 同步失败；保留上次课程缓存。"
            persisted.isSuccess
        }
        if (!enabled || !result) {
            if (stopFeatureOwner != null) stopFeatureOwner.invoke(retiredToken, retiredRevision)
            else if (preferencesOverride == null) runCatching {
                appContext.startService(Intent(appContext, QmplusClearService::class.java)
                    .putExtra(QmplusClearService.EXTRA_STOP_ONLY, true)
                    .putExtra(QmplusActivity.EXTRA_CONNECTION_TOKEN, retiredToken)
                    .putExtra(QmplusActivity.EXTRA_FEATURE_REVISION, retiredRevision ?: -1))
            }
        }
        notifyObservers()
        return result
    }

    private fun featureIsCurrentLocked(): Boolean = isFeatureEnabled &&
        (featureStore == null || featureRecord?.let(featureStore::isCurrent) == true)

    fun claimWarmRefresh(): Boolean = synchronized(stateLock) {
        if (warmRefreshStarted || closed.get() || !featureIsCurrentLocked() || isLoading || isSavingLogin ||
            isClearingSession || cookiesNeedClearing || connection != null || (snapshot == null && !savedLoginStatus.enabled)) return false
        warmRefreshStarted = true; true
    }

    fun beginConnection(): QmplusConnection? = synchronized(stateLock) {
        if (closed.get() || !featureIsCurrentLocked() || isLoading || isSavingLogin || isClearingSession || connection != null) return null
        // A second app Activity may have explicitly disconnected the shared QM profile.
        val storedGeneration = prefs.getLong(GENERATION, 0)
        if (storedGeneration != generation) {
            cancelCookieClearDeadlineLocked()
            revision++; generation = storedGeneration; snapshot = null
            cookiesNeedClearing = prefs.getBoolean(COOKIE_CLEAR_PENDING, false)
        }
        QmplusConnection(generation, UUID.randomUUID().toString(), featureRecord?.revision ?: 0).also { connection = it; notifyObservers() }
    }

    fun finishConnection(token: String?): Boolean = synchronized(stateLock) {
        val current = connection ?: return false
        if (token != current.token) return false
        connection = null; notifyObservers(); true
    }

    /** Explicit save only. Invalidate the old QM identity before publishing a new saved login. */
    fun saveLogin(account: String, password: CharArray, explicitOptIn: Boolean, onComplete: (Result<Unit>) -> Unit) {
        val ownedPassword = password.copyOf()
        val token = synchronized(stateLock) {
            if (closed.get() || isLoading || isSavingLogin || isClearingSession || connection != null || !explicitOptIn ||
                !QmplusCredentialLimits.valid(account, ownedPassword) || savedLoginStore == null) {
                ownedPassword.fill('\u0000')
                if (!closed.get()) handler.post { if (!closed.get()) onComplete(Result.failure(IllegalStateException("QM saved-login request is unavailable."))) }
                return
            }
            isSavingLogin = true; pendingLoginPassword = ownedPassword
            Pair(revision, savedLoginStatus.revision)
        }
        notifyObservers()
        try {
            worker.execute {
                val result: Result<QmplusCredentialStatus> = try {
                    runCatching {
                        beforeSavePublication?.invoke()
                        synchronized(stateLock) {
                            check(!closed.get() && revision == token.first && savedLoginStore?.status()?.revision == token.second)
                            val store = checkNotNull(savedLoginStore)
                            // An explicit resave of the identical authorized
                            // record must not log out an otherwise valid session.
                            // Compare secrets only on this worker and erase the
                            // loaded buffer; a pending cleanup never takes this path.
                            val unchanged = if (savedLoginStatus.enabled && !cookiesNeedClearing) {
                                val saved = store.load(token.second)
                                try {
                                    saved != null && saved.account == account.trim() &&
                                        saved.password.contentEquals(ownedPassword) &&
                                        store.status() == savedLoginStatus
                                } finally { saved?.erase() }
                            } else false
                            if (unchanged) return@synchronized savedLoginStatus
                            clearInternal(preservingPendingLogin = true)
                            val savedStatus = store.save(account, ownedPassword, true, savedLoginStatus.revision)
                            savedLoginStatus = savedStatus
                            manualContinuationRequired = false
                            savedStatus
                        }
                    }
                } finally { ownedPassword.fill('\u0000') }
                synchronized(stateLock) { isSavingLogin = false; if (pendingLoginPassword === ownedPassword) pendingLoginPassword = null }
                notifyObservers()
                if (!closed.get()) handler.post {
                    if (!closed.get()) {
                        val current = synchronized(stateLock) { result.isFailure || result.getOrNull() == savedLoginStatus }
                        onComplete(if (current) result.map { Unit } else Result.failure(IllegalStateException("QM saved-login result was invalidated.")))
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            ownedPassword.fill('\u0000')
            synchronized(stateLock) { isSavingLogin = false; if (pendingLoginPassword === ownedPassword) pendingLoginPassword = null }
        }
    }

    fun accept(bytes: ByteArray, expectedGeneration: Long) {
        val token = synchronized(stateLock) {
            if (closed.get() || !featureIsCurrentLocked() || isLoading || isClearingSession || generation != expectedGeneration ||
                bytes.size > QmplusPolicy.MAXIMUM_SNAPSHOT_BYTES) return
            isLoading = true; error = null; revision
        }
        notifyObservers()
        try {
            worker.execute {
                var cacheWriteFailed = false
                val result = runCatching {
                    val incoming = QmplusSnapshotCodec.decode(bytes)
                    beforeSavePublication?.invoke()
                    val parsed = QmplusSnapshotCodec.preservingKnownActivities(incoming, snapshot)
                    val canonical = String(QmplusSnapshotCodec.encode(parsed), StandardCharsets.UTF_8)
                    synchronized(stateLock) {
                        val publish = { synchronized(prefs) {
                            check(!closed.get() && isFeatureEnabled && token == revision && expectedGeneration == generation &&
                                prefs.getLong(GENERATION, 0) == expectedGeneration)
                            cacheWriteFailed = !prefs.edit().putString(SNAPSHOT, canonical).putLong(GENERATION, generation)
                                .putBoolean(COOKIE_CLEAR_PENDING, false).commit()
                            snapshot = parsed; cookiesNeedClearing = false; manualContinuationRequired = false
                            cancelCookieClearDeadlineLocked()
                        } }
                        if (featureStore != null) featureStore.whileCurrent(checkNotNull(featureRecord), publish)
                        else publish()
                    }
                }
                val published = synchronized(stateLock) {
                    if (closed.get() || !featureIsCurrentLocked() || token != revision || expectedGeneration != generation) false else {
                        error = result.exceptionOrNull()?.let { "QMplus 同步或保存失败；保留上次课程缓存。" }
                            ?: if (cacheWriteFailed) "本次课程数据已读取，但本地缓存未更新。重启后可能显示此前缓存。" else null
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
            if (closed.get() || !featureIsCurrentLocked() || generation != expectedGeneration) return
            error = "QMplus 同步失败；保留上次课程缓存。"
        }
        notifyObservers()
    }

    fun synchronizationNotReady(expectedGeneration: Long) {
        synchronized(stateLock) {
            if (closed.get() || !featureIsCurrentLocked() || generation != expectedGeneration || connection != null) return
            // A delayed Moodle configuration is a retryable read, not a failed login.
            manualContinuationRequired = false
            error = "QMplus 同步失败；保留上次课程缓存。"
        }
        notifyObservers()
    }

    fun connectionExpired(expectedGeneration: Long = generation) {
        synchronized(stateLock) {
            if (closed.get() || !featureIsCurrentLocked() || generation != expectedGeneration || connection != null) return
            error = "QMplus 会话已过期，请重新登录。"
        }
        notifyObservers()
    }

    fun connectionRequired(expectedGeneration: Long = generation) {
        synchronized(stateLock) {
            if (closed.get() || !featureIsCurrentLocked() || generation != expectedGeneration || connection != null) return
            manualContinuationRequired = true
            error = "自动登录已暂停，可选择“手动继续”查看官方页面。"
        }
        notifyObservers()
    }

    fun cookiesCleared(expectedGeneration: Long, expectedClearToken: Long? = null) {
        try {
            worker.execute {
                synchronized(stateLock) { synchronized(prefs) {
                    if (closed.get() || expectedGeneration != generation || prefs.getLong(GENERATION, 0) != expectedGeneration) return@execute
                    if (expectedClearToken != null && pendingCookieClearAttempt?.token != expectedClearToken) return@execute
                    if (prefs.edit().putBoolean(COOKIE_CLEAR_PENDING, false).commit()) cookiesNeedClearing = false
                    else error = "无法保存 QMplus 会话清除状态。"
                    isClearingSession = false
                    cancelCookieClearDeadlineLocked()
                } }
                notifyObservers()
            }
        } catch (_: RejectedExecutionException) { /* Final owner is closed; no view callback. */ }
    }

    fun cookieClearCouldNotStart(expectedGeneration: Long = generation, expectedClearToken: Long? = null) {
        synchronized(stateLock) {
            if (closed.get() || generation != expectedGeneration) return
            if (expectedClearToken != null && pendingCookieClearAttempt?.token != expectedClearToken) return
            cancelCookieClearDeadlineLocked()
            isClearingSession = false
            error = "QMplus 网页会话尚未清除；再次连接前会先清除旧会话。"
        }
        notifyObservers()
    }

    /** Full clear already uses the coordinator; invalidate before the durable removal. */
    fun clear() = clearInternal(preservingPendingLogin = false)

    private fun clearInternal(preservingPendingLogin: Boolean) = synchronized(stateLock) { synchronized(prefs) {
        cancelCookieClearDeadlineLocked()
        revision++
        connection = null
        if (!preservingPendingLogin) { pendingLoginPassword?.fill('\u0000'); pendingLoginPassword = null }
        // Separate encrypted domain; a durable tombstone invalidates in-flight
        // decrypt/fill requests in the private WebView process as well.
        val loginClear = runCatching { savedLoginStore?.clear() ?: QmplusCredentialStatus(savedLoginStatus.revision + 1) }
        savedLoginStatus = loginClear.getOrNull() ?: QmplusCredentialStatus(savedLoginStatus.revision, false)
        generation = maxOf(generation, prefs.getLong(GENERATION, 0)) + 1
        snapshot = null; isLoading = false; error = null; cookiesNeedClearing = true; isClearingSession = true
        manualContinuationRequired = false
        armCookieClearDeadlineLocked()
        check(prefs.edit().remove(SNAPSHOT).putLong(GENERATION, generation)
            .putBoolean(COOKIE_CLEAR_PENDING, true).commit()) { "QMplus cache clear failed." }
        notifyObservers()
        check(loginClear.isSuccess) { "QM saved-login clear failed." }
    } }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        synchronized(stateLock) {
            revision++; snapshot = null; connection = null; isClearingSession = false; isSavingLogin = false
            pendingLoginPassword?.fill('\u0000'); pendingLoginPassword = null
            cancelCookieClearDeadlineLocked()
        }
        observers.clear(); handler.removeCallbacksAndMessages(null); worker.shutdownNow()
    }

    private fun notifyObservers() {
        if (!closed.get()) handler.post { if (!closed.get()) observers.values.toList().forEach { it() } }
    }

    private fun armCookieClearDeadlineLocked() {
        val attempt = QmplusCookieClearAttempt(generation, revision)
        pendingCookieClearAttempt = attempt
        val weakRepository = WeakReference(this)
        val deadline = Runnable {
            // A lost private-process ACK must not strand the retained owner.
            // This does not claim the cookies were cleared: the durable pending
            // marker remains true, so the next connection clears before login.
            weakRepository.get()?.cookieClearCouldNotStart(attempt.generation, attempt.token)
        }
        cookieClearDeadline = deadline
        handler.postDelayed(deadline, cookieClearDeadlineMillis.coerceAtLeast(1))
    }

    private fun cancelCookieClearDeadlineLocked() {
        cookieClearDeadline?.let(handler::removeCallbacks)
        cookieClearDeadline = null
        pendingCookieClearAttempt = null
    }

    private companion object {
        const val SNAPSHOT = "snapshot_v1"
        const val GENERATION = "clear_generation"
        const val COOKIE_CLEAR_PENDING = "cookie_clear_pending"
    }
}
