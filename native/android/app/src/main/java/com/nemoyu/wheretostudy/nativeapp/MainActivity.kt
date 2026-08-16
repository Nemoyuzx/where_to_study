package com.nemoyu.wheretostudy.nativeapp

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.content.res.ColorStateList
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
import androidx.core.util.Consumer
import androidx.window.java.layout.WindowInfoTrackerCallbackAdapter
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import androidx.window.layout.WindowLayoutInfo
import androidx.window.layout.WindowMetricsCalculator
import java.util.concurrent.Executor
import kotlin.math.ceil

data class LocalDataClearResult(val failedItems: List<String>) {
    val isComplete: Boolean
        get() = failedItems.isEmpty()
}

class MainActivity : Activity() {
    private enum class Destination(
        val label: String,
        val navigationViewID: Int,
        val pageViewID: Int,
        val iconResource: Int,
    ) {
        PLANNER("空教室", R.id.navigation_planner, R.id.page_planner, R.drawable.ic_nav_classroom),
        CALENDAR("教学日历", R.id.navigation_calendar, R.id.page_calendar, R.drawable.ic_nav_calendar),
        SETTINGS("设置", R.id.navigation_settings, R.id.page_settings, R.drawable.ic_nav_settings),
    }

    private lateinit var content: FrameLayout
    private lateinit var adaptiveRoot: FrameLayout
    private val navigationViews = mutableMapOf<Destination, TextView>()
    private val credentialStore by lazy { SecureCredentialStore(this) }
    private val preferences by lazy { AppPreferences(this) }
    private val plannerQueryState by lazy { PlannerQueryState(preferences.campusID) }
    private lateinit var teachingCalendarSessionState: TeachingCalendarSessionState
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
    private var calendarPermissionRequestPending = false
    private var calendarImportToken: Long? = null
    private var pendingCalendarImport: PendingCalendarImport? = null
    private var notificationPermissionRequestPending = false
    private var pendingNotificationPermissionCompletion: ((Boolean) -> Unit)? = null
    private var currentLayoutSpec: AdaptiveLayoutSpec? = null
    private var currentFoldingFeature: FoldingFeature? = null
    private var windowLayoutListenerRegistered = false
    private val windowInfoTracker by lazy {
        WindowInfoTrackerCallbackAdapter(WindowInfoTracker.getOrCreate(this))
    }
    private val windowLayoutExecutor = Executor { command -> runOnUiThread(command) }
    private val windowLayoutInfoListener = Consumer<WindowLayoutInfo> { layoutInfo ->
        currentFoldingFeature = layoutInfo.displayFeatures
            .filterIsInstance<FoldingFeature>()
            .firstOrNull(::shouldAvoidFoldingFeature)
        scheduleAdaptiveLayout()
    }
    private val applyAdaptiveLayout = Runnable { updateAdaptiveLayout() }

    override fun onCreate(savedInstanceState: Bundle?) {
        DailyCourseNotificationRuntimeMode.activateFrom(intent)
        super.onCreate(savedInstanceState)
        Palette.configure(this)
        calendarPermissionRequestPending = savedInstanceState
            ?.getBoolean(CALENDAR_PERMISSION_PENDING_KEY, false)
            ?: false
        calendarImportToken = savedInstanceState
            ?.getLong(CALENDAR_IMPORT_TOKEN_KEY, NO_CALENDAR_IMPORT_TOKEN)
            ?.takeUnless { it == NO_CALENDAR_IMPORT_TOKEN }
        calendarImportInFlight = calendarImportToken != null
        notificationPermissionRequestPending = savedInstanceState
            ?.getBoolean(NOTIFICATION_PERMISSION_PENDING_KEY, false)
            ?: false
        selectedDestination = savedInstanceState
            ?.getString(SELECTED_DESTINATION_KEY)
            ?.let { saved -> Destination.entries.firstOrNull { it.name == saved } }
            ?: Destination.PLANNER
        teachingCalendarSessionState = TeachingCalendarSessionState(
            selectedDateMillis = savedInstanceState
                ?.getLong(TEACHING_CALENDAR_DATE_KEY, System.currentTimeMillis())
                ?: System.currentTimeMillis(),
            selectedModeName = savedInstanceState
                ?.getString(TEACHING_CALENDAR_MODE_KEY)
                ?: TeachingCalendarMode.WEEK.name,
            monthExpanded = savedInstanceState
                ?.getBoolean(TEACHING_CALENDAR_MONTH_EXPANDED_KEY, true)
                ?: true,
        )

        adaptiveRoot = FrameLayout(this).apply {
            id = R.id.adaptive_root
            setBackgroundColor(Palette.background)
            addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
                if (right - left != oldRight - oldLeft) scheduleAdaptiveLayout()
            }
        }
        applySystemInsets(adaptiveRoot)
        setContentView(adaptiveRoot)
        configureSystemBarIcons()
        updateAdaptiveLayout(force = true)
        DailyClassroomRefreshScheduler.ensureScheduled(this)
        DailyCourseSummaryScheduler.reconcile(this)
        refreshClassroomsAtStartup()
        if (calendarPermissionRequestPending && hasCalendarPermissions()) {
            resumeCalendarImportAfterRecreation()
        } else {
            calendarImportToken?.let(::reattachCalendarImport)
        }
    }

    override fun onResume() {
        super.onResume()
        val settingChanged = DailyCourseSummaryScheduler.synchronizePermissionState(this)
        DailyCourseSummaryScheduler.reconcile(this)
        if (settingChanged && ::content.isInitialized &&
            selectedDestination == Destination.SETTINGS
        ) {
            refreshCurrentPage()
        }
    }

    override fun onStart() {
        super.onStart()
        if (!windowLayoutListenerRegistered) {
            windowInfoTracker.addWindowLayoutInfoListener(
                this,
                windowLayoutExecutor,
                windowLayoutInfoListener,
            )
            windowLayoutListenerRegistered = true
        }
    }

    override fun onStop() {
        if (windowLayoutListenerRegistered) {
            windowInfoTracker.removeWindowLayoutInfoListener(windowLayoutInfoListener)
            windowLayoutListenerRegistered = false
        }
        super.onStop()
    }

    private fun phoneLayout(): FrameLayout = FrameLayout(this).apply {
        setBackgroundColor(Palette.background)
        content = FrameLayout(this@MainActivity).apply {
            setPadding(0, 0, 0, dp(76))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        addView(content)
        addView(LinearLayout(this@MainActivity).apply {
            id = R.id.phone_navigation
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(3), dp(10), dp(3))
            background = roundedBackground(
                this@MainActivity,
                Palette.surfaceVariant,
                Palette.border,
                radius = 30,
            )
            elevation = dp(8).toFloat()
            Destination.entries.forEach { destination ->
                addView(navigationTab(destination, compact = true))
            }
        }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(60), Gravity.BOTTOM).apply {
            marginStart = dp(44)
            marginEnd = dp(44)
            bottomMargin = dp(10)
        })
    }

    private fun sideNavigationLayout(spec: AdaptiveLayoutSpec): LinearLayout =
        LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        setBackgroundColor(Palette.background)
        addView(LinearLayout(this@MainActivity).apply {
            id = R.id.tablet_navigation
            orientation = LinearLayout.VERTICAL
            val horizontalPadding = if (spec.widthClass == WindowWidthClass.MEDIUM) 16 else 20
            setPadding(dp(horizontalPadding), dp(16), dp(horizontalPadding), dp(16))
            setBackgroundColor(Palette.surface)
            addView(TextView(this@MainActivity).apply {
                text = getString(R.string.brand_eyebrow)
                textSize = 12f
                setTextColor(Palette.muted)
                setTypeface(typeface, Typeface.BOLD)
            })
            addView(TextView(this@MainActivity).apply {
                text = getString(R.string.brand_name)
                textSize = 17f
                setTextColor(Palette.text)
                setTypeface(typeface, Typeface.BOLD)
                setPadding(0, dp(4), 0, dp(16))
            })
            Destination.entries.forEach { destination ->
                addView(navigationTab(destination, compact = false))
            }
        }, LinearLayout.LayoutParams(dp(spec.navigationWidthDp), ViewGroup.LayoutParams.MATCH_PARENT))
        if (spec.hingeSpacerDp > 0) {
            addView(View(this@MainActivity).apply {
                id = R.id.folding_feature_spacer
                setBackgroundColor(Palette.background)
            }, LinearLayout.LayoutParams(dp(spec.hingeSpacerDp), ViewGroup.LayoutParams.MATCH_PARENT))
        }
        content = FrameLayout(this@MainActivity).apply {
            setBackgroundColor(Palette.background)
        }
        addView(content, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
    }

    private fun scheduleAdaptiveLayout() {
        if (!::adaptiveRoot.isInitialized) return
        adaptiveRoot.removeCallbacks(applyAdaptiveLayout)
        adaptiveRoot.postDelayed(applyAdaptiveLayout, ADAPTIVE_LAYOUT_DEBOUNCE_MILLIS)
    }

    private fun updateAdaptiveLayout(force: Boolean = false) {
        if (!::adaptiveRoot.isInitialized) return
        val windowWidthDp = currentWindowWidthDp()
        if (windowWidthDp <= 0) return
        val spec = AdaptiveLayoutLogic.resolve(
            windowWidthDp = windowWidthDp,
            availableWidthDp = currentAvailableWidthDp(),
            verticalHinge = verticalHingeBoundsDp(),
        )
        if (!force && spec == currentLayoutSpec) return

        currentLayoutSpec = spec
        navigationViews.clear()
        adaptiveRoot.removeAllViews()
        val layout = if (spec.usesBottomNavigation) {
            phoneLayout()
        } else {
            sideNavigationLayout(spec)
        }
        adaptiveRoot.addView(
            layout,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        navigate(selectedDestination)
    }

    private fun currentWindowWidthDp(): Int {
        val widthPx = WindowMetricsCalculator.getOrCreate()
            .computeCurrentWindowMetrics(this)
            .bounds
            .width()
        return (widthPx.coerceAtLeast(0) / resources.displayMetrics.density).toInt()
    }

    private fun currentAvailableWidthDp(): Int {
        val widthPx = if (adaptiveRoot.width > 0) {
            adaptiveRoot.width - adaptiveRoot.paddingLeft - adaptiveRoot.paddingRight
        } else {
            WindowMetricsCalculator.getOrCreate()
                .computeCurrentWindowMetrics(this)
                .bounds
                .width()
        }
        return (widthPx.coerceAtLeast(0) / resources.displayMetrics.density).toInt()
    }

    private fun verticalHingeBoundsDp(): VerticalHingeBoundsDp? {
        val feature = currentFoldingFeature ?: return null
        if (!shouldAvoidFoldingFeature(feature) || adaptiveRoot.width <= 0) return null
        val rootLocation = IntArray(2).also(adaptiveRoot::getLocationInWindow)
        val contentOriginX = rootLocation[0] + adaptiveRoot.paddingLeft
        val contentWidthPx = adaptiveRoot.width - adaptiveRoot.paddingLeft - adaptiveRoot.paddingRight
        val leftPx = (feature.bounds.left - contentOriginX).coerceIn(0, contentWidthPx)
        val rightPx = (feature.bounds.right - contentOriginX).coerceIn(0, contentWidthPx)
        if (rightPx < leftPx || leftPx >= contentWidthPx) return null
        val density = resources.displayMetrics.density
        return VerticalHingeBoundsDp(
            left = (leftPx / density).toInt(),
            right = ceil(rightPx / density.toDouble()).toInt(),
        )
    }

    private fun shouldAvoidFoldingFeature(feature: FoldingFeature): Boolean =
        feature.orientation == FoldingFeature.Orientation.VERTICAL &&
            (feature.isSeparating || feature.occlusionType == FoldingFeature.OcclusionType.FULL)

    private fun navigationTab(destination: Destination, compact: Boolean): TextView =
        TextView(this).apply {
            id = destination.navigationViewID
            text = destination.label
            textSize = if (compact) 11f else 15f
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
            if (compact) {
                setCompoundDrawablesRelativeWithIntrinsicBounds(0, destination.iconResource, 0, 0)
                compoundDrawablePadding = dp(3)
            }
            setOnClickListener { navigate(destination) }
            layoutParams = if (compact) {
                LinearLayout.LayoutParams(0, dp(50), 1f).apply {
                    marginEnd = dp(4)
                }
            } else {
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(40)).apply {
                    bottomMargin = dp(4)
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
            val selected = item == destination
            val contentColor = if (selected) Palette.primaryText else Palette.muted
            view.setTextColor(contentColor)
            view.compoundDrawableTintList = ColorStateList.valueOf(contentColor)
            view.setTypeface(view.typeface, if (item == destination) Typeface.BOLD else Typeface.NORMAL)
            view.background = roundedBackground(
                this,
                when {
                    currentLayoutSpec?.usesBottomNavigation == true && selected -> Palette.background
                    currentLayoutSpec?.usesBottomNavigation == true -> Color.TRANSPARENT
                    selected -> Palette.selectionSurface
                    else -> Color.TRANSPARENT
                },
                radius = if (currentLayoutSpec?.usesBottomNavigation == true) 26 else UiMetrics.controlRadiusDp,
            )
        }
        val page = when (destination) {
            Destination.PLANNER -> PlannerPage(
                this,
                plannerQueryState,
                scheduleRepository,
                classroomRepository,
                currentLayoutSpec?.contentWidthDp ?: currentWindowWidthDp(),
            ).build()
            Destination.CALENDAR -> TeachingCalendarPage(
                this,
                scheduleRepository,
                holidayRepository,
                currentLayoutSpec?.contentWidthDp ?: currentWindowWidthDp(),
                teachingCalendarSessionState,
            ).build()
            Destination.SETTINGS -> SettingsPage(
                this,
                credentialStore,
                preferences,
                scheduleRepository,
                classroomRepository,
                currentLayoutSpec?.contentWidthDp ?: currentWindowWidthDp(),
            ).build()
        }
        page.id = destination.pageViewID
        content.removeAllViews()
        content.addView(
            page,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    fun refreshCurrentPage() {
        navigate(selectedDestination)
    }

    fun setDailyCourseNotificationsEnabled(
        enabled: Boolean,
        onComplete: (Boolean) -> Unit,
    ) {
        if (!enabled) {
            onComplete(DailyCourseSummaryScheduler.revoke(this))
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionRequestPending = true
            pendingNotificationPermissionCompletion = onComplete
            runCatching {
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST_CODE,
                )
            }.onFailure {
                notificationPermissionRequestPending = false
                pendingNotificationPermissionCompletion = null
                DailyCourseSummaryScheduler.revoke(this)
                onComplete(false)
            }
            return
        }
        if (!DailyCourseSummaryNotificationRuntime.hasPermission(this)) {
            DailyCourseSummaryScheduler.revoke(this)
            onComplete(false)
            return
        }
        if (!DailyCourseSummaryScheduler.authorize(this)) {
            onComplete(false)
            return
        }
        DailyCourseSummaryScheduler.reconcile(this)
        onComplete(true)
    }

    fun clearDailyCourseNotificationsForAccountChange(): Boolean =
        DailyCourseSummaryScheduler.revoke(this)

    fun reconcileDailyCourseNotifications() {
        DailyCourseSummaryScheduler.reconcile(this)
    }

    fun importCachedScheduleToSystemCalendar(
        onComplete: (Result<SystemCalendarImportResult>) -> Unit,
    ) {
        val schedule = scheduleRepository.schedule
        if (schedule == null) {
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
        calendarPermissionRequestPending = true
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
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            val granted = DailyCourseSummaryNotificationRuntime.hasPermission(this)
            val enabled = granted && DailyCourseSummaryScheduler.authorize(this)
            if (enabled) {
                DailyCourseSummaryScheduler.reconcile(this)
            } else {
                DailyCourseSummaryScheduler.revoke(this)
            }
            notificationPermissionRequestPending = false
            pendingNotificationPermissionCompletion?.invoke(enabled)
            pendingNotificationPermissionCompletion = null
            if (selectedDestination == Destination.SETTINGS) refreshCurrentPage()
            return
        }
        if (requestCode != CALENDAR_PERMISSION_REQUEST_CODE) return
        val pending = pendingCalendarImport
        pendingCalendarImport = null
        val shouldResume = calendarPermissionRequestPending
        calendarPermissionRequestPending = false
        if (hasCalendarPermissions()) {
            if (pending != null) {
                startCalendarImport(pending)
            } else if (shouldResume) {
                resumeCalendarImportAfterRecreation()
            }
        } else {
            val failure = Result.failure<SystemCalendarImportResult>(
                SystemCalendarImportException("需要允许日历读写权限才能导入课程。"),
            )
            if (pending != null) {
                finishCalendarImport(pending, failure)
            } else if (shouldResume) {
                showCalendarImportResult(failure)
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString(SELECTED_DESTINATION_KEY, selectedDestination.name)
        outState.putBoolean(
            CALENDAR_PERMISSION_PENDING_KEY,
            calendarPermissionRequestPending || pendingCalendarImport != null,
        )
        outState.putLong(
            CALENDAR_IMPORT_TOKEN_KEY,
            calendarImportToken ?: NO_CALENDAR_IMPORT_TOKEN,
        )
        outState.putBoolean(
            NOTIFICATION_PERMISSION_PENDING_KEY,
            notificationPermissionRequestPending,
        )
        outState.putLong(
            TEACHING_CALENDAR_DATE_KEY,
            teachingCalendarSessionState.selectedDate.timeInMillis,
        )
        outState.putString(
            TEACHING_CALENDAR_MODE_KEY,
            teachingCalendarSessionState.selectedMode.name,
        )
        outState.putBoolean(
            TEACHING_CALENDAR_MONTH_EXPANDED_KEY,
            teachingCalendarSessionState.monthExpanded,
        )
        super.onSaveInstanceState(outState)
    }

    fun clearAllLocalData(): LocalDataClearResult {
        val failures = mutableListOf<String>()
        fun clearItem(label: String, operation: () -> Unit) {
            runCatching(operation).onFailure { failures += label }
        }

        notificationPermissionRequestPending = false
        pendingNotificationPermissionCompletion = null
        if (!DailyClassroomRefreshScheduler.cancel(this)) {
            failures += "空教室后台刷新"
            runCatching(::refreshCurrentPage)
            return LocalDataClearResult(failures)
        }
        if (!DailyCourseSummaryScheduler.revoke(this)) {
            failures += "课程提醒授权"
            runCatching(::refreshCurrentPage)
            return LocalDataClearResult(failures)
        }
        LocalDataCoordinator.clear {
            clearItem("账号和密码") { credentialStore.clear() }
            clearItem("应用设置") { preferences.clear() }
            clearItem("后台刷新状态") { DailyClassroomRetryStore(this).clear() }
            clearItem("个人课表") { scheduleRepository.clearLocalDataCoordinated() }
            clearItem("空教室缓存") { classroomRepository.clearLocalDataCoordinated() }
            clearItem("节假日缓存") {
                if (holidayRepositoryDelegate.isInitialized()) {
                    holidayRepository.clearLocalDataCoordinated()
                } else {
                    HolidayStore(this).clear()
                }
            }
        }
        if (!DailyClassroomRefreshScheduler.cancel(this)) {
            failures += "空教室后台刷新"
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
        if (::adaptiveRoot.isInitialized) adaptiveRoot.removeCallbacks(applyAdaptiveLayout)
        pendingCalendarImport = null
        pendingNotificationPermissionCompletion = null
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
        calendarPermissionRequestPending = false
        val registration = systemCalendarImporter.importSchedule(pending.schedule) { result ->
            finishCalendarImport(pending, result)
        }
        registration.onSuccess { calendarImportToken = it.token }
            .onFailure { error ->
                finishCalendarImport(pending, Result.failure(error))
            }
    }

    private fun finishCalendarImport(
        pending: PendingCalendarImport,
        result: Result<SystemCalendarImportResult>,
    ) {
        calendarImportInFlight = false
        calendarPermissionRequestPending = false
        calendarImportToken = null
        if (pendingCalendarImport === pending) pendingCalendarImport = null
        pending.onComplete(result)
    }

    private fun reattachCalendarImport(token: Long) {
        calendarImportInFlight = true
        if (systemCalendarImporter.attach(token) { result ->
                calendarImportInFlight = false
                calendarImportToken = null
                showCalendarImportResult(result)
            }
        ) {
            return
        }
        calendarImportInFlight = false
        calendarImportToken = null
        showCalendarImportResult(
            Result.failure(SystemCalendarImportException("系统日历同步已中断，请重试。")),
        )
    }

    private fun resumeCalendarImportAfterRecreation() {
        calendarPermissionRequestPending = false
        val schedule = scheduleRepository.schedule
        if (schedule == null) {
            showCalendarImportResult(
                Result.failure(SystemCalendarImportException("请先获取个人课表。")),
            )
            return
        }
        if (systemCalendarImporter.isImporting) return
        calendarImportInFlight = true
        startCalendarImport(PendingCalendarImport(schedule, ::showCalendarImportResult))
    }

    private fun showCalendarImportResult(result: Result<SystemCalendarImportResult>) {
        result.onSuccess { summary ->
            android.widget.Toast.makeText(
                this,
                "已同步 ${summary.totalEvents} 条课程到系统日历。",
                android.widget.Toast.LENGTH_LONG,
            ).show()
        }.onFailure { error ->
            android.widget.Toast.makeText(
                this,
                error.message ?: "系统日历导入失败。",
                android.widget.Toast.LENGTH_LONG,
            ).show()
        }
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
            scheduleAdaptiveLayout()
            insets
        }
    }

    private fun configureSystemBarIcons() {
        val isLight = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK !=
            Configuration.UI_MODE_NIGHT_YES
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val lightBars = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            window.insetsController?.setSystemBarsAppearance(if (isLight) lightBars else 0, lightBars)
            return
        }

        @Suppress("DEPRECATION")
        var flags = if (isLight) View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR else 0
        if (isLight && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            flags = flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = flags
    }

    private companion object {
        const val ADAPTIVE_LAYOUT_DEBOUNCE_MILLIS = 80L
        const val SELECTED_DESTINATION_KEY = "selected_destination"
        const val CALENDAR_PERMISSION_REQUEST_CODE = 4107
        const val CALENDAR_PERMISSION_PENDING_KEY = "calendar_permission_request_pending"
        const val CALENDAR_IMPORT_TOKEN_KEY = "calendar_import_token"
        const val NO_CALENDAR_IMPORT_TOKEN = 0L
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 4108
        const val NOTIFICATION_PERMISSION_PENDING_KEY = "notification_permission_request_pending"
        const val TEACHING_CALENDAR_DATE_KEY = "teaching_calendar_date"
        const val TEACHING_CALENDAR_MODE_KEY = "teaching_calendar_mode"
        const val TEACHING_CALENDAR_MONTH_EXPANDED_KEY = "teaching_calendar_month_expanded"
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
