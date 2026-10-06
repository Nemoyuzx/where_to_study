package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import java.lang.ref.WeakReference

/** Context-free UI values and application-context services; never serialized. */
internal class ActivitySessionState(context: Context) {
    private val appContext = context.applicationContext
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
    private val gradesDelegate = lazy { AcademicGradesRepository(credentials::load) }
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
    var automaticRefreshKey: AutomaticScheduleLaunchRefreshKey? = null
    var customValidationToken = 0L
    var customValidationPending = false
    var applicationStarted = false

    fun detachObservers() {
        if (dailyInfoDelegate.isInitialized()) dailyInfo.clearUiObservers()
        if (shuttlesDelegate.isInitialized()) shuttles.clearUiObservers()
        if (gradesDelegate.isInitialized()) grades.clearUiObservers()
        if (holidayDelegate.isInitialized()) holidays.clearUiObservers()
        if (qmplusDelegate.isInitialized()) qmplus.clearUiObservers()
    }

    fun close() {
        detachObservers()
        automaticRefreshKey?.let { ProcessAutomaticScheduleLaunchRefreshGate.finish(it, succeeded = false) }
        automaticRefreshKey = null
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
