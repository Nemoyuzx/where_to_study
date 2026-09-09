package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.graphics.drawable.LayerDrawable
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.widget.TextView
import android.widget.Switch
import java.util.WeakHashMap
import kotlin.math.roundToInt
import androidx.core.graphics.ColorUtils

/** Bindings live on the view, without a global listener retaining detached pages. */
internal fun View.bindTheme(key: String, apply: () -> Unit) {
    @Suppress("UNCHECKED_CAST")
    val bindings = getTag(R.id.color_theme_bindings) as? MutableMap<String, () -> Unit>
        ?: mutableMapOf<String, () -> Unit>().also {
            setTag(R.id.color_theme_bindings, it)
            // Color context is complete once a newly rendered control joins its actual parent.
            addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(view: View) = view.refreshOwnColorTheme()
                override fun onViewDetachedFromWindow(view: View) = Unit
            })
        }
    bindings[key] = apply
    ThemeBindings.remember(this)
    apply()
}

fun TextView.setThemeTextColor(color: () -> Int) = bindTheme("text") {
    val requested = color()
    val adjustsInk = requested in setOf(
        Palette.text, Palette.muted, Palette.primaryText, Palette.onPrimary, Palette.onAccent,
        Palette.holiday, Palette.danger,
        Palette.assignment, Palette.schoolNotice, Palette.publicDeadline, Palette.conferenceDeadline,
        Palette.summerCampDeadline, Palette.hackathonDeadline, Palette.customDeadline,
    )
    setTextColor(if (Palette.selection.preset != "default" && adjustsInk)
        ColorThemeLogic.readableText(requested, themeSurfaceColor()) else requested)
}
fun View.setThemeBackgroundColor(color: () -> Int) = bindTheme("backgroundColor") { setBackgroundColor(color()) }

internal fun View.refreshColorTheme() {
    refreshOwnColorTheme()
    if (this is ViewGroup) repeat(childCount) { getChildAt(it).refreshColorTheme() }
}

private fun View.refreshOwnColorTheme() {
    @Suppress("UNCHECKED_CAST")
    val bindings = (getTag(R.id.color_theme_bindings) as? Map<String, () -> Unit>)?.toMap().orEmpty()
    // Resolve new surfaces before ink, so semantic labels can use their actual composite background.
    bindings.filterKeys { it != "text" }.values.forEach { it() }
    background?.refreshColorTheme()
    foreground?.refreshColorTheme()
    bindings["text"]?.invoke()
    if (this is Switch) refreshNativeSwitchTheme()
    invalidate()
}

internal fun View.themeSurfaceColor(): Int {
    var result = Palette.background
    generateSequence(this) { it.parent as? View }.toList().asReversed().forEach { view ->
        view.background?.themeFillColor()?.let { result = ColorUtils.compositeColors(it, result) }
    }
    return result
}

private fun Drawable.themeFillColor(): Int? = when (this) {
    is ThemeGradientDrawable -> currentFill()
    is ColorDrawable -> color
    is GradientDrawable -> color?.defaultColor
    is InsetDrawable -> drawable?.themeFillColor()
    is LayerDrawable -> if (numberOfLayers > 0) getDrawable(0).themeFillColor() else null
    else -> null
}

/** Keep framework-owned window surfaces synchronized without replacing page content. */
@Suppress("DEPRECATION")
internal fun bindWindowColorTheme(window: Window, modal: Boolean = false) {
    val root = window.decorView
    @Suppress("UNCHECKED_CAST")
    if ((root.getTag(R.id.color_theme_bindings) as? Map<String, () -> Unit>)?.containsKey("windowSurface") == true) return
    val original = root.background
    val originalStatus = window.statusBarColor
    val originalNavigation = window.navigationBarColor
    root.bindTheme("windowSurface") {
        val legacy = Palette.selection.preset == "default"
        window.setBackgroundDrawable(if (legacy) original else if (modal)
            themedRoundedBackground(root.context, { Palette.elevated }, radius = 16)
            else ColorDrawable(Palette.background))
        if (!modal) {
            window.statusBarColor = if (legacy) originalStatus else Palette.background
            window.navigationBarColor = if (legacy) originalNavigation else Palette.surface
        }
    }
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

    fun currentFill(): Int = fill()
}

fun themedRoundedBackground(
    context: Context,
    color: () -> Int,
    borderColor: () -> Int = { Color.TRANSPARENT },
    radius: Int = UiMetrics.controlRadiusDp,
    borderWidthDp: Float = 1f,
): GradientDrawable = ThemeGradientDrawable(context, color, borderColor, radius, borderWidthDp)
