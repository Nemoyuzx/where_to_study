package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdaptiveLayoutLogicTest {
    @Test
    fun widthClassesUseActualWindowBreakpoints() {
        assertEquals(WindowWidthClass.COMPACT, AdaptiveLayoutLogic.widthClass(0))
        assertEquals(WindowWidthClass.COMPACT, AdaptiveLayoutLogic.widthClass(599))
        assertEquals(WindowWidthClass.MEDIUM, AdaptiveLayoutLogic.widthClass(600))
        assertEquals(WindowWidthClass.MEDIUM, AdaptiveLayoutLogic.widthClass(839))
        assertEquals(WindowWidthClass.EXPANDED, AdaptiveLayoutLogic.widthClass(840))
        assertEquals(WindowWidthClass.EXPANDED, AdaptiveLayoutLogic.widthClass(1_600))
    }

    @Test
    fun navigationChangesAtWindowBreakpointsWithoutAFeature() {
        val compact = AdaptiveLayoutLogic.resolve(599)
        val medium = AdaptiveLayoutLogic.resolve(600)
        val expanded = AdaptiveLayoutLogic.resolve(840)

        assertTrue(compact.usesBottomNavigation)
        assertEquals(0, compact.navigationWidthDp)
        assertEquals(599, compact.contentWidthDp)
        assertFalse(medium.usesBottomNavigation)
        assertEquals(176, medium.navigationWidthDp)
        assertEquals(424, medium.contentWidthDp)
        assertEquals(224, expanded.navigationWidthDp)
        assertEquals(616, expanded.contentWidthDp)
    }

    @Test
    fun classificationUsesWindowWidthWhileContentUsesAvailableWidth() {
        val spec = AdaptiveLayoutLogic.resolve(
            windowWidthDp = 600,
            availableWidthDp = 576,
        )

        assertEquals(WindowWidthClass.MEDIUM, spec.widthClass)
        assertEquals(176, spec.navigationWidthDp)
        assertEquals(400, spec.contentWidthDp)
    }

    @Test
    fun verticalHingeSpacerMovesContentPastAFeature() {
        val spec = AdaptiveLayoutLogic.resolve(
            windowWidthDp = 1_200,
            availableWidthDp = 1_200,
            verticalHinge = VerticalHingeBoundsDp(left = 590, right = 610),
        )

        assertEquals(WindowWidthClass.EXPANDED, spec.widthClass)
        assertEquals(224, spec.navigationWidthDp)
        assertEquals(386, spec.hingeSpacerDp)
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
        assertEquals(2, AdaptiveContentLogic.plannerSlotColumns(479))
        assertEquals(3, AdaptiveContentLogic.plannerSlotColumns(480))
        assertEquals(5, AdaptiveContentLogic.plannerSlotColumns(600))
        assertEquals(7, AdaptiveContentLogic.plannerSlotColumns(840))

        assertEquals(2, AdaptiveContentLogic.plannerBuildingColumns(479))
        assertEquals(3, AdaptiveContentLogic.plannerBuildingColumns(480))
        assertEquals(4, AdaptiveContentLogic.plannerBuildingColumns(600))
        assertEquals(5, AdaptiveContentLogic.plannerBuildingColumns(840))

        assertEquals(1, AdaptiveContentLogic.plannerSummaryColumns(479))
        assertEquals(3, AdaptiveContentLogic.plannerSummaryColumns(480))
    }
}
