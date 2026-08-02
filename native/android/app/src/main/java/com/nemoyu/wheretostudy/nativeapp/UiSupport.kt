package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView

object Palette {
    val primary = Color.rgb(23, 107, 93)
    val primaryDark = Color.rgb(12, 74, 66)
    val accent = Color.rgb(209, 168, 69)
    val background = Color.rgb(244, 247, 244)
    val surface = Color.WHITE
    val text = Color.rgb(21, 32, 29)
    val muted = Color.rgb(101, 113, 109)
    val border = Color.rgb(220, 227, 222)
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
    setTextColor(if (selected) Color.WHITE else Palette.text)
    background = roundedBackground(
        context,
        if (selected) Palette.primary else Palette.surface,
        if (selected) Palette.primary else Palette.border,
        radius = 6,
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
