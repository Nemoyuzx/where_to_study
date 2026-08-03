package com.nemoyu.wheretostudy.nativeapp

internal data class GenerationSingleFlightRegistration(
    val token: Long,
    val shouldStart: Boolean,
)

internal class GenerationSingleFlight<T>(
    private val invalidatedError: () -> Throwable,
) {
    private data class Active<T>(
        val token: Long,
        val generation: Long,
        val completions: MutableList<(Result<T>) -> Unit>,
    )

    private val lock = Any()
    private var nextToken = 0L
    private var active: Active<T>? = null

    fun isRunning(): Boolean = synchronized(lock) { active != null }

    fun join(
        generation: Long,
        completion: (Result<T>) -> Unit,
    ): GenerationSingleFlightRegistration {
        val (registration, superseded) = synchronized(lock) {
            val stale = active
                ?.takeIf { it.generation != generation }
                ?.completions
                ?.toList()
                .orEmpty()
            if (stale.isNotEmpty()) active = null

            val current = active
            if (current != null) {
                current.completions += completion
                GenerationSingleFlightRegistration(current.token, false) to stale
            } else {
                nextToken += 1
                active = Active(nextToken, generation, mutableListOf(completion))
                GenerationSingleFlightRegistration(nextToken, true) to stale
            }
        }
        notify(superseded, Result.failure(invalidatedError()))
        return registration
    }

    fun complete(token: Long, result: Result<T>) {
        val pending = synchronized(lock) {
            val current = active?.takeIf { it.token == token } ?: return
            active = null
            current.completions.toList()
        }
        notify(pending, result)
    }

    fun cancel(token: Long, error: Throwable) {
        complete(token, Result.failure(error))
    }

    fun invalidate() {
        val pending = synchronized(lock) {
            active?.completions?.toList().orEmpty().also { active = null }
        }
        notify(pending, Result.failure(invalidatedError()))
    }

    private fun notify(completions: List<(Result<T>) -> Unit>, result: Result<T>) {
        completions.forEach { completion -> runCatching { completion(result) } }
    }
}
