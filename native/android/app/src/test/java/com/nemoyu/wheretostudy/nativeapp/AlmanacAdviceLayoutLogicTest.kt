package com.nemoyu.wheretostudy.nativeapp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AlmanacAdviceLayoutLogicTest {
    @Test fun chineseBadgeKeepsTheExistingHorizontalLayout() {
        assertFalse(AlmanacAdviceLayoutLogic.shouldStack(282, 24, 7, 80))
    }

    @Test fun englishLabelUsesItsNaturalWidthWithoutSqueezingTheBody() {
        assertFalse(AlmanacAdviceLayoutLogic.shouldStack(222, 88, 7, 80))
        assertTrue(AlmanacAdviceLayoutLogic.shouldStack(142, 88, 7, 80))
    }

    @Test fun largeFontsAndLongTranslationsFallBackToAFullWidthBody() {
        assertTrue(AlmanacAdviceLayoutLogic.shouldStack(222, 176, 7, 160))
        assertTrue(AlmanacAdviceLayoutLogic.shouldStack(222, 240, 7, 80))
    }

    @Test fun exactFitStaysHorizontalButOnePixelLessStacks() {
        assertFalse(AlmanacAdviceLayoutLogic.shouldStack(175, 88, 7, 80))
        assertTrue(AlmanacAdviceLayoutLogic.shouldStack(174, 88, 7, 80))
    }

    @Test fun anExtremelyNarrowContainerNeverAllocatesANegativeBodyColumn() {
        assertTrue(AlmanacAdviceLayoutLogic.shouldStack(0, 88, 7, 80))
        assertTrue(AlmanacAdviceLayoutLogic.shouldStack(-18, 88, 7, 80))
    }

    @Test fun remeasurementCanReturnFromStackedToHorizontal() {
        assertTrue(AlmanacAdviceLayoutLogic.shouldStack(142, 88, 7, 80))
        assertFalse(AlmanacAdviceLayoutLogic.shouldStack(282, 88, 7, 80))
    }
}
