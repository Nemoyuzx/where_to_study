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
import java.util.Calendar
import java.util.TimeZone
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
    const val runWindowMillis = 15L * 60L * 1_000L
    const val deliveryWindowMillis = 30L * 60L * 1_000L
    private val shanghai = TimeZone.getTimeZone("Asia/Shanghai")

    fun nextRunAt(afterMillis: Long): Long {
        val now = Calendar.getInstance(shanghai).apply { timeInMillis = afterMillis }
        val candidate = Calendar.getInstance(shanghai).apply {
            clear()
            set(
                now.get(Calendar.YEAR),
                now.get(Calendar.MONTH),
                now.get(Calendar.DAY_OF_MONTH),
                7,
                30,
                0,
            )
        }
        if (candidate.timeInMillis <= afterMillis) candidate.add(Calendar.DAY_OF_MONTH, 1)
        return candidate.timeInMillis
    }

    fun isWithinDeliveryWindow(nowMillis: Long): Boolean {
        val now = Calendar.getInstance(shanghai).apply { timeInMillis = nowMillis }
        val scheduled = Calendar.getInstance(shanghai).apply {
            clear()
            set(
                now.get(Calendar.YEAR),
                now.get(Calendar.MONTH),
                now.get(Calendar.DAY_OF_MONTH),
                7,
                30,
                0,
            )
        }
        return nowMillis in scheduled.timeInMillis..(scheduled.timeInMillis + deliveryWindowMillis)
    }

    fun draft(schedule: ScheduleSnapshot?, nowMillis: Long): DailyCourseSummaryDraft? {
        schedule ?: return null
        val target = Calendar.getInstance(shanghai).apply { timeInMillis = nowMillis }
        val courses = ScheduleLogic.courses(schedule, target)
        if (courses.isEmpty()) return null
        val termStart = parseContractDate(schedule.termStartDate) ?: return null
        val week = ScheduleLogic.weekNumber(termStart, target)
        val entries = courses.map { course ->
            val name = if (week in course.examWeekNumbers) "${course.name}（试）" else course.name
            val location = course.room.takeIf(String::isNotBlank)?.let { " @ $it" }.orEmpty()
            "${course.timeRange} $name$location"
        }
        return DailyCourseSummaryDraft(
            title = "今日课程 · ${courses.size} 门",
            body = entries.joinToString("；"),
        )
    }

    private fun parseContractDate(value: String): Calendar? {
        val parts = value.split('-').mapNotNull(String::toIntOrNull)
        if (parts.size != 3) return null
        val date = Calendar.getInstance(shanghai).apply {
            isLenient = false
            clear()
            set(parts[0], parts[1] - 1, parts[2], 0, 0, 0)
        }
        return runCatching { date.timeInMillis }.map { date }.getOrNull()
    }
}

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
    private const val PRIMARY_JOB_ID = 0x57545317
    private const val SECONDARY_JOB_ID = 0x57545318
    private val jobIDs = setOf(PRIMARY_JOB_ID, SECONDARY_JOB_ID)
    private val executionGate = DailyCourseNotificationExecutionGate()

    override fun reconcile(context: Context): Boolean = runCatching {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return@runCatching true
        val appContext = context.applicationContext
        val preferences = AppPreferences(appContext)
        val authorization = DailyCourseNotificationAuthorizationStore(appContext)
        val permissionGranted = DailyCourseSummaryNotificationRuntime.hasPermission(appContext)
        if (preferences.dailyCourseNotificationsEnabled && !permissionGranted) {
            revoke(appContext)
            return@runCatching true
        }
        val credentials = SecureCredentialStore(appContext).load()
        val schedule = runCatching { ScheduleStore(appContext).load() }.getOrNull()
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
        cancelJobs(appContext)
        schedule(appContext, PRIMARY_JOB_ID)
    }.getOrDefault(false)

    override fun cancel(context: Context) {
        if (DailyCourseNotificationRuntimeMode.isUiTesting) return
        val appContext = context.applicationContext
        runCatching { cancelJobs(appContext) }
        DailyCourseSummaryNotificationRuntime.cancel(appContext)
    }

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

    fun scheduleAfterCompletion(context: Context, completedJobID: Int): Boolean = runCatching {
        val appContext = context.applicationContext
        val preferences = AppPreferences(appContext)
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

    private fun canSchedule(context: Context): Boolean {
        val credentials = SecureCredentialStore(context).load()
        val hasSchedule = runCatching { ScheduleStore(context).load() }.getOrNull() != null
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
    ): Boolean {
        val delay = (DailyCourseSummaryLogic.nextRunAt(nowMillis) - nowMillis).coerceAtLeast(0L)
        val job = JobInfo.Builder(
            jobID,
            ComponentName(context, DailyCourseSummaryJobService::class.java),
        )
            .setMinimumLatency(delay)
            .setOverrideDeadline(delay + DailyCourseSummaryLogic.runWindowMillis)
            .setPersisted(true)
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

    override fun onStartJob(params: JobParameters): Boolean {
        if (!DailyCourseSummaryScheduler.isManagedJob(params.jobId) || activeParameters != null) {
            return false
        }
        activeParameters = params
        val generation = LocalDataCoordinator.snapshot()
        val notificationRevision = DailyCourseSummaryScheduler.executionRevision()
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
                        !DailyCourseSummaryLogic.isWithinDeliveryWindow(nowMillis)
                    ) {
                        null
                    } else {
                        DailyCourseSummaryLogic.draft(
                            ScheduleStore(context).load(),
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
                val canDeliver = LocalDataCoordinator.isCurrent(generation) &&
                    DailyCourseSummaryScheduler.isExecutionCurrent(notificationRevision) &&
                    AppPreferences(applicationContext).dailyCourseNotificationsEnabled &&
                    DailyCourseNotificationAuthorizationStore(applicationContext).isAuthorized &&
                    DailyCourseSummaryNotificationRuntime.hasPermission(applicationContext)
                if (canDeliver) {
                    DailyCourseSummaryNotificationRuntime.cancel(applicationContext)
                    draft?.let { DailyCourseSummaryNotificationRuntime.show(applicationContext, it) }
                }
                val nextScheduled = DailyCourseSummaryScheduler.scheduleAfterCompletion(
                    applicationContext,
                    params.jobId,
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
        return false
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
            DailyCourseSummaryScheduler.reconcile(context.applicationContext)
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
        if (!hasPermission(context)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        ensureChannel(manager)
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
                .setContentTitle(draft.title)
                .setContentText(draft.body)
                .setStyle(Notification.BigTextStyle().bigText(draft.body))
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

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL_ID,
            "每日课程摘要",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "每天约 07:30 显示当天个人课程摘要"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        })
    }
}
