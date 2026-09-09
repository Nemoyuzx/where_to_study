package com.nemoyu.wheretostudy.nativeapp

import android.content.BroadcastReceiver
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Local disk work only. goAsync retains the process, but does not remove the broadcast deadline. */
internal object LocalBroadcastWork {
    private val workers = Executors.newFixedThreadPool(2)
    private val deadlines = Executors.newSingleThreadScheduledExecutor()

    fun submit(result: BroadcastReceiver.PendingResult, operation: (() -> Boolean) -> Unit) {
        val completed = AtomicBoolean(false)
        fun finish() {
            if (completed.compareAndSet(false, true)) result.finish()
        }
        val work = FutureTask<Unit> {
            try {
                if (!completed.get()) operation { !completed.get() && !Thread.currentThread().isInterrupted }
            } catch (error: Exception) {
                Log.w("LocalBroadcastWork", "Local broadcast update did not complete", error)
            } finally {
                finish()
            }
        }
        val deadline = deadlines.schedule({
            work.cancel(true)
            finish()
        }, 8, TimeUnit.SECONDS)
        workers.execute {
            try { work.run() } finally { deadline.cancel(false) }
        }
    }
}
