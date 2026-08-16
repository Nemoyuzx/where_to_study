package com.nemoyu.wheretostudy.nativeapp

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ThemePaletteTest {
    @Test
    fun lightAndDarkThemesKeepBrandColorsAndUseDistinctSurfaces() {
        assertNotEquals(ThemePalettes.light.primary, ThemePalettes.dark.primary)
        assertNotEquals(ThemePalettes.light.primaryFill, ThemePalettes.dark.primaryFill)
        assertNotEquals(ThemePalettes.light.background, ThemePalettes.dark.background)
        assertNotEquals(ThemePalettes.light.surface, ThemePalettes.dark.surface)
        assertNotEquals(ThemePalettes.light.text, ThemePalettes.dark.text)
        assertNotEquals(ThemePalettes.light.primaryText, ThemePalettes.dark.primaryText)
    }

    @Test
    fun semanticTextColorsMeetNormalTextContrastInBothThemes() {
        listOf(ThemePalettes.light, ThemePalettes.dark).forEach { colors ->
            assertContrast("text on surface", colors.text, colors.surface)
            assertContrast("muted on surface", colors.muted, colors.surface)
            assertContrast("brand text on surface", colors.primaryText, colors.surface)
            assertContrast("selected text on primary fill", colors.onPrimary, colors.primaryFill)
            assertContrast("busy-slot text on accent", colors.onAccent, colors.accent)
            assertContrast("danger text on danger surface", colors.danger, colors.dangerSurface)
            assertContrast("holiday text on surface", colors.holiday, colors.surface)
            assertContrast("out-of-month text on surface", colors.outOfMonth, colors.surface)
        }
    }

    private fun assertContrast(label: String, foreground: Int, background: Int) {
        val ratio = contrastRatio(foreground, background)
        assertTrue("$label contrast was $ratio, expected at least $MINIMUM_CONTRAST", ratio >= MINIMUM_CONTRAST)
    }

    private fun contrastRatio(first: Int, second: Int): Double {
        val lighter = max(luminance(first), luminance(second))
        val darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private fun luminance(color: Int): Double {
        val red = linearChannel(color shr 16 and 0xFF)
        val green = linearChannel(color shr 8 and 0xFF)
        val blue = linearChannel(color and 0xFF)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private fun linearChannel(channel: Int): Double {
        val normalized = channel / 255.0
        return if (normalized <= 0.03928) {
            normalized / 12.92
        } else {
            ((normalized + 0.055) / 1.055).pow(2.4)
        }
    }

    private companion object {
        const val MINIMUM_CONTRAST = 4.5
    }
}
