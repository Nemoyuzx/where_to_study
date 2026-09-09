package com.nemoyu.wheretostudy.nativeapp

import android.Manifest
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
import android.os.PersistableBundle
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

data class DailyCourseSummaryDraft(
    val title: String,
    val body: String,
)

object DailyCourseSummaryLogic {
    const val defaultMinutes = 450
    const val runWindowMillis = 15L * 60L * 1_000L
    const val deliveryWindowMillis = 30L * 60L * 1_000L
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

    fun normalizedMinutes(value: Int): Int = value.takeIf { it in 0..1439 } ?: defaultMinutes

    fun formattedTime(minutes: Int): String = normalizedMinutes(minutes).let {
        String.format(Locale.US, "%02d:%02d", it / 60, it % 60)
    }

    fun dayKey(millis: Long): String = Calendar.getInstance(shanghai).run {
        timeInMillis = millis
        String.format(Locale.US, "%04d-%02d-%02d", get(Calendar.YEAR), get(Calendar.MONTH) + 1, get(Calendar.DAY_OF_MONTH))
    }

    private fun scheduledCalendar(dayMillis: Long, minutes: Int): Calendar =
        Calendar.getInstance(shanghai).apply {
            timeInMillis = dayMillis
            val validMinutes = normalizedMinutes(minutes)
            set(Calendar.HOUR_OF_DAY, validMinutes / 60)
            set(Calendar.MINUTE, validMinutes % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

    fun nextRunAt(afterMillis: Long, minutes: Int = defaultMinutes): Long {
        val candidate = scheduledCalendar(afterMillis, minutes)
        if (candidate.timeInMillis <= afterMillis) candidate.add(Calendar.DAY_OF_MONTH, 1)
        return candidate.timeInMillis
    }

    fun isWithinDeliveryWindow(
        nowMillis: Long,
        minutes: Int = defaultMinutes,
        scheduledAt: Long = scheduledCalendar(nowMillis, minutes).timeInMillis,
    ): Boolean = scheduledAt == scheduledCalendar(nowMillis, minutes).timeInMillis &&
        nowMillis in scheduledAt..(scheduledAt + deliveryWindowMillis)

    fun canDeliver(nowMillis: Long, minutes: Int, scheduledAt: Long, deliveredDay: String): Boolean =
        isWithinDeliveryWindow(nowMillis, minutes, scheduledAt) && dayKey(nowMillis) != deliveredDay

    fun reconciliationRunAt(nowMillis: Long, minutes: Int, deliveredDay: String): Long {
        val today = scheduledCalendar(nowMillis, minutes).timeInMillis
        return if (canDeliver(nowMillis, minutes, today, deliveredDay)) today else nextRunAt(nowMillis, minutes)
    }

    fun deliveryEndAt(scheduledAt: Long): Long {
        val midnight = Calendar.getInstance(shanghai).apply {
            timeInMillis = scheduledAt
            add(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        return minOf(scheduledAt + deliveryWindowMillis, midnight - 1)
    }

    fun matchesPlan(token: String, expectedToken: String, minutes: Int, expectedMinutes: Int,
        scheduledAt: Long, expectedAt: Long): Boolean = token.isNotEmpty() && token == expectedToken &&
        minutes == expectedMinutes && scheduledAt == expectedAt

    fun stoppedAction(currentPlan: Boolean, authorized: Boolean, userStopped: Boolean,
        nowMillis: Long, minutes: Int, scheduledAt: Long, deliveredDay: String): DailyCourseStoppedAction = when {
        !currentPlan || !authorized || userStopped -> DailyCourseStoppedAction.END
        canDeliver(nowMillis, minutes, scheduledAt, deliveredDay) -> DailyCourseStoppedAction.RETRY
        else -> DailyCourseStoppedAction.SCHEDULE_NEXT
    }

    fun draft(schedule: ScheduleSnapshot?, nowMillis: Long): DailyCourseSummaryDraft? {
        schedule ?: return null
        val target = Calendar.getInstance(shanghai).apply { timeInMillis = nowMillis }
        val courses = ScheduleLogic.courses(schedule, target)
        if (courses.isEmpty()) return null
        val entries = courses.map { course ->
            val location = course.room.takeIf(String::isNotBlank)?.let { " @ $it" }.orEmpty()
            "${course.timeRange} ${course.name}$location"
        }
        return DailyCourseSummaryDraft(
            title = "今日课程 · ${courses.size} 门",
            body = entries.joinToString("；"),
        )
    }

}

enum class DailyCourseStoppedAction { END, RETRY, SCHEDULE_NEXT }

enum class DailyCourseSummaryScheduleAction {
    CLEAR,
    RESCHEDULE,
}

object DailyCourseSummaryReconcileLogic {
    fun action(
        enabled: Boolean,
        permissionGranted: Boolean,
        hasCredentials: Boolean,
        hasSchedule: Boolean,
    ): DailyCourseSummaryScheduleAction = if (
        enabled && permissionGranted && hasCredentials && hasSchedule
    ) {
        DailyCourseSummaryScheduleAction.RESCHEDULE
    } else {
        DailyCourseSummaryScheduleAction.CLEAR
    }
}

internal class DailyCourseNotificationExecutionGate {
    private val revision = AtomicLong(0)
    private val revoked = AtomicBoolean(false)

    fun authorize() {
        revoked.set(false)
        revision.incrementAndGet()
    }

    fun revoke() {
        revoked.set(true)
        revision.incrementAndGet()
    }

    fun snapshot(): Long = revision.get()

    fun invalidate() { revision.incrementAndGet() }

    fun isCurrent(expectedRevision: Long): Boolean =
        !revoked.get() && revision.get() == expectedRevision
}

internal class CancellableDailyCourseNotificationWork {
    private val lock = Any()
    private var future: Future<*>? = null

    fun submit(executor: ExecutorService, operation: () -> Unit) {
        synchronized(lock) {
            check(future == null) { "课程摘要后台任务已在运行。" }
            future = executor.submit(operation)
        }
    }

    fun complete() {
        synchronized(lock) { future = null }
    }

    fun cancel() {
        synchronized(lock) {
            future?.cancel(true)
            future = null
        }
    }
}

internal data class DailyCourseNotificationRevocationOutcome(
    val authorizationRevoked: Boolean,
    val serviceDisabled: Boolean,
    val preferenceDisabled: Boolean,
) {
    val isComplete: Boolean
        get() = authorizationRevoked && serviceDisabled && preferenceDisabled

    val isPersistentlyFailClosed: Boolean
        get() = authorizationRevoked || serviceDisabled || preferenceDisabled
}

internal fun performDailyCourseNotificationRevocation(
    revokeAuthorization: () -> Unit,
    disableService: () -> Unit,
    disablePreference: () -> Unit,
    cancelRuntime: () -> Unit,
): DailyCourseNotificationRevocationOutcome {
    val authorizationRevoked = runCatching(revokeAuthorization).isSuccess
    val serviceDisabled = runCatching(disableService).isSuccess
    val preferenceDisabled = runCatching(disablePreference).isSuccess
    cancelRuntime()
    return DailyCourseNotificationRevocationOutcome(
        authorizationRevoked = authorizationRevoked,
        serviceDisabled = serviceDisabled,
        preferenceDisabled = preferenceDisabled,
    )
}

internal class DailyCourseNotificationAuthorizationStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    val isAuthorized: Boolean
        get() = preferences.getBoolean(AUTHORIZED_KEY, false)

    fun authorize() = save(true)

    fun revoke() = save(false)

    private fun save(value: Boolean) {
        if (!preferences.edit().putBoolean(AUTHORIZED_KEY, value).commit()) {
            throw IllegalStateException("无法保存课程摘要通知授权状态。")
        }
    }

    private companion object {
        const val PREFERENCES_NAME = "daily_course_notification_authorization_v1"
        const val AUTHORIZED_KEY = "authorized"
    }
}

internal object DailyCourseNotificationRuntimeMode {
    const val UI_TEST_INTENT_EXTRA =
        "com.nemoyu.wheretostudy.nativeapp.extra.UI_TEST_MODE"

    @Volatile
    private var uiTesting = false

    val isUiTesting: Boolean
        get() = uiTesting

    fun activateFrom(intent: Intent?) {
        if (BuildConfig.DEBUG && intent?.getBooleanExtra(UI_TEST_INTENT_EXTRA, false) == true) {
            uiTesting = true
        }
    }
}

interface DailyCourseSummaryScheduling {
    fun reconcile(context: Context): Boolean
    fun cancel(context: Context)
}

object DailyCourseSummaryScheduler : DailyCourseSummaryScheduling {
    internal const val JOB_MINUTES = "minutes"
    internal const val JOB_SCHEDULED_AT = "scheduled_at"
    internal const val JOB_TOKEN = "schedule_token"
    private const val PRIMARY_JOB_ID = 0x57545317
    private const val SECONDARY_JOB_ID = 0x57545318
    private val jobIDs = setOf(PRIMARY_JOB_ID, SECONDARY_JOB_ID)
    private val executionGate = DailyCourseNotificationExecutionGate()

    override fun reconcile(context: Context): Boolean = reconcileAt(context)

    @Synchronized
    internal fun reconcileAt(context: Context, nowMillis: Long = System.currentTimeMillis(),
        forceReschedule: Boolean = false, isActive: () -> Boolean = { !Thread.currentThread().isInterrupted }): Boolean = runCatching {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return@runCatching true
        if (!isActive()) return@runCatching false
        val appContext = context.applicationContext
        if (!PrivacyConsentStore(appContext).hasAcceptedCurrentPolicy) {
            cancel(appContext)
            return@runCatching true
        }
        val preferences = AppPreferences(appContext)
        val authorization = DailyCourseNotificationAuthorizationStore(appContext)
        val permissionGranted = DailyCourseSummaryNotificationRuntime.hasPermission(appContext)
        if (preferences.dailyCourseNotificationsEnabled && !permissionGranted) {
            revoke(appContext)
            return@runCatching true
        }
        val credentials = SecureCredentialStore(appContext).load()
        val schedule = loadUsableSchedule(appContext)
        if (!isActive()) return@runCatching false
        if (preferences.dailyCourseNotificationsEnabled &&
            (!authorization.isAuthorized || !isJobServiceExplicitlyEnabled(appContext) ||
                credentials?.account?.isNotBlank() != true ||
                credentials.password.isBlank())
        ) {
            revoke(appContext)
            return@runCatching true
        }
        val action = DailyCourseSummaryReconcileLogic.action(
            enabled = preferences.dailyCourseNotificationsEnabled && authorization.isAuthorized,
            permissionGranted = permissionGranted,
            hasCredentials = credentials?.account?.isNotBlank() == true &&
                credentials.password.isNotBlank(),
            hasSchedule = schedule != null,
        )
        if (action == DailyCourseSummaryScheduleAction.CLEAR) {
            cancel(appContext)
            return@runCatching true
        }
        val minutes = preferences.dailyCourseNotificationMinutes
        val scheduledAt = DailyCourseSummaryLogic.reconciliationRunAt(nowMillis, minutes,
            preferences.dailyCourseNotificationDeliveredDay)
        val pending = appContext.getSystemService(JobScheduler::class.java).allPendingJobs
            .filter { isManagedJob(it.id) }
        if (!forceReschedule && pending.any { job ->
            DailyCourseSummaryLogic.matchesPlan(job.extras.getString(JOB_TOKEN).orEmpty(),
                preferences.dailyCourseNotificationScheduleToken, job.extras.getInt(JOB_MINUTES, -1),
                minutes, job.extras.getLong(JOB_SCHEDULED_AT, 0L), scheduledAt)
        }) return@runCatching true
        invalidateSchedule(appContext)
        if (!isActive()) return@runCatching false
        schedule(appContext, PRIMARY_JOB_ID, nowMillis, scheduledAt)
    }.getOrDefault(false)

    @Synchronized
    override fun cancel(context: Context) {
        executionGate.invalidate()
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return
        val appContext = context.applicationContext
        runCatching { AppPreferences(appContext).dailyCourseNotificationScheduleToken = "" }
        runCatching { cancelJobs(appContext) }
        DailyCourseSummaryNotificationRuntime.cancel(appContext)
    }

    @Synchronized
    fun authorize(context: Context): Boolean {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return false
        val appContext = context.applicationContext
        return runCatching {
            check(DailyCourseSummaryNotificationRuntime.hasPermission(appContext)) {
                "通知权限未开启。"
            }
            AppPreferences(appContext).dailyCourseNotificationsEnabled = true
            DailyCourseNotificationAuthorizationStore(appContext).authorize()
            setJobServiceEnabled(appContext, true)
            executionGate.authorize()
            true
        }.getOrElse {
            revoke(appContext)
            false
        }
    }

    @Synchronized
    fun revoke(context: Context): Boolean {
        val appContext = context.applicationContext
        executionGate.revoke()
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return true

        val outcome = performDailyCourseNotificationRevocation(
            revokeAuthorization = {
                DailyCourseNotificationAuthorizationStore(appContext).revoke()
            },
            disableService = { setJobServiceEnabled(appContext, false) },
            disablePreference = {
                AppPreferences(appContext).dailyCourseNotificationsEnabled = false
            },
            cancelRuntime = { cancel(appContext) },
        )
        return outcome.isPersistentlyFailClosed
    }

    fun synchronizePermissionState(context: Context): Boolean {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return false
        val appContext = context.applicationContext
        val preferences = AppPreferences(appContext)
        if (!preferences.dailyCourseNotificationsEnabled ||
            DailyCourseSummaryNotificationRuntime.hasPermission(appContext)
        ) {
            return false
        }
        revoke(appContext)
        return true
    }

    fun isManagedJob(jobID: Int): Boolean = jobID in jobIDs

    fun managedJobIDs(): Set<Int> = jobIDs

    fun executionRevision(): Long = executionGate.snapshot()

    fun isExecutionCurrent(revision: Long): Boolean = executionGate.isCurrent(revision)

    @Synchronized
    fun updateTime(context: Context, minutes: Int): Boolean = runCatching {
        if (AppPreferences(context).dailyCourseNotificationMinutes == DailyCourseSummaryLogic.normalizedMinutes(minutes)) {
            return@runCatching reconcile(context)
        }
        executionGate.invalidate()
        AppPreferences(context).dailyCourseNotificationMinutes = minutes
        reconcile(context)
    }.getOrDefault(false)

    private fun invalidateSchedule(context: Context) {
        executionGate.invalidate()
        AppPreferences(context).dailyCourseNotificationScheduleToken = UUID.randomUUID().toString()
        cancelJobs(context)
    }

    @Synchronized
    fun scheduleAfterCompletion(context: Context, completedJobID: Int,
        expectedToken: String? = null, expectedRevision: Long? = null, expectedGeneration: Long? = null): Boolean = runCatching {
        val appContext = context.applicationContext
        val preferences = AppPreferences(appContext)
        if ((expectedToken != null && expectedToken != preferences.dailyCourseNotificationScheduleToken) ||
            (expectedRevision != null && !isExecutionCurrent(expectedRevision)) ||
            (expectedGeneration != null && !LocalDataCoordinator.isCurrent(expectedGeneration))) return@runCatching true
        if (preferences.dailyCourseNotificationsEnabled &&
            (!DailyCourseSummaryNotificationRuntime.hasPermission(appContext) ||
                !DailyCourseNotificationAuthorizationStore(appContext).isAuthorized ||
                !isJobServiceExplicitlyEnabled(appContext))
        ) {
            revoke(appContext)
            return@runCatching true
        }
        val nextJobID = if (completedJobID == PRIMARY_JOB_ID) {
            SECONDARY_JOB_ID
        } else {
            PRIMARY_JOB_ID
        }
        if (!canSchedule(appContext)) {
            cancel(appContext)
            true
        } else {
            schedule(appContext, nextJobID)
        }
    }.getOrDefault(false)

    @Synchronized
    internal fun withCurrentExecution(context: Context, token: String, revision: Long, generation: Long,
        operation: () -> Unit) {
        if (token.isNotEmpty() && token == AppPreferences(context).dailyCourseNotificationScheduleToken &&
            isExecutionCurrent(revision) && LocalDataCoordinator.isCurrent(generation)) operation()
    }

    @Synchronized
    internal fun retryAfterStop(context: Context, jobID: Int, minutes: Int, scheduledAt: Long,
        token: String, revision: Long, generation: Long, userStopped: Boolean,
        nowMillis: Long = System.currentTimeMillis()): Boolean = runCatching {
        val preferences = AppPreferences(context)
        val current = token.isNotEmpty() && token == preferences.dailyCourseNotificationScheduleToken &&
            minutes == preferences.dailyCourseNotificationMinutes && isExecutionCurrent(revision) &&
            LocalDataCoordinator.isCurrent(generation)
        val authorized = preferences.dailyCourseNotificationsEnabled &&
            DailyCourseNotificationAuthorizationStore(context).isAuthorized &&
            isJobServiceExplicitlyEnabled(context) && PrivacyConsentStore(context).hasAcceptedCurrentPolicy &&
            DailyCourseSummaryNotificationRuntime.hasPermission(context)
        when (DailyCourseSummaryLogic.stoppedAction(current, authorized, userStopped, nowMillis,
            minutes, scheduledAt, preferences.dailyCourseNotificationDeliveredDay)) {
            DailyCourseStoppedAction.END -> false
            DailyCourseStoppedAction.RETRY -> true
            DailyCourseStoppedAction.SCHEDULE_NEXT -> {
                // Use the other ID: the system is still finishing removal of the stopped ID.
                val nextID = if (jobID == PRIMARY_JOB_ID) SECONDARY_JOB_ID else PRIMARY_JOB_ID
                !schedule(context, nextID, nowMillis)
            }
        }
    }.getOrDefault(false)

    private fun canSchedule(context: Context): Boolean {
        if (!PrivacyConsentStore(context).hasAcceptedCurrentPolicy) return false
        val credentials = SecureCredentialStore(context).load()
        val hasSchedule = loadUsableSchedule(context) != null
        return DailyCourseSummaryReconcileLogic.action(
            enabled = AppPreferences(context).dailyCourseNotificationsEnabled &&
                DailyCourseNotificationAuthorizationStore(context).isAuthorized &&
                isJobServiceExplicitlyEnabled(context),
            permissionGranted = DailyCourseSummaryNotificationRuntime.hasPermission(context),
            hasCredentials = credentials?.account?.isNotBlank() == true &&
                credentials.password.isNotBlank(),
            hasSchedule = hasSchedule,
        ) == DailyCourseSummaryScheduleAction.RESCHEDULE
    }

    private fun cancelJobs(context: Context) {
        val scheduler = context.getSystemService(JobScheduler::class.java)
        jobIDs.forEach(scheduler::cancel)
    }

    private fun setJobServiceEnabled(context: Context, enabled: Boolean) {
        context.packageManager.setComponentEnabledSetting(
            ComponentName(context, DailyCourseSummaryJobService::class.java),
            if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            },
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun isJobServiceExplicitlyEnabled(context: Context): Boolean =
        context.packageManager.getComponentEnabledSetting(
            ComponentName(context, DailyCourseSummaryJobService::class.java),
        ) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED

    private fun schedule(
        context: Context,
        jobID: Int,
        nowMillis: Long = System.currentTimeMillis(),
        scheduledAt: Long = DailyCourseSummaryLogic.nextRunAt(nowMillis, AppPreferences(context).dailyCourseNotificationMinutes),
    ): Boolean {
        val preferences = AppPreferences(context)
        val minutes = preferences.dailyCourseNotificationMinutes
        val delay = (scheduledAt - nowMillis).coerceAtLeast(0L)
        val deadline = minOf(scheduledAt + DailyCourseSummaryLogic.runWindowMillis,
            DailyCourseSummaryLogic.deliveryEndAt(scheduledAt)) - nowMillis
        val job = JobInfo.Builder(
            jobID,
            ComponentName(context, DailyCourseSummaryJobService::class.java),
        )
            .setMinimumLatency(delay)
            .setOverrideDeadline(deadline.coerceAtLeast(0L))
            .setPersisted(true)
            .setExtras(PersistableBundle().apply {
                putInt(JOB_MINUTES, minutes)
                putLong(JOB_SCHEDULED_AT, scheduledAt)
                putString(JOB_TOKEN, preferences.dailyCourseNotificationScheduleToken)
            })
            .build()
        return context.getSystemService(JobScheduler::class.java).schedule(job) ==
            JobScheduler.RESULT_SUCCESS
    }
}

class DailyCourseSummaryJobService : JobService() {
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val activeWork = CancellableDailyCourseNotificationWork()
    @Volatile
    private var activeParameters: JobParameters? = null
    private var activeGeneration = 0L
    private var activeRevision = 0L

    override fun onStartJob(params: JobParameters): Boolean {
        if (!DailyCourseSummaryScheduler.isManagedJob(params.jobId) || activeParameters != null) {
            return false
        }
        if (!PrivacyConsentStore(applicationContext).hasAcceptedCurrentPolicy) {
            DailyCourseSummaryScheduler.cancel(applicationContext)
            return false
        }
        activeParameters = params
        val generation = LocalDataCoordinator.snapshot()
        val notificationRevision = DailyCourseSummaryScheduler.executionRevision()
        activeGeneration = generation
        activeRevision = notificationRevision
        val minutes = params.extras.getInt(DailyCourseSummaryScheduler.JOB_MINUTES, DailyCourseSummaryLogic.defaultMinutes)
        val scheduledAt = params.extras.getLong(DailyCourseSummaryScheduler.JOB_SCHEDULED_AT, 0L)
        val token = params.extras.getString(DailyCourseSummaryScheduler.JOB_TOKEN).orEmpty()
        fun isCurrentPlan(): Boolean {
            val preferences = AppPreferences(applicationContext)
            return token.isNotEmpty() && token == preferences.dailyCourseNotificationScheduleToken &&
                minutes == preferences.dailyCourseNotificationMinutes &&
                DailyCourseSummaryScheduler.isExecutionCurrent(notificationRevision)
        }
        activeWork.submit(worker) {
            if (Thread.currentThread().isInterrupted) return@submit
            val nowMillis = System.currentTimeMillis()
            val draft = runCatching {
                LocalDataCoordinator.withCurrent(generation) {
                    val context = applicationContext
                    val credentials = SecureCredentialStore(context).load()
                    val enabled = AppPreferences(context).dailyCourseNotificationsEnabled
                    val authorized = DailyCourseNotificationAuthorizationStore(context).isAuthorized
                    if (!enabled || !authorized || credentials?.account?.isBlank() != false ||
                        credentials.password.isBlank() ||
                        !DailyCourseSummaryNotificationRuntime.hasPermission(context) ||
                        !isCurrentPlan() ||
                        !DailyCourseSummaryLogic.canDeliver(nowMillis, minutes, scheduledAt,
                            AppPreferences(context).dailyCourseNotificationDeliveredDay)
                    ) {
                        null
                    } else {
                        DailyCourseSummaryLogic.draft(
                            loadUsableSchedule(context),
                            nowMillis,
                        )
                    }
                }
            }.getOrNull()
            if (Thread.currentThread().isInterrupted) return@submit
            mainHandler.post {
                if (activeParameters !== params) return@post
                activeParameters = null
                activeWork.complete()
                DailyCourseSummaryScheduler.withCurrentExecution(applicationContext, token, notificationRevision, generation) {
                    val deliveryMillis = System.currentTimeMillis()
                    val preferences = AppPreferences(applicationContext)
                    val canDeliver = isCurrentPlan() &&
                        DailyCourseSummaryLogic.canDeliver(deliveryMillis, minutes, scheduledAt,
                            preferences.dailyCourseNotificationDeliveredDay) &&
                        PrivacyConsentStore(applicationContext).hasAcceptedCurrentPolicy &&
                        AppPreferences(applicationContext).dailyCourseNotificationsEnabled &&
                        DailyCourseNotificationAuthorizationStore(applicationContext).isAuthorized &&
                        DailyCourseSummaryNotificationRuntime.hasPermission(applicationContext)
                    if (canDeliver) {
                        DailyCourseSummaryNotificationRuntime.cancel(applicationContext)
                        draft?.let {
                            // Persist before posting: retries and time edits must not notify twice today.
                            runCatching {
                                preferences.dailyCourseNotificationDeliveredDay = DailyCourseSummaryLogic.dayKey(deliveryMillis)
                                DailyCourseSummaryNotificationRuntime.show(applicationContext, it)
                            }
                        }
                    }
                }
                // A cancelled plan must never replace the job created by a time/account change.
                if (!isCurrentPlan() || !LocalDataCoordinator.isCurrent(generation)) {
                    jobFinished(params, false)
                    return@post
                }
                val nextScheduled = DailyCourseSummaryScheduler.scheduleAfterCompletion(
                    applicationContext,
                    params.jobId,
                    token, notificationRevision, generation,
                )
                jobFinished(params, !nextScheduled)
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        if (activeParameters !== params) return false
        activeParameters = null
        activeWork.cancel()
        val userStopped = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            params.stopReason in setOf(JobParameters.STOP_REASON_CANCELLED_BY_APP, JobParameters.STOP_REASON_USER)
        return DailyCourseSummaryScheduler.retryAfterStop(applicationContext, params.jobId,
            params.extras.getInt(DailyCourseSummaryScheduler.JOB_MINUTES, -1),
            params.extras.getLong(DailyCourseSummaryScheduler.JOB_SCHEDULED_AT, 0L),
            params.extras.getString(DailyCourseSummaryScheduler.JOB_TOKEN).orEmpty(),
            activeRevision, activeGeneration, userStopped)
    }

    override fun onDestroy() {
        activeParameters = null
        activeWork.cancel()
        mainHandler.removeCallbacksAndMessages(null)
        worker.shutdownNow()
        super.onDestroy()
    }
}

class DailyCourseSummaryRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action in supportedActions) {
            val appContext = context.applicationContext
            val timeChanged = intent?.action == Intent.ACTION_TIME_CHANGED
            LocalBroadcastWork.submit(goAsync()) { isActive ->
                DailyCourseSummaryScheduler.reconcileAt(appContext, forceReschedule = timeChanged, isActive = isActive)
            }
        }
    }

    private companion object {
        val supportedActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )
    }
}

object DailyCourseSummaryNotificationRuntime {
    private const val CHANNEL_ID = "daily_course_summary_v1"
    private const val NOTIFICATION_ID = 0x57545327

    fun hasPermission(context: Context): Boolean {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE
        ) {
            return false
        }
        return true
    }

    fun show(context: Context, draft: DailyCourseSummaryDraft) {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return
        if (!PrivacyConsentStore(context).hasAcceptedCurrentPolicy) return
        if (!hasPermission(context)) return
        val localizedContext = AppLocale.wrap(context, AppPreferences(context).languageCode)
        val manager = context.getSystemService(NotificationManager::class.java)
        ensureChannel(manager, localizedContext)
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        manager.notify(
            NOTIFICATION_ID,
            builder
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(localizedContext.uiText(draft.title))
                .setContentText(localizedContext.uiText(draft.body))
                .setStyle(Notification.BigTextStyle().bigText(localizedContext.uiText(draft.body)))
                .setContentIntent(pendingIntent)
                .setCategory(Notification.CATEGORY_EVENT)
                .setAutoCancel(true)
                .build(),
        )
    }

    fun cancel(context: Context) {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    fun isManagedNotification(notificationID: Int): Boolean = notificationID == NOTIFICATION_ID

    private fun ensureChannel(manager: NotificationManager, context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL_ID,
            context.uiText("每日课程摘要"),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.daily_course_notification_channel_description)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        })
    }
}
