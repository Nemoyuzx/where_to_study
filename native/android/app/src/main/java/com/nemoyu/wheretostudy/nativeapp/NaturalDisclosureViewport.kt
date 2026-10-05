package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.view.View
import android.widget.FrameLayout

/** A height-animated viewport must not remeasure its natural body at that
 * shrinking height: doing so compresses/reflows rows during collapse. */
internal class NaturalDisclosureViewport(context: Context) : FrameLayout(context) {
    init { clipChildren = true; clipToPadding = true }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        var naturalWidth = 0; var naturalHeight = 0
        for (index in 0 until childCount) {
            val child = getChildAt(index)
            if (child.visibility == View.GONE) continue
            measureChildWithMargins(child, widthMeasureSpec, 0,
                MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED), 0)
            val margins = child.layoutParams as LayoutParams
            naturalWidth = maxOf(naturalWidth, child.measuredWidth + margins.leftMargin + margins.rightMargin)
            naturalHeight = maxOf(naturalHeight, child.measuredHeight + margins.topMargin + margins.bottomMargin)
        }
        setMeasuredDimension(resolveSize(naturalWidth + paddingLeft + paddingRight, widthMeasureSpec),
            resolveSize(naturalHeight + paddingTop + paddingBottom, heightMeasureSpec))
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        for (index in 0 until childCount) {
            val child = getChildAt(index)
            if (child.visibility == View.GONE) continue
            val margins = child.layoutParams as LayoutParams
            val x = if (layoutDirection == LAYOUT_DIRECTION_RTL)
                width - paddingRight - margins.rightMargin - child.measuredWidth else paddingLeft + margins.leftMargin
            val y = paddingTop + margins.topMargin
            child.layout(x, y, x + child.measuredWidth, y + child.measuredHeight)
        }
    }
}
