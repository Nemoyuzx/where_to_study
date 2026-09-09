package com.nemoyu.wheretostudy.nativeapp

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ColorThemeLogicTest {
    @Test
    fun presetsMatchSharedContractExactly() {
        val json = javaClass.classLoader!!.getResourceAsStream("color-themes.json")!!
            .bufferedReader().use { JSONObject(it.readText()) }
        val presets = json.getJSONArray("presets")
        assertEquals(presets.length(), ColorThemeLogic.presets.size)
        ColorThemeLogic.presets.forEachIndexed { index, actual ->
            val expected = presets.getJSONObject(index)
            assertEquals(expected.getString("id"), actual.id)
            assertEquals(expected.getString("nameZh"), actual.nameZh)
            assertEquals(expected.getString("nameEn"), actual.nameEn)
            assertEquals(expected.getString("primary"), actual.seeds.primary)
            assertEquals(expected.getString("accent"), actual.seeds.accent)
            assertEquals(expected.getString("selectedDate"), actual.seeds.selectedDate)
        }
    }

    @Test
    fun defaultReturnsExactLegacyPalettesAndUnknownPresetFallsBack() {
        assertSame(ThemePalettes.light, ColorThemeLogic.palette(ColorThemeSelection(), false))
        assertSame(ThemePalettes.dark, ColorThemeLogic.palette(ColorThemeSelection(), true))
        assertSame(ThemePalettes.light, ColorThemeLogic.palette(ColorThemeSelection("unknown"), false))
        assertEquals("default", ColorThemeLogic.validPreset(null))
    }

    @Test
    fun hexValidationAcceptsOnlySixRgbDigitsAndNormalizes() {
        assertEquals("#ABCDEF", ColorThemeLogic.normalize(" \t#abcDEF\n"))
        assertEquals("#0123AB", ColorThemeLogic.normalize("0123ab"))
        listOf("", "#ABC", "12345", "1234567", "#123456FF", "#12 3456", "0xABCDEF", "GGGGGG", "##123456").forEach {
            assertNull(it, ColorThemeLogic.normalize(it))
        }
    }

    @Test
    fun allPresetsAndExtremeCustomColorsHaveReadablePrimaryAndSelectedDate() {
        val selections = ColorThemeLogic.presets.map { ColorThemeSelection(it.id) } +
            listOf("#000000", "#FFFFFF", "#808080", "#FF0000", "#00FF00", "#0000FF", "#FFFF00")
                .map { ColorThemeSelection("custom", ThemeSeeds(it, it, it)) }
        selections.forEach { selection ->
            listOf(false, true).forEach { dark ->
                val colors = ColorThemeLogic.palette(selection, dark)
                fun check(label: String, foreground: Int, background: Int) {
                    val contrast = ColorThemeLogic.contrast(foreground, background)
                    assertTrue("${selection.preset}/${selection.seeds}/$dark/$label = $contrast", contrast >= 4.5)
                }
                check("primary fill", colors.onPrimary, colors.primaryFill)
                check("selected date", colors.onPrimary, colors.selectedDate)
                check("primary text", colors.primaryText, colors.surface)
                check("accent text", colors.onAccent, colors.accent)
                val legacy = if (dark) ThemePalettes.dark else ThemePalettes.light
                assertEquals(legacy.assignment, colors.assignment)
                assertEquals(legacy.schoolNotice, colors.schoolNotice)
                assertEquals(legacy.publicDeadline, colors.publicDeadline)
                assertEquals(legacy.conferenceDeadline, colors.conferenceDeadline)
                assertEquals(legacy.summerCampDeadline, colors.summerCampDeadline)
                assertEquals(legacy.hackathonDeadline, colors.hackathonDeadline)
                assertEquals(legacy.customDeadline, colors.customDeadline)
                assertEquals(legacy.nowIndicator, colors.nowIndicator)
                assertEquals(legacy.danger, colors.danger)
                assertEquals(legacy.background, colors.background)
            }
        }
    }

    @Test
    fun textOnTintedSelectionSurfacesKeepsContrast() {
        ColorThemeLogic.presets.drop(1).forEach { preset ->
            listOf(false, true).forEach { dark ->
                val colors = ColorThemeLogic.palette(ColorThemeSelection(preset.id), dark)
                val text = ColorThemeLogic.readableText(colors.primaryText, colors.selectionSurface)
                assertTrue(ColorThemeLogic.contrast(text, colors.selectionSurface) >= 4.5)
            }
        }
    }

    @Test
    fun accessibleFillUsesFirstPassingTwoPercentStep() {
        val seed = ColorThemeLogic.color("#FFFFFF")
        val fill = ColorThemeLogic.fill(seed)
        assertEquals(ColorThemeLogic.color("#757575"), fill)
        assertTrue(ColorThemeLogic.contrast(ColorThemeLogic.color("#7A7A7A"), -1) < 4.5)
        assertEquals(seed, ColorThemeLogic.text(seed, dark = true))
    }
}
