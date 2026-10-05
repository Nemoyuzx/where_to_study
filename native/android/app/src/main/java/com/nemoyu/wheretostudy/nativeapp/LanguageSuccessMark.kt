package com.nemoyu.wheretostudy.nativeapp

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator

/** A locally drawn success mark; it never owns transition readiness or haptics. */
internal class LanguageSuccessMark(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val ring = Path()
    private val check = Path()
    private val segment = Path()
    private val measure = PathMeasure()
    private var progress = 0f
    private var animation: ValueAnimator? = null

    fun play(reducedMotion: Boolean) {
        animation?.cancel()
        if (reducedMotion) { progress = 1f; invalidate(); return }
        progress = 0f
        animation = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 380; interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { progress = it.animatedValue as Float; invalidate() }
            start()
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        val size = minOf(w, h).toFloat()
        val dx = (w - size) / 2f; val dy = (h - size) / 2f
        paint.strokeWidth = size * .055f
        ring.reset(); ring.addCircle(w / 2f, h / 2f, size * .43f, Path.Direction.CW)
        check.reset(); check.moveTo(dx + size * .27f, dy + size * .51f)
        check.lineTo(dx + size * .43f, dy + size * .66f)
        check.lineTo(dx + size * .74f, dy + size * .34f)
    }

    override fun onDraw(canvas: Canvas) {
        paint.color = Palette.primaryText
        drawPart(canvas, ring, (progress / .48f).coerceIn(0f, 1f))
        drawPart(canvas, check, ((progress - .28f) / .72f).coerceIn(0f, 1f))
    }

    private fun drawPart(canvas: Canvas, path: Path, fraction: Float) {
        segment.reset(); measure.setPath(path, false)
        measure.getSegment(0f, measure.length * fraction, segment, true)
        canvas.drawPath(segment, paint)
    }

    override fun onDetachedFromWindow() {
        animation?.cancel(); animation = null
        super.onDetachedFromWindow()
    }
}
