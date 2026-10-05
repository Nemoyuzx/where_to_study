package com.nemoyu.wheretostudy.nativeapp

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.animation.AccelerateDecelerateInterpolator
import kotlin.math.roundToInt

/** Reveals a natural-size body through a clipped viewport, without scaling its rows. */
internal class DisclosureMotionController(
    private val section: ViewGroup,
    private val content: ViewGroup,
    private val indicator: View,
    private val durationMillis: Long = 220L,
    private val onSettled: () -> Unit = {},
    private val onDetached: () -> Unit = {},
) {
    private var animator: ValueAnimator? = null
    val isRunning: Boolean get() = animator?.isRunning == true

    init {
        section.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) = Unit
            override fun onViewDetachedFromWindow(view: View) {
                cancel()
                onDetached()
            }
        })
    }

    fun cancel() {
        val previous = animator
        animator = null
        previous?.cancel()
    }

    fun animateTo(expanded: Boolean, hasContent: Boolean = content.childCount > 0) {
        // Cancellation cannot settle a new target. Keep the current viewport and
        // opacity so a quick reversal never jumps back to either endpoint.
        cancel()
        indicator.animate().cancel()
        val startHeight = if (content.visibility == View.VISIBLE) {
            content.layoutParams.height.takeIf { it >= 0 } ?: content.height
        } else 0
        val startAlpha = if (content.visibility == View.VISIBLE) content.alpha else 0f
        val startRotation = indicator.rotation
        val showContent = expanded && hasContent
        val targetRotation = if (expanded) 180f else 0f
        val margins = content.layoutParams as? ViewGroup.MarginLayoutParams
        val width = section.width - section.paddingLeft - section.paddingRight -
            (margins?.leftMargin ?: 0) - (margins?.rightMargin ?: 0)
        if (hasContent && width > 0) {
            content.measure(
                View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
            )
        }
        val targetHeight = if (showContent) content.measuredHeight else 0

        fun settle() {
            content.visibility = if (showContent) View.VISIBLE else View.GONE
            content.layoutParams.height = ViewGroup.LayoutParams.WRAP_CONTENT
            content.alpha = 1f
            content.requestLayout()
            indicator.rotation = targetRotation
            if (section.isAttachedToWindow) onSettled()
        }

        if (!section.isAttachedToWindow || width <= 0 ||
            (Build.VERSION.SDK_INT >= 26 && !ValueAnimator.areAnimatorsEnabled())
        ) {
            settle()
            return
        }
        if (hasContent) {
            content.layoutParams.height = startHeight
            content.alpha = startAlpha
            content.visibility = View.VISIBLE
            content.requestLayout()
        }
        val next = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = durationMillis
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float
                if (hasContent) {
                    content.layoutParams.height =
                        (startHeight + (targetHeight - startHeight) * progress).roundToInt()
                    content.alpha = startAlpha + ((if (showContent) 1f else 0f) - startAlpha) * progress
                    content.requestLayout()
                }
                indicator.rotation = startRotation + (targetRotation - startRotation) * progress
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (animator !== animation) return
                    animator = null
                    settle()
                }
            })
        }
        animator = next
        next.start()
    }
}
