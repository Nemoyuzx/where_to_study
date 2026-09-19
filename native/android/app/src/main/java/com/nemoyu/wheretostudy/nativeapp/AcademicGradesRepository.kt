package com.nemoyu.wheretostudy.nativeapp

import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

/** Private, bounded process memory only. A credential change invalidates every pending result. */
internal class AcademicGradesRepository(
    private val credentials: () -> Credentials?,
    private val fetchTerms: (Credentials) -> AcademicTerms = SjdAcademicClient()::terms,
    private val fetchGrades: (Credentials, String, String) -> AcademicGrades = SjdAcademicClient()::grades,
) {
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val observers = mutableSetOf<() -> Unit>()
    private var owner: Credentials? = null
    private var generation = -1L
    private var request = 0L
    private var closed = false
    private val cache = linkedMapOf<Pair<String, String>, AcademicGrades>()
    var terms: AcademicTerms? = null; private set
    var selectedTermID: String? = null; private set
    var recordType = "1"; private set
    var isLoading = false; private set
    var error: String? = null; private set
    val snapshot: AcademicGrades? get() {
        reconcile()
        return selectedTermID?.let { cache[it to recordType] }
    }
    val hasCredentials: Boolean get() = credentials()?.let {
        it.account.isNotBlank() && it.password.isNotBlank()
    } == true

    fun addObserver(observer: () -> Unit) { observers += observer }
    fun removeObserver(observer: () -> Unit) { observers -= observer }

    fun reconcile() {
        val current = credentials()
        val currentGeneration = LocalDataCoordinator.snapshot()
        if (current != owner || generation != currentGeneration) {
            owner = current; generation = currentGeneration; request += 1
            cache.clear(); terms = null; selectedTermID = null; recordType = "1"
            isLoading = false; error = null
        }
    }

    fun load(force: Boolean = false) {
        reconcile()
        if (closed || isLoading || !hasCredentials) return
        if (!force && snapshot != null) return
        val capturedOwner = owner ?: return
        val capturedGeneration = generation
        val token = ++request
        val selected = selectedTermID
        val type = recordType
        val knownTerms = if (force) null else terms
        isLoading = true; error = null; notifyObservers()
        worker.execute {
            val catalogResult = runCatching { knownTerms ?: fetchTerms(capturedOwner) }
            val result = runCatching {
                val catalog = catalogResult.getOrThrow()
                val termID = selected ?: catalog.currentTermID.takeIf(String::isNotBlank)
                    ?: throw ScheduleClientException("学校未返回当前学期，请选择学期。")
                catalog to fetchGrades(capturedOwner, termID, type)
            }
            handler.post {
                if (closed || token != request || !LocalDataCoordinator.isCurrent(capturedGeneration) ||
                    credentials() != capturedOwner
                ) {
                    reconcile()
                    if (!closed) notifyObservers()
                    return@post
                }
                isLoading = false
                catalogResult.onSuccess { terms = it }
                result.onSuccess { (catalog, grades) ->
                    terms = catalog; selectedTermID = grades.termID
                    cache[grades.termID to grades.recordType] = grades
                    while (cache.size > 8) cache.remove(cache.keys.first())
                }.onFailure { error = "成绩获取失败，请重试或检查账号设置。" }
                notifyObservers()
            }
        }
    }

    fun select(termID: String, type: String = recordType) {
        require(type in setOf("1", "0", ""))
        reconcile()
        if (termID.isNotBlank() && terms?.terms?.none { it.id == termID } != false) return
        request += 1; isLoading = false; error = null
        selectedTermID = termID; recordType = type
        notifyObservers(); load()
    }

    fun clear() {
        request += 1; cache.clear(); terms = null; selectedTermID = null
        isLoading = false; error = null
    }
    fun close() { closed = true; clear(); observers.clear(); handler.removeCallbacksAndMessages(null); worker.shutdownNow() }
    private fun notifyObservers() { observers.toList().forEach { it() } }
}
