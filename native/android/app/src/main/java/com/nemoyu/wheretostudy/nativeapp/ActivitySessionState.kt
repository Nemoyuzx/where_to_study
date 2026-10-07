package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/** Context-free UI values and application-context services; never serialized. */
internal class ActivitySessionState(context: Context) {
    private val appContext = context.applicationContext
    private val localWorker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)
    private var lastCourseReminderExactAccess: Boolean? = null
    val credentials = SecureCredentialStore(appContext)
    val preferences = AppPreferences(appContext)
    val newAssignments = NewAssignmentNotices(appContext)
    private val scheduleDelegate = lazy { ScheduleRepository(appContext, credentials, preferences) }
    val schedule by scheduleDelegate
    private val classroomsDelegate = lazy { ClassroomRepository(appContext, credentials) }
    val classrooms by classroomsDelegate
    private val weatherDelegate = lazy { WeatherRepository() }
    val weather by weatherDelegate
    private val shuttlesDelegate = lazy { ShuttleBusRepository() }
    val shuttles by shuttlesDelegate
    private val gradesDelegate = lazy { AcademicGradesRepository(credentials::load, credentialIdentity = credentials::cachedIdentity) }
    val grades by gradesDelegate
    private val dailyInfoDelegate = lazy { CalendarDailyInfoRepository(assignmentClient = UCloudAssignmentClient(credentials,
        publication = { scope, items, restored -> newAssignments.accept("ucloud", scope,
            items.map { NewAssignmentNotice("${it.courseID.orEmpty()}:${it.id}", it.title, it.courseName, it.deadline) }, restored) },
        cleared = { newAssignments.clear("ucloud") }), preferences = preferences) }
    val dailyInfo by dailyInfoDelegate
    private val qmplusDelegate = lazy { QmplusRepository(appContext,
        assignmentPublication = { generation, snapshot, restored ->
            newAssignments.accept("qmplus", generation.toString(), NewAssignmentNotice.qmplus(snapshot), restored)
        }, assignmentsCleared = { newAssignments.clear("qmplus") }) }
    val qmplus by qmplusDelegate
    val holidayDelegate = lazy { HolidayRepository(appContext) }
    val holidays by holidayDelegate
    val uiOwner = CurrentActivityOwner()
    val planner = PlannerQueryState(preferences.campusID)
    var calendar: TeachingCalendarSessionState? = null
    var query: InformationQuerySessionState? = null
    var courses: InformationQuerySessionState? = null
    var settings: SettingsPageDraft? = null
    val scrollAnchors = mutableMapOf<String, ScrollAnchor>()
    var customValidationToken = 0L
    var customValidationPending = false
    var applicationStarted = false

    fun ensureClassroomRefreshScheduled() {
        val generation = LocalDataCoordinator.snapshot()
        val isActive = { !closed.get() && !Thread.currentThread().isInterrupted && LocalDataCoordinator.isCurrent(generation) }
        if (!isActive()) return
        try {
            localWorker.execute {
                if (isActive()) DailyClassroomRefreshScheduler.ensureScheduled(appContext, isActive)
            }
        } catch (_: RejectedExecutionException) { /* The retained session was closed. */ }
    }

    /** The retained session owns local IO; callbacks resolve the current weak UI owner. */
    fun reconcileNotifications(force: Boolean = false) {
        val generation = LocalDataCoordinator.snapshot()
        val isActive = { !closed.get() && !Thread.currentThread().isInterrupted && LocalDataCoordinator.isCurrent(generation) }
        if (!isActive()) return
        try {
            localWorker.execute {
                if (!isActive()) return@execute
                val changed = runCatching {
                    val summaryChanged = DailyCourseSummaryScheduler.synchronizePermissionState(appContext)
                    val reminderChanged = CourseReminderScheduler.synchronizePermissionState(appContext)
                    val exactAccess = CourseReminderScheduler.hasExactAccess(appContext)
                    val exactChanged = lastCourseReminderExactAccess != null && lastCourseReminderExactAccess != exactAccess
                    lastCourseReminderExactAccess = exactAccess
                    DailyCourseSummaryScheduler.reconcileAt(appContext, forceReschedule = force, isActive = isActive)
                    CourseReminderScheduler.reconcile(appContext, force = force, isActive = isActive)
                    summaryChanged || reminderChanged || exactChanged
                }.getOrDefault(false)
                if (changed) mainHandler.post {
                    if (!closed.get() && LocalDataCoordinator.isCurrent(generation)) uiOwner.current()?.notificationSettingsDidChange()
                }
            }
        } catch (_: RejectedExecutionException) { /* A closed retained session cannot schedule more work. */ }
    }

    fun detachObservers() {
        if (dailyInfoDelegate.isInitialized()) dailyInfo.clearUiObservers()
        if (shuttlesDelegate.isInitialized()) shuttles.clearUiObservers()
        if (gradesDelegate.isInitialized()) grades.clearUiObservers()
        if (holidayDelegate.isInitialized()) holidays.clearUiObservers()
        if (qmplusDelegate.isInitialized()) qmplus.clearUiObservers()
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        localWorker.shutdownNow()
        mainHandler.removeCallbacksAndMessages(null)
        detachObservers()
        settings = null
        customValidationToken++
        customValidationPending = false
        scrollAnchors.clear()
        if (scheduleDelegate.isInitialized()) schedule.close()
        if (classroomsDelegate.isInitialized()) classrooms.close()
        if (weatherDelegate.isInitialized()) weather.close()
        if (shuttlesDelegate.isInitialized()) shuttles.close()
        if (gradesDelegate.isInitialized()) grades.close()
        if (dailyInfoDelegate.isInitialized()) dailyInfo.close()
        if (holidayDelegate.isInitialized()) holidays.close()
        if (qmplusDelegate.isInitialized()) qmplus.close()
    }
}

internal class CurrentActivityOwner {
    private var reference = WeakReference<MainActivity>(null)
    fun attach(activity: MainActivity) { reference = WeakReference(activity) }
    fun detach(activity: MainActivity) { if (reference.get() === activity) reference.clear() }
    fun current(): MainActivity? = reference.get()?.takeUnless { it.isFinishing || it.isDestroyed }
}
