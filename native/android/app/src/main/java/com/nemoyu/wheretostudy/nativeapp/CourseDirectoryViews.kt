package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.ColorUtils

private fun courseTintSurface(): Int = ColorUtils.blendARGB(Palette.primaryFill, Palette.surface, 0.91f)
private fun courseTintText(): Int = ColorThemeLogic.readableText(Palette.primaryText, courseTintSurface())

internal fun courseDirectoryRow(context: MainActivity, key: String, name: String, teachers: List<String>,
    counts: CourseSubmissionCounts, termLabel: String? = null, onDetails: (() -> Unit)? = null,
    onOpen: () -> Unit): View = LinearLayout(context).apply {
    tag = key
    UiText.preserveRawText(this)
    orientation = LinearLayout.VERTICAL
    contentDescription = (listOf(name) + teachers + listOfNotNull(termLabel,
        counts.pending?.let { context.getString(R.string.course_pending_count, it) },
        counts.submitted?.let { context.getString(R.string.course_submitted_count, it) })).joinToString(" · ")
    addView(LinearLayout(context).apply {
        tag = "$key.disclosure.header"
        isClickable = true; isFocusable = true
        contentDescription = name
        setOnClickListener { if (isAttachedToWindow) { context.performControlHaptic(it); onOpen() } }
        orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        minimumHeight = context.dp(72); setPadding(0, context.dp(12), 0, context.dp(12))
        addView(ImageView(context).apply {
            setImageResource(R.drawable.ic_course_book); scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(context.dp(10), context.dp(10), context.dp(10), context.dp(10))
            background = themedRoundedBackground(context, ::courseTintSurface, radius = 10)
            bindTheme("courseBookTint") { imageTintList = ColorStateList.valueOf(courseTintText()) }
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(context.dp(40), context.dp(40)).apply { marginEnd = context.dp(12) })
        addView(LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(TextView(context).apply {
                text = name; UiText.preserveRawText(this); textSize = 17f
                includeFontPadding = false; setTypeface(typeface, Typeface.BOLD); setThemeTextColor { Palette.text }
            })
            val labels = teachers + listOfNotNull(
                counts.pending?.let { context.getString(R.string.course_pending_count, it) },
                counts.submitted?.let { context.getString(R.string.course_submitted_count, it) }, termLabel)
            if (labels.isNotEmpty()) addView(CourseChipFlow(context).apply {
                labels.forEach { label -> addView(TextView(context).apply {
                    text = label; UiText.preserveRawText(this); textSize = 12f; includeFontPadding = false
                    setThemeTextColor(::courseTintText); background = themedRoundedBackground(context, ::courseTintSurface, radius = 6)
                    setPadding(context.dp(6), context.dp(3), context.dp(6), context.dp(3))
                }) }
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                .apply { topMargin = context.dp(6) })
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        addView(ImageView(context).apply {
            tag = "$key.disclosure.indicator"
            setImageResource(R.drawable.ic_chevron_down)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(context.dp(7), context.dp(7), context.dp(7), context.dp(7))
            bindTheme("courseChevronTint") { imageTintList = ColorStateList.valueOf(Palette.muted) }
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(context.dp(UiMetrics.controlHeightDp), context.dp(UiMetrics.controlHeightDp)).apply {
            gravity = Gravity.CENTER_VERTICAL; marginStart = context.dp(12)
        })
        if (onDetails != null) addView(ImageView(context).apply {
            tag = "$key.details"
            setImageResource(R.drawable.ic_settings_info); scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(context.dp(7), context.dp(7), context.dp(7), context.dp(7))
            bindTheme("courseInfoTint") { imageTintList = ColorStateList.valueOf(Palette.muted) }
            contentDescription = context.uiText("课程详情")
            isClickable = true; isFocusable = true
            setOnClickListener { if (isAttachedToWindow) onDetails() }
        }, LinearLayout.LayoutParams(context.dp(UiMetrics.controlHeightDp), context.dp(UiMetrics.controlHeightDp)).apply {
            gravity = Gravity.CENTER_VERTICAL
        })
    }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    addView(View(context).apply { setThemeBackgroundColor { Palette.border } },
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1).apply { marginStart = context.dp(52) })
}

/** Let real font-scale/long teacher labels wrap without changing the app's typography or control metrics. */
private class CourseChipFlow(context: Context) : ViewGroup(context) {
    private val gap = context.dp(4)
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val available = MeasureSpec.getSize(widthMeasureSpec).coerceAtLeast(1)
        var x = 0; var y = 0; var lineHeight = 0
        repeat(childCount) { index ->
            val child = getChildAt(index)
            child.measure(MeasureSpec.makeMeasureSpec(available, MeasureSpec.AT_MOST),
                MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
            if (x > 0 && x + child.measuredWidth > available) { y += lineHeight + gap; x = 0; lineHeight = 0 }
            x += child.measuredWidth + gap; lineHeight = maxOf(lineHeight, child.measuredHeight)
        }
        setMeasuredDimension(resolveSize(available, widthMeasureSpec), resolveSize(y + lineHeight, heightMeasureSpec))
    }
    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val available = right - left
        var x = 0; var y = 0; var lineHeight = 0
        repeat(childCount) { index ->
            val child = getChildAt(index)
            if (x > 0 && x + child.measuredWidth > available) { y += lineHeight + gap; x = 0; lineHeight = 0 }
            val childLeft = if (layoutDirection == LAYOUT_DIRECTION_RTL) available - x - child.measuredWidth else x
            child.layout(childLeft, y, childLeft + child.measuredWidth, y + child.measuredHeight)
            x += child.measuredWidth + gap; lineHeight = maxOf(lineHeight, child.measuredHeight)
        }
    }
}
