package com.nemoyu.wheretostudy.nativeapp

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

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
    private var selectedDestination = Destination.PLANNER

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
                Destination.PLANNER -> PlannerPage(this, preferences, scheduleRepository).build()
                Destination.CALENDAR -> TeachingCalendarPage(this, scheduleRepository).build()
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

    override fun onDestroy() {
        scheduleRepository.close()
        super.onDestroy()
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
    }
}
