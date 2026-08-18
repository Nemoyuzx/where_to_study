package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.roundToInt

data class ThemeColors(
    val primary: Int,
    val primaryFill: Int,
    val primaryDark: Int,
    val primaryText: Int,
    val onPrimary: Int,
    val accent: Int,
    val onAccent: Int,
    val background: Int,
    val surface: Int,
    val surfaceVariant: Int,
    val text: Int,
    val muted: Int,
    val border: Int,
    val danger: Int,
    val dangerSurface: Int,
    val dangerBorder: Int,
    val nowIndicator: Int,
    val holiday: Int,
    val outOfMonth: Int,
    val selectionSurface: Int,
    val segmentedSelection: Int,
)

object ThemePalettes {
    val light = ThemeColors(
        primary = 0xFF166B5D.toInt(), primaryFill = 0xFF166B5D.toInt(),
        primaryDark = 0xFF0C4A42.toInt(), primaryText = 0xFF166B5D.toInt(),
        onPrimary = 0xFFFFFFFF.toInt(), accent = 0xFFE2BC62.toInt(),
        onAccent = 0xFF151515.toInt(), background = 0xFFF2F2F7.toInt(),
        surface = 0xFFFFFFFF.toInt(), surfaceVariant = 0xFFE5E5EA.toInt(),
        text = 0xFF111111.toInt(), muted = 0xFF6E6E73.toInt(),
        border = 0xFFC6C6C8.toInt(), danger = 0xFF8A2D1C.toInt(),
        dangerSurface = 0xFFFFF2F1.toInt(), dangerBorder = 0xFFFFB8B3.toInt(),
        nowIndicator = 0xFFFF3B30.toInt(), holiday = 0xFFC62835.toInt(),
        outOfMonth = 0xFF6E6E73.toInt(), selectionSurface = 0xFFDDECE8.toInt(),
        segmentedSelection = 0xFFFFFFFF.toInt(),
    )

    val dark = ThemeColors(
        primary = 0xFF5AD2B8.toInt(), primaryFill = 0xFF197565.toInt(),
        primaryDark = 0xFF0C4A42.toInt(), primaryText = 0xFF5AD2B8.toInt(),
        onPrimary = 0xFFFFFFFF.toInt(), accent = 0xFF876622.toInt(),
        onAccent = 0xFFFFFFFF.toInt(), background = 0xFF000000.toInt(),
        surface = 0xFF1C1C1E.toInt(), surfaceVariant = 0xFF2C2C2E.toInt(),
        text = 0xFFFFFFFF.toInt(), muted = 0xFF98989D.toInt(),
        border = 0xFF38383A.toInt(), danger = 0xFFFFB4A2.toInt(),
        dangerSurface = 0xFF3B1715.toInt(), dangerBorder = 0xFF7D312C.toInt(),
        nowIndicator = 0xFFFF453A.toInt(), holiday = 0xFFFF9A9D.toInt(),
        outOfMonth = 0xFF98989D.toInt(), selectionSurface = 0xFF233A35.toInt(),
        segmentedSelection = 0xFF636366.toInt(),
    )

    fun forConfiguration(configuration: Configuration): ThemeColors =
        if (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        ) dark else light
}

object Palette {
    private var colors = ThemePalettes.light

    val primary get() = colors.primary
    val primaryFill get() = colors.primaryFill
    val primaryDark get() = colors.primaryDark
    val primaryText get() = colors.primaryText
    val onPrimary get() = colors.onPrimary
    val accent get() = colors.accent
    val onAccent get() = colors.onAccent
    val background get() = colors.background
    val surface get() = colors.surface
    val surfaceVariant get() = colors.surfaceVariant
    val text get() = colors.text
    val muted get() = colors.muted
    val border get() = colors.border
    val danger get() = colors.danger
    val dangerSurface get() = colors.dangerSurface
    val dangerBorder get() = colors.dangerBorder
    val nowIndicator get() = colors.nowIndicator
    val holiday get() = colors.holiday
    val outOfMonth get() = colors.outOfMonth
    val selectionSurface get() = colors.selectionSurface
    val segmentedSelection get() = colors.segmentedSelection

    fun configure(context: Context) {
        colors = ThemePalettes.forConfiguration(context.resources.configuration)
    }
}

object UiMetrics {
    const val pagePaddingDp = 20
    const val surfacePaddingDp = 16
    const val surfaceRadiusDp = 8
    const val controlRadiusDp = 8
    const val controlHeightDp = 36
    const val compactControlHeightDp = 36
    const val sectionSpacingDp = 16
}

fun Context.dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

fun roundedBackground(
    context: Context,
    color: Int,
    borderColor: Int = Color.TRANSPARENT,
    radius: Int = UiMetrics.controlRadiusDp,
    borderWidthDp: Float = 1f,
): GradientDrawable = GradientDrawable().apply {
    shape = GradientDrawable.RECTANGLE
    setColor(color)
    cornerRadius = context.dp(radius).toFloat()
    if (borderColor != Color.TRANSPARENT) {
        val borderWidth = (borderWidthDp * context.resources.displayMetrics.density)
            .roundToInt()
            .coerceAtLeast(1)
        setStroke(borderWidth, borderColor)
    }
}

fun pageTitle(
    context: Context,
    title: String,
    subtitle: String? = null,
    subtitleIconResource: Int = 0,
): LinearLayout =
    LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, context.dp(4), 0, context.dp(18))
        addView(TextView(context).apply {
            text = context.getString(R.string.planner_eyebrow)
            textSize = 12f
            setTextColor(Palette.muted)
            setTypeface(typeface, Typeface.BOLD)
        })
        addView(TextView(context).apply {
            text = title
            textSize = 34f
            setTextColor(Palette.text)
            setTypeface(typeface, Typeface.BOLD)
            includeFontPadding = false
            setPadding(0, context.dp(4), 0, 0)
        })
        if (subtitle != null) {
            addView(TextView(context).apply {
                text = subtitle
                textSize = 14f
                setTextColor(Palette.muted)
                setPadding(0, context.dp(5), 0, 0)
                if (subtitleIconResource != 0) {
                    setCompoundDrawablesRelativeWithIntrinsicBounds(
                        subtitleIconResource,
                        0,
                        0,
                        0,
                    )
                    compoundDrawablePadding = context.dp(7)
                    compoundDrawableTintList = ColorStateList.valueOf(Palette.muted)
                }
            })
        }
    }

fun sectionTitle(
    context: Context,
    title: String,
    iconResource: Int = 0,
): TextView = TextView(context).apply {
    text = title
    textSize = 17f
    setTextColor(Palette.text)
    setTypeface(typeface, Typeface.BOLD)
    includeFontPadding = false
    gravity = Gravity.CENTER_VERTICAL
    setPadding(0, 0, 0, context.dp(12))
    if (iconResource != 0) {
        val iconSize = context.dp(18)
        val icon = context.getDrawable(iconResource)?.mutate()?.apply {
            setBounds(0, 0, iconSize, iconSize)
        }
        setCompoundDrawablesRelative(icon, null, null, null)
        compoundDrawablePadding = context.dp(6)
        compoundDrawableTintList = ColorStateList.valueOf(Palette.text)
    }
}

fun surface(context: Context): LinearLayout = LinearLayout(context).apply {
    orientation = LinearLayout.VERTICAL
    background = roundedBackground(
        context,
        Palette.surface,
        Palette.border,
        radius = UiMetrics.surfaceRadiusDp,
    )
    setPadding(
        context.dp(UiMetrics.surfacePaddingDp),
        context.dp(UiMetrics.surfacePaddingDp),
        context.dp(UiMetrics.surfacePaddingDp),
        context.dp(UiMetrics.surfacePaddingDp),
    )
}

fun fixedTab(context: Context, label: String, onClick: () -> Unit): TextView =
    TextView(context).apply {
        text = label
        textSize = 15f
        gravity = Gravity.CENTER
        setTextColor(Palette.text)
        isClickable = true
        isFocusable = true
        minHeight = context.dp(UiMetrics.controlHeightDp)
        setOnClickListener { onClick() }
    }

fun TextView.setSelectedStyle(context: Context, selected: Boolean) {
    setTextColor(if (selected) Palette.onPrimary else Palette.text)
    background = roundedBackground(
        context,
        if (selected) Palette.primaryFill else Palette.surface,
        if (selected) Palette.primaryFill else Palette.border,
        radius = UiMetrics.controlRadiusDp,
    )
    setTypeface(typeface, if (selected) Typeface.BOLD else Typeface.NORMAL)
}

fun TextView.setCompactSelectedStyle(context: Context, selected: Boolean) {
    setTextColor(Palette.text)
    background = roundedBackground(
        context,
        if (selected) Palette.segmentedSelection else Color.TRANSPARENT,
        radius = UiMetrics.controlRadiusDp,
    )
    setTypeface(typeface, if (selected) Typeface.BOLD else Typeface.NORMAL)
}

fun verticalPage(context: Context): LinearLayout = LinearLayout(context).apply {
    orientation = LinearLayout.VERTICAL
    setPadding(
        context.dp(UiMetrics.pagePaddingDp),
        context.dp(UiMetrics.pagePaddingDp),
        context.dp(UiMetrics.pagePaddingDp),
        context.dp(28),
    )
    layoutParams = ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
    )
}

fun spacer(context: Context, height: Int): View = View(context).apply {
    layoutParams = LinearLayout.LayoutParams(1, context.dp(height))
}
