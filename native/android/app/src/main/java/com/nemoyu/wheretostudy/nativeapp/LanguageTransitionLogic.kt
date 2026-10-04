package com.nemoyu.wheretostudy.nativeapp

import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Bounded pure rules; never owns an Activity, view or image history. */
internal object LanguageTransitionLogic {
    const val MAXIMUM_PIXELS = 96 * 1024
    const val MAXIMUM_BITMAP_BYTES = MAXIMUM_PIXELS * 4
    const val MAXIMUM_WORKING_BYTES = MAXIMUM_BITMAP_BYTES * 3

    fun bufferSize(width: Int, height: Int): Pair<Int, Int> {
        require(width > 0 && height > 0)
        val scale = min(1.0, sqrt(MAXIMUM_PIXELS.toDouble() / (width.toDouble() * height)))
        val w = max(1, (width * scale).toInt())
        val h = max(1, min((height * scale).toInt(), MAXIMUM_PIXELS / w))
        return w to h
    }

    /** Sliding-window box blur: O(pixels), radius bounded, no native SDK dependence. */
    fun blur(pixels: IntArray, width: Int, height: Int, cancelled: () -> Boolean = { false }) {
        require(width > 0 && height > 0 && width.toLong() * height <= MAXIMUM_PIXELS)
        require(pixels.size == width * height)
        val scratch = IntArray(pixels.size)
        val radius = 3
        try {
            repeat(2) {
                pass(pixels, scratch, width, height, radius, horizontal = true, cancelled = cancelled)
                pass(scratch, pixels, width, height, radius, horizontal = false, cancelled = cancelled)
            }
        } finally { scratch.fill(0) }
    }

    private fun pass(input: IntArray, output: IntArray, width: Int, height: Int, radius: Int,
        horizontal: Boolean, cancelled: () -> Boolean) {
        val lines = if (horizontal) height else width
        val length = if (horizontal) width else height
        val window = radius * 2 + 1
        for (line in 0 until lines) {
            if (cancelled()) throw java.util.concurrent.CancellationException()
            fun index(position: Int): Int = if (horizontal) line * width + position else position * width + line
            var a = 0; var r = 0; var g = 0; var b = 0
            fun add(position: Int, sign: Int) {
                val color = input[index(position.coerceIn(0, length - 1))]
                a += (color ushr 24) * sign; r += ((color ushr 16) and 255) * sign
                g += ((color ushr 8) and 255) * sign; b += (color and 255) * sign
            }
            for (offset in -radius..radius) add(offset, 1)
            for (position in 0 until length) {
                output[index(position)] = ((a / window) shl 24) or ((r / window) shl 16) or
                    ((g / window) shl 8) or (b / window)
                add(position - radius, -1); add(position + radius + 1, 1)
            }
        }
    }
}

internal class LanguageLayoutReadiness {
    private var previous: List<Int>? = null
    private var stableFrames = 0
    fun reset() { previous = null; stableFrames = 0 }
    fun observe(targetLocale: Boolean, attached: Boolean, restoring: Boolean, layoutRequested: Boolean,
        bounds: List<Int>): Boolean {
        if (!targetLocale || !attached || restoring || layoutRequested || bounds.size != 4 ||
            bounds[2] <= 0 || bounds[3] <= 0) { reset(); return false }
        stableFrames = if (previous == bounds) stableFrames + 1 else 1
        previous = bounds.toList()
        return stableFrames >= 2
    }
}
