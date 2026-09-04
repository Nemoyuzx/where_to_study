package com.nemoyu.wheretostudy.nativeapp

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

internal class DailyClassroomRetryStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun recordRetryIfAllowed(date: String): Boolean {
        val previousAttempts = if (preferences.getString(DATE_KEY, null) == date) {
            preferences.getInt(ATTEMPTS_KEY, 0)
        } else {
            0
        }
        if (!DailyClassroomRefreshLogic.canRequestRetry(previousAttempts)) return false
        return preferences.edit()
            .putString(DATE_KEY, date)
            .putInt(ATTEMPTS_KEY, previousAttempts + 1)
            .commit()
    }

    fun clear() {
        if (!preferences.edit().clear().commit()) {
            throw IllegalStateException("无法清除后台刷新状态。")
        }
    }

    private companion object {
        const val PREFERENCES_NAME = "daily_classroom_retry_v1"
        const val DATE_KEY = "date"
        const val ATTEMPTS_KEY = "attempts"
    }
}

object DailyClassroomRefreshScheduler {
    private const val PRIMARY_JOB_ID = 0x57545307
    private const val SECONDARY_JOB_ID = 0x57545308
    private val jobIDs = setOf(PRIMARY_JOB_ID, SECONDARY_JOB_ID)

    fun ensureScheduled(context: Context): Boolean = synchronized(this) {
        if (!PrivacyConsentStore(context).hasAcceptedCurrentPolicy) {
            return@synchronized cancel(context)
        }
        runCatching {
            val scheduler = context.getSystemService(JobScheduler::class.java)
            when (scheduleAction(context, scheduler, forceReschedule = false)) {
                DailyClassroomScheduleAction.CANCEL -> cancelState(context, scheduler)
                DailyClassroomScheduleAction.KEEP -> true
                DailyClassroomScheduleAction.SCHEDULE -> schedule(context, PRIMARY_JOB_ID)
            }
        }.onFailure { error ->
            Log.e(TAG, "Unable to ensure daily classroom refresh job", error)
        }.getOrDefault(false)
    }

    fun scheduleAfterCompletion(context: Context, completedJobID: Int): Boolean =
        synchronized(this) {
            if (!PrivacyConsentStore(context).hasAcceptedCurrentPolicy) {
                return@synchronized cancel(context)
            }
            runCatching {
                val scheduler = context.getSystemService(JobScheduler::class.java)
                when (scheduleAction(context, scheduler, forceReschedule = true)) {
                    DailyClassroomScheduleAction.CANCEL -> cancelState(context, scheduler)
                    DailyClassroomScheduleAction.KEEP -> true
                    DailyClassroomScheduleAction.SCHEDULE -> {
                        val nextJobID = if (completedJobID == PRIMARY_JOB_ID) {
                            SECONDARY_JOB_ID
                        } else {
                            PRIMARY_JOB_ID
                        }
                        schedule(context, nextJobID)
                    }
                }
            }.getOrDefault(false)
        }

    fun isManagedJob(jobID: Int): Boolean = jobID in jobIDs

    fun hasValidCredentials(context: Context): Boolean = runCatching {
        if (!PrivacyConsentStore(context).hasAcceptedCurrentPolicy) {
            return@runCatching false
        }
        val credentials = loadCredentials(context)
        DailyClassroomRefreshLogic.refreshDecision(
            credentials?.account,
            credentials?.password,
        ) == ClassroomRefreshDecision.FETCH
    }.getOrDefault(false)

    fun cancel(context: Context): Boolean = synchronized(this) {
        runCatching {
            cancelState(
                context,
                context.getSystemService(JobScheduler::class.java),
            )
        }.getOrDefault(false)
    }

    fun reschedule(context: Context): Boolean = synchronized(this) {
        if (!PrivacyConsentStore(context).hasAcceptedCurrentPolicy) {
            return@synchronized cancel(context)
        }
        runCatching {
            val scheduler = context.getSystemService(JobScheduler::class.java)
            when (scheduleAction(context, scheduler, forceReschedule = true)) {
                DailyClassroomScheduleAction.CANCEL -> cancelState(context, scheduler)
                DailyClassroomScheduleAction.KEEP -> true
                DailyClassroomScheduleAction.SCHEDULE -> {
                    cancelManagedJobs(scheduler) && schedule(context, PRIMARY_JOB_ID)
                }
            }
        }.getOrDefault(false)
    }

    private fun scheduleAction(
        context: Context,
        scheduler: JobScheduler,
        forceReschedule: Boolean,
    ): DailyClassroomScheduleAction {
        val credentials = loadCredentials(context)
        val hasValidCredentials = DailyClassroomRefreshLogic.refreshDecision(
            credentials?.account,
            credentials?.password,
        ) == ClassroomRefreshDecision.FETCH
        return DailyClassroomRefreshSchedulingLogic.action(
            account = credentials?.account,
            password = credentials?.password,
            hasPendingJob = hasValidCredentials &&
                scheduler.allPendingJobs.any { it.id in jobIDs },
            forceReschedule = forceReschedule,
        )
    }

    private fun cancelManagedJobs(scheduler: JobScheduler): Boolean {
        val cancelled = jobIDs.map { jobID ->
            runCatching { scheduler.cancel(jobID) }.isSuccess
        }.all { it }
        val nonePending = runCatching {
            scheduler.allPendingJobs.none { it.id in jobIDs }
        }.getOrDefault(false)
        return cancelled && nonePending
    }

    private fun cancelState(context: Context, scheduler: JobScheduler): Boolean {
        val managedJobsCancelled = cancelManagedJobs(scheduler)
        val retryStateCleared = runCatching {
            DailyClassroomRetryStore(context.applicationContext).clear()
        }.isSuccess
        return DailyClassroomRefreshSchedulingLogic.cancellationSucceeded(
            managedJobsCancelled,
            retryStateCleared,
        )
    }

    private fun loadCredentials(context: Context): Credentials? = runCatching {
        SecureCredentialStore(context.applicationContext).load()
    }.getOrNull()

    private fun schedule(
        context: Context,
        jobID: Int,
        nowMillis: Long = System.currentTimeMillis(),
    ): Boolean {
        val scheduler = context.getSystemService(JobScheduler::class.java)
        val delay = (DailyClassroomRefreshLogic.nextRunAt(nowMillis) - nowMillis).coerceAtLeast(0L)
        val job = JobInfo.Builder(
            jobID,
            ComponentName(context, DailyClassroomRefreshJobService::class.java),
        )
            .setMinimumLatency(delay)
            .setOverrideDeadline(delay + DailyClassroomRefreshLogic.runWindowMillis)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setBackoffCriteria(
                DailyClassroomRefreshLogic.retryBackoffMillis,
                JobInfo.BACKOFF_POLICY_LINEAR,
            )
            .setPersisted(true)
            .build()
        val result = scheduler.schedule(job)
        if (result != JobScheduler.RESULT_SUCCESS) {
            Log.e(TAG, "JobScheduler rejected daily classroom refresh job $jobID")
        }
        return result == JobScheduler.RESULT_SUCCESS
    }

    private const val TAG = "ClassroomRefreshJob"
}

class DailyClassroomRefreshJobService : JobService() {
    private var activeParameters: JobParameters? = null
    private var repository: ClassroomRepository? = null

    override fun onStartJob(params: JobParameters): Boolean {
        if (!DailyClassroomRefreshScheduler.isManagedJob(params.jobId) || activeParameters != null) {
            return false
        }
        if (!PrivacyConsentStore(applicationContext).hasAcceptedCurrentPolicy ||
            !DailyClassroomRefreshScheduler.hasValidCredentials(applicationContext)
        ) {
            DailyClassroomRefreshScheduler.cancel(applicationContext)
            return false
        }

        val activeRepository = ClassroomRepository(
            applicationContext,
            SecureCredentialStore(applicationContext),
            loadCachedData = false,
        )
        activeParameters = params
        repository = activeRepository
        activeRepository.refresh(force = true) { result ->
            if (activeParameters !== params) return@refresh
            activeParameters = null
            repository = null
            activeRepository.close()
            val retryStore = DailyClassroomRetryStore(applicationContext)
            if (!DailyClassroomRefreshScheduler.hasValidCredentials(applicationContext)) {
                runCatching(retryStore::clear)
                DailyClassroomRefreshScheduler.cancel(applicationContext)
                jobFinished(params, false)
                return@refresh
            }
            val shouldRetry = DailyClassroomRefreshLogic.shouldRetry(result.exceptionOrNull()) &&
                retryStore.recordRetryIfAllowed(ClassroomRepository.today())
            if (shouldRetry) {
                val credentialsRemainValid =
                    DailyClassroomRefreshScheduler.hasValidCredentials(applicationContext)
                if (!credentialsRemainValid) {
                    runCatching(retryStore::clear)
                    DailyClassroomRefreshScheduler.cancel(applicationContext)
                }
                jobFinished(params, credentialsRemainValid)
                return@refresh
            }
            runCatching(retryStore::clear)
            val nextScheduled = DailyClassroomRefreshScheduler.scheduleAfterCompletion(
                applicationContext,
                params.jobId,
            )
            jobFinished(params, !nextScheduled)
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        if (activeParameters !== params) return false
        activeParameters = null
        repository?.close()
        repository = null
        return DailyClassroomRefreshScheduler.hasValidCredentials(applicationContext)
    }

    override fun onDestroy() {
        activeParameters = null
        repository?.close()
        repository = null
        super.onDestroy()
    }
}

class DailyClassroomRefreshRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action in supportedActions) {
            DailyClassroomRefreshScheduler.reschedule(context.applicationContext)
        }
    }

    private companion object {
        val supportedActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
        )
    }
}
