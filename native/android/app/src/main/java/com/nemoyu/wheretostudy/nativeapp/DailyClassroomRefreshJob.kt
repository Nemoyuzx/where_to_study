package com.nemoyu.wheretostudy.nativeapp

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context

object DailyClassroomRefreshScheduler {
    private const val PRIMARY_JOB_ID = 0x57545307
    private const val SECONDARY_JOB_ID = 0x57545308
    private val jobIDs = setOf(PRIMARY_JOB_ID, SECONDARY_JOB_ID)

    fun ensureScheduled(context: Context): Boolean = runCatching {
        val scheduler = context.getSystemService(JobScheduler::class.java)
        scheduler.allPendingJobs.any { it.id in jobIDs } || schedule(context, PRIMARY_JOB_ID)
    }.getOrDefault(false)

    fun scheduleAfterCompletion(context: Context, completedJobID: Int): Boolean = runCatching {
        val nextJobID = if (completedJobID == PRIMARY_JOB_ID) {
            SECONDARY_JOB_ID
        } else {
            PRIMARY_JOB_ID
        }
        schedule(context, nextJobID)
    }.getOrDefault(false)

    fun isManagedJob(jobID: Int): Boolean = jobID in jobIDs

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
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPersisted(true)
            .build()
        return scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS
    }
}

class DailyClassroomRefreshJobService : JobService() {
    private var activeParameters: JobParameters? = null
    private var repository: ClassroomRepository? = null

    override fun onStartJob(params: JobParameters): Boolean {
        if (!DailyClassroomRefreshScheduler.isManagedJob(params.jobId) || activeParameters != null) {
            return false
        }

        val activeRepository = ClassroomRepository(
            applicationContext,
            SecureCredentialStore(applicationContext),
            loadCachedData = false,
        )
        activeParameters = params
        repository = activeRepository
        activeRepository.refresh(force = true) {
            if (activeParameters !== params) return@refresh
            activeParameters = null
            repository = null
            activeRepository.close()
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
        return true
    }

    override fun onDestroy() {
        activeParameters = null
        repository?.close()
        repository = null
        super.onDestroy()
    }
}
