package com.nemoyu.wheretostudy.nativeapp

import java.util.Locale
import java.util.Date
import java.util.TimeZone
import java.text.SimpleDateFormat
import org.junit.Assert.*
import org.junit.Test

class AppLocaleLogicTest {
    @Test fun knownChromeCatalogUsesDistinctCompiledResourceIDs() {
        assertEquals(1430, NativeUiTextCatalog.resources.size)
        assertEquals(NativeUiTextCatalog.resources.size, NativeUiTextCatalog.resources.values.toSet().size)
        assertTrue(NativeUiTextCatalog.resources.values.all { it != 0 })
        assertTrue("设置" in NativeUiTextCatalog.resources)
        assertTrue("打开教学云平台" in NativeUiTextCatalog.resources)
        assertTrue("启用 QMplus" in NativeUiTextCatalog.resources)
        assertTrue("仅适用国院" in NativeUiTextCatalog.resources)
        listOf("鼠尾草", "陶土", "梅子", "石墨", "夜蓝").forEach {
            assertTrue(it in NativeUiTextCatalog.resources)
        }
        assertFalse("EBU5303 Synthetic course" in NativeUiTextCatalog.resources)
    }

    @Test fun allThirteenLanguagesHaveDistinctCanonicalTagsAndNativeNames() {
        val languages = AppLanguage.entries.filter { it != AppLanguage.SYSTEM }
        assertEquals(13, languages.size)
        assertEquals(13, languages.map { it.code }.distinct().size)
        languages.forEach { language ->
            assertEquals(language, AppLanguage.fromCode(language.code))
            assertTrue(language.nativeName.isNotBlank())
            assertEquals(language, AppLanguage.fromLocale(AppLocale.resolvedLocale(language, Locale.US)))
        }
    }

    @Test fun chineseScriptAndRegionsSelectTraditionalWithoutOverridingExplicitHans() {
        listOf("zh-Hant", "zh-TW", "zh-HK", "zh-MO", "zh_Hant_TW", "zh-Hant-CN")
            .forEach { assertEquals(it, AppLanguage.TRADITIONAL_CHINESE, AppLanguage.fromCode(it)) }
        listOf("zh", "zh-CN", "zh-SG", "zh-Hans-TW")
            .forEach { assertEquals(it, AppLanguage.SIMPLIFIED_CHINESE, AppLanguage.fromCode(it)) }
    }

    @Test fun supportedRegionalTagsAndLegacyIndonesianTagsDoNotBecomeEnglish() {
        assertEquals(AppLanguage.PORTUGUESE, AppLanguage.fromCode("pt-BR"))
        assertEquals(AppLanguage.SPANISH, AppLanguage.fromCode("es-MX"))
        assertEquals(AppLanguage.ARABIC, AppLanguage.fromCode("ar-EG"))
        assertEquals(AppLanguage.INDONESIAN, AppLanguage.fromCode("in-ID"))
        assertEquals(AppLanguage.INDONESIAN, AppLanguage.fromCode("id-ID"))
        assertEquals(AppLanguage.SYSTEM, AppLanguage.fromCode("system"))
        assertNull(AppLanguage.fromCode("fr-FR"))
        assertNull(AppLanguage.fromCode(""))
    }

    @Test fun followingSystemKeepsSupportedRegionAndInfersChineseScript() {
        val traditional = AppLocale.resolvedLocale(AppLanguage.SYSTEM, Locale.forLanguageTag("zh-TW"))
        assertEquals("Hant", traditional.script)
        assertEquals("TW", traditional.country)
        val portuguese = AppLocale.resolvedLocale(AppLanguage.SYSTEM, Locale.forLanguageTag("pt-BR"))
        assertEquals("pt", portuguese.language)
        assertEquals("BR", portuguese.country)
        assertEquals(Locale.US, AppLocale.resolvedLocale(AppLanguage.SYSTEM, Locale.FRANCE))
    }

    @Test fun followingSystemUsesTheFirstSupportedPreferredLocaleRatherThanAlwaysEnglish() {
        val spanish = Locale.forLanguageTag("es-MX")
        assertEquals(spanish, AppLocale.preferredSupportedLocale(listOf(Locale.FRANCE, spanish, Locale.US)))
        val traditional = Locale.forLanguageTag("zh-HK")
        assertEquals(traditional, AppLocale.preferredSupportedLocale(listOf(traditional, Locale.US)))
        assertEquals(Locale.US, AppLocale.preferredSupportedLocale(emptyList()))
    }

    @Test fun selectingALocaleDoesNotChangeTheProcessDefaultUsedByContractCode() {
        val previous = Locale.getDefault()
        AppLocale.resolvedLocale(AppLanguage.THAI, Locale.US)
        AppLocale.resolvedLocale(AppLanguage.ARABIC, Locale.US)
        assertEquals(previous, Locale.getDefault())
        val contractDate = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC"); isLenient = false
        }
        assertEquals("2026-01-01", contractDate.format(Date(1767225600000L)))
        assertEquals("1234", String.format(Locale.US, "%d", 1234))
    }
}
