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

object PhoneNavigationLayoutLogic {
    const val HEIGHT_DP = 56
    const val ITEM_HEIGHT_DP = 46
    const val HORIZONTAL_MARGIN_DP = 32
    const val BOTTOM_MARGIN_DP = 10
    const val CONTENT_GAP_DP = 8
    const val CONTENT_INSET_DP = HEIGHT_DP + BOTTOM_MARGIN_DP + CONTENT_GAP_DP
    const val SELECTION_ANIMATION_MILLIS = 220L
}

object AdaptiveLayoutLogic {
    const val MEDIUM_BREAKPOINT_DP = 700
    const val EXPANDED_BREAKPOINT_DP = 1000
    const val MEDIUM_NAVIGATION_WIDTH_DP = 210
    const val EXPANDED_NAVIGATION_WIDTH_DP = 230
    const val COLLAPSED_NAVIGATION_WIDTH_DP = 72
    const val COLLAPSED_NAVIGATION_ITEM_SIZE_DP = 48

    fun navigationHorizontalPaddingDp(
        collapsed: Boolean,
        widthClass: WindowWidthClass,
    ): Int = when {
        collapsed -> 0
        widthClass == WindowWidthClass.MEDIUM -> 16
        else -> 20
    }

    fun widthClass(windowWidthDp: Int): WindowWidthClass = when {
        windowWidthDp < MEDIUM_BREAKPOINT_DP -> WindowWidthClass.COMPACT
        windowWidthDp < EXPANDED_BREAKPOINT_DP -> WindowWidthClass.MEDIUM
        else -> WindowWidthClass.EXPANDED
    }

    fun resolve(
        windowWidthDp: Int,
        availableWidthDp: Int = windowWidthDp,
        verticalHinge: VerticalHingeBoundsDp? = null,
        navigationCollapsed: Boolean = false,
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
        val expandedNavigationWidth = hinge?.let { minOf(preferredNavigationWidth, it.left) }
            ?: preferredNavigationWidth
        val navigationWidth = if (navigationCollapsed) {
            minOf(COLLAPSED_NAVIGATION_WIDTH_DP, expandedNavigationWidth)
        } else {
            expandedNavigationWidth
        }
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
        contentWidthDp >= 840 -> 7
        contentWidthDp >= 600 -> 6
        contentWidthDp >= 480 -> 4
        else -> 3
    }

    fun plannerBuildingColumns(contentWidthDp: Int): Int = when {
        contentWidthDp >= 840 -> 5
        contentWidthDp >= 600 -> 4
        contentWidthDp >= 480 -> 3
        else -> 2
    }

    fun plannerSummaryColumns(@Suppress("UNUSED_PARAMETER") contentWidthDp: Int): Int = 3

    fun plannerResultColumns(contentWidthDp: Int): Int =
        if (contentWidthDp >= 600) 2 else 1
}
