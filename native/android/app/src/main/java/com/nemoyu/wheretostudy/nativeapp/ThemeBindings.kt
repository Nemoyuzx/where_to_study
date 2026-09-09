package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.Switch
import java.util.WeakHashMap
import kotlin.math.roundToInt

/** Bindings live on the view, without a global listener retaining detached pages. */
internal fun View.bindTheme(key: String, apply: () -> Unit) {
    @Suppress("UNCHECKED_CAST")
    val bindings = getTag(R.id.color_theme_bindings) as? MutableMap<String, () -> Unit>
        ?: mutableMapOf<String, () -> Unit>().also { setTag(R.id.color_theme_bindings, it) }
    bindings[key] = apply
    ThemeBindings.remember(this)
    apply()
}

fun TextView.setThemeTextColor(color: () -> Int) = bindTheme("text") { setTextColor(color()) }
fun View.setThemeBackgroundColor(color: () -> Int) = bindTheme("backgroundColor") { setBackgroundColor(color()) }

internal fun View.refreshColorTheme() {
    @Suppress("UNCHECKED_CAST")
    (getTag(R.id.color_theme_bindings) as? Map<String, () -> Unit>)?.values?.toList()?.forEach { it() }
    background?.refreshColorTheme()
    foreground?.refreshColorTheme()
    if (this is Switch) refreshNativeSwitchTheme()
    if (this is ViewGroup) repeat(childCount) { getChildAt(it).refreshColorTheme() }
    invalidate()
}

/** Also reaches currently visible popup windows without retaining their views. */
internal object ThemeBindings {
    private val views = WeakHashMap<View, Unit>()
    fun remember(view: View) { views[view] = Unit }
    fun refreshAll(root: View) {
        (views.keys.toList().map { it.rootView } + root).distinct().forEach { it.refreshColorTheme() }
    }
}

private data class SwitchTints(val thumb: ColorStateList?, val track: ColorStateList?)

private fun Switch.refreshNativeSwitchTheme() {
    @Suppress("UNCHECKED_CAST")
    val bindings = getTag(R.id.color_theme_bindings) as? Map<String, () -> Unit>
    if (bindings?.containsKey("trackTintList") == true) return
    val original = getTag(R.id.color_theme_native_tints) as? SwitchTints
        ?: SwitchTints(thumbTintList, trackTintList).also { setTag(R.id.color_theme_native_tints, it) }
    if (Palette.selection.preset == "default") {
        thumbTintList = original.thumb
        trackTintList = original.track
    } else {
        val states = arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf())
        thumbTintList = ColorStateList(states, intArrayOf(Palette.primaryText, Palette.muted))
        trackTintList = ColorStateList(states, intArrayOf(Palette.primaryFill, Palette.surfaceVariant))
    }
}

private fun Drawable.refreshColorTheme() {
    if (this is ThemeGradientDrawable) refreshColors()
    if (this is LayerDrawable) repeat(numberOfLayers) { getDrawable(it).refreshColorTheme() }
}

private class ThemeGradientDrawable(
    context: Context,
    private val fill: () -> Int,
    private val border: () -> Int,
    radius: Int,
    borderWidthDp: Float,
) : GradientDrawable() {
    private val borderWidth = (borderWidthDp * context.resources.displayMetrics.density)
        .roundToInt().coerceAtLeast(1)

    init {
        shape = RECTANGLE
        cornerRadius = context.dp(radius).toFloat()
        refreshColors()
    }

    fun refreshColors() {
        setColor(fill())
        val outline = border()
        setStroke(if (outline == Color.TRANSPARENT) 0 else borderWidth, outline)
    }
}

fun themedRoundedBackground(
    context: Context,
    color: () -> Int,
    borderColor: () -> Int = { Color.TRANSPARENT },
    radius: Int = UiMetrics.controlRadiusDp,
    borderWidthDp: Float = 1f,
): GradientDrawable = ThemeGradientDrawable(context, color, borderColor, radius, borderWidthDp)
