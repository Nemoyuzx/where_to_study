package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdaptiveLayoutLogicTest {
    @Test
    fun collapsedNavigationItemsAreCenteredSquaresInsideTheRail() {
        assertEquals(72, AdaptiveLayoutLogic.COLLAPSED_NAVIGATION_WIDTH_DP)
        assertEquals(48, AdaptiveLayoutLogic.COLLAPSED_NAVIGATION_ITEM_SIZE_DP)
        assertTrue(
            AdaptiveLayoutLogic.COLLAPSED_NAVIGATION_ITEM_SIZE_DP <
                AdaptiveLayoutLogic.COLLAPSED_NAVIGATION_WIDTH_DP,
        )
    }

    @Test
    fun widthClassesUseActualWindowBreakpoints() {
        assertEquals(WindowWidthClass.COMPACT, AdaptiveLayoutLogic.widthClass(0))
        assertEquals(WindowWidthClass.COMPACT, AdaptiveLayoutLogic.widthClass(699))
        assertEquals(WindowWidthClass.MEDIUM, AdaptiveLayoutLogic.widthClass(700))
        assertEquals(WindowWidthClass.MEDIUM, AdaptiveLayoutLogic.widthClass(999))
        assertEquals(WindowWidthClass.EXPANDED, AdaptiveLayoutLogic.widthClass(1_000))
        assertEquals(WindowWidthClass.EXPANDED, AdaptiveLayoutLogic.widthClass(1_600))
    }

    @Test
    fun navigationChangesAtWindowBreakpointsWithoutAFeature() {
        val compact = AdaptiveLayoutLogic.resolve(699)
        val medium = AdaptiveLayoutLogic.resolve(700)
        val expanded = AdaptiveLayoutLogic.resolve(1_000)

        assertTrue(compact.usesBottomNavigation)
        assertEquals(0, compact.navigationWidthDp)
        assertEquals(699, compact.contentWidthDp)
        assertFalse(medium.usesBottomNavigation)
        assertEquals(210, medium.navigationWidthDp)
        assertEquals(490, medium.contentWidthDp)
        assertEquals(230, expanded.navigationWidthDp)
        assertEquals(770, expanded.contentWidthDp)
    }

    @Test
    fun collapsedRailReturnsTabletWidthToResponsiveContent() {
        val expanded = AdaptiveLayoutLogic.resolve(windowWidthDp = 900)
        val collapsed = AdaptiveLayoutLogic.resolve(
            windowWidthDp = 900,
            navigationCollapsed = true,
        )

        assertEquals(210, expanded.navigationWidthDp)
        assertEquals(690, expanded.contentWidthDp)
        assertEquals(AdaptiveLayoutLogic.COLLAPSED_NAVIGATION_WIDTH_DP, collapsed.navigationWidthDp)
        assertEquals(828, collapsed.contentWidthDp)
        assertFalse(collapsed.usesBottomNavigation)
    }

    @Test
    fun collapsedRailUsesTheWholeSeventyTwoDpContainerForCenteredIcons() {
        assertEquals(
            0,
            AdaptiveLayoutLogic.navigationHorizontalPaddingDp(
                collapsed = true,
                widthClass = WindowWidthClass.MEDIUM,
            ),
        )
        assertEquals(
            16,
            AdaptiveLayoutLogic.navigationHorizontalPaddingDp(
                collapsed = false,
                widthClass = WindowWidthClass.MEDIUM,
            ),
        )
        assertEquals(
            20,
            AdaptiveLayoutLogic.navigationHorizontalPaddingDp(
                collapsed = false,
                widthClass = WindowWidthClass.EXPANDED,
            ),
        )
    }

    @Test
    fun collapsedFoldableRailKeepsContentBeyondTheHinge() {
        val collapsed = AdaptiveLayoutLogic.resolve(
            windowWidthDp = 1_200,
            availableWidthDp = 1_200,
            verticalHinge = VerticalHingeBoundsDp(left = 590, right = 610),
            navigationCollapsed = true,
        )

        assertEquals(72, collapsed.navigationWidthDp)
        assertEquals(538, collapsed.hingeSpacerDp)
        assertEquals(610, collapsed.navigationWidthDp + collapsed.hingeSpacerDp)
        assertEquals(590, collapsed.contentWidthDp)
    }

    @Test
    fun collapsedPreferenceDoesNotReplaceCompactBottomNavigation() {
        val compact = AdaptiveLayoutLogic.resolve(
            windowWidthDp = 699,
            navigationCollapsed = true,
        )

        assertTrue(compact.usesBottomNavigation)
        assertEquals(0, compact.navigationWidthDp)
        assertEquals(699, compact.contentWidthDp)
    }

    @Test
    fun classificationUsesWindowWidthWhileContentUsesAvailableWidth() {
        val spec = AdaptiveLayoutLogic.resolve(
            windowWidthDp = 700,
            availableWidthDp = 676,
        )

        assertEquals(WindowWidthClass.MEDIUM, spec.widthClass)
        assertEquals(210, spec.navigationWidthDp)
        assertEquals(466, spec.contentWidthDp)
    }

    @Test
    fun verticalHingeSpacerMovesContentPastAFeature() {
        val spec = AdaptiveLayoutLogic.resolve(
            windowWidthDp = 1_200,
            availableWidthDp = 1_200,
            verticalHinge = VerticalHingeBoundsDp(left = 590, right = 610),
        )

        assertEquals(WindowWidthClass.EXPANDED, spec.widthClass)
        assertEquals(230, spec.navigationWidthDp)
        assertEquals(380, spec.hingeSpacerDp)
        assertEquals(590, spec.contentWidthDp)
        assertEquals(610, spec.navigationWidthDp + spec.hingeSpacerDp)
    }

    @Test
    fun hingeBeforePreferredNavigationShrinksNavigationIntoLeftPane() {
        val spec = AdaptiveLayoutLogic.resolve(
            windowWidthDp = 900,
            availableWidthDp = 900,
            verticalHinge = VerticalHingeBoundsDp(left = 160, right = 180),
        )

        assertEquals(160, spec.navigationWidthDp)
        assertEquals(20, spec.hingeSpacerDp)
        assertEquals(720, spec.contentWidthDp)
    }

    @Test
    fun invalidOrOutOfWindowFeaturesDoNotAddSpacer() {
        assertEquals(
            0,
            AdaptiveLayoutLogic.resolve(
                windowWidthDp = 900,
                verticalHinge = VerticalHingeBoundsDp(450, 400),
            ).hingeSpacerDp,
        )
        assertEquals(
            0,
            AdaptiveLayoutLogic.resolve(
                windowWidthDp = 900,
                verticalHinge = VerticalHingeBoundsDp(900, 920),
            ).hingeSpacerDp,
        )
        assertEquals(
            0,
            AdaptiveLayoutLogic.resolve(
                windowWidthDp = 900,
                verticalHinge = VerticalHingeBoundsDp(0, 20),
            ).hingeSpacerDp,
        )
    }

    @Test
    fun compactWindowUsesTwoPanesAroundAReportedVerticalFeature() {
        val spec = AdaptiveLayoutLogic.resolve(
            windowWidthDp = 540,
            availableWidthDp = 540,
            verticalHinge = VerticalHingeBoundsDp(left = 260, right = 280),
        )

        assertFalse(spec.usesBottomNavigation)
        assertTrue(spec.avoidsVerticalHinge)
        assertEquals(260, spec.navigationWidthDp)
        assertEquals(20, spec.hingeSpacerDp)
        assertEquals(260, spec.contentWidthDp)
    }

    @Test
    fun plannerColumnsUseContentPaneWidthRatherThanWholeDeviceWidth() {
        assertEquals(3, AdaptiveContentLogic.plannerSlotColumns(320))
        assertEquals(3, AdaptiveContentLogic.plannerSlotColumns(479))
        assertEquals(4, AdaptiveContentLogic.plannerSlotColumns(480))
        assertEquals(6, AdaptiveContentLogic.plannerSlotColumns(600))
        assertEquals(7, AdaptiveContentLogic.plannerSlotColumns(840))

        assertEquals(2, AdaptiveContentLogic.plannerBuildingColumns(479))
        assertEquals(3, AdaptiveContentLogic.plannerBuildingColumns(480))
        assertEquals(4, AdaptiveContentLogic.plannerBuildingColumns(600))
        assertEquals(5, AdaptiveContentLogic.plannerBuildingColumns(840))

        assertEquals(3, AdaptiveContentLogic.plannerSummaryColumns(320))
        assertEquals(3, AdaptiveContentLogic.plannerSummaryColumns(479))
        assertEquals(3, AdaptiveContentLogic.plannerSummaryColumns(480))
    }

    @Test
    fun classroomQueryCampusIsIndependentFromTheDefaultCampusValue() {
        val defaultCampusID = "01"
        val queryState = PlannerQueryState(defaultCampusID)

        queryState.selectCampus("04")

        assertEquals("01", defaultCampusID)
        assertEquals("04", queryState.campusID)
    }

    @Test
    fun compactYearCalendarAlwaysUsesTwoMonthColumns() {
        assertEquals(2, YearCalendarLogic.columns(320))
        assertEquals(2, YearCalendarLogic.columns(699))
        assertEquals(3, YearCalendarLogic.columns(700))
        assertEquals(4, YearCalendarLogic.columns(1_100))
    }
}
