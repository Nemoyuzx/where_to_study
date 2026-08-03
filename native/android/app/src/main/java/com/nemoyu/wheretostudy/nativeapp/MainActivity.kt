package com.nemoyu.wheretostudy.nativeapp

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

data class LocalDataClearResult(val failedItems: List<String>) {
    val isComplete: Boolean
        get() = failedItems.isEmpty()
}

class MainActivity : Activity() {
    private enum class Destination(val label: String) {
        PLANNER("空教室"),
        CALENDAR("教学日历"),
        SETTINGS("设置"),
    }

    private lateinit var content: FrameLayout
    private val navigationViews = mutableMapOf<Destination, TextView>()
    private val credentialStore by lazy { SecureCredentialStore(this) }
    private val preferences by lazy { AppPreferences(this) }
    private val scheduleRepository by lazy {
        ScheduleRepository(this, credentialStore, preferences)
    }
    private val classroomRepository by lazy {
        ClassroomRepository(this, credentialStore)
    }
    private val holidayRepositoryDelegate = lazy {
        HolidayRepository(this)
    }
    private val holidayRepository by holidayRepositoryDelegate
    private val systemCalendarImporterDelegate = lazy {
        SystemCalendarImporter(this)
    }
    private val systemCalendarImporter by systemCalendarImporterDelegate
    private var selectedDestination = Destination.PLANNER
    private var calendarImportInFlight = false
    private var pendingCalendarImport: PendingCalendarImport? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = if (resources.configuration.screenWidthDp >= TABLET_BREAKPOINT_DP) {
            tabletLayout()
        } else {
            phoneLayout()
        }
        applySystemInsets(root)
        setContentView(root)
        configureSystemBarIcons()
        navigate(Destination.PLANNER)
        DailyClassroomRefreshScheduler.ensureScheduled(this)
        refreshClassroomsAtStartup()
    }

    private fun phoneLayout(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(Palette.background)
        content = FrameLayout(this@MainActivity).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
        }
        addView(content)
        addView(LinearLayout(this@MainActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(6), dp(8), dp(6))
            setBackgroundColor(Palette.surface)
            Destination.entries.forEach { destination ->
                addView(navigationTab(destination, compact = true))
            }
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(62)))
    }

    private fun tabletLayout(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        setBackgroundColor(Palette.background)
        addView(LinearLayout(this@MainActivity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(24), dp(18), dp(18))
            setBackgroundColor(Palette.surface)
            addView(TextView(this@MainActivity).apply {
                text = getString(R.string.brand_eyebrow)
                textSize = 12f
                setTextColor(Palette.muted)
                setTypeface(typeface, Typeface.BOLD)
            })
            addView(TextView(this@MainActivity).apply {
                text = getString(R.string.brand_name)
                textSize = 20f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
                setPadding(0, dp(4), 0, dp(22))
            })
            Destination.entries.forEach { destination ->
                addView(navigationTab(destination, compact = false))
            }
        }, LinearLayout.LayoutParams(dp(224), ViewGroup.LayoutParams.MATCH_PARENT))
        content = FrameLayout(this@MainActivity).apply {
            setBackgroundColor(Palette.background)
        }
        addView(content, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
    }

    private fun navigationTab(destination: Destination, compact: Boolean): TextView =
        TextView(this).apply {
            text = destination.label
            textSize = if (compact) 13f else 15f
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
            setOnClickListener { navigate(destination) }
            layoutParams = if (compact) {
                LinearLayout.LayoutParams(0, dp(50), 1f).apply {
                    marginEnd = dp(5)
                }
            } else {
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)).apply {
                    bottomMargin = dp(8)
                }
            }
            navigationViews[destination] = this
        }

    private fun navigate(destination: Destination) {
        selectedDestination = destination
        if (destination == Destination.SETTINGS) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        navigationViews.forEach { (item, view) ->
            view.setTextColor(if (item == destination) Color.WHITE else Palette.text)
            view.setTypeface(view.typeface, if (item == destination) Typeface.BOLD else Typeface.NORMAL)
            view.background = roundedBackground(
                this,
                if (item == destination) Palette.primary else Color.TRANSPARENT,
                radius = 6,
            )
        }
        content.removeAllViews()
        content.addView(
            when (destination) {
                Destination.PLANNER -> PlannerPage(
                    this,
                    preferences,
                    scheduleRepository,
                    classroomRepository,
                ).build()
                Destination.CALENDAR -> TeachingCalendarPage(
                    this,
                    scheduleRepository,
                    holidayRepository,
                ).build()
                Destination.SETTINGS -> SettingsPage(
                    this,
                    credentialStore,
                    preferences,
                    scheduleRepository,
                ).build()
            },
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    fun refreshCurrentPage() {
        navigate(selectedDestination)
    }

    fun importCachedScheduleToSystemCalendar(
        onComplete: (Result<SystemCalendarImportResult>) -> Unit,
    ) {
        val schedule = scheduleRepository.schedule
        if (schedule == null || schedule.courses.isEmpty()) {
            onComplete(Result.failure(SystemCalendarImportException("请先获取个人课表。")))
            return
        }
        if (calendarImportInFlight || systemCalendarImporter.isImporting) {
            onComplete(Result.failure(SystemCalendarImportException("课表正在导入系统日历。")))
            return
        }

        calendarImportInFlight = true
        val pending = PendingCalendarImport(schedule, onComplete)
        if (hasCalendarPermissions()) {
            startCalendarImport(pending)
            return
        }
        pendingCalendarImport = pending
        runCatching {
            requestPermissions(CALENDAR_PERMISSIONS, CALENDAR_PERMISSION_REQUEST_CODE)
        }.onFailure { error ->
            finishCalendarImport(
                pending,
                Result.failure(SystemCalendarImportException("无法申请系统日历权限。", error)),
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALENDAR_PERMISSION_REQUEST_CODE) return
        val pending = pendingCalendarImport ?: return
        pendingCalendarImport = null
        if (hasCalendarPermissions()) {
            startCalendarImport(pending)
        } else {
            finishCalendarImport(
                pending,
                Result.failure(SystemCalendarImportException("需要允许日历读写权限才能导入课程。")),
            )
        }
    }

    fun clearAllLocalData(): LocalDataClearResult {
        val failures = mutableListOf<String>()
        fun clearItem(label: String, operation: () -> Unit) {
            runCatching(operation).onFailure { failures += label }
        }

        clearItem("账号和密码") { credentialStore.clear() }
        clearItem("应用设置") { preferences.clear() }
        clearItem("个人课表") { scheduleRepository.clearLocalData() }
        clearItem("空教室缓存") { classroomRepository.clearLocalData() }
        clearItem("节假日缓存") {
            if (holidayRepositoryDelegate.isInitialized()) {
                holidayRepository.clearLocalData()
            } else {
                HolidayStore(this).clear()
            }
        }
        runCatching(::refreshCurrentPage)
        return LocalDataClearResult(failures)
    }

    private fun refreshClassroomsAtStartup() {
        classroomRepository.refresh(force = false) { result ->
            if (result.isSuccess && selectedDestination == Destination.PLANNER) {
                refreshCurrentPage()
            }
        }
    }

    override fun onDestroy() {
        pendingCalendarImport = null
        scheduleRepository.close()
        classroomRepository.close()
        if (holidayRepositoryDelegate.isInitialized()) {
            holidayRepository.close()
        }
        if (systemCalendarImporterDelegate.isInitialized()) {
            systemCalendarImporter.close()
        }
        super.onDestroy()
    }

    private fun hasCalendarPermissions(): Boolean = CALENDAR_PERMISSIONS.all { permission ->
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun startCalendarImport(pending: PendingCalendarImport) {
        pendingCalendarImport = null
        systemCalendarImporter.importSchedule(pending.schedule) { result ->
            finishCalendarImport(pending, result)
        }
    }

    private fun finishCalendarImport(
        pending: PendingCalendarImport,
        result: Result<SystemCalendarImportResult>,
    ) {
        calendarImportInFlight = false
        if (pendingCalendarImport === pending) pendingCalendarImport = null
        pending.onComplete(result)
    }

    private fun applySystemInsets(root: View) {
        root.setOnApplyWindowInsetsListener { view, insets ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars())
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            } else {
                @Suppress("DEPRECATION")
                view.setPadding(
                    insets.systemWindowInsetLeft,
                    insets.systemWindowInsetTop,
                    insets.systemWindowInsetRight,
                    insets.systemWindowInsetBottom,
                )
            }
            insets
        }
    }

    private fun configureSystemBarIcons() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val lightBars = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            window.insetsController?.setSystemBarsAppearance(lightBars, lightBars)
            return
        }

        @Suppress("DEPRECATION")
        var flags = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            flags = flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = flags
    }

    private companion object {
        const val TABLET_BREAKPOINT_DP = 700
        const val CALENDAR_PERMISSION_REQUEST_CODE = 4107
        val CALENDAR_PERMISSIONS = arrayOf(
            Manifest.permission.READ_CALENDAR,
            Manifest.permission.WRITE_CALENDAR,
        )
    }

    private data class PendingCalendarImport(
        val schedule: ScheduleSnapshot,
        val onComplete: (Result<SystemCalendarImportResult>) -> Unit,
    )
}
