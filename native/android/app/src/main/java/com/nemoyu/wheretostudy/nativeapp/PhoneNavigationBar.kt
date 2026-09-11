package com.nemoyu.wheretostudy.nativeapp

import android.animation.ValueAnimator
import android.content.Context
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.ColorUtils

/** A single moving selection surface. Text/icons never scale or relayout during selection. */
internal class PhoneNavigationBar(context: Context) : FrameLayout(context) {
    private val indicator = View(context).apply {
        id = R.id.phone_navigation_indicator
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        background = themedRoundedBackground(context, { Palette.surface }, radius = 24)
    }
    private val items = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
    }
    private var selectedIndex = 0
    private data class Geometry(val width: Int, val height: Int, val x: Float, val y: Float)
    private var lastGeometry: Geometry? = null

    init {
        clipToOutline = true
        background = themedRoundedBackground(context,
            { ColorUtils.blendARGB(Palette.surface, Palette.surfaceVariant, 0.62f) },
            { ColorUtils.blendARGB(Palette.border, Palette.surface, 0.68f) },
            radius = PhoneNavigationLayoutLogic.HEIGHT_DP / 2)
        elevation = context.dp(4).toFloat()
        // Child coordinates below are physical (left), including in RTL layouts.
        addView(indicator, LayoutParams(0, context.dp(PhoneNavigationLayoutLogic.ITEM_HEIGHT_DP), Gravity.TOP or Gravity.LEFT))
        addView(items, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT).apply {
            setMargins(context.dp(4), context.dp(4), context.dp(4), context.dp(4))
        })
        addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            // Text weight and destination content also request layout. Only a real
            // geometry change should interrupt an in-flight selection animation.
            if (indicatorGeometry() != lastGeometry) updateIndicator(false)
        }
    }

    fun setItems(tabs: List<TextView>) {
        items.removeAllViews()
        tabs.forEach { tab ->
            items.addView(tab, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
        }
    }

    fun select(index: Int, animate: Boolean) {
        val next = index.coerceIn(0, (items.childCount - 1).coerceAtLeast(0))
        if (next == selectedIndex && indicator.width > 0) return
        selectedIndex = next
        updateIndicator(animate)
    }

    private fun indicatorGeometry(): Geometry? {
        val selected = items.getChildAt(selectedIndex) ?: return null
        if (selected.width <= 0 || items.height <= 0) return null
        val inset = context.dp(2)
        val width = (selected.width - inset * 2).coerceAtLeast(1)
        val height = minOf(context.dp(PhoneNavigationLayoutLogic.ITEM_HEIGHT_DP), items.height)
        return Geometry(width, height, (items.left + selected.left + inset).toFloat(),
            items.top + (items.height - height) / 2f)
    }

    private fun updateIndicator(animate: Boolean) {
        val geometry = indicatorGeometry() ?: return
        lastGeometry = geometry
        if (indicator.layoutParams.width != geometry.width || indicator.layoutParams.height != geometry.height) {
            indicator.layoutParams = LayoutParams(geometry.width, geometry.height, Gravity.TOP or Gravity.LEFT)
        }
        indicator.translationY = geometry.y
        val target = geometry.x
        indicator.animate().cancel()
        if (animate && (Build.VERSION.SDK_INT < 26 || ValueAnimator.areAnimatorsEnabled())) {
            indicator.animate().translationX(target)
                .setDuration(PhoneNavigationLayoutLogic.SELECTION_ANIMATION_MILLIS)
                .setInterpolator(PathInterpolator(0.2f, 0f, 0f, 1f)).start()
        } else {
            indicator.translationX = target
        }
    }

    override fun onDetachedFromWindow() {
        indicator.animate().cancel()
        super.onDetachedFromWindow()
    }
}
