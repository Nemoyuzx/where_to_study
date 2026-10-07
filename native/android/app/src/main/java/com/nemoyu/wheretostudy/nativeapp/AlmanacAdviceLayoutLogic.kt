package com.nemoyu.wheretostudy.nativeapp

internal object AlmanacAdviceLayoutLogic {
    fun shouldStack(
        availableWidthPx: Int,
        naturalLabelWidthPx: Int,
        gapPx: Int,
        minimumBodyWidthPx: Int,
    ): Boolean = naturalLabelWidthPx.coerceAtLeast(0).toLong() + gapPx.coerceAtLeast(0) +
        minimumBodyWidthPx.coerceAtLeast(0) > availableWidthPx.coerceAtLeast(0)
}
