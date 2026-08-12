package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView

data class ThemeColors(
    val primary: Int,
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
)

object ThemePalettes {
    val light = ThemeColors(
        primary = 0xFF176B5D.toInt(), primaryDark = 0xFF0C4A42.toInt(),
        primaryText = 0xFF0C4A42.toInt(), onPrimary = 0xFFFFFFFF.toInt(),
        accent = 0xFFD1A845.toInt(), onAccent = 0xFF15201D.toInt(),
        background = 0xFFF4F7F4.toInt(), surface = 0xFFFFFFFF.toInt(),
        surfaceVariant = 0xFFEDF2EE.toInt(), text = 0xFF15201D.toInt(),
        muted = 0xFF65716D.toInt(), border = 0xFFDCE3DE.toInt(),
        danger = 0xFF8A2D1C.toInt(), dangerSurface = 0xFFFFF2ED.toInt(),
        dangerBorder = 0xFFE6B7AA.toInt(), nowIndicator = 0xFFC62835.toInt(),
        holiday = 0xFFA92F36.toInt(), outOfMonth = 0xFF6A7670.toInt(),
    )

    val dark = ThemeColors(
        primary = 0xFF176B5D.toInt(), primaryDark = 0xFF0C4A42.toInt(),
        primaryText = 0xFF78CDBD.toInt(), onPrimary = 0xFFFFFFFF.toInt(),
        accent = 0xFFD8AE4E.toInt(), onAccent = 0xFF211A08.toInt(),
        background = 0xFF101512.toInt(), surface = 0xFF181E1B.toInt(),
        surfaceVariant = 0xFF222A26.toInt(), text = 0xFFEDF5F1.toInt(),
        muted = 0xFFAAB8B2.toInt(), border = 0xFF3A4741.toInt(),
        danger = 0xFFFFB4A2.toInt(), dangerSurface = 0xFF40221D.toInt(),
        dangerBorder = 0xFF8C4A3D.toInt(), nowIndicator = 0xFFC62835.toInt(),
        holiday = 0xFFFF9A9D.toInt(), outOfMonth = 0xFF7C8A83.toInt(),
    )

    fun forConfiguration(configuration: Configuration): ThemeColors =
        if (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        ) dark else light
}

object Palette {
    private var colors = ThemePalettes.light

    val primary get() = colors.primary
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

    fun configure(context: Context) {
        colors = ThemePalettes.forConfiguration(context.resources.configuration)
    }
}

fun Context.dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

fun roundedBackground(
    context: Context,
    color: Int,
    borderColor: Int = Color.TRANSPARENT,
    radius: Int = 6,
): GradientDrawable = GradientDrawable().apply {
    shape = GradientDrawable.RECTANGLE
    setColor(color)
    cornerRadius = context.dp(radius).toFloat()
    if (borderColor != Color.TRANSPARENT) {
        setStroke(context.dp(1), borderColor)
    }
}

fun pageTitle(context: Context, title: String, subtitle: String? = null): LinearLayout =
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
            textSize = 28f
            setTextColor(Palette.text)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, context.dp(4), 0, 0)
        })
        if (subtitle != null) {
            addView(TextView(context).apply {
                text = subtitle
                textSize = 14f
                setTextColor(Palette.muted)
                setPadding(0, context.dp(5), 0, 0)
            })
        }
    }

fun sectionTitle(context: Context, title: String): TextView = TextView(context).apply {
    text = title
    textSize = 18f
    setTextColor(Palette.text)
    setTypeface(typeface, Typeface.BOLD)
    setPadding(0, 0, 0, context.dp(12))
}

fun surface(context: Context): LinearLayout = LinearLayout(context).apply {
    orientation = LinearLayout.VERTICAL
    background = roundedBackground(context, Palette.surface, Palette.border, radius = 6)
    setPadding(context.dp(16), context.dp(16), context.dp(16), context.dp(16))
}

fun fixedTab(context: Context, label: String, onClick: () -> Unit): TextView =
    TextView(context).apply {
        text = label
        textSize = 15f
        gravity = Gravity.CENTER
        setTextColor(Palette.text)
        isClickable = true
        isFocusable = true
        minHeight = context.dp(44)
        setOnClickListener { onClick() }
    }

fun TextView.setSelectedStyle(context: Context, selected: Boolean) {
    setTextColor(if (selected) Palette.onPrimary else Palette.text)
    background = roundedBackground(
        context,
        if (selected) Palette.primary else Palette.surface,
        if (selected) Palette.primary else Palette.border,
        radius = 6,
    )
    setTypeface(typeface, if (selected) Typeface.BOLD else Typeface.NORMAL)
}

fun TextView.setCompactSelectedStyle(context: Context, selected: Boolean) {
    setTextColor(if (selected) Palette.onPrimary else Palette.text)
    background = roundedBackground(
        context,
        if (selected) Palette.primary else Color.TRANSPARENT,
        radius = 8,
    )
    setTypeface(typeface, if (selected) Typeface.BOLD else Typeface.NORMAL)
}

fun verticalPage(context: Context): LinearLayout = LinearLayout(context).apply {
    orientation = LinearLayout.VERTICAL
    setPadding(context.dp(20), context.dp(20), context.dp(20), context.dp(28))
    layoutParams = ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
    )
}

fun spacer(context: Context, height: Int): View = View(context).apply {
    layoutParams = LinearLayout.LayoutParams(1, context.dp(height))
}
