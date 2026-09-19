package com.nemoyu.wheretostudy.nativeapp

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executors

internal class CourseReminderStateStore(context: Context) {
    private val preferences = context.getSharedPreferences("course_reminder_state_v1", Context.MODE_PRIVATE)
    val authorized: Boolean get() = preferences.getBoolean("authorized", false)
    val accountKey: String get() = preferences.getString("account_key", "").orEmpty()
    val token: String get() = preferences.getString("token", "").orEmpty()
    val scheduledAt: Long get() = preferences.getLong("scheduled_at", 0L)
    val keys: Set<String> get() = preferences.getStringSet("keys", emptySet()).orEmpty().toSet()
    val delivered: Set<String> get() = preferences.getStringSet("delivered", emptySet()).orEmpty().toSet()
    val exact: Boolean get() = preferences.getBoolean("exact", false)
    val registered: Boolean get() = preferences.getBoolean("registered", false)
    val recoveryToken: String get() = preferences.getString("recovery_token", "").orEmpty()
    val recoveryAttempt: Int get() = preferences.getInt("recovery_attempt", 0)
    val recoveryAt: Long get() = preferences.getLong("recovery_at", 0L)
    val recoveryOwner: String get() = preferences.getString("recovery_owner", "").orEmpty()
    val recoveryOffsets: String get() = preferences.getString("recovery_offsets", "").orEmpty()

    fun authorize(accountKey: String) {
        check(preferences.edit().putBoolean("authorized", true).putString("account_key", accountKey).commit())
    }

    fun revoke() {
        check(preferences.edit().clear().commit())
    }

    fun plan(token: String, scheduledAt: Long, keys: Set<String>, exact: Boolean, registered: Boolean = false) {
        check(preferences.edit().putString("token", token).putLong("scheduled_at", scheduledAt)
            .putStringSet("keys", keys).putBoolean("exact", exact).putBoolean("registered", registered).commit())
    }

    fun recovery(token: String, attempt: Int, at: Long, owner: String, offsets: String) {
        check(preferences.edit().putString("recovery_token", token).putInt("recovery_attempt", attempt)
            .putLong("recovery_at", at).putString("recovery_owner", owner).putString("recovery_offsets", offsets).commit())
    }

    fun markDelivered(keys: Set<String>, validKeys: Set<String>) {
        check(preferences.edit().putStringSet("delivered", (delivered + keys).intersect(validKeys)).commit())
    }
}

/** The Android I/O boundary also lets scheduler tests inject real failure paths. */
internal open class CourseReminderPlatform {
    open fun ownerKey(context: Context): String = CourseReminderScheduler.accountKey(context, throwOnFailure = true)
    open fun drafts(context: Context): List<CourseReminderDraft> = CourseReminderScheduler.loadDrafts(context)
    open fun register(context: Context, exact: Boolean, at: Long, intent: PendingIntent) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        if (exact) alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        else alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
    }
}

/** One next-time plan, with an independent inexact backup and bounded persisted recovery. */
internal object CourseReminderScheduler {
    const val ACTION_DELIVER = "com.nemoyu.wheretostudy.nativeapp.COURSE_REMINDER"
    const val EXTRA_TOKEN = "course_reminder_token"
    const val EXTRA_AT = "course_reminder_at"
    private const val REQUEST_CODE = 0x57545337
    private const val BACKUP_REQUEST_CODE = 0x57545339
    private val recoveryJobIDs = setOf(0x57545340, 0x57545341)
    internal const val RECOVERY_TOKEN = "recovery_token"
    internal const val RECOVERY_ATTEMPT = "recovery_attempt"
    internal const val maximumRecoveryAttempts = 3
    private const val RECOVERY_DELAY = 60_000L
    private val executionGate = DailyCourseNotificationExecutionGate()

    fun accountKey(context: Context, throwOnFailure: Boolean = false): String = SecureCredentialStore(context).load(throwOnFailure)?.account
        ?.takeIf(String::isNotBlank)?.let(CourseDeletionLogic::accountKey).orEmpty()

    fun hasExactAccess(context: Context): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

    @Synchronized
    fun authorize(context: Context): Boolean = runCatching {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return@runCatching false
        check(CourseReminderNotificationRuntime.hasPermission(context))
        CourseReminderStateStore(context).authorize(accountKey(context, throwOnFailure = true))
        setReceiverEnabled(context, true)
        AppPreferences(context).courseRemindersEnabled = true
        executionGate.authorize()
        // Delivery trouble must not silently revoke the user's saved opt-in.
        reconcile(context)
        true
    }.getOrElse { revoke(context); false }

    @Synchronized
    fun revoke(context: Context): Boolean {
        executionGate.revoke()
        if (DailyCourseNotificationRuntimeMode.isUiTesting) {
            return runCatching { AppPreferences(context).courseRemindersEnabled = false }.isSuccess
        }
        return performDailyCourseNotificationRevocation(
            revokeAuthorization = { CourseReminderStateStore(context).revoke() },
            disableService = { setReceiverEnabled(context, false) },
            disablePreference = { AppPreferences(context).courseRemindersEnabled = false },
            cancelRuntime = { cancel(context) },
        ).isPersistentlyFailClosed
    }

    @Synchronized
    fun cancel(context: Context) {
        executionGate.invalidate()
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return
        runCatching { CourseReminderStateStore(context).plan("", 0L, emptySet(), false) }
        runCatching { clearRecovery(context) }
        runCatching { cancelAlarm(context) }
        CourseReminderNotificationRuntime.cancel(context)
    }

    @Synchronized
    fun updateOffsets(context: Context, values: List<Int>): Boolean = runCatching {
        val normalized = CourseReminderPlanning.validateOffsets(values)
        val preferences = AppPreferences(context)
        if (normalized != preferences.courseReminderOffsets) {
            cancel(context)
            preferences.courseReminderOffsets = normalized
        }
        reconcile(context)
    }.getOrDefault(false)

    fun synchronizePermissionState(context: Context): Boolean {
        if (!AppPreferences(context).courseRemindersEnabled || CourseReminderNotificationRuntime.hasPermission(context)) return false
        revoke(context)
        return true
    }

    @Synchronized
    fun reconcile(context: Context, nowMillis: Long = System.currentTimeMillis(), force: Boolean = false,
        isActive: () -> Boolean = { !Thread.currentThread().isInterrupted },
        platform: CourseReminderPlatform = CourseReminderPlatform()): Boolean = runCatching {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return@runCatching true
        if (!isActive()) return@runCatching false
        val app = context.applicationContext
        val preferences = AppPreferences(app)
        val state = CourseReminderStateStore(app)
        if (!preferences.courseRemindersEnabled || !PrivacyConsentStore(app).hasAcceptedCurrentPolicy) {
            cancel(app)
            return@runCatching true
        }
        if (!isAuthorized(app, state, platform)) {
            revoke(app)
            return@runCatching true
        }
        val generation = LocalDataCoordinator.snapshot()
        val drafts = LocalDataCoordinator.withCurrent(generation) { platform.drafts(app) }
        if (!isActive() || !LocalDataCoordinator.isCurrent(generation)) return@runCatching false
        val batch = CourseReminderPlanning.nextBatch(drafts, nowMillis, state.delivered)
        val keys = batch.mapTo(mutableSetOf(), CourseReminderDraft::key)
        val at = batch.firstOrNull()?.fireAtMillis ?: 0L
        val exact = hasExactAccess(app)
        if (!force && at > 0 && state.registered && state.token.isNotEmpty() && state.scheduledAt == at && state.keys == keys && state.exact == exact) {
            clearRecovery(app)
            return@runCatching true
        }
        executionGate.invalidate()
        cancelAlarm(app)
        val token = if (batch.isEmpty()) "" else UUID.randomUUID().toString()
        state.plan(token, at, keys, exact)
        if (!isActive()) { cancel(app); return@runCatching false }
        if (batch.isNotEmpty()) {
            // Register the backup first. Revoking exact access removes exact alarms and kills
            // this process, but this separately identified inexact alarm remains able to wake it.
            platform.register(app, false, at, pendingIntent(app, token, at, backup = true))
            var exactRegistered = false
            if (exact) {
                try {
                    platform.register(app, true, at, pendingIntent(app, token, at, backup = false))
                    exactRegistered = true
                } catch (_: SecurityException) {
                    // A permission revocation racing registration leaves the backup usable.
                }
            }
            state.plan(token, at, keys, exactRegistered, registered = true)
        }
        clearRecovery(app)
        true
    }.getOrElse { scheduleRecovery(context, nowMillis, isActive = isActive) }

    /** Reload the effective schedule at delivery; never post a stale precomputed course body. */
    @Synchronized
    internal fun deliver(context: Context, token: String, scheduledAt: Long,
        nowMillis: Long = System.currentTimeMillis(), isActive: () -> Boolean = { !Thread.currentThread().isInterrupted },
        post: (CourseReminderDraft) -> Unit = { CourseReminderNotificationRuntime.show(context.applicationContext, it) },
        platform: CourseReminderPlatform = CourseReminderPlatform()): Boolean = runCatching {
        if (DailyCourseNotificationRuntimeMode.isUiTesting || !isActive()) return@runCatching false
        val app = context.applicationContext
        val state = CourseReminderStateStore(app)
        val revision = executionGate.snapshot()
        val generation = LocalDataCoordinator.snapshot()
        if (token.isEmpty() || token != state.token || scheduledAt != state.scheduledAt || !isAuthorized(app, state, platform)) {
            return@runCatching false
        }
        LocalDataCoordinator.withCurrent(generation) {
            val drafts = platform.drafts(app)
            val due = CourseReminderPlanning.deliverable(drafts, state.keys, scheduledAt, nowMillis, state.delivered)
            if (!isActive() || !executionGate.isCurrent(revision) || !isAuthorized(app, state, platform)) return@withCurrent
            val allKeys = drafts.mapTo(mutableSetOf(), CourseReminderDraft::key)
            due.forEach { reminder ->
                if (isActive() && executionGate.isCurrent(revision) && LocalDataCoordinator.isCurrent(generation)) {
                    // Persist first: a duplicate broadcast or a clock rollback must not notify again.
                    // A transient failure for one course must not interrupt this batch or future slots.
                    runCatching {
                        state.markDelivered(setOf(reminder.key), allKeys)
                        post(reminder)
                    }
                }
            }
        }
        if (isActive() && executionGate.isCurrent(revision) && LocalDataCoordinator.isCurrent(generation)) {
            // Successful processing replaces both alarms together. Any late backup carries
            // the old token and is rejected even if the OS already queued its broadcast.
            reconcile(app, nowMillis, force = true, isActive = isActive, platform = platform)
        }
        true
    }.getOrElse { scheduleRecovery(context, nowMillis, isActive = isActive) }

    internal fun executionRevision(): Long = executionGate.snapshot()
    internal fun isExecutionCurrent(revision: Long): Boolean = executionGate.isCurrent(revision)

    internal fun loadDrafts(context: Context): List<CourseReminderDraft> {
        val credentials = SecureCredentialStore(context).load(throwOnFailure = true) ?: return emptyList()
        if (credentials.account.isBlank() || credentials.password.isBlank()) return emptyList()
        return CourseReminderPlanning.expand(loadUsableSchedule(context, throwOnReadFailure = true),
            CourseDeletionLogic.accountKey(credentials.account), AppPreferences(context).courseReminderOffsets)
    }

    private fun isAuthorized(context: Context, state: CourseReminderStateStore,
        platform: CourseReminderPlatform = CourseReminderPlatform()): Boolean =
        PrivacyConsentStore(context).hasAcceptedCurrentPolicy && AppPreferences(context).courseRemindersEnabled &&
            state.authorized && state.accountKey == platform.ownerKey(context) &&
            context.packageManager.getComponentEnabledSetting(ComponentName(context, CourseReminderAlarmReceiver::class.java)) ==
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED && CourseReminderNotificationRuntime.hasPermission(context)

    private fun setReceiverEnabled(context: Context, enabled: Boolean) {
        context.packageManager.setComponentEnabledSetting(ComponentName(context, CourseReminderAlarmReceiver::class.java),
            if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP)
    }

    private fun pendingIntent(context: Context, token: String, at: Long, backup: Boolean): PendingIntent = PendingIntent.getBroadcast(
        context, if (backup) BACKUP_REQUEST_CODE else REQUEST_CODE,
        Intent(context, CourseReminderAlarmReceiver::class.java).setAction(ACTION_DELIVER)
            .putExtra(EXTRA_TOKEN, token).putExtra(EXTRA_AT, at),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun cancelAlarm(context: Context) {
        listOf(REQUEST_CODE, BACKUP_REQUEST_CODE).forEach { code ->
            val pending = PendingIntent.getBroadcast(context, code,
                Intent(context, CourseReminderAlarmReceiver::class.java).setAction(ACTION_DELIVER),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE) ?: return@forEach
            context.getSystemService(AlarmManager::class.java).cancel(pending)
            pending.cancel()
        }
    }

    internal fun isRecoveryJob(id: Int): Boolean = id in recoveryJobIDs

    private fun clearRecovery(context: Context) {
        try { CourseReminderStateStore(context).recovery("", 0, 0, "", "") }
        finally { recoveryJobIDs.forEach(context.getSystemService(JobScheduler::class.java)::cancel) }
    }

    private fun recoveryEligible(context: Context, state: CourseReminderStateStore): Boolean =
        !DailyCourseNotificationRuntimeMode.isUiTesting && state.authorized &&
            AppPreferences(context).courseRemindersEnabled && PrivacyConsentStore(context).hasAcceptedCurrentPolicy &&
            CourseReminderNotificationRuntime.hasPermission(context) &&
            context.packageManager.getComponentEnabledSetting(ComponentName(context, CourseReminderAlarmReceiver::class.java)) ==
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED

    /** JobScheduler is independent of AlarmManager, so alarm-registration failures can recover too. */
    private fun scheduleRecovery(context: Context, nowMillis: Long, replacePending: Boolean = false,
        isActive: () -> Boolean = { !Thread.currentThread().isInterrupted }): Boolean = runCatching {
        val app = context.applicationContext
        val state = CourseReminderStateStore(app)
        if (!isActive() || !recoveryEligible(app, state)) return@runCatching false
        val offsets = AppPreferences(app).courseReminderOffsets.joinToString(",")
        if (state.recoveryToken.isNotEmpty() && (state.recoveryOwner != state.accountKey || state.recoveryOffsets != offsets)) {
            clearRecovery(app)
        }
        if (!replacePending && state.recoveryAt > nowMillis &&
            app.getSystemService(JobScheduler::class.java).allPendingJobs.any { job ->
                isRecoveryJob(job.id) && job.extras.getString(RECOVERY_TOKEN) == state.recoveryToken &&
                    job.extras.getInt(RECOVERY_ATTEMPT) == state.recoveryAttempt
            }) return@runCatching true
        val token = state.recoveryToken.ifEmpty { UUID.randomUUID().toString() }
        val attempt = state.recoveryAttempt + 1
        if (attempt > maximumRecoveryAttempts) {
            state.recovery(token, maximumRecoveryAttempts, 0L, state.accountKey, offsets)
            recoveryJobIDs.forEach(app.getSystemService(JobScheduler::class.java)::cancel)
            return@runCatching false
        }
        val at = nowMillis + RECOVERY_DELAY
        state.recovery(token, attempt, at, state.accountKey, offsets)
        val job = JobInfo.Builder(recoveryJobIDs.elementAt((attempt - 1) % 2),
            ComponentName(app, CourseReminderRecoveryJobService::class.java))
            .setMinimumLatency(RECOVERY_DELAY).setOverrideDeadline(2 * RECOVERY_DELAY).setPersisted(true)
            .setExtras(android.os.PersistableBundle().apply {
                putString(RECOVERY_TOKEN, token); putInt(RECOVERY_ATTEMPT, attempt)
            }).build()
        app.getSystemService(JobScheduler::class.java).schedule(job) == JobScheduler.RESULT_SUCCESS
    }.getOrDefault(false)

    @Synchronized
    internal fun recover(context: Context, token: String, attempt: Int,
        nowMillis: Long = System.currentTimeMillis(), platform: CourseReminderPlatform = CourseReminderPlatform(),
        isActive: () -> Boolean = { !Thread.currentThread().isInterrupted }): Boolean {
        val state = CourseReminderStateStore(context)
        if (!matchesRecovery(context, state, token, attempt) || !isActive()) return false
        // A wall-clock rollback (or a forced system test) must not mistake this running
        // attempt for a future pending retry and then finish without scheduling its successor.
        state.recovery(token, attempt, minOf(nowMillis, state.recoveryAt), state.recoveryOwner, state.recoveryOffsets)
        // Reconciliation only schedules future times; a failed/expired slot is never replayed.
        return reconcile(context, nowMillis, force = true, isActive = isActive, platform = platform)
    }

    private fun matchesRecovery(context: Context, state: CourseReminderStateStore, token: String, attempt: Int): Boolean =
        token.isNotEmpty() && state.recoveryToken == token && state.recoveryAttempt == attempt &&
            state.recoveryAt > 0 && state.recoveryOwner == state.accountKey &&
            state.recoveryOffsets == AppPreferences(context).courseReminderOffsets.joinToString(",") &&
            recoveryEligible(context, state)

    @Synchronized
    internal fun recoveryStopped(context: Context, token: String, attempt: Int) {
        if (matchesRecovery(context, CourseReminderStateStore(context), token, attempt)) {
            scheduleRecovery(context, System.currentTimeMillis(), replacePending = true)
        }
    }
}

class CourseReminderRecoveryJobService : JobService() {
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val work = CancellableDailyCourseNotificationWork()
    @Volatile private var active: JobParameters? = null

    override fun onStartJob(params: JobParameters): Boolean {
        if (!CourseReminderScheduler.isRecoveryJob(params.jobId) || active != null) return false
        active = params
        work.submit(worker) {
            runCatching {
                CourseReminderScheduler.recover(applicationContext,
                    params.extras.getString(CourseReminderScheduler.RECOVERY_TOKEN).orEmpty(),
                    params.extras.getInt(CourseReminderScheduler.RECOVERY_ATTEMPT),
                    isActive = { active === params && !Thread.currentThread().isInterrupted })
            }
            handler.post {
                if (active === params) { active = null; work.complete(); jobFinished(params, false) }
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        if (active !== params) return false
        active = null
        work.cancel()
        val userStopped = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && params.stopReason in
            setOf(JobParameters.STOP_REASON_USER, JobParameters.STOP_REASON_CANCELLED_BY_APP)
        if (!userStopped) CourseReminderScheduler.recoveryStopped(applicationContext,
            params.extras.getString(CourseReminderScheduler.RECOVERY_TOKEN).orEmpty(),
            params.extras.getInt(CourseReminderScheduler.RECOVERY_ATTEMPT))
        return false
    }

    override fun onDestroy() {
        active = null; work.cancel(); handler.removeCallbacksAndMessages(null); worker.shutdownNow()
        super.onDestroy()
    }
}

class CourseReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != CourseReminderScheduler.ACTION_DELIVER) return
        val token = intent.getStringExtra(CourseReminderScheduler.EXTRA_TOKEN).orEmpty()
        val at = intent.getLongExtra(CourseReminderScheduler.EXTRA_AT, 0L)
        LocalBroadcastWork.submit(goAsync()) { active ->
            CourseReminderScheduler.deliver(context.applicationContext, token, at, isActive = active)
        }
    }
}

class CourseReminderRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action !in supportedActions) return
        LocalBroadcastWork.submit(goAsync()) { active ->
            CourseReminderScheduler.reconcile(context.applicationContext, force = true, isActive = active)
        }
    }

    private companion object {
        val supportedActions = setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_DATE_CHANGED, Intent.ACTION_MY_PACKAGE_REPLACED) +
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setOf(AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)
            else emptySet()
    }
}

internal object CourseReminderNotificationRuntime {
    private const val CHANNEL_ID = "course_reminders_v1"
    private const val NOTIFICATION_ID = 0x57545338
    private const val TAG_PREFIX = "course_reminder:"

    fun hasPermission(context: Context): Boolean {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            manager.getNotificationChannel(CHANNEL_ID)?.importance != NotificationManager.IMPORTANCE_NONE)
    }

    fun show(context: Context, reminder: CourseReminderDraft) {
        if (!PrivacyConsentStore(context).hasAcceptedCurrentPolicy || !hasPermission(context)) return
        val localized = AppLocale.wrap(context, AppPreferences(context).languageCode)
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, localized.getString(R.string.course_reminder_title),
                NotificationManager.IMPORTANCE_DEFAULT).apply { lockscreenVisibility = Notification.VISIBILITY_PRIVATE })
        }
        val time = SimpleDateFormat("HH:mm", Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("Asia/Shanghai") }
            .format(Date(reminder.startsAtMillis))
        val location = reminder.location.takeIf(String::isNotBlank)?.let { " · $it" }.orEmpty()
        val title = localized.getString(R.string.course_reminder_notification_title, reminder.leadMinutes)
        val courseTitle = if (reminder.title.startsWith("考试 · ")) {
            "${localized.uiText("考试")} · ${reminder.title.removePrefix("考试 · ")}"
        } else reminder.title
        val body = "$courseTitle · $time$location"
        val launch = PendingIntent.getActivity(context, NOTIFICATION_ID, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, CHANNEL_ID)
            else @Suppress("DEPRECATION") Notification.Builder(context)
        manager.notify(TAG_PREFIX + reminder.occurrenceKey, NOTIFICATION_ID,
            builder.setSmallIcon(R.drawable.ic_notification).setContentTitle(title).setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body)).setContentIntent(launch)
                .setCategory(Notification.CATEGORY_EVENT).setVisibility(Notification.VISIBILITY_PRIVATE)
                .setAutoCancel(true).build())
    }

    fun cancel(context: Context) {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.activeNotifications.filter { it.id == NOTIFICATION_ID && it.tag?.startsWith(TAG_PREFIX) == true }
            .forEach { manager.cancel(it.tag, it.id) }
    }
}
