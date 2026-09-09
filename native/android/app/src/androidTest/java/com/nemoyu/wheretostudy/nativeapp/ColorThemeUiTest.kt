package com.nemoyu.wheretostudy.nativeapp

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.LayerDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ScrollView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Calendar

@RunWith(AndroidJUnit4::class)
class ColorThemeUiTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private var previousLanguage = AppLanguage.SYSTEM.code

    @Before fun prepare() {
        ensurePrivacyConsentForUiTest()
        previousLanguage = AppPreferences(context).languageCode
        InstrumentationRegistry.getArguments().getString("themeLanguage")?.let {
            AppPreferences(context).languageCode = it
        }
        context.getSharedPreferences(ColorThemePreferences.NAME, Context.MODE_PRIVATE).edit().clear().commit()
    }

    @After fun restore() {
        context.getSharedPreferences(ColorThemePreferences.NAME, Context.MODE_PRIVATE).edit().clear().commit()
        AppPreferences(context).languageCode = previousLanguage
    }

    private fun launch(): ActivityScenario<MainActivity> {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .putExtra(DailyCourseNotificationRuntimeMode.UI_TEST_INTENT_EXTRA, true)
        return ActivityScenario.launch(intent)
    }

    @Test fun persistenceIsLocalValidatesAndRecoversCorruptOrLegacyFields() {
        val store = ColorThemePreferences(context)
        assertEquals(ColorThemeSelection(), store.load())
        val custom = ThemeSeeds(" abcdef ", "#123456", "aabbcc")
        assertTrue(store.save(ColorThemeSelection("custom", custom)))
        val saved = store.load()
        assertEquals("#ABCDEF", saved.custom.primary)
        assertFalse(store.save(ColorThemeSelection("custom", ThemeSeeds("bad"))))
        assertEquals(saved, store.load())
        assertTrue(store.save(saved.copy(preset = "rose")))
        assertEquals(saved.custom, ColorThemePreferences(context).load().custom)
        val raw = context.getSharedPreferences(ColorThemePreferences.NAME, Context.MODE_PRIVATE)
        raw.edit().putString("preset", "future").putInt("primary", 4).putString("accent", "broken").commit()
        val recovered = store.load()
        assertEquals("default", recovered.preset)
        assertEquals(ThemeSeeds().primary, recovered.custom.primary)
        assertEquals(ThemeSeeds().accent, recovered.custom.accent)
        assertEquals("#AABBCC", recovered.custom.selectedDate)
    }

    @Test fun clearingThemeStoreRemovesCustomSeedsAndReportsWriteFailures() {
        val store = ColorThemePreferences(context)
        assertTrue(store.save(ColorThemeSelection("custom", ThemeSeeds("#ABCDEF", "#123456", "#654321"))))
        store.clear()
        assertEquals(ColorThemeSelection(), ColorThemePreferences(context).load())
        assertTrue(context.getSharedPreferences(ColorThemePreferences.NAME, Context.MODE_PRIVATE).all.isEmpty())

        val failingEditor = java.lang.reflect.Proxy.newProxyInstance(
            android.content.SharedPreferences.Editor::class.java.classLoader,
            arrayOf(android.content.SharedPreferences.Editor::class.java),
        ) { proxy, method, _ -> if (method.name == "commit") false else proxy } as android.content.SharedPreferences.Editor
        val failingPreferences = java.lang.reflect.Proxy.newProxyInstance(
            android.content.SharedPreferences::class.java.classLoader,
            arrayOf(android.content.SharedPreferences::class.java),
        ) { _, method, _ ->
            if (method.name == "edit") failingEditor else throw UnsupportedOperationException(method.name)
        } as android.content.SharedPreferences
        val failingContext = object : android.content.ContextWrapper(context) {
            override fun getSharedPreferences(name: String, mode: Int): android.content.SharedPreferences = failingPreferences
        }
        try {
            ColorThemePreferences(failingContext).clear()
            fail("A failed commit must not report successful theme removal")
        } catch (expected: IllegalStateException) {
            assertTrue(expected.message!!.contains("颜色主题"))
        }
    }

    @Test fun clearingAllLocalDataRestoresDefaultThemeSeedsAndVisibleUi() {
        launch().use { scenario -> scenario.onActivity { activity ->
            activity.findViewById<View>(R.id.navigation_settings).performClick()
            assertTrue(activity.applyColorTheme(ColorThemeSelection("custom", ThemeSeeds("#ABCDEF", "#000000", "#FFFFFF"))))
            val result = activity.clearAllLocalData()
            assertTrue("Clear failed: ${result.failedItems}", result.isComplete)
            assertEquals(ColorThemeSelection(), ColorThemePreferences(activity).load())
            assertEquals(ColorThemeSelection(), Palette.selection)
            assertEquals(ThemePalettes.forConfiguration(activity.resources.configuration).primary, Palette.primary)
            assertEquals(Palette.primaryText, activity.findViewById<TextView>(R.id.navigation_settings).currentTextColor)
            assertEquals(ThemeSeeds().primary, activity.findViewById<EditText>(R.id.settings_color_theme_primary).text.toString())
            assertEquals(ThemeSeeds().accent, activity.findViewById<EditText>(R.id.settings_color_theme_accent).text.toString())
            assertEquals(ThemeSeeds().selectedDate, activity.findViewById<EditText>(R.id.settings_color_theme_selected_date).text.toString())
            assertTrue(activity.getSharedPreferences(ColorThemePreferences.NAME, Context.MODE_PRIVATE).all.isEmpty())
        } }
    }

    @Test fun settingsRecolorsInPlacePreservingInputsAndScrollAndRestoresAfterRecreation() {
        launch().use { scenario ->
            scenario.onActivity { activity ->
                activity.findViewById<View>(R.id.navigation_settings).performClick()
                val page = activity.findViewById<ScrollView>(R.id.page_settings)
                val primary = activity.findViewById<EditText>(R.id.settings_color_theme_primary)
                primary.setText(" invalid draft ")
                page.scrollTo(0, 300)
                val scroll = page.scrollY
                val accountSettings = activity.getSharedPreferences("app_preferences_v1", Context.MODE_PRIVATE).all.toMap()
                val credentials = activity.getSharedPreferences("secure_credentials_v1", Context.MODE_PRIVATE).all.toMap()
                val theme = ColorThemeSelection("ocean")
                assertTrue(activity.applyColorTheme(theme))
                assertSame(page, activity.findViewById(R.id.page_settings))
                assertSame(primary, activity.findViewById(R.id.settings_color_theme_primary))
                assertEquals(" invalid draft ", primary.text.toString())
                assertEquals(scroll, page.scrollY)
                assertEquals(accountSettings, activity.getSharedPreferences("app_preferences_v1", Context.MODE_PRIVATE).all)
                assertEquals(credentials, activity.getSharedPreferences("secure_credentials_v1", Context.MODE_PRIVATE).all)
                assertEquals(Palette.primaryText, activity.findViewById<TextView>(R.id.navigation_settings).currentTextColor)
                activity.findViewById<View>(R.id.settings_color_theme_apply).performClick()
                assertNotNull(primary.error)
                assertEquals("ocean", ColorThemePreferences(activity).load().preset)
            }
            scenario.recreate()
            scenario.onActivity { activity ->
                assertNotNull(activity.findViewById<View>(R.id.page_settings))
                assertEquals("ocean", Palette.selection.preset)
                assertEquals(Palette.primaryText, activity.findViewById<TextView>(R.id.navigation_settings).currentTextColor)
            }
        }
    }

    @Test fun presetControlsPreserveCustomColorsAndRestoreExactDefault() {
        launch().use { scenario -> scenario.onActivity { activity ->
            activity.findViewById<View>(R.id.navigation_settings).performClick()
            val page = activity.findViewById<View>(R.id.page_settings)
            activity.findViewById<EditText>(R.id.settings_color_theme_primary).setText("#FFFFFF")
            activity.findViewById<EditText>(R.id.settings_color_theme_accent).setText("#000000")
            activity.findViewById<EditText>(R.id.settings_color_theme_selected_date).setText("#FFFFFF")
            activity.findViewById<View>(R.id.settings_color_theme_apply).performClick()
            val custom = ColorThemePreferences(activity).load().custom
            assertEquals("custom", Palette.selection.preset)
            ColorThemeLogic.presets.forEach { preset ->
                page.findViewWithTag<View>("color_theme_${preset.id}").performClick()
                assertEquals(preset.id, Palette.selection.preset)
                assertEquals(custom, ColorThemePreferences(activity).load().custom)
                assertTrue(page.findViewWithTag<View>("color_theme_${preset.id}").isSelected)
            }
            activity.findViewById<View>(R.id.settings_color_theme_restore).performClick()
            assertEquals("default", Palette.selection.preset)
            assertEquals(ThemePalettes.forConfiguration(activity.resources.configuration).primary, Palette.primary)
            assertEquals(custom, ColorThemePreferences(activity).load().custom)
        } }
    }

    @Test fun calendarViewAndSelectionSurviveColorChangeAndCanvasPixelsChange() {
        launch().use { scenario -> scenario.onActivity { activity ->
            activity.findViewById<View>(R.id.navigation_calendar).performClick()
            val page = activity.findViewById<View>(R.id.page_calendar)
            val period = activity.findViewById<TextView>(R.id.calendar_period_label).text.toString()
            val date = Calendar.getInstance()
            val year = YearCalendarView(activity, date.get(Calendar.YEAR), listOf(YearCalendarDay(date, 2, emptyList())), 400, date, { _, _, _, _ -> }, {})
            year.measure(View.MeasureSpec.makeMeasureSpec(activity.dp(400), View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            year.layout(0, 0, year.measuredWidth, year.measuredHeight)
            fun pixels(): Bitmap = Bitmap.createBitmap(year.width, year.height, Bitmap.Config.ARGB_8888).also { year.draw(Canvas(it)) }
            val before = pixels()
            val key = year.selectedDateKey()
            assertTrue(activity.applyColorTheme(ColorThemeSelection("violet")))
            year.refreshColorTheme()
            val after = pixels()
            assertFalse(before.sameAs(after))
            assertEquals(key, year.selectedDateKey())
            assertSame(page, activity.findViewById(R.id.page_calendar))
            assertEquals(period, activity.findViewById<TextView>(R.id.calendar_period_label).text.toString())
            before.recycle(); after.recycle()
        } }
    }

    @Test fun defaultRoundedDrawablePixelsMatchLegacyHelper() {
        val colors = listOf(ThemePalettes.light, ThemePalettes.dark)
        colors.forEach { theme ->
            listOf(theme.primaryFill, theme.selectedDate, theme.surface).forEach { fill ->
                listOf(0, theme.border).forEach { border ->
                    fun render(drawable: Drawable): Bitmap = Bitmap.createBitmap(160, 80, Bitmap.Config.ARGB_8888).also {
                        drawable.setBounds(0, 0, 160, 80)
                        drawable.draw(Canvas(it))
                    }
                    val legacy = render(roundedBackground(context, fill, border))
                    val themed = render(themedRoundedBackground(context, { fill }, { border }))
                    assertTrue("Default drawable pixels changed", legacy.sameAs(themed))
                    legacy.recycle(); themed.recycle()
                }
            }
        }
    }

    @Test fun visibleDialogActionsRecolorAndRestoreWithoutDismissal() {
        launch().use { scenario -> scenario.onActivity { activity ->
            val dialog = android.app.AlertDialog.Builder(activity)
                .setTitle("Theme Test").setPositiveButton("Done", null).showLocalized()
            try {
                val button = dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE)
                val original = button.textColors
                assertTrue(activity.applyColorTheme(ColorThemeSelection("rose")))
                assertTrue(dialog.isShowing)
                assertEquals(Palette.primaryText, button.currentTextColor)
                assertTrue(activity.applyColorTheme(ColorThemeSelection()))
                assertTrue(dialog.isShowing)
                assertEquals(original, button.textColors)
            } finally {
                dialog.dismiss()
            }
        } }
    }

    @Test fun timelineAndMonthSelectionRecolorWithoutRebuildingViews() {
        launch().use { scenario -> scenario.onActivity { activity ->
            activity.findViewById<View>(R.id.navigation_calendar).performClick()
            activity.findViewById<View>(R.id.calendar_mode_month).performClick()
            val month = activity.findViewById<ViewGroup>(R.id.calendar_month_grid)
            fun fill(drawable: Drawable?): Int? = when (drawable) {
                is GradientDrawable -> drawable.color?.defaultColor
                is LayerDrawable -> fill(drawable.getDrawable(0))
                else -> null
            }
            fun selected(view: View): View? {
                if (fill(view.background) == Palette.selectedDate) return view
                if (view is ViewGroup) repeat(view.childCount) { selected(view.getChildAt(it))?.let { found -> return found } }
                return null
            }
            val cell = selected(month)!!
            val dateDescription = cell.contentDescription.toString()
            val date = Calendar.getInstance()
            val timeline = CalendarTimelineView(activity, listOf(TimelineDay(date, emptyList(), emptyList())), date, compact = true)
            timeline.measure(View.MeasureSpec.makeMeasureSpec(activity.dp(320), View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            timeline.layout(0, 0, timeline.measuredWidth, timeline.measuredHeight)
            fun pixels(): Bitmap = Bitmap.createBitmap(timeline.width, timeline.height, Bitmap.Config.ARGB_8888).also { timeline.draw(Canvas(it)) }
            val before = pixels()
            assertTrue(activity.applyColorTheme(ColorThemeSelection("violet")))
            timeline.refreshColorTheme()
            val after = pixels()
            assertFalse("Selected timeline header did not repaint", before.sameAs(after))
            assertSame(month, activity.findViewById(R.id.calendar_month_grid))
            assertEquals(Palette.selectedDate, fill(cell.background))
            assertEquals(dateDescription, cell.contentDescription.toString())
            before.recycle(); after.recycle()
        } }
    }

    @Test fun narrowLargeTextThemeCardKeepsInputsAndChoicesReadable() {
        launch().use { scenario -> scenario.onActivity { activity ->
            val card = ColorThemeSettingsView(activity)
            fun enlarge(view: View) {
                if (view is TextView) view.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, view.textSize * 1.6f)
                if (view is ViewGroup) repeat(view.childCount) { enlarge(view.getChildAt(it)) }
            }
            enlarge(card)
            card.measure(View.MeasureSpec.makeMeasureSpec(activity.dp(280), View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            card.layout(0, 0, card.measuredWidth, card.measuredHeight)
            fun verify(view: View) {
                if (view is TextView) {
                    val layout = view.layout
                    assertNotNull("Missing layout for ${view.text}", layout)
                    assertTrue("Clipped text: ${view.text}", layout.height <= view.height - view.compoundPaddingTop - view.compoundPaddingBottom)
                    repeat(layout.lineCount) { assertEquals(0, layout.getEllipsisCount(it)) }
                }
                if (view is ViewGroup) repeat(view.childCount) { verify(view.getChildAt(it)) }
            }
            verify(card)
            val bitmap = Bitmap.createBitmap(card.width, card.height, Bitmap.Config.ARGB_8888)
            card.draw(Canvas(bitmap))
            val language = if (AppLocale.isEnglish(activity)) "en" else "zh"
            java.io.File(activity.cacheDir, "color-theme-large-text-$language.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            bitmap.recycle()
        } }
    }
}
