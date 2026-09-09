package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import kotlin.math.pow
import kotlin.math.roundToInt

data class ThemeSeeds(
    val primary: String = "#166B5D",
    val accent: String = "#E2BC62",
    val selectedDate: String = "#2563EB",
) {
    fun normalized(): ThemeSeeds? {
        return ThemeSeeds(
            ColorThemeLogic.normalize(primary) ?: return null,
            ColorThemeLogic.normalize(accent) ?: return null,
            ColorThemeLogic.normalize(selectedDate) ?: return null,
        )
    }
}

data class ColorThemePreset(val id: String, val nameZh: String, val nameEn: String, val seeds: ThemeSeeds)

data class ColorThemeSelection(val preset: String = "default", val custom: ThemeSeeds = ThemeSeeds()) {
    val seeds: ThemeSeeds get() = ColorThemeLogic.presets.firstOrNull { it.id == preset }?.seeds ?: custom
}

/** Shared sRGB contract: contracts/v1/color-themes.json and docs/color-themes.md. */
object ColorThemeLogic {
    val presets = listOf(
        ColorThemePreset("default", "默认青绿", "Classic Teal", ThemeSeeds()),
        ColorThemePreset("ocean", "海洋蓝", "Ocean Blue", ThemeSeeds("#356A8A", "#75939A", "#3354A2")),
        ColorThemePreset("violet", "鸢尾紫", "Iris Violet", ThemeSeeds("#70558F", "#A08AAB", "#504AA0")),
        ColorThemePreset("amber", "暖琥珀", "Warm Amber", ThemeSeeds("#92603A", "#A9946E", "#78533F")),
        ColorThemePreset("rose", "玫瑰", "Rose", ThemeSeeds("#A4556D", "#B3909A", "#803F68")),
    )
    private val rgbPattern = Regex("^#?[0-9A-Fa-f]{6}$")

    fun normalize(value: String): String? = value.trim().takeIf(rgbPattern::matches)
        ?.removePrefix("#")?.uppercase(java.util.Locale.ROOT)?.let { "#$it" }

    fun validPreset(value: String?): String = value?.takeIf { candidate ->
        candidate == "custom" || presets.any { it.id == candidate }
    } ?: "default"

    fun color(value: String): Int = (0xFF000000L or value.removePrefix("#").toLong(16)).toInt()

    fun mix(seed: Int, target: Int, amount: Double): Int {
        fun channel(shift: Int): Int = (((seed ushr shift) and 255) * (1 - amount) +
            ((target ushr shift) and 255) * amount).roundToInt().coerceIn(0, 255)
        return (255 shl 24) or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
    }

    private fun luminance(color: Int): Double {
        fun linear(shift: Int): Double {
            val component = ((color ushr shift) and 255) / 255.0
            return if (component <= 0.04045) component / 12.92 else ((component + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    fun contrast(first: Int, second: Int): Double {
        val a = luminance(first)
        val b = luminance(second)
        return (maxOf(a, b) + 0.05) / (minOf(a, b) + 0.05)
    }

    private fun accessible(seed: Int, against: Int, target: Int): Int {
        if (contrast(seed, against) >= 4.5) return seed
        return (1..50).asSequence().map { mix(seed, target, it * 0.02) }
            .first { contrast(it, against) >= 4.5 }
    }

    fun fill(seed: Int): Int = accessible(seed, -1, 0xFF000000.toInt())
    fun readableText(seed: Int, background: Int): Int = accessible(
        seed,
        background,
        if (contrast(0xFF000000.toInt(), background) >= contrast(-1, background)) 0xFF000000.toInt() else -1,
    )
    fun text(seed: Int, dark: Boolean): Int = if (dark) {
        accessible(seed, 0xFF282828.toInt(), -1)
    } else fill(seed)

    fun palette(selection: ColorThemeSelection, dark: Boolean): ThemeColors {
        val original = if (dark) ThemePalettes.dark else ThemePalettes.light
        if (validPreset(selection.preset) == "default") return original
        val seeds = selection.seeds
        val primary = color(seeds.primary)
        val accent = color(seeds.accent)
        val selected = color(seeds.selectedDate)
        fun surface(base: String, amount: Double) = mix(color(base), primary, amount)
        val background = if (dark) surface("#14171C", 0.12) else surface("#F4F4F5", 0.045)
        val card = if (dark) surface("#22262D", 0.10) else surface("#FFFFFF", 0.012)
        val elevated = if (dark) surface("#2A2F38", 0.08) else surface("#FFFFFF", 0.006)
        val variant = if (dark) surface("#2D333D", 0.10) else surface("#EEF0F3", 0.055)
        val border = if (dark) surface("#46505F", 0.18) else surface("#D6DAE0", 0.16)
        val surfaces = listOf(background, card, elevated, variant)
        val mostDemandingSurface = if (dark) surfaces.maxBy(::luminance) else surfaces.minBy(::luminance)
        val textTarget = if (dark) -1 else 0xFF000000.toInt()
        val body = accessible(color(if (dark) "#EEF2F6" else "#263240"), mostDemandingSurface, textTarget)
        val secondary = accessible(color(if (dark) "#B0BCCB" else "#4F5E6E"), mostDemandingSurface, textTarget)
        val primaryText = accessible(text(primary, dark), mostDemandingSurface, textTarget)
        return original.copy(
            primary = primaryText,
            primaryFill = fill(primary),
            primaryDark = mix(fill(primary), 0xFF000000.toInt(), 0.25),
            primaryText = primaryText,
            selectedDate = fill(selected),
            accent = accent,
            onAccent = if (contrast(accent, -1) >= 4.5) -1 else 0xFF000000.toInt(),
            background = background,
            surface = card,
            elevated = elevated,
            surfaceVariant = variant,
            border = border,
            text = body,
            muted = secondary,
            outOfMonth = secondary,
            segmentedSelection = elevated,
            selectionSurface = mix(primary, card, if (dark) 0.86 else 0.92),
        )
    }
}

/** Appearance is local and independent of credentials, account saves and network work. */
class ColorThemePreferences(context: Context) {
    private val preferences = context.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    fun load(): ColorThemeSelection {
        fun read(key: String): String? = runCatching { preferences.getString(key, null) }.getOrNull()
        val defaults = ThemeSeeds()
        return ColorThemeSelection(
            ColorThemeLogic.validPreset(read("preset")),
            ThemeSeeds(
                ColorThemeLogic.normalize(read("primary").orEmpty()) ?: defaults.primary,
                ColorThemeLogic.normalize(read("accent").orEmpty()) ?: defaults.accent,
                ColorThemeLogic.normalize(read("selectedDate").orEmpty()) ?: defaults.selectedDate,
            ),
        )
    }

    fun save(selection: ColorThemeSelection): Boolean {
        val custom = selection.custom.normalized() ?: return false
        if (selection.preset != ColorThemeLogic.validPreset(selection.preset)) return false
        return preferences.edit().putString("preset", selection.preset)
            .putString("primary", custom.primary).putString("accent", custom.accent)
            .putString("selectedDate", custom.selectedDate).commit()
    }

    /** Full local-data removal also discards saved custom seeds. Preset restore does not. */
    fun clear() {
        if (!preferences.edit().clear().commit()) {
            throw IllegalStateException("无法清除本地颜色主题。")
        }
    }

    companion object {
        const val NAME = "color_theme_preferences"
    }
}
