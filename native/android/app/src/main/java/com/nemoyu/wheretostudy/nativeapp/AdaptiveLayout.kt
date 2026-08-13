package com.nemoyu.wheretostudy.nativeapp

enum class WindowWidthClass {
    COMPACT,
    MEDIUM,
    EXPANDED,
}

data class VerticalHingeBoundsDp(
    val left: Int,
    val right: Int,
)

data class AdaptiveLayoutSpec(
    val widthClass: WindowWidthClass,
    val navigationWidthDp: Int,
    val hingeSpacerDp: Int,
    val contentWidthDp: Int,
    val avoidsVerticalHinge: Boolean,
) {
    val usesBottomNavigation: Boolean
        get() = widthClass == WindowWidthClass.COMPACT && !avoidsVerticalHinge
}

object AdaptiveLayoutLogic {
    const val MEDIUM_BREAKPOINT_DP = 600
    const val EXPANDED_BREAKPOINT_DP = 840
    const val MEDIUM_NAVIGATION_WIDTH_DP = 176
    const val EXPANDED_NAVIGATION_WIDTH_DP = 224

    fun widthClass(windowWidthDp: Int): WindowWidthClass = when {
        windowWidthDp < MEDIUM_BREAKPOINT_DP -> WindowWidthClass.COMPACT
        windowWidthDp < EXPANDED_BREAKPOINT_DP -> WindowWidthClass.MEDIUM
        else -> WindowWidthClass.EXPANDED
    }

    fun resolve(
        windowWidthDp: Int,
        availableWidthDp: Int = windowWidthDp,
        verticalHinge: VerticalHingeBoundsDp? = null,
    ): AdaptiveLayoutSpec {
        val safeAvailableWidth = availableWidthDp.coerceAtLeast(0)
        val widthClass = widthClass(windowWidthDp.coerceAtLeast(0))
        val hinge = verticalHinge?.takeIf {
            it.left > 0 && it.right >= it.left && it.right < safeAvailableWidth
        }
        if (widthClass == WindowWidthClass.COMPACT && hinge == null) {
            return AdaptiveLayoutSpec(widthClass, 0, 0, safeAvailableWidth, false)
        }

        val preferredNavigationWidth = when (widthClass) {
            WindowWidthClass.COMPACT -> checkNotNull(hinge).left
            WindowWidthClass.MEDIUM -> MEDIUM_NAVIGATION_WIDTH_DP
            WindowWidthClass.EXPANDED -> EXPANDED_NAVIGATION_WIDTH_DP
        }
        val navigationWidth = hinge?.let { minOf(preferredNavigationWidth, it.left) }
            ?: preferredNavigationWidth
        val hingeSpacer = hingeSpacerDp(
            navigationWidthDp = navigationWidth,
            verticalHinge = hinge,
        )

        return AdaptiveLayoutSpec(
            widthClass = widthClass,
            navigationWidthDp = navigationWidth,
            hingeSpacerDp = hingeSpacer,
            contentWidthDp = (safeAvailableWidth - navigationWidth - hingeSpacer).coerceAtLeast(0),
            avoidsVerticalHinge = hinge != null,
        )
    }

    fun hingeSpacerDp(
        navigationWidthDp: Int,
        verticalHinge: VerticalHingeBoundsDp?,
    ): Int {
        val hinge = verticalHinge ?: return 0
        if (hinge.right < hinge.left) return 0
        return (hinge.right - navigationWidthDp.coerceAtMost(hinge.left)).coerceAtLeast(0)
    }
}

object AdaptiveContentLogic {
    fun plannerSlotColumns(contentWidthDp: Int): Int = when {
        contentWidthDp >= AdaptiveLayoutLogic.EXPANDED_BREAKPOINT_DP -> 7
        contentWidthDp >= AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP -> 5
        contentWidthDp >= 480 -> 3
        else -> 2
    }

    fun plannerBuildingColumns(contentWidthDp: Int): Int = when {
        contentWidthDp >= AdaptiveLayoutLogic.EXPANDED_BREAKPOINT_DP -> 5
        contentWidthDp >= AdaptiveLayoutLogic.MEDIUM_BREAKPOINT_DP -> 4
        contentWidthDp >= 480 -> 3
        else -> 2
    }

    fun plannerSummaryColumns(contentWidthDp: Int): Int =
        if (contentWidthDp >= 480) 3 else 1
}
